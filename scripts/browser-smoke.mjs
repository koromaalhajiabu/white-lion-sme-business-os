import { chromium } from 'playwright';
import fs from 'node:fs';

const base = 'https://koromaalhajiabu.github.io/white-lion-sme-business-os/';
const report = { testedAt: new Date().toISOString(), base, browsers: [], summary: 'running' };

async function runViewport(name, viewport) {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport, serviceWorkers: 'block' });
  const page = await context.newPage();
  const result = { name, viewport, pageErrors: [], consoleErrors: [], failedRequests: [], checks: [] };
  page.on('pageerror', e => result.pageErrors.push(String(e.stack || e)));
  page.on('console', m => { if (m.type() === 'error') result.consoleErrors.push(m.text()); });
  page.on('requestfailed', r => result.failedRequests.push({url:r.url(), error:r.failure()?.errorText}));
  try {
    await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(8000);
    result.startup = await page.evaluate(() => ({
      title: document.title,
      ready: document.readyState,
      mainNavBound: !!window.__wlMainNavBound,
      startupComplete: !!window.__wlStartupComplete,
      startupError: window.__wlStartupError || null,
      scriptFailures: window.__wlScriptFail || [],
      currentCrumb: document.querySelector('#crumb')?.textContent || null,
      viewText: (document.querySelector('#view')?.innerText || '').slice(0,500),
      visibleOverlays: [...document.querySelectorAll('body *')].filter(el => {
        const s=getComputedStyle(el), r=el.getBoundingClientRect();
        return s.position==='fixed' && s.display!=='none' && s.visibility!=='hidden' && Number(s.opacity||1)>0 && r.width>=innerWidth*.8 && r.height>=innerHeight*.8;
      }).map(el=>({tag:el.tagName,id:el.id,cls:String(el.className).slice(0,100),z:getComputedStyle(el).zIndex,pointer:getComputedStyle(el).pointerEvents}))
    }));
    result.checks.push({name:'app loaded', pass:!!result.startup.startupComplete});
    result.checks.push({name:'main navigation listeners registered', pass:result.startup.mainNavBound});
    if (viewport.width < 720) {
      await page.locator('#menuBtn').click({timeout:5000}).catch(e=>result.checks.push({name:'mobile menu tap',pass:false,error:e.message}));
      await page.waitForTimeout(300);
    }
    for (const [key, expected] of [['products','Products'],['sales','Sales'],['purchases','Purchases'],['expenses','Expenses'],['settings','Business settings']]) {
      if (viewport.width < 720) {
        const sidebarOpen = await page.locator('#sidebar').evaluate(el => el.classList.contains('open'));
        if (!sidebarOpen) {
          await page.locator('#menuBtn').click({timeout:5000});
          await page.waitForTimeout(200);
        }
      }
      const button = page.locator('[data-page="'+key+'"]').first();
      const exists = await button.count();
      if (!exists) { result.checks.push({name:'navigate '+key,pass:false,error:'nav button missing'}); continue; }
      const box = await button.boundingBox();
      const hit = box ? await page.evaluate(({x,y}) => {
        const el=document.elementFromPoint(x,y);
        return {tag:el?.tagName,id:el?.id,cls:String(el?.className||'').slice(0,100),target:!!el?.closest('[data-page]')};
      }, {x:box.x+box.width/2,y:box.y+box.height/2}) : null;
      await button.click({timeout:5000}).catch(e=>result.checks.push({name:'tap '+key,pass:false,error:e.message,box,hit}));
      await page.waitForTimeout(700);
      const state = await page.evaluate(() => ({crumb:document.querySelector('#crumb')?.textContent||'', title:document.querySelector('#view h1')?.textContent||'', view:(document.querySelector('#view')?.innerText||'').slice(0,180)}));
      result.checks.push({name:'navigate '+key,pass:state.crumb.toLowerCase().includes(expected.toLowerCase().split(' ')[0]) || state.title.toLowerCase().includes(expected.toLowerCase().split(' ')[0]),state,box,hit});
    }
    const add = page.locator('#view #addBtn');
    if (await add.count()) {
      await add.click({timeout:5000}).catch(e=>result.checks.push({name:'open add-record form',pass:false,error:e.message}));
      await page.waitForTimeout(250);
      result.checks.push({name:'open add-record form',pass:await page.locator('#modalBack.show').count()>0});
    }
    result.final = await page.evaluate(() => ({
      crumb:document.querySelector('#crumb')?.textContent||'',
      mainNavBound:!!window.__wlMainNavBound,
      errors:window.__wlStartupError||null
    }));
  } catch (e) { result.fatal = String(e.stack || e); }
  await page.screenshot({path:'browser-'+name+'.png', fullPage:false}).catch(()=>{});
  await browser.close();
  report.browsers.push(result);
}

await runViewport('android-mobile',{width:390,height:844,isMobile:true,hasTouch:true});
await runViewport('desktop',{width:1365,height:900});
const all = report.browsers.flatMap(b=>b.checks);
report.summary = all.length && all.every(c=>c.pass) ? 'PASS' : 'FAIL';
report.failedChecks = all.filter(c=>!c.pass);
fs.writeFileSync('browser-smoke-report.json', JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
if (report.summary !== 'PASS') process.exitCode=1;
