"""Durable single-worker recording queue. Audio commits precede any paid work."""
import asyncio, hashlib, io, json, os, sqlite3, time, uuid, wave, re, logging
from ..db import DATA
from .budget import reserve
import httpx


def connect():
    db = sqlite3.connect(DATA/'recordings.sqlite', timeout=30)
    db.row_factory = sqlite3.Row
    db.executescript('''
    CREATE TABLE IF NOT EXISTS recordings(id TEXT PRIMARY KEY, mid TEXT, owner TEXT, mode TEXT, ended INTEGER DEFAULT 0, expected INTEGER, created REAL);
    CREATE UNIQUE INDEX IF NOT EXISTS recording_meeting ON recordings(mid);
    CREATE TABLE IF NOT EXISTS chunks(rid TEXT, seq INTEGER, audio BLOB, digest TEXT, duration REAL, state TEXT DEFAULT 'queued', attempts INTEGER DEFAULT 0, available REAL DEFAULT 0, result TEXT DEFAULT '[]', error TEXT DEFAULT '', PRIMARY KEY(rid,seq));
    CREATE TABLE IF NOT EXISTS calls(at REAL, seconds REAL);
    ''')
    return db


def wav(raw):
    try:
        with wave.open(io.BytesIO(raw)) as w:
            if w.getnchannels()!=1 or w.getsampwidth()!=2 or not 8000<=w.getframerate()<=96000: raise ValueError()
            rate=w.getframerate(); frames=w.readframes(w.getnframes())
            if len(frames)!=w.getnframes()*2: raise ValueError()
            duration=len(frames)/2/rate
            if not 0<duration<=15.1: raise ValueError()
            return rate,frames,duration
    except Exception: raise ValueError('유효한 15초 이하 모노 PCM WAV가 필요합니다.')


def create(mid, owner, mode):
    with connect() as db:
        old=db.execute('SELECT * FROM recordings WHERE mid=?',(mid,)).fetchone()
        if old:return dict(old)
        rid=str(uuid.uuid4())
        db.execute('INSERT INTO recordings(id,mid,owner,mode,created) VALUES(?,?,?,?,?)',(rid,mid,owner,mode,time.time()))
        return dict(db.execute('SELECT * FROM recordings WHERE id=?',(rid,)).fetchone())


def put(rid, seq, raw):
    _,_,duration=wav(raw)
    digest=hashlib.sha256(raw).hexdigest()
    with connect() as db:
        db.execute('BEGIN IMMEDIATE')
        rec=db.execute('SELECT * FROM recordings WHERE id=?',(rid,)).fetchone()
        old=db.execute('SELECT digest FROM chunks WHERE rid=? AND seq=?',(rid,seq)).fetchone()
        if old:
            if old['digest']!=digest:raise ValueError('같은 순번의 다른 음성은 덮어쓸 수 없습니다.')
            return
        if seq<0 or seq>=10000 or (rec['ended'] and seq>=rec['expected']):raise ValueError('잘못된 구간 순번입니다.')
        total=db.execute('SELECT COALESCE(SUM(duration),0) FROM chunks WHERE rid=?',(rid,)).fetchone()[0]
        if total+duration>7201:raise ValueError('최대 120분입니다.')
        db.execute('INSERT INTO chunks(rid,seq,audio,digest,duration) VALUES(?,?,?,?,?)',(rid,seq,raw,digest,duration))


def status(rid):
    with connect() as db:
        rec=dict(db.execute('SELECT * FROM recordings WHERE id=?',(rid,)).fetchone())
        chunks=[dict(r) for r in db.execute('SELECT seq,duration,state,attempts,result,error FROM chunks WHERE rid=? ORDER BY seq',(rid,))]
    segments=[]
    for c in chunks:
        for s in json.loads(c.pop('result')):
            # Only trim matching boundary words when timestamps also overlap.
            if segments and s['start']<segments[-1]['end']:
                a=segments[-1]['text'].split(); b=s['text'].split()
                for n in range(min(len(a),len(b)),0,-1):
                    if [re.sub(r'[^\w]', '', x) for x in a[-n:]]==[re.sub(r'[^\w]', '', x) for x in b[:n]]:b=b[n:];break
                s['text']=' '.join(b)
            if s['text'].strip():segments.append(s)
    grouped=[]
    for s in segments:
        if grouped and s['start']-grouped[-1]['start']<8000 and s['start']<=grouped[-1]['end']+1500:
            grouped[-1]['text']+=' '+s['text'];grouped[-1]['end']=max(grouped[-1]['end'],s['end'])
        else:grouped.append(dict(s))
    segments=grouped
    complete=bool(rec['ended'] and len(chunks)==rec['expected'] and all(c['seq']==i and c['state']=='done' for i,c in enumerate(chunks)))
    return {**rec,'chunks':chunks,'segments':segments,'complete':complete}


def prepare(db, row):
    rate,frames,duration=wav(row['audio']); prefix=b''
    if row['seq']:
        prev=db.execute('SELECT audio FROM chunks WHERE rid=? AND seq=?',(row['rid'],row['seq']-1)).fetchone()
        if prev:
            pr,pf,_=wav(prev['audio'])
            if pr==rate:prefix=pf[-rate*2:]
    offset=db.execute('SELECT COALESCE(SUM(duration),0) FROM chunks WHERE rid=? AND seq<?',(row['rid'],row['seq'])).fetchone()[0]
    output=io.BytesIO()
    with wave.open(output,'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes(prefix+frames)
    overlap=len(prefix)/2/rate
    return output.getvalue(), offset-overlap, duration+overlap


def allowance(db, seconds):
    now=time.time()
    for period, column, limit in [(60,'COUNT(*)',int(os.getenv('GROQ_RPM','20'))),(86400,'COUNT(*)',int(os.getenv('GROQ_RPD','2000'))),(3600,'COALESCE(SUM(seconds),0)',int(os.getenv('GROQ_ASH','7200'))),(86400,'COALESCE(SUM(seconds),0)',int(os.getenv('GROQ_ASD','28800')))]:
        used=db.execute(f'SELECT {column} FROM calls WHERE at>?',(now-period,)).fetchone()[0]
        if used+(1 if 'COUNT' in column else seconds)>limit:return False
    return True


async def tick(publish):
    with connect() as db:
        row=db.execute('''SELECT c.*,r.mode,r.mid,r.owner FROM chunks c JOIN recordings r ON r.id=c.rid
          WHERE c.state='queued' AND c.available<=? AND NOT EXISTS
          (SELECT 1 FROM chunks p WHERE p.rid=c.rid AND p.seq<c.seq AND p.state!='done')
          AND (SELECT COUNT(*) FROM chunks p WHERE p.rid=c.rid AND p.seq<c.seq)=c.seq
          ORDER BY c.available,c.seq,r.created LIMIT 1''',(time.time(),)).fetchone()
        if not row:return
        db.execute('BEGIN IMMEDIATE')
        raw,offset,seconds=prepare(db,row)
        if row['mode']=='groq':
            if not allowance(db,seconds):return
            try:reserve('groq',max(10,seconds)/3600*.04*float(os.getenv('USD_KRW','1500')),{'recording':row['rid'],'seq':row['seq'],'attempt':row['attempts']+1,'audioSeconds':seconds})
            except ValueError as e:
                db.execute("UPDATE chunks SET state='budget',error=? WHERE rid=? AND seq=?",(str(e),row['rid'],row['seq']));return
            db.execute('INSERT INTO calls VALUES(?,?)',(time.time(),seconds))
        db.execute("UPDATE chunks SET state='processing',attempts=attempts+1 WHERE rid=? AND seq=?",(row['rid'],row['seq']))
    try:
        if row['mode']=='mock':
            result=[{'start':0,'end':seconds,'text':f'[Mock 예시 {row["seq"]+1}] 함께 나눈 이야기를 검토해 주세요.'}]
        else:
            async with httpx.AsyncClient(timeout=90) as client:
                response=await client.post('https://api.groq.com/openai/v1/audio/transcriptions',headers={'Authorization':'Bearer '+os.environ['GROQ_API_KEY']},files={'file':('segment.wav',raw,'audio/wav')},data={'model':'whisper-large-v3-turbo','language':'ko','response_format':'verbose_json','timestamp_granularities[]':'word'})
            response.raise_for_status(); body=response.json()
            result=body.get('words') or body.get('segments') or [{'start':0,'end':seconds,'text':body.get('text','')}]
        segments=[]
        for s in result:
            start=max(0,offset+max(0,min(seconds,float(s.get('start',0)))))
            end=max(start,offset+max(0,min(seconds,float(s.get('end',seconds)))))
            # The preceding chunk owns the first half of the overlap; keep crossing words.
            if row['seq'] and end<=offset+0.5:continue
            segments.append({'speaker':None,'text':s.get('word',s.get('text','')).strip(),'start':round(start*1000),'end':round(end*1000),'timestamp':f'{int(start)//60:02}:{int(start)%60:02}'})
        with connect() as db:db.execute("UPDATE chunks SET state='done',result=?,error='' WHERE rid=? AND seq=?",(json.dumps(segments,ensure_ascii=False),row['rid'],row['seq']))
        publish(row['mid'],{'id':row['owner']},status(row['rid']))
    except Exception as e:
        with connect() as db:
            current=db.execute('SELECT state FROM chunks WHERE rid=? AND seq=?',(row['rid'],row['seq'])).fetchone()
        if not current or current['state']=='done':
            logging.getLogger(__name__).warning('Transcript publish deferred; audio result preserved')
            return
        delay= min(300, 10*2**row['attempts'])
        if isinstance(e,httpx.HTTPStatusError) and e.response.status_code==429:
            try:delay=max(delay,float(e.response.headers.get('retry-after','60')))
            except ValueError:delay=max(delay,60)
        with connect() as db:db.execute('UPDATE chunks SET state=?,available=?,error=? WHERE rid=? AND seq=?',('failed' if row['attempts']>=2 else 'queued',time.time()+delay,'전사 실패. 원본은 보관되어 있습니다.',row['rid'],row['seq']))


async def worker(publish):
    with connect() as db:db.execute("UPDATE chunks SET state='queued' WHERE state='processing'")
    while True:
        try:await tick(publish)
        except asyncio.CancelledError:raise
        except Exception:logging.getLogger(__name__).exception('Recording queue iteration failed')
        await asyncio.sleep(1)


def delete_recordings(mid=None, owner=None):
    with connect() as db:
        rows=db.execute('SELECT id FROM recordings WHERE mid=? OR owner=?',(mid,owner)).fetchall()
        for row in rows:db.execute('DELETE FROM chunks WHERE rid=?',(row['id'],));db.execute('DELETE FROM recordings WHERE id=?',(row['id'],))


async def reserve_upload(seconds):
    # File uploads and live sessions share the same account rate counters.
    while True:
        with connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if allowance(db,seconds):
                reserve('groq',max(10,seconds)/3600*.04*float(os.getenv('USD_KRW','1500')),{'audioSeconds':seconds,'source':'upload'})
                db.execute('INSERT INTO calls VALUES(?,?)',(time.time(),seconds))
                return
        await asyncio.sleep(2)
