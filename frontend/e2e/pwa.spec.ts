import {expect, test} from '@playwright/test';

test('PWA assets, responsive home and offline navigation', async ({page, context})=>{
 await page.goto('/');
 const manifest = await page.request.get('/manifest.webmanifest');
 expect((await manifest.json()).display).toBe('standalone');
 expect((await page.request.get('/icon.svg')).ok()).toBeTruthy();
 await page.evaluate(()=>navigator.serviceWorker.ready.then(()=>undefined));
 await expect.poll(()=>page.evaluate(()=>Boolean(navigator.serviceWorker.controller))).toBe(true);
 for(const width of [320, 375, 430, 768, 1280]){
   await page.setViewportSize({width,height:800});
   await expect(page.getByRole('button',{name:'새 순모임 시작'})).toBeVisible();
   expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
 }
 await context.setOffline(true);
 await page.goto('/history');
 await expect(page.getByRole('heading',{name:'잠시 연결이 끊겼어요.'})).toBeVisible();
 await context.setOffline(false);
 await page.getByRole('button',{name:'다시 연결'}).click();
 await expect(page.getByRole('heading',{name:'기록을 위한 나만의 공간'})).toBeVisible();
});
