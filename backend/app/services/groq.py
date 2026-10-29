import os, json, asyncio, tempfile
from pathlib import Path
import httpx
from .budget import reserve
FORMATS={'.mp3','.aac','.ogg','.flac','.wav','.m4a','.mp4','.webm','.opus','.mov','.mkv'}
async def run(*args):
    p=await asyncio.create_subprocess_exec(*args,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE)
    out,_=await p.communicate()
    if p.returncode: raise ValueError('음성 디코딩에 실패했습니다.')
    return out
async def transcribe(path:Path):
    probe=json.loads(await run('ffprobe','-v','error','-show_entries','format=duration','-of','json',str(path)))
    duration=float(probe['format']['duration'])
    if not 0<duration<=7201: raise ValueError('음성은 최대 2시간입니다.')
    segments=[]
    with tempfile.TemporaryDirectory() as tmp:
        await run('ffmpeg','-v','error','-i',str(path),'-vn','-ac','1','-ar','16000','-c:a','libmp3lame','-b:a','32k','-f','segment','-segment_time','600',tmp+'/%03d.mp3')
        async with httpx.AsyncClient(timeout=180) as client:
            offset=0.
            for part in sorted(Path(tmp).glob('*.mp3')):
                seconds=float(json.loads(await run('ffprobe','-v','error','-show_entries','format=duration','-of','json',str(part)))['format']['duration'])
                if part.stat().st_size>24*1024*1024: raise ValueError('압축 파일이 API 제한을 초과했습니다.')
                from .live import reserve_upload
                await reserve_upload(seconds)
                with part.open('rb') as f:
                    response=await client.post('https://api.groq.com/openai/v1/audio/transcriptions',headers={'Authorization':'Bearer '+os.environ['GROQ_API_KEY']},files={'file':(part.name,f)},data={'model':'whisper-large-v3-turbo','language':'ko','response_format':'verbose_json'})
                response.raise_for_status()
                result=response.json()
                for s in result.get('segments') or [{'text':result.get('text',''),'start':0,'end':seconds}]:
                    start=offset+s.get('start',0)
                    segments.append({'speaker':None,'text':s['text'],'start':round(start*1000),'end':round((offset+s.get('end',seconds))*1000),'timestamp':f'{int(start)//60:02}:{int(start)%60:02}'})
                offset+=seconds
    return {'text':'\n'.join(s['text'] for s in segments),'segments':segments,'sttMetadata':{'provider':'groq','model':'whisper-large-v3-turbo','duration':duration,'diarization':'unverified; manual confirmation required'}}
