import {request, expect} from '@playwright/test';

export async function issueTestInvite(baseURL: string){
 const admin = await request.newContext({baseURL, extraHTTPHeaders:{'X-Moimlog':'1'}});
 try{
   expect((await admin.post('/api/auth/login',{
     data:{email:'e2e-admin@example.test', password:'local-test-admin-123'},
   })).ok()).toBeTruthy();
   const invite = await admin.post('/api/admin/invitations');
   expect(invite.ok()).toBeTruthy();
   return (await invite.json()).token as string;
 }finally{await admin.dispose();}
}
