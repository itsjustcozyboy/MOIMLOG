import os, json, uuid, time, secrets, hashlib, asyncio, shutil
from pathlib import Path
from contextlib import asynccontextmanager
from dotenv import load_dotenv
load_dotenv()
from fastapi import FastAPI, HTTPException, Request, Response, Depends, UploadFile, File, BackgroundTasks
from fastapi.responses import StreamingResponse
from sqlalchemy import select, delete
from pwdlib import PasswordHash
from .db import SessionLocal, User, AuthSession, Meeting, DATA
from .schemas import MeetingInput, Credentials, SettingsInput, TranscriptInput, SpeakerInput, AnalysisInput, ReportUpdate
from .services.transcript import parse_transcript
from .services.ai_analysis import analyze, validate_people
from .services.docx_generator import generate
from .services.groq import transcribe, FORMATS

password_hash=PasswordHash.recommended()
TASKS=set()
def dump(v):return json.dumps(v,ensure_ascii=False,default=str)
def uid():return str(uuid.uuid4())
def folder(user_id):
    path=DATA/user_id;path.mkdir(exist_ok=True);return path

def cleanup():
    with SessionLocal() as db:
        now=int(time.time())
        db.execute(delete(AuthSession).where(AuthSession.expires<now))
        for u in db.scalars(select(User)):
            days=json.loads(u.settings).get('retentionDays',90)
            for m in db.scalars(select(Meeting).where(Meeting.user_id==u.id,Meeting.updated<now-days*86400)):
                for p in folder(u.id).glob(m.id+'.*'):p.unlink(missing_ok=True)
                live.delete_recordings(mid=m.id)
                db.delete(m)
        db.commit()

@asynccontextmanager
async def lifespan(app):
    cleanup()
    with SessionLocal() as db:
        for m in db.scalars(select(Meeting)):
            d=json.loads(m.data)
            if d.get('job',{}).get('state')=='processing':
                d['job']={'state':'failed','error':'서버가 재시작되었습니다. 다시 시도해 주세요.'};m.data=dump(d)
        db.commit()
    async def periodic():
        while True:
            await asyncio.sleep(3600);cleanup()
    task=asyncio.create_task(periodic())
    live_task=asyncio.create_task(live.worker(publish_live))
    yield
    task.cancel()
    live_task.cancel()
    for t in TASKS:t.cancel()

app=FastAPI(title='MOIMLOG API',lifespan=lifespan)
@app.middleware('http')
async def security(request,call_next):
    if request.method not in ['GET','HEAD','OPTIONS'] and request.headers.get('x-moimlog')!='1':
        return Response('요청 출처를 확인할 수 없습니다.',status_code=403)
    response=await call_next(request)
    response.headers['Cache-Control']='no-store'
    response.headers['X-Content-Type-Options']='nosniff'
    response.headers['Referrer-Policy']='same-origin'
    return response

def current(request:Request):
    token=request.cookies.get('moimlog_session','')
    with SessionLocal() as db:
        s=db.get(AuthSession,hashlib.sha256(token.encode()).hexdigest())
        if not s or s.expires<int(time.time()):raise HTTPException(401,'로그인해 주세요.')
        user=db.get(User,s.user_id)
        return {'id':user.id,'email':user.email,**json.loads(user.settings)}

def owned(mid,user):
    with SessionLocal() as db:
        m=db.get(Meeting,mid)
        if not m or m.user_id!=user['id']:raise HTTPException(404,'보고서를 찾을 수 없습니다.')
        return {'id':m.id,**json.loads(m.data),'updated':m.updated}

def save(mid,user,data):
    with SessionLocal() as db:
        m=db.get(Meeting,mid)
        if not m or m.user_id!=user['id']:raise HTTPException(404,'보고서를 찾을 수 없습니다.')
        data={k:v for k,v in data.items() if k not in ['id','updated']}
        m.data=dump(data);m.updated=int(time.time());db.commit()
    return owned(mid,user)

def idle(d):
    if d.get('id'):
        with live.connect() as db:r=db.execute('SELECT id FROM recordings WHERE mid=?',(d['id'],)).fetchone()
        if r and not live.status(r['id'])['complete']:raise HTTPException(409,'진행 중인 녹음의 저장과 전사를 먼저 완료해 주세요.')
    if d.get('job',{}).get('state')=='processing':raise HTTPException(409,'처리 중입니다. 완료 후 수정해 주세요.')

def session(response,user_id):
    token=secrets.token_urlsafe(48)
    with SessionLocal() as db:
        db.add(AuthSession(token=hashlib.sha256(token.encode()).hexdigest(),user_id=user_id,expires=int(time.time())+7*86400));db.commit()
    response.set_cookie('moimlog_session',token,httponly=True,samesite='lax',secure=os.getenv('COOKIE_SECURE','false').lower()=='true',max_age=7*86400,path='/')

ATTEMPTS={}
@app.post('/api/auth/login')
@app.post('/api/auth/register')
def auth(body:Credentials,response:Response,request:Request):
    action=request.url.path.rsplit('/',1)[-1]
    if action not in ['login','register']:raise HTTPException(404)
    key=request.client.host;now=time.time();ATTEMPTS[key]=[t for t in ATTEMPTS.get(key,[]) if now-t<300]
    if len(ATTEMPTS[key])>=20:raise HTTPException(429,'잠시 후 다시 시도해 주세요.')
    ATTEMPTS[key].append(now)
    with SessionLocal() as db:
        email=body.email.strip().lower()
        user=db.scalar(select(User).where(User.email==email))
        if action=='register':
            if '@' not in email or user:raise HTTPException(400,'이메일을 확인하거나 로그인해 주세요.')
            user=User(id=uid(),email=email,password=password_hash.hash(body.password),settings=dump({'name':body.name,'community':'','isLeader':True,'members':[],'retentionDays':90}))
            db.add(user);db.commit()
        elif not user or not password_hash.verify(body.password,user.password):raise HTTPException(401,'이메일 또는 비밀번호를 확인해 주세요.')
        session(response,user.id)
    return {'ok':True}

@app.post('/api/auth/logout')
def logout(request:Request,response:Response):
    token=request.cookies.get('moimlog_session','')
    with SessionLocal() as db:
        db.execute(delete(AuthSession).where(AuthSession.token==hashlib.sha256(token.encode()).hexdigest()));db.commit()
    response.delete_cookie('moimlog_session');return {'ok':True}

@app.get('/api/config')
def config():
    return {'ai':bool(os.getenv('OPENAI_API_KEY')),'speech':bool(os.getenv('GROQ_API_KEY') and shutil.which('ffprobe') and shutil.which('ffmpeg')),'maxAudioMB':100,'maxTextMB':2,'maxAudioMinutes':120}
@app.get('/api/me')
def me(user=Depends(current)):return user
@app.put('/api/me')
def update_me(body:SettingsInput,user=Depends(current)):
    with SessionLocal() as db:
        u=db.get(User,user['id']);u.settings=body.model_dump_json();db.commit()
    cleanup();return {'id':user['id'],'email':user['email'],**body.model_dump()}
@app.delete('/api/me')
def delete_me(user=Depends(current)):
    with SessionLocal() as db:
        db.execute(delete(Meeting).where(Meeting.user_id==user['id']));db.execute(delete(AuthSession).where(AuthSession.user_id==user['id']));db.execute(delete(User).where(User.id==user['id']));db.commit()
    live.delete_recordings(owner=user['id'])
    shutil.rmtree(DATA/user['id'],ignore_errors=True);return {'ok':True}

@app.post('/api/meetings')
def create(body:MeetingInput,user=Depends(current)):
    mid=uid();data={**body.model_dump(mode='json'),'status':'draft','text':'','segments':[],'mapping':{},'job':{'state':'idle'}}
    with SessionLocal() as db:
        db.add(Meeting(id=mid,user_id=user['id'],data=dump(data),updated=int(time.time())));db.commit()
    return owned(mid,user)
@app.get('/api/meetings')
def meetings(user=Depends(current)):
    with SessionLocal() as db:
        return [{'id':m.id,**{k:v for k,v in json.loads(m.data).items() if k in ['meetingDate','title','leader','participants','status','step','mode']}} for m in db.scalars(select(Meeting).where(Meeting.user_id==user['id']).order_by(Meeting.updated.desc()))]
@app.get('/api/meetings/{mid}')
def get_meeting(mid:str,user=Depends(current)):return owned(mid,user)
@app.patch('/api/meetings/{mid}')
def patch(mid:str,body:MeetingInput,user=Depends(current)):
    d=owned(mid,user);idle(d)
    incoming=body.model_dump(mode='json')
    if any(d.get(k)!=v for k,v in incoming.items() if k!='step'):
        d.pop('report',None);d['status']='draft'
        ids={p['id'] for p in incoming['participants']};d['mapping']={k:v if v in ids or v=='OTHER' else None for k,v in d.get('mapping',{}).items()}
    d.update(incoming);return save(mid,user,d)
@app.delete('/api/meetings/{mid}')
def delete_meeting(mid:str,user=Depends(current)):
    d=owned(mid,user)
    with SessionLocal() as db:db.execute(delete(Meeting).where(Meeting.id==mid));db.commit()
    live.delete_recordings(mid=mid)
    for p in folder(user['id']).glob(mid+'.*'):p.unlink(missing_ok=True)
    return {'ok':True}

async def read_upload(file,limit):
    buf=bytearray()
    while chunk:=await file.read(1024*1024):
        buf.extend(chunk)
        if len(buf)>limit:raise HTTPException(413,'파일 크기 제한을 초과했습니다.')
    if not buf:raise HTTPException(400,'빈 파일입니다.')
    return bytes(buf)

@app.post('/api/meetings/{mid}/upload')
async def upload(mid:str,file:UploadFile=File(...),user=Depends(current)):
    d=owned(mid,user);idle(d);ext=Path(file.filename or '').suffix.lower()
    if ext=='.txt':
        raw=await read_upload(file,2*1024*1024)
        try:text=raw.decode('utf-8-sig')
        except UnicodeDecodeError:raise HTTPException(400,'UTF-8로 저장한 TXT를 올려 주세요.')
        if '\x00' in text or not text.strip() or len(text)>1000000:raise HTTPException(400,'유효한 TXT 전사문이 필요합니다. 최대 100만 자입니다.')
        d.update(text=text,segments=parse_transcript(text),mapping={},step=3,status='draft')
    elif ext in FORMATS:
        if not config()['speech']:raise HTTPException(503,'Groq 설정이 필요합니다. TXT 업로드를 이용해 주세요.')
        raw=await read_upload(file,100*1024*1024)
        for p in folder(user['id']).glob(mid+'.audio.*'):p.unlink(missing_ok=True)
        path=folder(user['id'])/(mid+'.audio'+ext);path.write_bytes(raw);d['audio']=path.name
    else:raise HTTPException(400,'지원되지 않는 파일 형식입니다. WebM 녹음은 지원하지 않습니다. MP4 또는 WAV를 사용해 주세요.')
    d.pop('report',None);return save(mid,user,d)

@app.put('/api/meetings/{mid}/transcription')
def edit_transcript(mid:str,body:TranscriptInput,user=Depends(current)):
    d=owned(mid,user);idle(d);segments=parse_transcript(body.text)
    d.update(text=body.text,segments=segments,mapping={k:v for k,v in d.get('mapping',{}).items() if k in {s['speaker'] for s in segments}},status='draft');d.pop('report',None)
    return save(mid,user,d)
@app.get('/api/meetings/{mid}/transcription')
def transcription(mid:str,user=Depends(current)):
    d=owned(mid,user);return {k:d.get(k) for k in ['text','segments','job','sttMetadata']}
@app.put('/api/meetings/{mid}/speakers')
def speakers(mid:str,body:SpeakerInput,user=Depends(current)):
    d=owned(mid,user);idle(d);keys={s['speaker'] for s in d.get('segments',[]) if s['speaker']};ids={p['id'] for p in d['participants']}|{'OTHER',None}
    if set(body.mapping)-keys or any(v not in ids for v in body.mapping.values()):raise HTTPException(422,'잘못된 화자 또는 참석자 ID입니다.')
    if d.get('mapping')!=body.mapping:d.pop('report',None);d['status']='draft'
    d['mapping']=body.mapping;return save(mid,user,d)

async def worker(mid,user,kind,mode=None):
    try:
        d=owned(mid,user)
        if kind=='analysis':
            r=await analyze(d,mode);d.update(report=r.model_dump(),status='review',mode=mode,step=6)
        else:
            result=await transcribe(folder(user['id'])/d['audio']);d.update(result)
            d['text']='\n'.join(f"{s['speaker'] or '미확인'} [{s['timestamp']}]: {s['text']}" for s in result['segments']);d['mapping']={};d['step']=3
            (folder(user['id'])/d['audio']).unlink(missing_ok=True);d.pop('audio',None)
        d['job']={'state':'done','kind':kind};save(mid,user,d)
    except asyncio.CancelledError:raise
    except Exception as e:
        try:
            d=owned(mid,user);d['job']={'state':'failed','kind':kind,'error':str(e) if isinstance(e,ValueError) else '처리에 실패했습니다. 설정과 파일을 확인하고 다시 시도해 주세요.'};save(mid,user,d)
        except Exception:pass

def launch(mid,user,d,kind,mode=None):
    idle(d);d['job']={'state':'processing','kind':kind};save(mid,user,d)
    task=asyncio.create_task(worker(mid,user,kind,mode));TASKS.add(task);task.add_done_callback(TASKS.discard)
    return {'state':'processing'}
@app.post('/api/meetings/{mid}/analyze')
async def analysis(mid:str,body:AnalysisInput,user=Depends(current)):
    d=owned(mid,user)
    if not d.get('segments'):raise HTTPException(400,'전사문을 먼저 업로드해 주세요.')
    if body.mode=='ai' and (not body.consent or not config()['ai']):raise HTTPException(400,'OpenAI 설정 및 외부 전송 동의가 필요합니다.')
    return launch(mid,user,d,'analysis',body.mode)
@app.post('/api/meetings/{mid}/transcribe')
async def stt(mid:str,body:AnalysisInput,user=Depends(current)):
    d=owned(mid,user)
    if not body.consent:raise HTTPException(400,'참석자 녹음 및 외부 전송 동의가 필요합니다.')
    if not d.get('audio') or not config()['speech']:raise HTTPException(400,'음성 파일과 Groq 설정을 확인해 주세요.')
    return launch(mid,user,d,'stt')
@app.get('/api/meetings/{mid}/report')
def report(mid:str,user=Depends(current)):
    d=owned(mid,user)
    if not d.get('report'):raise HTTPException(404,'보고서 초안이 없습니다.')
    return d['report']
@app.put('/api/meetings/{mid}/report')
def update_report(mid:str,body:ReportUpdate,user=Depends(current)):
    d=owned(mid,user);idle(d)
    if {p.participantId for p in body.report.participants}!={p['id'] for p in d['participants']} or len(body.report.participants)!=len(d['participants']):raise HTTPException(422,'참석자 ID를 확인해 주세요.')
    d['report']=body.report.model_dump();d['status']='complete' if body.complete else 'review';d['step']=7 if body.complete else 6
    return save(mid,user,d)

def template_path(user):
    personal=folder(user['id'])/'template.docx'
    if personal.exists():return personal
    import unicodedata
    directory=Path('backend/templates')
    expected='26_순보고서.docx'
    # macOS uploads may use decomposed Hangul filenames on Linux filesystems.
    return next((p for p in directory.glob('*.docx') if unicodedata.normalize('NFC',p.name)==expected),directory/expected)
# Live capture uses authenticated, idempotent sequence uploads.
from .services import live
from pydantic import BaseModel, Field
class LiveStart(BaseModel):
    consent: bool
    mock: bool = False
class LiveEnd(BaseModel):
    count: int = Field(ge=0,le=10000)

def live_owned(mid,user):
    owned(mid,user)
    with live.connect() as db:r=db.execute('SELECT * FROM recordings WHERE mid=? AND owner=?',(mid,user['id'])).fetchone()
    if not r:raise HTTPException(404,'녹음 세션이 없습니다.')
    return dict(r)

def publish_live(mid,user,s):
    d=owned(mid,user)
    d.update(segments=s['segments'],text='\n'.join(f"화자 미확인 [{x['timestamp']}]: {x['text']}" for x in s['segments']),mapping={},sttMetadata={'provider':s['mode'],'diarization':False},status='draft')
    d.pop('report',None)
    save(mid,user,d)

@app.post('/api/meetings/{mid}/recording')
def start_live(mid:str,body:LiveStart,user=Depends(current)):
    d=owned(mid,user)
    if d.get('job',{}).get('state')=='processing':raise HTTPException(409,'기존 작업 처리 중입니다.')
    if not body.consent:raise HTTPException(400,'녹음 및 Groq 전송 동의가 필요합니다.')
    if not body.mock and not os.getenv('GROQ_API_KEY'):raise HTTPException(503,'Groq 키가 없습니다. Mock 체험을 선택해 주세요.')
    return live.create(mid,user['id'],'mock' if body.mock else 'groq')

@app.get('/api/meetings/{mid}/recording')
def get_live(mid:str,user=Depends(current)):
    from .services.budget import summary
    return {**live.status(live_owned(mid,user)['id']), 'budget':summary()}

@app.put('/api/meetings/{mid}/recording/chunks/{seq}')
async def chunk_live(mid:str,seq:int,file:UploadFile=File(...),user=Depends(current)):
    r=live_owned(mid,user);raw=await read_upload(file,3*1024*1024)
    try:live.put(r['id'],seq,raw)
    except ValueError as e:raise HTTPException(409,str(e))
    return {'saved':seq}

@app.post('/api/meetings/{mid}/recording/end')
def end_live(mid:str,body:LiveEnd,user=Depends(current)):
    r=live_owned(mid,user)
    with live.connect() as db:
        maximum=db.execute('SELECT MAX(seq) FROM chunks WHERE rid=?',(r['id'],)).fetchone()[0]
        if (maximum is not None and maximum>=body.count) or (r['ended'] and r['expected']!=body.count):raise HTTPException(409,'종료 구간 수가 일치하지 않습니다.')
        db.execute('UPDATE recordings SET ended=1,expected=? WHERE id=?',(body.count,r['id']))
    s=live.status(r['id']);publish_live(mid,user,s);return s

@app.post('/api/meetings/{mid}/recording/retry')
def retry_live(mid:str,user=Depends(current)):
    r=live_owned(mid,user)
    with live.connect() as db:db.execute("UPDATE chunks SET state='queued',attempts=0,available=0 WHERE rid=? AND state IN ('failed','budget')",(r['id'],))
    return {'ok':True}

@app.post('/api/meetings/{mid}/recording/review')
def review_live(mid:str,user=Depends(current)):
    r=live_owned(mid,user);s=live.status(r['id'])
    if not s['complete']:raise HTTPException(409,'모든 구간의 저장과 전사를 마친 뒤 검토할 수 있습니다.')
    publish_live(mid,user,s);d=owned(mid,user);d['step']=3;return save(mid,user,d)

@app.get('/api/meetings/{mid}/recording/audio/{seq}')
def audio_live(mid:str,seq:int,user=Depends(current)):
    r=live_owned(mid,user)
    with live.connect() as db:row=db.execute('SELECT audio FROM chunks WHERE rid=? AND seq=?',(r['id'],seq)).fetchone()
    if not row:raise HTTPException(404)
    return Response(row['audio'],media_type='audio/wav',headers={'Content-Disposition':f'attachment; filename="recording-{seq:05}.wav"'})

@app.get('/api/template')
def template_status(user=Depends(current)):return {'exists':template_path(user).exists(),'name':'26_순보고서.docx'}
@app.post('/api/template')
async def upload_template(file:UploadFile=File(...),user=Depends(current)):
    if Path(file.filename or '').suffix.lower()!='.docx':raise HTTPException(400,'DOCX 파일을 선택해 주세요.')
    raw=await read_upload(file,10*1024*1024)
    try:
        import zipfile, io
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            if sum(i.file_size for i in z.infolist())>50*1024*1024:raise ValueError()
        from docx import Document
        doc=Document(io.BytesIO(raw))
        if not doc.tables:raise ValueError()
    except Exception:raise HTTPException(400,'표가 포함된 유효한 DOCX 원본이 필요합니다.')
    (folder(user['id'])/'template.docx').write_bytes(raw);return {'exists':True}
@app.post('/api/meetings/{mid}/generate-docx')
def docx(mid:str,user=Depends(current)):
    d=owned(mid,user)
    if not d.get('report'):raise HTTPException(400,'보고서를 먼저 작성해 주세요.')
    try:raw=generate(template_path(user),d)
    except ValueError as e:raise HTTPException(422,str(e))
    path=folder(user['id'])/(mid+'.docx');path.write_bytes(raw)
    return {'url':f'/api/meetings/{mid}/download'}
@app.get('/api/meetings/{mid}/download')
def download(mid:str,user=Depends(current)):
    d=owned(mid,user)
    # Always regenerate from the latest reviewed report; never serve a stale artifact.
    if not d.get('report'):raise HTTPException(400,'보고서가 없습니다.')
    try:raw=generate(template_path(user),d)
    except ValueError as e:raise HTTPException(422,str(e))
    return Response(raw,media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document',headers={'Content-Disposition':f'attachment; filename="{d["meetingDate"]}_moim_report.docx"'})

# Production SPA is served on the same origin as the API after `npm run build`.
from fastapi.responses import FileResponse
DIST=Path(__file__).resolve().parents[2]/'frontend'/'dist'
@app.get('/{path:path}', include_in_schema=False)
def web(path:str):
    if path.startswith('api/') or path=='api':raise HTTPException(404,'API를 찾을 수 없습니다.')
    if not (DIST/'index.html').exists():raise HTTPException(404,'프런트엔드를 빌드하거나 5173 포트에 접속해 주세요.')
    target=(DIST/path).resolve()
    if not target.is_relative_to(DIST.resolve()):raise HTTPException(404)
    return FileResponse(target if target.is_file() else DIST/'index.html')
