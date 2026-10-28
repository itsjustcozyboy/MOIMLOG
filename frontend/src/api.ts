export async function api<T=any>(path:string,method='GET',body?:unknown):Promise<T>{
 const form=body instanceof FormData;
 const res=await fetch('/api'+path,{method,credentials:'same-origin',headers:{'X-Moimlog':'1',...(!form&&body!==undefined?{'Content-Type':'application/json'}:{})},body:body===undefined?undefined:form?body:JSON.stringify(body)});
 if(!res.ok){const data=await res.json().catch(()=>null);throw new Error(typeof data?.detail==='string'?data.detail:res.status===401?'로그인이 필요합니다.':'요청을 처리하지 못했습니다. 입력 내용을 확인해 주세요.');}
 return res.json();
}
export function upload(path:string,file:File,onProgress:(n:number)=>void):Promise<any>{return new Promise((resolve,reject)=>{const xhr=new XMLHttpRequest();xhr.open('POST','/api'+path);xhr.setRequestHeader('X-Moimlog','1');xhr.upload.onprogress=e=>{if(e.lengthComputable)onProgress(Math.round(e.loaded/e.total*100));};xhr.onerror=()=>reject(new Error('연결이 끊겼습니다. 다시 시도해 주세요.'));xhr.onload=()=>{let d;try{d=JSON.parse(xhr.responseText);}catch{reject(new Error('서버 응답을 확인할 수 없습니다.'));return;}if(xhr.status>=200&&xhr.status<300)resolve(d);else reject(new Error(typeof d.detail==='string'?d.detail:'파일을 업로드하지 못했습니다.'));};const body=new FormData();body.append('file',file);xhr.send(body);});}
