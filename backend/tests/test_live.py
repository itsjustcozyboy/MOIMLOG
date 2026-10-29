import asyncio, io, wave, json
import pytest
from backend.app.services import live
from backend.app.main import publish_live
H={'X-Moimlog':'1'}

def audio(seconds=15, value=0):
    out=io.BytesIO()
    with wave.open(out,'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(16000);w.writeframes(int(value).to_bytes(2,'little')*int(seconds*16000))
    return out.getvalue()

def test_live_flow(account,meeting):
    base='/api/meetings/'+meeting['id']+'/recording'
    assert account.post(base,json={'consent':False,'mock':True},headers=H).status_code==400
    rid=account.post(base,json={'consent':True,'mock':True},headers=H).json()['id']
    for seq in [1,0,0]:assert account.put(base+f'/chunks/{seq}',files={'file':('x.wav',audio())},headers=H).status_code==200
    assert account.put(base+'/chunks/0',files={'file':('x.wav',audio(value=1))},headers=H).status_code==409
    assert account.post(base+'/end',json={'count':2},headers=H).status_code==200
    for _ in range(3):asyncio.run(live.tick(publish_live))
    s=account.get(base).json();assert s['complete'];assert len(s['chunks'])==2
    assert all(x['speaker'] is None for x in s['segments'])
    assert account.get(base+'/audio/0').content==audio()
    m=account.post(base+'/review',headers=H).json();assert m['step']==3 and 'Mock' in m['text']
    assert account.put('/api/meetings/'+meeting['id']+'/transcription',json={'text':m['text']},headers=H).json()['segments'][0]['speaker'] is None
    account.delete('/api/meetings/'+meeting['id'],headers=H)
    with live.connect() as db:assert db.execute('SELECT COUNT(*) FROM chunks WHERE rid=?',(rid,)).fetchone()[0]==0

def test_gap_and_budget(monkeypatch):
    r=live.create('gap','test','groq');live.put(r['id'],1,audio())
    asyncio.run(live.tick(lambda *args:None))
    assert live.status(r['id'])['chunks'][0]['attempts']==0
    live.put(r['id'],0,audio())
    monkeypatch.setenv('AI_MONTHLY_BUDGET_KRW','0')
    asyncio.run(live.tick(lambda *args:None))
    s=live.status(r['id']);assert s['chunks'][0]['state']=='budget'
    live.put(r['id'],2,audio(1)) # recording continues without paid calls
    live.delete_recordings(mid='gap')

def test_wav_overlap_limits_and_120_minutes(monkeypatch):
    r=live.create('long','test','mock')
    raw=audio()
    for seq in range(480):live.put(r['id'],seq,raw)
    with pytest.raises(ValueError):live.put(r['id'],480,audio(2))
    with live.connect() as db:
        row=db.execute('SELECT * FROM chunks WHERE rid=? AND seq=479',(r['id'],)).fetchone()
        merged,offset,duration=live.prepare(db,row)
        assert offset==7184 and duration==16
        with wave.open(io.BytesIO(merged)) as w:assert w.getnframes()==256000
        monkeypatch.setenv('GROQ_RPM','1');db.execute('DELETE FROM calls');db.execute('INSERT INTO calls VALUES(?,?)',(live.time.time(),16));assert not live.allowance(db,16)
    live.delete_recordings(mid='long')

def test_invalid_and_missing_finish(account,meeting):
    base='/api/meetings/'+meeting['id']+'/recording'
    account.post(base,json={'consent':True,'mock':True},headers=H)
    assert account.put(base+'/chunks/0',files={'file':('x.wav',b'invalid')},headers=H).status_code==409
    account.post(base+'/end',json={'count':1},headers=H)
    assert account.post(base+'/review',headers=H).status_code==409

def test_retry_preserves_audio(monkeypatch):
    r=live.create('failure','test','groq');raw=audio(2);live.put(r['id'],0,raw)
    monkeypatch.setenv('GROQ_API_KEY','test-not-real');monkeypatch.setattr(live,'reserve',lambda *a:None)
    monkeypatch.setattr(live,'allowance',lambda *a:True)
    class Failure:
        async def __aenter__(self):return self
        async def __aexit__(self,*a):pass
        async def post(self,*a,**kw):raise RuntimeError('fake outage')
    monkeypatch.setattr(live.httpx,'AsyncClient',lambda **kw:Failure())
    for attempt in range(3):
        with live.connect() as db:db.execute('UPDATE chunks SET available=0 WHERE rid=?',(r['id'],))
        asyncio.run(live.tick(lambda *args:None))
    assert live.status(r['id'])['chunks'][0]['state']=='failed'
    with live.connect() as db:assert db.execute('SELECT audio FROM chunks WHERE rid=?',(r['id'],)).fetchone()[0]==raw
    live.delete_recordings(mid='failure')

def test_owner_isolation(account,meeting):
    base='/api/meetings/'+meeting['id']+'/recording'
    account.post(base,json={'consent':True,'mock':True},headers=H)
    account.post('/api/auth/logout',headers=H)
    assert account.get(base).status_code==401
    account.post('/api/auth/register',json={'email':'other-live@test.example','password':'test-password-123','name':'다른 사용자'},headers=H)
    assert account.get(base).status_code==404

def test_boundary_dedup():
    r=live.create('dedup','test','mock')
    for seq in [0,1]:live.put(r['id'],seq,audio())
    with live.connect() as db:
        for seq,start,end,text in [(0,14000,15000,'함께 기도합니다.'),(1,14500,15500,'기도합니다. 감사합니다.')]:
            db.execute("UPDATE chunks SET state='done',result=? WHERE rid=? AND seq=?",(json.dumps([{'speaker':None,'start':start,'end':end,'timestamp':'00:14','text':text}]),r['id'],seq))
    result=live.status(r['id'])['segments'];assert ' '.join(s['text'] for s in result)=='함께 기도합니다. 감사합니다.'
    live.delete_recordings(mid='dedup')
