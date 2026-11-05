/* White Lion SME OS — Supabase account and workspace foundation.
   This layer does not sync local IndexedDB records yet. */
(() => {
  const SUPABASE_URL = 'https://nclncqlgnxnijlumznnt.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_iPIsAysPnlvPCAoqntoNRg_dKcSZxKX';
  const $ = (id) => document.getElementById(id);
  let client = null, session = null, activeBusiness = null;

  const style = document.createElement('style');
  style.textContent = `
    #wlCloudBox{background:#1b2b47;border:1px solid #40516d;border-radius:12px;padding:12px;color:#fff;font-size:12px}
    #wlCloudBox button{border:0;border-radius:8px;padding:8px 10px;background:#d6ad57;color:#152238;font-weight:700;margin:5px 4px 0 0}
    #wlCloudBox input,#wlCloudBox select{width:100%;padding:9px;border:1px solid #52627b;border-radius:8px;background:#101b31;color:#fff;margin:5px 0}
    #wlCloudBox .muted{color:#bac6d8;font-size:10px}#wlCloudBox .cloud-actions{display:flex;flex-wrap:wrap}
    #wlCloudBox .cloud-status{margin:6px 0;color:#f0d28b;overflow-wrap:anywhere}
    #wlCloudBox details{margin-top:8px}#wlCloudBox summary{cursor:pointer;color:#f0d28b;font-weight:700}
    #wlDeveloperBox{margin-top:14px;background:#111d32;border:1px solid #b58c3d;border-radius:13px;padding:15px;color:#fff;font-size:12px}
    #wlDeveloperBox h3{margin:0 0 8px;color:#f0d28b;font-size:15px}
    #wlDeveloperBox button{border:0;border-radius:8px;padding:8px 10px;background:#d6ad57;color:#152238;font-weight:700;margin:5px 5px 5px 0}
    #wlDeveloperBox button.danger{background:#d86b70;color:#fff}
    #wlDeveloperBox .dev-row{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:9px 0;border-top:1px solid #34435b}
    #wlDeveloperBox .dev-meta{color:#bac6d8;font-size:10px}
    #wlDeveloperBox .dev-actions{display:flex;flex-wrap:wrap;gap:4px}
  `;
  document.head.appendChild(style);

  function say(message) {
    const el = $('wlCloudStatus');
    if (el) el.textContent = message;
    if (typeof window.toast === 'function') window.toast(message);
  }
  function addPanel() {
    const host = document.querySelector('.content');
    if (!host || $('wlCloudBox')) return;
    const box = document.createElement('section');
    box.id = 'wlCloudBox';
    box.innerHTML = `
      <div style="font-weight:800">CLOUD ACCOUNT</div>
      <div class="muted">Sign in to access your online business workspaces.</div>
      <div id="wlCloudStatus" class="cloud-status">Connecting securely…</div>
      <div id="wlCloudAuth">
        <input id="wlCloudEmail" type="email" autocomplete="email" placeholder="Email address">
        <input id="wlCloudPassword" type="password" autocomplete="current-password" placeholder="Password (minimum 8 characters)">
        <div class="cloud-actions"><button id="wlSignIn">Sign in</button><button id="wlSignUp">Create account</button></div>
      </div>
      <div id="wlCloudWork" hidden>
        <select id="wlBusinessSelect" aria-label="Choose business"></select>
        <div class="cloud-actions"><button id="wlCreateBusiness">＋ New business</button><button id="wlSignOut">Sign out</button></div>
        <details><summary>Business modules</summary><div id="wlModules" class="muted">Select a business to view modules.</div></details>
      </div>`;
    host.insertAdjacentElement('afterbegin', box);
    const dev = document.createElement('section');
    dev.id = 'wlDeveloperBox';
    dev.hidden = true;
    dev.innerHTML = `
      <h3>WHITE LION · PRIVATE DEVELOPER CONSOLE</h3>
      <div id="wlDevIdentity" class="dev-meta">Verifying developer permissions…</div>
      <div id="wlDevStatus" class="cloud-status">Loading secure platform controls…</div>
      <div id="wlDevStats" class="dev-meta"></div>
      <div class="dev-actions">
        <button id="wlDevRefresh">Refresh dashboard</button>
        <button id="wlDevFreeze">Freeze platform</button>
        <button id="wlDevAssign">Manage business access</button>
      </div>
      <div id="wlDevBusinesses"></div>
      <div class="dev-meta" style="margin-top:10px">Developer access is verified by Supabase database permissions. This console does not expose passwords or secret API keys.</div>`;
    box.insertAdjacentElement('afterend', dev);
    $('wlDevRefresh').onclick = loadDeveloperDashboard;
    $('wlDevFreeze').onclick = toggleMaintenance;
    $('wlDevAssign').onclick = manageBusinessAccess;
    $('wlSignIn').onclick = () => authenticate(false);
    $('wlSignUp').onclick = () => authenticate(true);
    $('wlSignOut').onclick = async () => { await client.auth.signOut(); session = null; activeBusiness = null; $('wlDeveloperBox').hidden = true; showSignedOut(); };
    $('wlCreateBusiness').onclick = createBusiness;
    $('wlBusinessSelect').onchange = async (e) => {
      const chosen = (window.__wlBusinesses || []).find(b => b.id === e.target.value);
      if (chosen) await selectBusiness(chosen);
    };
  }
  function showSignedOut() {
    $('wlCloudAuth').hidden = false; $('wlCloudWork').hidden = true;
    $('wlCloudStatus').textContent = 'Not signed in. Local records remain on this device.';
  }
  async function authenticate(signUp) {
    const email = $('wlCloudEmail').value.trim();
    const password = $('wlCloudPassword').value;
    if (!email || password.length < 8) return say('Enter a valid email and a password of at least 8 characters.');
    say(signUp ? 'Creating your account…' : 'Signing in…');
    const result = signUp
      ? await client.auth.signUp({ email, password })
      : await client.auth.signInWithPassword({ email, password });
    if (result.error) return say(result.error.message);
    if (signUp && !result.data.session) return say('Account created. Check your email to confirm it, then sign in.');
    session = result.data.session;
    if (session) await loadBusinesses();
    else say('Account created. Check your email for the confirmation link.');
  }
  async function loadBusinesses() {
    const { data: memberships, error } = await client.from('business_members')
      .select('business_id,role,is_active,businesses(id,name,industry,currency_code)')
      .eq('user_id', session.user.id).eq('is_active', true);
    if (error) return say('Could not load workspaces: ' + error.message);
    const businesses = (memberships || []).map(m => ({...m.businesses, role:m.role})).filter(b => b.id);
    window.__wlBusinesses = businesses;
    $('wlCloudAuth').hidden = true; $('wlCloudWork').hidden = false;
    $('wlBusinessSelect').innerHTML = businesses.length
      ? businesses.map(b => `<option value="${b.id}">${escapeHtml(b.name)} — ${escapeHtml(b.role)}</option>`).join('')
      : '<option value="">No business workspace yet</option>';
    if (businesses.length) await selectBusiness(businesses[0]);
    else say('Signed in. Create your first business workspace.');
    await checkDeveloperAccess();
  }
  function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }
  async function selectBusiness(business) {
    activeBusiness = business;
    $('wlBusinessSelect').value = business.id;
    const sideName = $('sideBusiness'), sideIndustry = $('sideIndustry');
    if (sideName) sideName.textContent = business.name;
    if (sideIndustry) sideIndustry.textContent = business.industry + ' · ' + business.currency_code;
    const { data: modules, error } = await client.from('business_industry_modules')
      .select('module_key,is_enabled').eq('business_id', business.id).order('module_key');
    $('wlModules').textContent = error ? 'Module list unavailable: ' + error.message :
      (modules || []).filter(m => m.is_enabled).map(m => m.module_key.replaceAll('_',' ')).join(' · ') || 'No modules enabled';
    say('Signed in as ' + session.user.email + '. Workspace: ' + business.name + '. Cloud record sync is not enabled yet.');
    window.dispatchEvent(new CustomEvent('whiteLionWorkspaceChanged', { detail: { business, modules: modules || [] } }));
  }
  async function checkDeveloperAccess() {
    const panel = $('wlDeveloperBox');
    if (!panel || !session) return;
    panel.hidden = session.user.email?.toLowerCase() !== 'koromaalhaji0@gmail.com';
    if (panel.hidden) return;
    $('wlDevIdentity').textContent = 'Authenticated: ' + session.user.email + ' · Private developer';
    await loadDeveloperDashboard();
  }
  async function loadDeveloperDashboard() {
    const status = $('wlDevStatus');
    if (!session || session.user.email?.toLowerCase() !== 'koromaalhaji0@gmail.com') return;
    status.textContent = 'Checking developer authorization and loading platform data…';
    const { data, error } = await client.rpc('get_platform_dashboard');
    if (error) { status.textContent = 'Developer database setup required: ' + error.message; return; }
    const maintenance = data.maintenance || {enabled:false};
    $('wlDevStats').textContent = 'Businesses: ' + data.business_count + ' · Suspended: ' + data.suspended_count + ' · Registered accounts: ' + data.user_count + ' · Platform mode: ' + (maintenance.enabled ? 'MAINTENANCE' : 'LIVE');
    $('wlDevFreeze').textContent = maintenance.enabled ? 'Unfreeze platform' : 'Freeze platform';
    $('wlDevFreeze').className = maintenance.enabled ? '' : 'danger';
    $('wlDevBusinesses').innerHTML = (data.businesses || []).map(b => `
      <div class="dev-row">
        <div><strong>${escapeHtml(b.name)}</strong><div class="dev-meta">${escapeHtml(b.industry)} · Owner: ${escapeHtml(b.owner_email || 'Unknown')} · ${b.member_count} members</div><div class="dev-meta">${b.is_suspended ? 'SUSPENDED' : 'ACTIVE'} · ${escapeHtml(b.id)}</div></div>
        <div class="dev-actions"><button data-dev-business="${b.id}" data-suspended="${b.is_suspended ? 'true':'false'}">${b.is_suspended ? 'Restore':'Suspend'}</button></div>
      </div>`).join('') || '<div class="dev-meta">No business workspaces have been created.</div>';
    $('wlDevBusinesses').querySelectorAll('[data-dev-business]').forEach(button => {
      button.onclick = async () => {
        const suspend = button.dataset.suspended !== 'true';
        if (!confirm((suspend ? 'Suspend' : 'Restore') + ' this business workspace?')) return;
        const result = await client.rpc('set_platform_business_suspension', {p_business_id:button.dataset.devBusiness,p_is_suspended:suspend});
        if (result.error) { status.textContent = result.error.message; return; }
        await loadDeveloperDashboard();
      };
    });
    status.textContent = 'Developer authorization verified by Supabase. Platform controls are available.';
  }
  async function toggleMaintenance() {
    const dashboard = await client.rpc('get_platform_dashboard');
    if (dashboard.error) { $('wlDevStatus').textContent = dashboard.error.message; return; }
    const current = !!dashboard.data.maintenance?.enabled;
    const next = !current;
    const message = next ? (prompt('Maintenance notice shown to users:', 'The platform is temporarily undergoing maintenance.') || 'The platform is temporarily undergoing maintenance.') : 'The platform is operational.';
    if (!confirm(next ? 'Enable platform maintenance mode?' : 'Disable maintenance mode and restore normal operation?')) return;
    const result = await client.rpc('set_platform_maintenance', {p_enabled:next,p_message:message});
    if (result.error) { $('wlDevStatus').textContent = result.error.message; return; }
    await loadDeveloperDashboard();
  }
  async function manageBusinessAccess() {
    const businesses = window.__wlBusinesses || [];
    const businessId = prompt('Enter the business ID to manage (copy it from the developer list):');
    if (!businessId) return;
    const email = prompt('Enter the registered user email:');
    if (!email) return;
    const role = (prompt('Role: admin, manager, cashier, storekeeper, accountant, viewer', 'manager') || '').toLowerCase();
    const allowed = ['admin','manager','cashier','storekeeper','accountant','viewer'];
    if (!allowed.includes(role)) { $('wlDevStatus').textContent = 'Invalid role selected.'; return; }
    const active = confirm('Keep this member active? Choose Cancel to deactivate access.');
    const result = await client.rpc('set_platform_member_access', {
      p_business_id:businessId.trim(),p_email:email.trim(),p_role:role,p_is_active:active
    });
    if (result.error) { $('wlDevStatus').textContent = result.error.message; return; }
    $('wlDevStatus').textContent = 'Business membership updated and audited.';
    await loadDeveloperDashboard();
  }
  async function createBusiness() {
    const name = prompt('Enter the business or organisation name:');
    if (!name || name.trim().length < 2) return;
    const industry = prompt('Industry profile (e.g. Retail, Pharmacy, Restaurant, Services):', 'Multi-industry') || 'Multi-industry';
    const currency = prompt('Default currency code:', 'SLE') || 'SLE';
    say('Creating business workspace…');
    const { data, error } = await client.rpc('create_business', {
      p_name: name.trim(), p_industry: industry.trim(), p_currency_code: currency.trim().toUpperCase()
    });
    if (error) return say('Could not create workspace: ' + error.message);
    await loadBusinesses();
    const created = (window.__wlBusinesses || []).find(b => b.id === data);
    if (created) await selectBusiness(created);
    say('Business workspace created successfully.');
  }
  function loadSdk() {
    return new Promise((resolve, reject) => {
      if (window.supabase?.createClient) return resolve();
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
      script.onload = resolve; script.onerror = () => reject(new Error('Could not load Supabase library.'));
      document.head.appendChild(script);
    });
  }
  async function init() {
    addPanel();
    try {
      await loadSdk();
      client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
      });
      const { data } = await client.auth.getSession();
      session = data.session;
      if (session) await loadBusinesses(); else showSignedOut();
      client.auth.onAuthStateChange((_event, nextSession) => {
        session = nextSession;
        if (session) setTimeout(() => loadBusinesses(), 0);
        else showSignedOut();
      });
      window.whiteLionCloud = {
        getClient: () => client,
        getSession: () => session,
        getActiveBusiness: () => activeBusiness
      };
      window.dispatchEvent(new CustomEvent('whiteLionCloudReady'));
    } catch (error) {
      say(error.message || 'Cloud connection could not be initialised.');
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();