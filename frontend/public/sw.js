// Network only for private data. Do not cache authenticated API responses or reports.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('fetch',event=>{if(event.request.method==='GET'&&event.request.mode==='navigate'){event.respondWith(fetch(event.request).catch(()=>new Response('<!doctype html><html lang="ko"><meta name="viewport" content="width=device-width"><title>모임록 · 오프라인</title><body style="font-family:sans-serif;padding:48px;background:#F6F8FC;color:#172033"><h2>잠시 연결이 끊겼어요.</h2><p>온라인으로 돌아오면 저장된 모임을 다시 열 수 있어요.</p><button onclick="location.reload()">다시 연결</button></body></html>',{headers:{'Content-Type':'text/html; charset=utf-8'}})));}});
