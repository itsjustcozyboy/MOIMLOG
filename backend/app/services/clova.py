import os, json, httpx, asyncio, subprocess
from pathlib import Path

FORMATS={'.mp3','.aac','.ac3','.ogg','.flac','.wav','.m4a','.avi','.mp4','.mov','.wmv','.flv','.mkv'}
async def transcribe(path:Path):
    # ffprobe validates actual decodability and enforces sync API's 2-hour limit.
    process=await asyncio.create_subprocess_exec('ffprobe','-v','error','-show_entries','format=duration','-of','json',str(path),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    output,_=await process.communicate()
    if process.returncode:raise ValueError('지원되는 유효한 음성 파일이 아닙니다.')
    duration=float(json.loads(output)['format']['duration'])
    if not 0<duration<=7200:raise ValueError('음성은 2시간 이하여야 합니다.')
    params={'language':'ko-KR','completion':'sync','fullText':True,'wordAlignment':True,'diarization':{'enable':True}}
    async with httpx.AsyncClient(timeout=7500) as client:
        with path.open('rb') as f:
            res=await client.post(os.environ['CLOVA_SPEECH_INVOKE_URL'].rstrip('/')+'/recognizer/upload',headers={'X-CLOVASPEECH-API-KEY':os.environ['CLOVA_SPEECH_SECRET']},files={'media':(path.name,f)},data={'params':json.dumps(params)})
        res.raise_for_status(); result=res.json()
    if result.get('result')!='COMPLETED':raise ValueError('CLOVA 음성 변환을 완료하지 못했습니다.')
    segments=[{'speaker':'Speaker '+str(s['speaker']['label']) if s.get('speaker') else None,'text':s['text'],'start':s.get('start'),'end':s.get('end'),'timestamp':f"{s.get('start',0)//60000:02}:{s.get('start',0)//1000%60:02}"} for s in result.get('segments',[])]
    return {'text':result.get('text',''),'segments':segments,'sttMetadata':{k:result.get(k) for k in ['version','speakers','confidence','params']}}
