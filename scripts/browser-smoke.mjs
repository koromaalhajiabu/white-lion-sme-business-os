import { chromium } from 'playwright';
import fs from 'node:fs';

const base = process.env.WHITE_LION_SMOKE_URL || 'https://koromaalhajiabu.github.io/white-lion-sme-business-os/';
const testEmail = process.env.WHITE_LION_TEST_EMAIL || '';
const testPassword = process.env.WHITE_LION_TEST_PASSWORD || '';
const hasTestCredentials = Boolean(testEmail && testPassword);
const report = { testedAt: new Date().toISOString(), base, browsers: [], summary: 'running' };

function record(result, name, pass, details = {}) {
  result.checks.push({ name, pass: Boolean(pass), ...details });
}

function skip(result, name, reason) {
  result.checks.push({ name, skipped: true, reason });
}

async function runViewport(name, viewport) {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport, serviceWorkers: 'allow' });
  const page = await context.newPage();
  const result = { name, viewport, pageErrors: [], consoleErrors: [], failedRequests: [], checks: [] };
  page.on('pageerror', e => result.pageErrors.push(String(e.stack || e)));
  page.on('console', m => { if (m.type() === 'error') result.consoleErrors.push(m.text()); });
  page.on('requestfailed', r => result.failedRequests.push({ url: r.url(), error: r.failure()?.errorText }));

  try {
    await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(3500);
    await page.evaluate(async () => {
      if ('serviceWorker' in navigator) {
        try { await navigator.serviceWorker.ready; } catch (_) {}
      }
    });
    await page.reload({ waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(3500);

    result.startup = await page.evaluate(() => {
      const app = document.querySelector('.app');
      const auth = document.querySelector('#wlCloudAuth');
      const sidebar = document.querySelector('#sidebar');
      const visible = el => {
        if (!el) return false;
        const style = getComputedStyle(el);
        const rect = el.getBoundingClientRect();
        return style.display !== 'none' && style.visibility !== 'hidden' &&
          Number(style.opacity || 1) > 0 && rect.width > 0 && rect.height > 0;
      };
      return {
        title: document.title,
        ready: document.readyState,
        startupComplete: !!window.__wlStartupComplete,
        startupError: window.__wlStartupError || null,
        scriptFailures: window.__wlScriptFail || [],
        serviceWorkerControlled: !!navigator.serviceWorker?.controller,
        serviceWorkerScript: navigator.serviceWorker?.controller?.scriptURL || null,
        publicMode: !!app?.classList.contains('wl-public-mode'),
        loginVisible: visible(document.querySelector('#wlCloudBox')) && visible(auth) &&
          visible(document.querySelector('#wlCloudEmail')) &&
          visible(document.querySelector('#wlCloudPassword')) &&
          visible(document.querySelector('#wlSignIn')),
        sidebarVisible: visible(sidebar),
        currentCrumb: document.querySelector('#crumb')?.textContent || null,
        viewText: (document.querySelector('#view')?.innerText || '').slice(0, 350)
      };
    });

    record(result, 'application startup completed', !!result.startup.startupComplete, {
      startupError: result.startup.startupError,
      scriptFailures: result.startup.scriptFailures
    });
    record(result, 'service worker controls app after reload', !!result.startup.serviceWorkerControlled, {
      script: result.startup.serviceWorkerScript
    });

    // The signed-out experience intentionally hides private workspace navigation.
    // Only authenticate when dedicated CI credentials have been configured.
    let authenticatedWorkspace = false;
    if (hasTestCredentials) {
      const email = page.locator('#wlCloudEmail');
      const password = page.locator('#wlCloudPassword');
      if (await email.count() && await password.count()) {
        await email.fill(testEmail);
        await password.fill(testPassword);
        await page.locator('#wlSignIn').click({ timeout: 10000 });
        try {
          await page.waitForFunction(() => {
            const app = document.querySelector('.app');
            const active = window.whiteLionCloud?.getActiveBusiness?.();
            return !app?.classList.contains('wl-public-mode') &&
              Boolean(active?.id || (window.__wlBusinesses || []).length);
          }, null, { timeout: 30000 });
          authenticatedWorkspace = true;
          record(result, 'dedicated CI account signed in and loaded a business workspace', true);
        } catch (_) {
          const status = await page.locator('#wlCloudStatus').textContent().catch(() => '');
          record(result, 'dedicated CI account signed in and loaded a business workspace', false, {
            status: (status || '').trim().slice(0, 300),
            hint: 'Check WHITE_LION_TEST_EMAIL / WHITE_LION_TEST_PASSWORD and ensure that account has an active business membership.'
          });
        }
      } else {
        record(result, 'dedicated CI account login form available', false);
      }
    } else {
      record(result, 'signed-out login screen is visible', result.startup.publicMode && result.startup.loginVisible, {
        publicMode: result.startup.publicMode,
        loginVisible: result.startup.loginVisible
      });
      record(result, 'private workspace navigation is hidden while signed out', !result.startup.sidebarVisible);
      skip(result, 'authenticated workspace navigation and module actions',
        'No WHITE_LION_TEST_EMAIL and WHITE_LION_TEST_PASSWORD secrets are configured. Private navigation is intentionally hidden until sign-in.');
    }

    if (authenticatedWorkspace) {
      const workspaceState = await page.evaluate(() => {
        const app = document.querySelector('.app');
        const sidebar = document.querySelector('#sidebar');
        const active = window.whiteLionCloud?.getActiveBusiness?.();
        const style = sidebar ? getComputedStyle(sidebar) : null;
        return {
          publicMode: !!app?.classList.contains('wl-public-mode'),
          activeBusiness: active?.id || null,
          sidebarDisplay: style?.display || null,
          sidebarVisibility: style?.visibility || null
        };
      });
      record(result, 'authenticated workspace shell is visible', !workspaceState.publicMode &&
        Boolean(workspaceState.activeBusiness) && workspaceState.sidebarDisplay !== 'none' &&
        workspaceState.sidebarVisibility !== 'hidden', workspaceState);

      if (viewport.width < 720) {
        await page.locator('#menuBtn').click({ timeout: 10000 });
        await page.waitForFunction(() => document.querySelector('#sidebar')?.classList.contains('open'), null, { timeout: 5000 });
        record(result, 'mobile workspace menu opens', true);
      }

      for (const [key, expected] of [
        ['products', 'Products'], ['sales', 'Sales'], ['purchases', 'Purchases'],
        ['expenses', 'Expenses'], ['actions', 'Executive Action Centre'],
        ['reorder', 'Smart Reorder Planner'], ['finance', 'Financial Planning'],
        ['billing', 'Plans & Billing'], ['settings', 'Business settings']
      ]) {
        if (viewport.width < 720) {
          const isOpen = await page.locator('#sidebar').evaluate(el => el.classList.contains('open'));
          if (!isOpen) {
            await page.locator('#menuBtn').click({ timeout: 5000 });
            await page.waitForTimeout(150);
          }
        }
        const button = page.locator('#sidebar [data-page="' + key + '"]').first();
        if (!(await button.count())) {
          record(result, 'navigate ' + key, false, { error: 'Navigation item missing from sidebar.' });
          continue;
        }
        try {
          await button.click({ timeout: 8000 });
          await page.waitForTimeout(450);
          const state = await page.evaluate(() => ({
            crumb: document.querySelector('#crumb')?.textContent || '',
            title: document.querySelector('#view h1')?.textContent || '',
            view: (document.querySelector('#view')?.innerText || '').slice(0, 220)
          }));
          const expectedWord = expected.toLowerCase().split(' ')[0];
          const passed = state.crumb.toLowerCase().includes(expectedWord) ||
            state.title.toLowerCase().includes(expectedWord);
          record(result, 'navigate ' + key, passed, { state });
        } catch (error) {
          record(result, 'navigate ' + key, false, { error: String(error.message || error) });
        }

        if (key === 'actions') {
          const actionText = await page.locator('#view').innerText();
          for (const section of [
            'Management alerts', 'Management tasks', 'Branch performance',
            'Stock replenishment recommendations', 'Investigate recent sales', 'Executive activity'
          ]) {
            record(result, 'action centre section: ' + section, actionText.includes(section));
          }
        }
      }

      await page.locator('#sidebar [data-page="products"]').click({ timeout: 8000 });
      await page.waitForTimeout(400);
      const add = page.locator('#view #addBtn');
      if (await add.count()) {
        await add.scrollIntoViewIfNeeded();
        await add.click({ timeout: 8000 });
        await page.waitForTimeout(200);
        const modalOpen = await page.locator('#modalBack.show').count() > 0;
        record(result, 'open product form without saving', modalOpen);
        if (modalOpen) {
          await page.locator('#cancelModal').click();
          record(result, 'close product form without saving', await page.locator('#modalBack.show').count() === 0);
        }
      } else {
        record(result, 'open product form without saving', false, { error: 'Add product button missing.' });
      }

      await page.locator('#sidebar [data-page="dashboard"]').click({ timeout: 8000 });
      await page.waitForTimeout(300);
      const quick = page.locator('#view [data-go="products"]').first();
      if (await quick.count()) {
        await quick.click({ timeout: 8000 });
        await page.waitForTimeout(300);
        const crumb = (await page.locator('#crumb').textContent()) || '';
        record(result, 'dashboard quick action opens products', crumb.toLowerCase().includes('products'), { crumb });
      } else {
        record(result, 'dashboard quick action opens products', false, { error: 'Quick action missing.' });
      }

      const themeButton = page.locator('#themeToggle');
      if (await themeButton.count()) {
        const beforeTheme = await page.locator('html').getAttribute('data-theme');
        await themeButton.click({ timeout: 8000 });
        const afterTheme = await page.locator('html').getAttribute('data-theme');
        record(result, 'appearance toggle responds', beforeTheme !== afterTheme, {
          before: beforeTheme, after: afterTheme
        });
      }
    }

    // The offline check verifies that the local application shell can relaunch.
    // Cloud sign-in/synchronisation are not expected to work without a network.
    await context.setOffline(true);
    let offlineReloadError = null;
    await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 })
      .catch(error => { offlineReloadError = String(error.message || error); });
    await page.waitForTimeout(1200);
    const offlineState = await page.evaluate(() => ({
      title: document.title,
      startupComplete: !!window.__wlStartupComplete,
      loginFormPresent: !!document.querySelector('#wlCloudEmail'),
      viewPresent: !!document.querySelector('#view')
    }));
    record(result, 'offline application shell relaunches', !!offlineState.startupComplete &&
      !!offlineState.loginFormPresent && !!offlineState.viewPresent, {
        state: offlineState,
        reloadError: offlineReloadError
      });
    await context.setOffline(false);

    result.final = await page.evaluate(() => ({
      publicMode: !!document.querySelector('.app')?.classList.contains('wl-public-mode'),
      activeBusiness: window.whiteLionCloud?.getActiveBusiness?.()?.id || null,
      startupError: window.__wlStartupError || null
    }));
  } catch (error) {
    result.fatal = String(error.stack || error);
  }

  await page.screenshot({ path: 'browser-' + name + '.png', fullPage: false }).catch(() => {});
  await browser.close();
  report.browsers.push(result);
}

await runViewport('android-mobile', { width: 390, height: 844, isMobile: true, hasTouch: true });
await runViewport('desktop', { width: 1365, height: 900 });

const all = report.browsers.flatMap(browser => browser.checks);
report.failedChecks = all.filter(check => check.pass === false);
report.skippedChecks = all.filter(check => check.skipped);
report.summary = report.failedChecks.length
  ? 'FAIL'
  : report.skippedChecks.length
    ? 'PASS_WITH_SKIPS'
    : 'PASS';
fs.writeFileSync('browser-smoke-report.json', JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
if (report.failedChecks.length) process.exitCode = 1;
