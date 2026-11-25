import {useState} from 'react';
import {useQuery, useQueryClient} from '@tanstack/react-query';
import {api} from './api';

type Invite = {id: string; expires: number; state: string};

export default function Invitations(){
 const qc = useQueryClient();
 const invites = useQuery({queryKey:['invitations'], queryFn:()=>api<Invite[]>('/admin/invitations')});
 const [link,setLink] = useState('');
 const [error,setError] = useState('');
 const [busy,setBusy] = useState(false);
 async function change(id?:string){
   setError('');
   setBusy(true);
   try{
     if(id){
       await api('/admin/invitations/'+id,'DELETE');
       setLink('');
     }else{
       const invite = await api<{token:string}>('/admin/invitations','POST');
       setLink(new URL('/#invite='+encodeURIComponent(invite.token),window.location.origin).href);
     }
     await qc.invalidateQueries({queryKey:['invitations']});
   }catch(e){setError((e as Error).message);}
   finally{setBusy(false);}
 }
 return <section className="card settings-card">
   <h2>초대 관리</h2>
   <button className="btn" disabled={busy} onClick={()=>void change()}>24시간 초대 링크 발급</button>
   {link&&<label>새 초대 링크<input value={link} readOnly onFocus={e=>e.currentTarget.select()}/></label>}
   {error&&<p role="alert">{error}</p>}
   {invites.isLoading&&<p role="status">초대를 불러오는 중입니다.</p>}
   {invites.isError&&<button onClick={()=>void invites.refetch()}>초대 다시 불러오기</button>}
   {invites.data?.map(invite=><p key={invite.id}>
     {new Date(invite.expires*1000).toLocaleString('ko-KR')} · {({pending:'사용 가능',used:'사용 완료',expired:'만료',revoked:'취소'})[invite.state]}
     {invite.state==='pending'&&<button className="btn secondary" disabled={busy} onClick={()=>void change(invite.id)}>취소</button>}
   </p>)}
 </section>;
}
