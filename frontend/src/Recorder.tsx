import {useState,useRef,useEffect} from 'react';
import {Mic,Pause,Play,Square,AlertCircle} from 'lucide-react';
import {api} from './api';
import {chunks,store,encodeWav,removeLocal} from './recordingStore';
import type {StoredChunk} from './recordingStore';
import type {Meeting} from './types';
type Status={budget?:{estimatedKrw:number;limitKrw:number};mode:string;ended:number;expected:number;complete:boolean;chunks:{seq:number;state:string;duration:number;error:string}[];segments:{start:number;timestamp:string;text:string}[]};
const stamp=(s:number)=>`${String(Math.floor(s/60)).padStart(2,'0')}:${String(Math.floor(s%60)).padStart(2,'0')}`;
export default function Recorder({mid,enabled,onComplete,busy}:{mid:string;enabled:boolean;onComplete:(m:Meeting)=>void;busy:boolean}){
 const [state,setState]=useState<'idle'|'starting'|'recording'|'paused'|'done'>('idle');
 const [seconds,setSeconds]=useState(0),[error,setError]=useState(''),[connection,setConnection]=useState('연결 확인 중'),[consent,setConsent]=useState(false),[mock,setMock]=useState(!enabled),[level,setLevel]=useState(0),[status,setStatus]=useState<Status|null>(null),[pending,setPending]=useState(0),[preview,setPreview]=useState(false),[caption,setCaption]=useState('');
 const stream=useRef<MediaStream|null>(null),context=useRef<AudioContext|null>(null),node=useRef<AudioWorkletNode|null>(null),sequence=useRef(0),syncing=useRef(false),active=useRef(false),ending=useRef(false),elapsed=useRef(0),mounted=useRef(true),log=useRef<HTMLDivElement>(null),speech=useRef<any>(null);
 const wakeLock=useRef<WakeLockSentinel|null>(null), captureStart=useRef(0);
 const writing=useRef<Promise<void>|null>(null);
 const unsaved=useRef<StoredChunk[]>([]);
 const base='/meetings/'+mid+'/recording';
 const supported=!!navigator.mediaDevices?.getUserMedia&&'AudioWorkletNode' in window;
 const Recognition=(window as any).SpeechRecognition||(window as any).webkitSpeechRecognition;
 async function keepScreenAwake(){
   if(!active.current||document.visibilityState!=='visible'||!navigator.wakeLock||wakeLock.current)return;
   try{
     const lock=await navigator.wakeLock.request('screen');
     if(!active.current||document.visibilityState!=='visible'){await lock.release();return;}
     wakeLock.current=lock;
     lock.addEventListener('release',()=>{if(wakeLock.current===lock)wakeLock.current=null;},{once:true});
   }catch{/* Recording remains available when the browser denies the lock. */}
 }
 function releaseScreen(){
   const lock=wakeLock.current;
   wakeLock.current=null;
   void lock?.release().catch(()=>{});
 }
 function persistPending(){
   if(!writing.current){
     writing.current=writePending().finally(()=>{writing.current=null;});
   }
   return writing.current;
 }
 async function writePending(){
   try{
     while(unsaved.current.length){
       await store(unsaved.current[0]);
       unsaved.current.shift();
     }
   }catch(e){
     if(mounted.current){pause();setError('기기 저장 실패. 이 화면을 유지하고 저장 공간을 확보해 주세요.');}
     throw e;
   }
 }
 async function sync(){if(syncing.current)return;syncing.current=true;try{
   await persistPending();
   const local=await chunks(mid);setPending(local.filter(c=>!c.sent).length);
   for(const c of local.filter(c=>!c.sent)){const f=new FormData();f.append('file',c.blob,'segment.wav');await api(base+'/chunks/'+c.seq,'PUT',f);await store({...c,sent:true});}
   if(ending.current&&unsaved.current.length===0&&(await chunks(mid)).every(c=>c.sent)){await api(base+'/end','POST',{count:sequence.current});ending.current=false;localStorage.removeItem('moimlog-end-'+mid);}
   const s=await api<Status>(base);if(mounted.current){setStatus(s);setConnection('서버 연결됨 · 원본 자동 저장');setPending((await chunks(mid)).filter(c=>!c.sent).length+unsaved.current.length);}
 }catch(e){if(mounted.current)setConnection('서버 미연결 또는 미생성 · 기기 저장분 재전송 대기');}finally{syncing.current=false;}}
 useEffect(()=>{mounted.current=true;let alive=true;
   (async()=>{try{const local=await chunks(mid);let remote:Status|null=null;try{remote=await api<Status>(base);}catch{}
     if(!alive)return;const count=Math.max(0,...local.map(c=>c.seq+1),...(remote?.chunks.map(c=>c.seq+1)||[]));sequence.current=count;ending.current=localStorage.getItem('moimlog-end-'+mid)!==null;
     const duration=new Map<number,number>();remote?.chunks.forEach(c=>duration.set(c.seq,c.duration));local.forEach(c=>duration.set(c.seq,c.duration));elapsed.current=[...duration.values()].reduce((a,b)=>a+b,0);setSeconds(elapsed.current);setStatus(remote);
     if(count||remote){setState(remote?.ended?'done':'paused');setMock(remote?remote.mode==='mock':localStorage.getItem('moimlog-mode-'+mid)==='mock');setError('저장된 녹음을 복구했습니다. 재개하거나 저장된 구간으로 종료해 주세요.');}await sync();
   }catch(e){setError('기기 저장소를 열 수 없습니다. 브라우저 저장 공간을 확인해 주세요.');}})();
   const visibility=()=>{
     if(document.visibilityState==='hidden'&&active.current){
       pause();
       setError('화면이 비활성화되어 녹음을 일시정지했습니다. 돌아오면 저장 구간을 확인하고 재개해 주세요.');
     }else void keepScreenAwake();
   };
   document.addEventListener('visibilitychange',visibility);
   const timer=setInterval(()=>void sync(),2500);const online=()=>void sync();window.addEventListener('online',online);
   const navigateGuard=(e:MouseEvent)=>{const target=e.target as Element;if(active.current&&target.closest('a,button')&&!target.closest('.recorder')){e.preventDefault();e.stopPropagation();setError('녹음을 먼저 일시정지하거나 종료해 주세요.');}};document.addEventListener('click',navigateGuard,true);
   const before=(e:BeforeUnloadEvent)=>{if(active.current||ending.current){e.preventDefault();}};window.addEventListener('beforeunload',before);
   return()=>{alive=false;mounted.current=false;clearInterval(timer);releaseScreen();document.removeEventListener('visibilitychange',visibility);window.removeEventListener('online',online);window.removeEventListener('beforeunload',before);document.removeEventListener('click',navigateGuard,true);node.current?.port.postMessage('stop');stream.current?.getTracks().forEach(t=>t.stop());void context.current?.close();speech.current?.abort();};
 },[mid]);
 useEffect(()=>{if(state!=='recording')return;const t=setInterval(()=>setSeconds(Math.min(7200,elapsed.current+(performance.now()-captureStart.current)/1000)),250);return()=>clearInterval(t);},[state]);
 useEffect(()=>{if(log.current&&log.current.scrollHeight-log.current.scrollTop-log.current.clientHeight<150)log.current.scrollTop=log.current.scrollHeight;},[status?.segments.length]);
 function stopPreview(){speech.current?.abort();speech.current=null;setCaption('');}
 function startPreview(){if(!preview||!Recognition)return;const r=new Recognition();speech.current=r;r.lang='ko-KR';r.continuous=true;r.interimResults=true;r.onresult=(event:any)=>setCaption(Array.from(event.results as any).map((x:any)=>x[0].transcript).join(' '));r.onerror=()=>setCaption('임시 자막이 중단되었습니다. Groq 전사는 계속됩니다.');try{r.start();}catch{setCaption('임시 자막을 시작하지 못했습니다.');}}
 async function capture(){
   stream.current=await navigator.mediaDevices.getUserMedia({audio:{channelCount:1,echoCancellation:true}});
   context.current=new AudioContext({sampleRate:16000});await context.current.resume();await context.current.audioWorklet.addModule('/pcm-worklet.js');
   node.current=new AudioWorkletNode(context.current,'pcm-capture',{processorOptions:{seconds:Math.max(0,7200-elapsed.current)}});const source=context.current.createMediaStreamSource(stream.current);source.connect(node.current);node.current.connect(context.current.destination);
   node.current.port.onmessage=({data})=>{
     if(data.level!==undefined)setLevel(Math.min(100,data.level*400));
     if(data.samples){const seq=sequence.current++;const blob=encodeWav(data.samples,data.rate);const chunk={key:mid+':'+seq,mid,seq,blob,duration:data.samples.length/data.rate,sent:false};unsaved.current.push(chunk);
       elapsed.current+=chunk.duration;
       captureStart.current=performance.now();
       if(mounted.current){setSeconds(elapsed.current);setPending(n=>n+1);}
       void persistPending().then(sync).catch(()=>{});
     }
     if(data.stopped){active.current=false;releaseScreen();if(mounted.current)setState('done');stopPreview();finish();stream.current?.getTracks().forEach(t=>t.stop());void context.current?.close();}
   };
   stream.current.getAudioTracks()[0].onended=()=>{if(active.current){pause();setError('마이크 연결이 끊겼습니다. 저장 구간을 확인하고 재개해 주세요.');}};
   context.current.onstatechange=()=>{if(context.current?.state!=='running'&&active.current){pause();setError('브라우저가 녹음을 중단했습니다. 화면을 켠 뒤 재개해 주세요.');}};
   active.current=true;captureStart.current=performance.now();setState('recording');startPreview();void keepScreenAwake();
 }
 async function start(){setState('starting');setError('');try{await chunks(mid);await navigator.storage?.persist?.();await api(base,'POST',{consent,mock});localStorage.setItem('moimlog-mode-'+mid,mock?'mock':'groq');await capture();}catch(e){setError('마이크 권한·HTTPS·서버 설정을 확인해 주세요. '+(e as Error).message);stream.current?.getTracks().forEach(t=>t.stop());void context.current?.close();setState(status?'paused':'idle');}}
 function pause(){node.current?.port.postMessage('pause');active.current=false;releaseScreen();setState('paused');stopPreview();}
 async function resume(){setError('');try{if(!node.current||context.current?.state==='closed'||!stream.current?.active)await start();else{await context.current?.resume();node.current.port.postMessage('resume');active.current=true;captureStart.current=performance.now();setState('recording');startPreview();void keepScreenAwake();}}catch(e){setError((e as Error).message);}}
 function finish(){ending.current=true;localStorage.setItem('moimlog-end-'+mid,String(sequence.current));void sync();}
 function stop(){active.current=false;releaseScreen();setState('done');stopPreview();if(node.current&&context.current?.state!=='closed')node.current.port.postMessage('stop');else finish();}
 return <div className="recorder">
 <label className="checkbox-row"><input type="checkbox" checked={consent} disabled={state==='recording'} onChange={e=>setConsent(e.target.checked)}/>모든 참석자가 녹음과 Groq 음성 전송에 동의했습니다.</label>
 {state==='idle'&&<label className="checkbox-row"><input type="checkbox" checked={mock} onChange={e=>setMock(e.target.checked)}/>Mock STT 체험 (음성 인식 없이 예시 문장 표시 · 외부 전송 없음)</label>}
 {Recognition&&<label className="checkbox-row"><input type="checkbox" checked={preview} disabled={state==='recording'} onChange={e=>setPreview(e.target.checked)}/>즉시 자막 미리보기 선택: 음성이 브라우저 제공업체의 외부 인식 서버로 전송될 수 있습니다. 저장하지 않으며 최종 전사는 Groq를 사용합니다.</label>}
 {!supported&&<p className="error-text">이 브라우저는 AudioWorklet 녹음을 지원하지 않습니다. 음성파일 업로드를 이용해 주세요.</p>}
 {error&&<p className="error-text" role="alert">{error}</p>}
 <div className={'recording-circle '+(state==='recording'?'recording':'')}><Mic size={32}/></div><div className="recording-timer">{stamp(seconds)}</div>
 <p role="status">{state==='recording'?'녹음 중 · 약 15초마다 전사':state==='paused'?'일시정지 · 저장 구간 보존':state==='done'?'녹음 종료 · 마지막 구간 처리 중':'마이크 사용 준비'}{mock?' · Mock 예시':''}</p>
 <meter aria-label="음성 입력 크기" min={0} max={100} value={state==='recording'?level:0}/><p className="field-hint">{connection} · 업로드 대기 {pending}개</p>
 <div className="button-row">{state==='idle'||state==='starting'?<button className="btn" disabled={!consent||!supported||busy||state==='starting'} onClick={start}><Mic size={17}/>녹음 시작</button>:state!=='done'?<><button className="btn secondary" disabled={!consent||seconds>=7200} onClick={state==='paused'?resume:pause}>{state==='paused'?<Play size={17}/>:<Pause size={17}/>} {state==='paused'?'재개':'일시정지'}</button><button className="btn" onClick={()=>{if(window.confirm('녹음을 종료하고 저장할까요?'))stop();}}><Square size={17}/>녹음 종료</button></>:null}</div>
 {caption&&<p className="temporary-caption">임시 자막 (미확정): {caption}</p>}
 <details><summary>나눔 전사문 보기 · 음성을 글자로 옮기는 데 시간이 걸려요</summary><div className="live-transcript" ref={log} role="log" aria-label="누적 전사문">{status?.segments.map((s,i)=><p key={i}><small>{s.timestamp} · 화자 미확인 · 확정{mock?' (Mock)':''}</small><br/>{s.text}</p>)}{!status?.segments.length&&<p>인식된 문장이 여기에 표시됩니다.</p>}</div>
 </details>
 {status?.budget&&<p className="field-hint">이번 달 전체 API 내부 예약액 {status.budget.estimatedKrw.toLocaleString()}원 / {status.budget.limitKrw.toLocaleString()}원 · 실제 청구액과 다를 수 있습니다.</p>}
 <p role="status">전사 {status?.chunks.filter(c=>c.state==='done').length||0} / {status?.chunks.length||0}구간 완료</p>
 {status?.chunks.filter(c=>c.state!=='done').map(c=><p className="field-hint" key={c.seq}>구간 {c.seq+1} · {({queued:'서버 저장 완료 · Groq 전사 대기',processing:'전사 중',failed:'전사 실패',budget:'예산 한도 도달'} as Record<string,string>)[c.state]} {c.error}</p>)}
 {status?.chunks.some(c=>['failed','budget'].includes(c.state))&&<button className="btn secondary" onClick={async()=>{try{await api(base+'/retry','POST');await sync();}catch(e){setError((e as Error).message);}}}>실패 구간 재시도</button>}
 {status?.complete&&<button className="btn" onClick={async()=>{try{const m=await api<Meeting>(base+'/review','POST');onComplete(m);}catch(e){setError((e as Error).message);}}}>최종 전사문 확인하기</button>}
 {status?.chunks.length? <details><summary>저장된 원본 WAV 구간 다운로드</summary>{status.chunks.map(c=><a key={c.seq} href={'/api'+base+'/audio/'+c.seq} download>구간 {c.seq+1} 다운로드 </a>)}{state==='done'&&pending===0&&<button className="btn secondary" onClick={async()=>{await removeLocal(mid);setError('이 기기의 복사본을 삭제했습니다. 서버 원본은 유지됩니다.');}}>이 기기의 저장된 복사본 삭제</button>}</details>:null}
 <div className="recorder-help"><AlertCircle size={16}/><span>최대 120분 · 기기와 서버에 원본 구간 보관. STT 실패 시에도 녹음은 계속됩니다. 화면을 켜 두세요. 탭 종료 시 아직 저장되지 않은 최대 15초는 복구할 수 없습니다. 일시정지·재개 시 짧은 구간에도 최소 10초가 무료 사용량 한도에 반영될 수 있습니다.</span></div>
 </div>;
}
