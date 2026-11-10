import { chromium } from 'playwright';
import fs from 'node:fs';

const base = process.env.WHITE_LION_SMOKE_URL || 'https://koromaalhajiabu.github.io/white-lion-sme-business-os/';
const report = { testedAt: new Date().toISOString(), base, browsers: [], summary: 'running' };

async function runViewport(name, viewport) {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport, serviceWorkers: 'allow' });
  const page = await context.newPage();
  const result = { name, viewport, pageErrors: [], consoleErrors: [], failedRequests: [], checks: [] };
  page.on('pageerror', e => result.pageErrors.push(String(e.stack || e)));
  page.on('console', m => { if (m.type() === 'error') result.consoleErrors.push(m.text()); });
  page.on('requestfailed', r => result.failedRequests.push({url:r.url(), error:r.failure()?.errorText}));
  try {
    await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(4000);
    await page.evaluate(async () => { if ('serviceWorker' in navigator) await navigator.serviceWorker.ready; });
    await page.reload({ waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(5000);
    result.startup = await page.evaluate(() => ({
      title: document.title,
      ready: document.readyState,
      mainNavBound: !!window.__wlMainNavBound,
      startupComplete: !!window.__wlStartupComplete,
      startupError: window.__wlStartupError || null,
      scriptFailures: window.__wlScriptFail || [],
      serviceWorkerControlled: !!navigator.serviceWorker?.controller,
      serviceWorkerScript: navigator.serviceWorker?.controller?.scriptURL || null,
      currentCrumb: document.querySelector('#crumb')?.textContent || null,
      viewText: (document.querySelector('#view')?.innerText || '').slice(0,500),
      visibleOverlays: [...document.querySelectorAll('body *')].filter(el => {
        const s=getComputedStyle(el), r=el.getBoundingClientRect();
        return s.position==='fixed' && s.display!=='none' && s.visibility!=='hidden' && Number(s.opacity||1)>0 && r.width>=innerWidth*.8 && r.height>=innerHeight*.8;
      }).map(el=>({tag:el.tagName,id:el.id,cls:String(el.className).slice(0,100),z:getComputedStyle(el).zIndex,pointer:getComputedStyle(el).pointerEvents}))
    }));
    result.checks.push({name:'app loaded', pass:!!result.startup.startupComplete});
    result.checks.push({name:'service worker controls app after reload', pass:!!result.startup.serviceWorkerControlled, state:result.startup.serviceWorkerScript});
    result.checks.push({name:'main navigation listeners registered', pass:result.startup.mainNavBound});
    // Exercise the new planner directly as the public smoke runner has no authenticated workspace.
    await page.evaluate(() => window.setPage('reorder'));
    await page.waitForTimeout(700);
    const reorderView = await page.locator('#view').innerText();
    result.checks.push({name:'Smart Reorder Planner renders',pass:reorderView.includes('Demand forecast & reorder queue') && reorderView.includes('Suggested order')});
    await page.evaluate(() => window.setPage('dashboard'));
    await page.waitForTimeout(300);
    if (viewport.width < 720) {
      await page.locator('#menuBtn').click({timeout:5000}).catch(e=>result.checks.push({name:'mobile menu tap',pass:false,error:e.message}));
      await page.waitForTimeout(300);
    }
    for (const [key, expected] of [['products','Products'],['sales','Sales'],['purchases','Purchases'],['expenses','Expenses'],['actions','Executive Action Centre'],['reorder','Smart Reorder Planner'],['finance','Financial Planning'],['billing','Plans & Billing'],['settings','Business settings']]) {
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
      if (key === 'actions') {
        const actionText = await page.locator('#view').innerText();
        for (const section of ['Management alerts','Management tasks','Branch performance','Stock replenishment recommendations','Investigate recent sales','Executive activity']) {
          result.checks.push({name:'action centre section: '+section,pass:actionText.includes(section)});
        }
      }
    }
    // Exercise a real in-section action, not just sidebar navigation.
    if (viewport.width < 720) {
      await page.locator('#menuBtn').click().catch(()=>{});
      await page.waitForTimeout(150);
    }
    await page.locator('[data-page="products"]').click({timeout:5000});
    await page.waitForTimeout(500);
    const add = page.locator('#view #addBtn');
    if (await add.count()) {
      await add.scrollIntoViewIfNeeded();
      await add.click({timeout:5000}).catch(e=>result.checks.push({name:'open product form',pass:false,error:e.message}));
      await page.waitForTimeout(250);
      result.checks.push({name:'open product form',pass:await page.locator('#modalBack.show').count()>0});
      if (await page.locator('#modalBack.show').count()) {
        await page.locator('#cancelModal').click();
        result.checks.push({name:'close product form',pass:await page.locator('#modalBack.show').count()===0});
      }
    } else {
      result.checks.push({name:'open product form',pass:false,error:'Add product button missing'});
    }

    // Verify dashboard quick actions route to the expected module.
    if (viewport.width < 720) {
      await page.locator('#menuBtn').click().catch(()=>{});
      await page.waitForTimeout(150);
    }
    await page.locator('[data-page="dashboard"]').click({timeout:5000});
    await page.waitForTimeout(400);
    const quick = page.locator('#view [data-go="products"]').first();
    if (await quick.count()) {
      await quick.click({timeout:5000});
      await page.waitForTimeout(400);
      const quickState = await page.locator('#crumb').textContent();
      result.checks.push({name:'dashboard quick action opens products',pass:(quickState||'').toLowerCase().includes('products'),state:quickState});
    } else {
      result.checks.push({name:'dashboard quick action opens products',pass:false,error:'Quick action missing'});
    }

    // Appearance controls must respond to taps without disrupting navigation.
    const beforeTheme = await page.locator('html').getAttribute('data-theme');
    const themeButton = page.locator('#themeToggle');
    if (await themeButton.count()) {
      await themeButton.click({timeout:5000});
      const afterTheme = await page.locator('html').getAttribute('data-theme');
      result.checks.push({name:'appearance toggle responds',pass:beforeTheme!==afterTheme,state:{before:beforeTheme,after:afterTheme}});
    }
    // Verify the cached application shell can still launch after the network is removed.
    await page.context().setOffline(true);
    await page.reload({waitUntil:'domcontentloaded',timeout:30000}).catch(e=>{result.offlineReloadError=e.message});
    await page.waitForTimeout(1200);
    const offlineState = await page.evaluate(() => ({
      title:document.title,
      startupComplete:!!window.__wlStartupComplete,
      crumb:document.querySelector('#crumb')?.textContent||''
    }));
    result.checks.push({name:'offline app-shell launch',pass:!!offlineState.startupComplete,state:offlineState,error:result.offlineReloadError||null});
    await page.context().setOffline(false);

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
