/* White Lion SME OS — Supabase workspace, master-data and atomic transaction sync. */
(() => {
  const SUPABASE_URL = 'https://nclncqlgnxnijlumznnt.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_iPIsAysPnlvPCAoqntoNRg_dKcSZxKX';
  const $ = (id) => document.getElementById(id);
  let client = null, session = null, activeBusiness = null, selectedBranch = null;

  const style = document.createElement('style');
  style.textContent = `
    #wlCloudBox{background:#1b2b47;border:1px solid #40516d;border-radius:12px;padding:12px;color:#fff;font-size:12px}
    #wlCloudBox button{border:0;border-radius:8px;padding:8px 10px;background:#d6ad57;color:#152238;font-weight:700;margin:5px 4px 0 0}
    #wlCloudBox input,#wlCloudBox select{width:100%;padding:9px;border:1px solid #52627b;border-radius:8px;background:#101b31;color:#fff;margin:5px 0}
    #wlCloudBox .muted{color:#bac6d8;font-size:10px}#wlCloudBox .cloud-actions{display:flex;flex-wrap:wrap}
    #wlCloudBox .cloud-status{margin:6px 0;color:#f0d28b;overflow-wrap:anywhere}
    #wlCloudBox details{margin-top:8px}#wlCloudBox summary{cursor:pointer;color:#f0d28b;font-weight:700}#wlCloudBox .branch-stock{display:grid;grid-template-columns:1fr auto;gap:5px;padding:6px 0;border-bottom:1px solid #34435b}#wlCloudBox .branch-note{color:#bac6d8;font-size:10px;margin:6px 0;overflow-wrap:anywhere}
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
    const host = document.querySelector('.main');
    const anchor = document.querySelector('.topbar');
    if (!host || !anchor || $('wlCloudBox')) return;
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
        <div class="cloud-actions"><button id="wlCreateBusiness">＋ New business</button><button id="wlSyncNow">Upload local records</button><button id="wlDownloadNow">Download cloud records</button><button id="wlSignOut">Sign out</button></div><div id="wlSyncStatus" class="cloud-status">Local records are not yet synced.</div>
        <details id="wlBranchManager" open><summary>Branch management</summary>
          <div class="muted" style="margin:7px 0">Create branches, select a working branch, assign staff and inspect branch stock.</div>
          <select id="wlBranchSelect" aria-label="Select active branch"><option value="">Loading branches…</option></select>
          <div class="cloud-actions"><button id="wlCreateBranch">＋ Create branch</button><button id="wlRefreshBranches">Refresh branches</button></div>
          <div id="wlBranchStatus" class="cloud-status">Select a business to load its branches.</div>
          <div id="wlBranchInventory" class="muted"></div>
          <details><summary>Assign staff to this branch</summary>
            <select id="wlBranchMemberSelect" aria-label="Select business member"><option value="">Load business members…</option></select>
            <div class="cloud-actions"><button id="wlAssignBranchMember">Assign staff</button><button id="wlRemoveBranchMember">Deactivate assignment</button></div>
            <div id="wlBranchMembers" class="muted"></div>
          </details>
        </details>
        <details><summary>Business modules</summary><div id="wlModules" class="muted">Select a business to view modules.</div></details>
      </div>`;
    anchor.insertAdjacentElement('afterend', box);
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
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin-top:15px"><h3 style="margin:0">Registered accounts</h3><button id="wlDevAccountsRefresh">Refresh accounts</button></div>
      <div id="wlDevAccounts" class="dev-meta">Account directory loads after developer verification.</div>
      <div class="dev-meta" style="margin-top:10px">Deletion requests suspend access immediately. Accounts remain recoverable for 30 days. Business owners and developer accounts are protected. Permanent deletion is only available after the recovery period through the secure server-side function.</div>
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin-top:16px"><h3 style="margin:0">30-day deletion &amp; recovery</h3><button id="wlDevDeletionRefresh">Refresh requests</button></div>
      <div id="wlDevDeletions" class="dev-meta">Deletion requests load after developer verification.</div>
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin-top:18px"><h3 style="margin:0">Platform activity &amp; audit log</h3><button id="wlDevAuditRefresh">Refresh activity</button></div>
      <input id="wlDevAuditSearch" type="search" placeholder="Search actions, accounts, workspaces…" aria-label="Search platform audit log" style="width:100%;box-sizing:border-box;padding:9px;border:1px solid #52627b;border-radius:8px;background:#101b31;color:#fff;margin:8px 0">
      <div id="wlDevAudit" class="dev-meta">Recent platform activity will appear here.</div>
      <div class="dev-meta" style="margin-top:10px">The audit log records actions made after this feature is installed. Existing historical audit entries are not backfilled.</div>
      <div class="dev-meta" style="margin-top:10px">Developer access is verified by Supabase database permissions. This console does not expose passwords or secret API keys.</div>`;
    box.insertAdjacentElement('afterend', dev);
    $('wlDevRefresh').onclick = loadDeveloperDashboard;
    $('wlDevFreeze').onclick = toggleMaintenance;
    $('wlDevAssign').onclick = manageBusinessAccess;
    $('wlDevAccountsRefresh').onclick = loadDeveloperAccounts;
    $('wlDevDeletionRefresh').onclick = loadDeveloperDeletionRequests;
    $('wlDevAuditRefresh').onclick = loadDeveloperActivity;
    $('wlDevAuditSearch').oninput = renderDeveloperActivity;
    $('wlSignIn').onclick = () => authenticate(false);
    $('wlSignUp').onclick = () => authenticate(true);
    $('wlSignOut').onclick = async () => { await client.auth.signOut(); session = null; activeBusiness = null; $('wlDeveloperBox').hidden = true; showSignedOut(); };
    $('wlCreateBusiness').onclick = createBusiness;
    $('wlSyncNow').onclick = syncLocalRecords;
    $('wlDownloadNow').onclick = downloadCloudRecords;
    $('wlCreateBranch').onclick = createBranch;
    $('wlRefreshBranches').onclick = loadBranches;
    $('wlBranchSelect').onchange = async (e) => {
      selectedBranch = (window.__wlBranches || []).find(b => b.id === e.target.value) || null;
      await loadBranchDetails();
    };
    $('wlAssignBranchMember').onclick = () => setBranchMember(true);
    $('wlRemoveBranchMember').onclick = () => setBranchMember(false);
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
    // Show the private developer console independently of workspace membership loading.
    // A developer account may not belong to a business workspace, and membership RLS errors
    // must not prevent the developer dashboard from appearing.
    void checkDeveloperAccess();
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
  }
  function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }
  async function createBranch() {
    if (!activeBusiness) return say('Select a business workspace first.');
    const name = prompt('New branch name:');
    if (!name || name.trim().length < 2) return;
    const address = prompt('Branch address (optional):') || '';
    $('wlBranchStatus').textContent = 'Creating branch…';
    const {data,error} = await client.rpc('create_business_branch', {
      p_business_id:activeBusiness.id,p_name:name.trim(),p_address:address.trim() || null
    });
    if (error) { $('wlBranchStatus').textContent = 'Could not create branch: ' + error.message; return; }
    $('wlBranchStatus').textContent = 'Branch created successfully.';
    await loadBranches(data?.branch_id);
  }
  async function loadBranches(preferredId) {
    if (!activeBusiness || !client) return;
    $('wlBranchStatus').textContent = 'Loading branches…';
    const {data,error} = await client.from('branches')
      .select('id,name,address,is_active,created_at')
      .eq('business_id',activeBusiness.id).order('created_at');
    if (error) { $('wlBranchStatus').textContent = 'Could not load branches: ' + error.message; return; }
    window.__wlBranches = data || [];
    const active = window.__wlBranches.filter(b => b.is_active);
    $('wlBranchSelect').innerHTML = active.length
      ? active.map(b => '<option value="' + escapeHtml(b.id) + '">' + escapeHtml(b.name) + (b.address ? ' · ' + escapeHtml(b.address) : '') + '</option>').join('')
      : '<option value="">No active branches — create one</option>';
    selectedBranch = active.find(b => b.id === (preferredId || selectedBranch?.id)) || active[0] || null;
    $('wlBranchSelect').value = selectedBranch?.id || '';
    window.dispatchEvent(new CustomEvent('whiteLionBranchChanged', {detail:{branch:selectedBranch,branches:active}}));
    $('wlBranchStatus').textContent = active.length + ' active branch(es) available. Branch selection currently controls branch management and stock viewing; sales/purchase posting will be connected in the next integration step.';
    await loadBranchDetails();
  }
  async function loadBranchDetails() {
    if (!activeBusiness || !selectedBranch) {
      $('wlBranchInventory').textContent = 'No active branch selected.';
      $('wlBranchMembers').textContent = '';
      $('wlBranchMemberSelect').innerHTML = '<option value="">No branch selected</option>';
      return;
    }
    const [stockResult, memberResult, assignmentResult] = await Promise.all([
      client.from('branch_inventory').select('product_id,quantity_on_hand,products(name,sku,unit)')
        .eq('business_id',activeBusiness.id).eq('branch_id',selectedBranch.id).order('updated_at',{ascending:false}),
      client.from('business_members').select('user_id,role,is_active')
        .eq('business_id',activeBusiness.id).eq('is_active',true),
      client.from('branch_members').select('user_id,is_active')
        .eq('business_id',activeBusiness.id).eq('branch_id',selectedBranch.id)
    ]);
    if (stockResult.error) $('wlBranchInventory').textContent = 'Stock unavailable: ' + stockResult.error.message;
    else {
      const rows = stockResult.data || [];
      $('wlBranchInventory').innerHTML = '<div class="branch-note"><strong>Stock at ' + escapeHtml(selectedBranch.name) + '</strong></div>' +
        (rows.map(row => '<div class="branch-stock"><span>' + escapeHtml(row.products?.name || row.product_id) + '</span><strong>' + Number(row.quantity_on_hand || 0).toLocaleString() + ' ' + escapeHtml(row.products?.unit || '') + '</strong></div>').join('') || '<div class="branch-note">No stock records in this branch yet.</div>');
    }
    if (memberResult.error) $('wlBranchMemberSelect').innerHTML = '<option value="">Members unavailable</option>';
    else {
      const members = memberResult.data || [];
      $('wlBranchMemberSelect').innerHTML = '<option value="">Choose a business member…</option>' +
        members.map(m => '<option value="' + escapeHtml(m.user_id) + '">' + escapeHtml(m.user_id) + ' · ' + escapeHtml(m.role) + '</option>').join('');
    }
    if (assignmentResult.error) $('wlBranchMembers').textContent = 'Assignments unavailable: ' + assignmentResult.error.message;
    else {
      const assignments = assignmentResult.data || [];
      const memberMap = new Map((memberResult.data || []).map(m => [m.user_id,m]));
      $('wlBranchMembers').innerHTML = '<div class="branch-note"><strong>Branch assignments</strong></div>' +
        (assignments.map(a => '<div class="branch-note">' + escapeHtml(a.user_id) + ' · ' + escapeHtml(memberMap.get(a.user_id)?.role || 'member') + ' · ' + (a.is_active ? 'ACTIVE' : 'INACTIVE') + '</div>').join('') || '<div class="branch-note">No staff assigned yet.</div>');
    }
  }
  async function setBranchMember(isActive) {
    if (!activeBusiness || !selectedBranch) return say('Select a branch first.');
    const userId = $('wlBranchMemberSelect').value;
    if (!userId) return say('Choose a business member first.');
    const {error} = await client.rpc('set_branch_member_access', {
      p_business_id:activeBusiness.id,p_branch_id:selectedBranch.id,p_user_id:userId,p_is_active:isActive
    });
    if (error) { $('wlBranchStatus').textContent = 'Could not update branch assignment: ' + error.message; return; }
    $('wlBranchStatus').textContent = isActive ? 'Staff member assigned to branch.' : 'Branch assignment deactivated.';
    await loadBranchDetails();
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
    say('Signed in as ' + session.user.email + '. Workspace: ' + business.name + '. Cloud sync is available for products, customers, suppliers and expenses.');
    updateSyncStatus();
    window.dispatchEvent(new CustomEvent('whiteLionWorkspaceChanged', { detail: { business, modules: modules || [] } }));
    await loadBranches();
  }
  async function checkDeveloperAccess() {
    const panel = $('wlDeveloperBox');
    if (!panel || !session) return;
    panel.hidden = session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com';
    if (panel.hidden) return;
    $('wlDevIdentity').textContent = 'Authenticated: ' + session.user.email + ' · Private developer';
    await loadDeveloperDashboard();
  }
  async function loadDeveloperDashboard() {
    const status = $('wlDevStatus');
    if (!session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') return;
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
    await loadDeveloperAccounts();
    await loadDeveloperDeletionRequests();
    await loadDeveloperActivity();
  }
  async function loadDeveloperActivity() {
    const host = $('wlDevAudit');
    if (!host || !session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') return;
    host.textContent = 'Loading platform activity…';
    const {data,error} = await client.rpc('get_platform_audit_log', {p_limit:150});
    if (error) {
      host.textContent = 'Audit log unavailable: ' + error.message + '. Run migration 007 first.';
      return;
    }
    window.__wlPlatformAudit = Array.isArray(data) ? data : [];
    renderDeveloperActivity();
  }
  function renderDeveloperActivity() {
    const host = $('wlDevAudit');
    if (!host) return;
    const query = ($('wlDevAuditSearch')?.value || '').trim().toLowerCase();
    const events = (window.__wlPlatformAudit || []).filter(event => {
      const text = [event.action,event.actor_email,event.business_name,event.entity_table,event.entity_id,JSON.stringify(event.details || {})].join(' ').toLowerCase();
      return !query || text.includes(query);
    });
    host.innerHTML = events.map(event => {
      const when = event.occurred_at ? new Date(event.occurred_at).toLocaleString() : 'Time unavailable';
      const details = event.details && Object.keys(event.details).length ? JSON.stringify(event.details) : '';
      return '<div class="dev-row"><div style="min-width:0"><strong>' + escapeHtml(String(event.action || 'Platform event').replaceAll('_',' ')) + '</strong><div class="dev-meta">' + escapeHtml(event.actor_email || 'System / unknown actor') + ' · ' + escapeHtml(when) + '</div><div class="dev-meta">' + escapeHtml(event.business_name || 'Platform-wide') + (event.entity_table ? ' · ' + escapeHtml(event.entity_table) : '') + (event.entity_id ? ' · ' + escapeHtml(event.entity_id) : '') + '</div>' + (details ? '<div class="dev-meta">' + escapeHtml(details) + '</div>' : '') + '</div></div>';
    }).join('') || '<div class="dev-meta">No matching audit events found in the latest 150 records.</div>';
  }
  async function loadDeveloperAccounts() {
    const host = $('wlDevAccounts');
    if (!host || !session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') return;
    host.textContent = 'Loading registered accounts…';
    const {data,error} = await client.rpc('get_platform_accounts');
    if (error) { host.textContent = 'Account directory unavailable: ' + error.message + '. Run migration 006 first.'; return; }
    const accounts = Array.isArray(data) ? data : [];
    host.innerHTML = accounts.map(a => {
      const active = a.is_active !== false;
      const name = a.full_name || 'Name not provided';
      const last = a.last_sign_in_at ? new Date(a.last_sign_in_at).toLocaleString() : 'Never signed in';
      const protectedAccount = a.email?.toLowerCase() === 'koromaalhajiabu0@gmail.com';
      return '<div class="dev-row"><div style="min-width:0"><strong>' + escapeHtml(name) + '</strong><div class="dev-meta">' + escapeHtml(a.email || '') + '</div><div class="dev-meta">' + (active ? 'ACTIVE' : 'SUSPENDED') + ' · ' + (a.email_confirmed ? 'Email verified' : 'Email not verified') + ' · ' + Number(a.business_count || 0) + ' workspaces</div><div class="dev-meta">Last sign-in: ' + escapeHtml(last) + '</div></div><div class="dev-actions"><button data-account-user="' + escapeHtml(a.user_id) + '" data-account-active="' + (active ? 'true':'false') + '" ' + (protectedAccount ? 'disabled' : '') + '>' + (active ? 'Suspend access' : 'Restore access') + '</button>' + (!protectedAccount ? '<button class="danger" data-account-delete="' + escapeHtml(a.user_id) + '" data-account-email="' + escapeHtml(a.email || '') + '">Request deletion</button>' : '') + '</div></div>';
    }).join('') || '<div class="dev-meta">No registered accounts found.</div>';
    host.querySelectorAll('[data-account-delete]').forEach(button => {
      button.onclick = async () => {
        const email = button.dataset.accountEmail || '';
        const confirmation = prompt('This will suspend the account immediately and start a 30-day recovery period. Type the exact account email to confirm:', '');
        if (confirmation === null) return;
        if (confirmation.trim().toLowerCase() !== email.toLowerCase()) { say('Email confirmation did not match. No deletion request was created.'); return; }
        if (!confirm('Confirm deletion request for ' + email + '? The account remains recoverable for 30 days.')) return;
        button.disabled = true;
        const result = await client.rpc('request_platform_account_deletion', {
          p_user_id:button.dataset.accountDelete,p_confirm_email:confirmation.trim()
        });
        if (result.error) { say(result.error.message); button.disabled = false; return; }
        say('Deletion request created. Access suspended; 30-day recovery period started.');
        await loadDeveloperAccounts();
        await loadDeveloperDeletionRequests();
      };
    });
    host.querySelectorAll('[data-account-user]').forEach(button => {
      button.onclick = async () => {
        const suspend = button.dataset.accountActive === 'true';
        if (!confirm((suspend ? 'Suspend this account across all business workspaces?' : 'Restore this account access across business workspaces?') + ' Existing records will be preserved.')) return;
        button.disabled = true;
        const result = await client.rpc('set_platform_account_access', {
          p_user_id:button.dataset.accountUser,
          p_is_active:!suspend,
          p_note:''
        });
        if (result.error) { $('wlDevStatus').textContent = result.error.message; button.disabled = false; return; }
        $('wlDevStatus').textContent = suspend ? 'Account access suspended. Existing data preserved.' : 'Account access restored.';
        await loadDeveloperAccounts();
      };
    });
  }

  async function loadDeveloperDeletionRequests() {
    const host = $('wlDevDeletions');
    if (!host || !session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') return;
    host.textContent = 'Loading deletion requests…';
    const {data,error} = await client.rpc('get_platform_account_deletion_requests');
    if (error) { host.textContent = 'Deletion workflow unavailable: ' + error.message + '. Run migration 008 first.'; return; }
    const requests = Array.isArray(data) ? data : [];
    const pendingUsers = new Set(requests.filter(d => d.status === 'pending').map(d => d.target_user_id));
    document.querySelectorAll('#wlDevAccounts [data-account-user]').forEach(button => {
      if (pendingUsers.has(button.dataset.accountUser) && button.dataset.accountActive === 'false') {
        button.disabled = true;
        button.title = 'Cancel the pending deletion request before restoring access';
      }
    });
    host.innerHTML = requests.map(d => {
      const due = d.scheduled_for ? new Date(d.scheduled_for) : null;
      const remaining = due ? Math.max(0,Math.ceil((due.getTime()-Date.now())/86400000)) : 0;
      const pending = d.status === 'pending';
      const dueLabel = due ? due.toLocaleString() : 'Unknown';
      return '<div class="dev-row"><div style="min-width:0"><strong>' + escapeHtml(d.target_email) + '</strong><div class="dev-meta">' + escapeHtml(d.status.toUpperCase()) + ' · ' + (pending && remaining > 0 ? remaining + ' days remaining' : pending ? 'Eligible for permanent deletion' : 'Closed') + '</div><div class="dev-meta">Scheduled: ' + escapeHtml(dueLabel) + '</div><div class="dev-meta">Request: ' + escapeHtml(d.id) + '</div>' + (d.failure_note ? '<div class="dev-meta">Note: ' + escapeHtml(d.failure_note) + '</div>' : '') + '</div><div class="dev-actions">' + (pending && remaining > 0 ? '<button data-cancel-deletion="' + escapeHtml(d.id) + '">Cancel &amp; restore</button>' : '') + (pending && remaining <= 0 ? '<button class="danger" data-process-deletion="' + escapeHtml(d.id) + '">Permanently delete</button>' : '') + '</div></div>';
    }).join('') || '<div class="dev-meta">No account deletion requests.</div>';
    host.querySelectorAll('[data-cancel-deletion]').forEach(button => {
      button.onclick = async () => {
        if (!confirm('Cancel this deletion request and restore the account to its previous access state?')) return;
        button.disabled = true;
        const result = await client.rpc('cancel_platform_account_deletion',{p_request_id:button.dataset.cancelDeletion});
        if (result.error) { say(result.error.message); button.disabled = false; return; }
        say('Deletion request cancelled. Previous account access state restored.');
        await loadDeveloperAccounts(); await loadDeveloperDeletionRequests();
      };
    });
    host.querySelectorAll('[data-process-deletion]').forEach(button => {
      button.onclick = async () => {
        const requestId = button.dataset.processDeletion;
        if (!confirm('PERMANENTLY DELETE this account from Supabase Auth? The 30-day recovery period has ended. This cannot be undone. Business-owner accounts are blocked.')) return;
        button.disabled = true; button.textContent = 'Processing…';
        const {data,error} = await client.functions.invoke('process-account-deletions',{body:{request_id:requestId}});
        if (error) { say('Secure deletion function error: ' + error.message + '. Confirm the Edge Function is deployed.'); button.disabled = false; button.textContent = 'Permanently delete'; return; }
        say(data?.message || 'Deletion function completed.');
        await loadDeveloperAccounts(); await loadDeveloperDeletionRequests(); await loadDeveloperActivity();
      };
    });
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

  function syncStatus(message) {
    const el = $('wlSyncStatus');
    if (el) el.textContent = message;
  }
  async function updateSyncStatus() {
    if (!activeBusiness) return;
    const names = ['products','customers','suppliers','expenses'];
    let pending = 0;
    for (const name of names) {
      const rows = await all(name);
      pending += rows.filter(row => !row.cloudSyncedFor || row.cloudSyncedFor !== activeBusiness.id).length;
    }
    const txRows = [...await all('sales'), ...await all('purchases')];
    const txPending = txRows.filter(row => row.cloudSyncedFor !== activeBusiness.id).length;
    syncStatus(pending + ' master/expense records and ' + txPending + ' sales/purchases pending for this workspace.');
  }

  async function downloadCloudRecords() {
    if (!client || !activeBusiness) return say('Select a business before downloading cloud records.');
    const button=$('wlDownloadNow'); if(button)button.disabled=true;
    syncStatus('Downloading cloud records…');
    let added=0,updated=0,skipped=0;
    try {
      const businessId=activeBusiness.id;
      const localProducts=await all('products'), localCustomers=await all('customers'),
        localSuppliers=await all('suppliers'), localExpenses=await all('expenses'),
        localSales=await all('sales'), localPurchases=await all('purchases');
      const [pRes,cRes,sRes,eRes]=await Promise.all([
        client.from('products').select('id,client_record_id,sku,name,category,unit,cost_price,selling_price,reorder_level,is_active').eq('business_id',businessId),
        client.from('customers').select('id,client_record_id,name,phone,email,address,notes').eq('business_id',businessId),
        client.from('suppliers').select('id,client_record_id,name,phone,email,address,notes').eq('business_id',businessId),
        client.from('expenses').select('id,client_record_id,category,description,amount,payment_method,expense_date').eq('business_id',businessId)
      ]);
      for(const [label,result] of [['products',pRes],['customers',cRes],['suppliers',sRes],['expenses',eRes]]) if(result.error)throw new Error('Could not download '+label+': '+result.error.message);
      const branches=window.__wlBranches||[];
      const branchIds=branches.map(b=>b.id);
      const inventoryResult=branchIds.length?await client.from('branch_inventory').select('branch_id,product_id,quantity_on_hand').eq('business_id',businessId).in('branch_id',branchIds):{data:[],error:null};
      if(inventoryResult.error)throw new Error('Could not download branch stock: '+inventoryResult.error.message);
      const selectedStock=new Map((inventoryResult.data||[]).filter(x=>x.branch_id===selectedBranch?.id).map(x=>[x.product_id,Number(x.quantity_on_hand||0)]));
      const productMap=new Map();
      for(const cloud of pRes.data||[]){
        const old=localProducts.find(x=>x.cloudClientRecordId===cloud.client_record_id);
        if(old&&old.cloudSyncedFor!==businessId){skipped++;continue;}
        const row={...(old||{}),id:old?.id||('cloud-product-'+cloud.client_record_id),
          cloudClientRecordId:cloud.client_record_id,cloudSyncedFor:businessId,cloudSyncedAt:new Date().toISOString(),
          name:cloud.name,sku:cloud.sku||'',category:cloud.category||'',unit:cloud.unit||'unit',
          cost:Number(cloud.cost_price||0),price:Number(cloud.selling_price||0),reorder:Number(cloud.reorder_level||0),
          stock:selectedStock.get(cloud.id)||0,active:cloud.is_active};
        await put('products',row);productMap.set(cloud.id,row.id);old?updated++:added++;
      }
      const syncSimple=async(type,rows,localRows,mapRow)=>{
        for(const cloud of rows||[]){
          const old=localRows.find(x=>x.cloudClientRecordId===cloud.client_record_id);
          if(old&&old.cloudSyncedFor!==businessId){skipped++;continue;}
          const row={...(old||{}),id:old?.id||('cloud-'+type+'-'+cloud.client_record_id),
            cloudClientRecordId:cloud.client_record_id,cloudSyncedFor:businessId,
            cloudSyncedAt:new Date().toISOString(),...mapRow(cloud)};
          await put(type,row);old?updated++:added++;
        }
      };
      await syncSimple('customers',cRes.data,localCustomers,r=>({name:r.name,phone:r.phone||'',email:r.email||'',address:r.address||'',notes:r.notes||''}));
      await syncSimple('suppliers',sRes.data,localSuppliers,r=>({name:r.name,phone:r.phone||'',email:r.email||'',address:r.address||'',notes:r.notes||''}));
      await syncSimple('expenses',eRes.data,localExpenses,r=>({category:r.category,description:r.description,amount:Number(r.amount||0),payment:r.payment_method||'cash',date:r.expense_date}));
      const [saleRes,purchaseRes]=await Promise.all([
        client.from('offline_sales').select('id,client_transaction_id,receipt,transaction_date,customer_name,payment_method,total,branch_id').eq('business_id',businessId),
        client.from('offline_purchases').select('id,client_transaction_id,transaction_date,supplier_name,total,branch_id').eq('business_id',businessId)
      ]);
      if(saleRes.error)throw new Error('Could not download sales: '+saleRes.error.message);
      if(purchaseRes.error)throw new Error('Could not download purchases: '+purchaseRes.error.message);
      const [saleItemsRes,purchaseItemsRes]=await Promise.all([
        client.from('offline_sale_items').select('sale_id,product_id,product_name,quantity,unit_price,line_total').eq('business_id',businessId),
        client.from('offline_purchase_items').select('purchase_id,product_id,product_name,quantity,unit_cost,line_total').eq('business_id',businessId)
      ]);
      if(saleItemsRes.error)throw new Error('Could not download sale items: '+saleItemsRes.error.message);
      if(purchaseItemsRes.error)throw new Error('Could not download purchase items: '+purchaseItemsRes.error.message);
      const importTransactions=async(type,rows,itemRows)=>{
        for(const cloud of rows||[]){
          const old=(type==='sales'?localSales:localPurchases).find(x=>x.cloudTransactionId===cloud.client_transaction_id);
          if(old&&old.cloudSyncedFor!==businessId){skipped++;continue;}
          const items=itemRows.filter(i=>i[type==='sales'?'sale_id':'purchase_id']===cloud.id).map(i=>({
            productId:productMap.get(i.product_id)||('cloud-product-id-'+i.product_id),
            name:i.product_name,quantity:Number(i.quantity),
            ...(type==='sales'?{unitPrice:Number(i.unit_price)}:{unitCost:Number(i.unit_cost),cost:Number(i.unit_cost)})
          }));
          const row={...(old||{}),id:old?.id||('cloud-'+type+'-'+cloud.client_transaction_id),
            cloudTransactionId:cloud.client_transaction_id,cloudSyncedFor:businessId,
            cloudSyncedAt:new Date().toISOString(),branchId:cloud.branch_id||null,
            receipt:cloud.receipt||('PUR-'+cloud.client_transaction_id.slice(0,10)),
            date:cloud.transaction_date,customer:cloud.customer_name||'',supplier:cloud.supplier_name||'',
            payment:cloud.payment_method||'cash',total:Number(cloud.total||0),items};
          await put(type,row);old?updated++:added++;
        }
      };
      await importTransactions('sales',saleRes.data,saleItemsRes.data||[]);
      await importTransactions('purchases',purchaseRes.data,purchaseItemsRes.data||[]);
      syncStatus('Download complete: '+added+' new, '+updated+' refreshed, '+skipped+' local unsynced records preserved.');
      say('Cloud download completed. Local unsynced records were preserved.');
      window.dispatchEvent(new CustomEvent('whiteLionCloudDownloaded'));
    } catch(error) {
      syncStatus('Download paused: '+error.message+'. Existing local records were preserved where possible.');
      say('Cloud download error: '+error.message);
    } finally {if(button)button.disabled=false;}
  }

  async function syncLocalRecords() {
    if (!client || !session || !activeBusiness) return say('Sign in and select a business workspace first.');
    if (!navigator.onLine) { syncStatus('Offline. Records remain safely on this device; reconnect to sync.'); return; }
    if (!confirm('Upload this device’s local products, customers, suppliers, expenses, sales and purchases into “' + activeBusiness.name + '”? Continue only if ALL these local records belong in this workspace.')) return;
    const button = $('wlSyncNow');
    if (button) { button.disabled = true; button.textContent = 'Syncing…'; }
    const types = ['products','customers','suppliers','expenses'];
    let total = 0, transactionTotal = 0;
    try {
      for (const type of types) {
        const rows = await all(type);
        for (const row of rows) {
          const localId = String(row.id);
          let stableId = row.cloudClientRecordId;
          if (!stableId) {
            stableId = crypto.randomUUID();
            row.cloudClientRecordId = stableId;
            await put(type, row);
          }
          if (row.cloudSyncedFor === activeBusiness.id) continue;
          if (type === 'products' && !selectedBranch?.id) throw new Error('Select an active branch before syncing product opening stock.');
          const payload = type === 'products' ? {
            branch_id:selectedBranch.id,
            client_record_id:stableId, sku:row.sku || null, name:row.name || 'Unnamed product',
            category:row.category || null, unit:row.unit || 'unit',
            cost_price:Number(row.cost || 0), selling_price:Number(row.price || 0),
            reorder_level:Number(row.reorder || 0), quantity_on_hand:Number(row.stock || 0)
          } : type === 'expenses' ? {
            client_record_id:stableId, category:row.category || 'General',
            description:row.description || 'Expense', amount:Number(row.amount || 0),
            payment_method:row.payment || 'cash', expense_date:row.date || new Date().toISOString().slice(0,10)
          } : {
            client_record_id:stableId, name:row.name || (type === 'customers' ? 'Unnamed customer':'Unnamed supplier'),
            phone:row.phone || null, email:row.email || null, address:row.address || null, notes:row.notes || null
          };
          const {data,error} = await client.rpc('sync_local_records', {
            p_business_id:activeBusiness.id,
            p_event_id:type + ':' + stableId,
            p_record_type:type,
            p_records:[payload]
          });
          if (error) throw new Error(type + ' record ' + localId + ': ' + error.message);
          row.cloudSyncedFor = activeBusiness.id;
          row.cloudSyncedAt = new Date().toISOString();
          await put(type,row);
          total++;
        }
      }
      // Transactions are posted only after master data, especially products, has cloud IDs.
      const productRows = await all('products');
      const productByLocalId = new Map(productRows.map(p => [String(p.id), p]));
      for (const type of ['sales','purchases']) {
        const rows = await all(type);
        for (const row of rows) {
          if (row.cloudSyncedFor === activeBusiness.id) continue;
          if (!row.branchId) throw new Error('Transaction ' + (row.receipt || row.id) + ' has no saved branch. Select a branch when recording new transactions; older transactions must be assigned deliberately before syncing.');
          if (!row.cloudTransactionId) {
            row.cloudTransactionId = crypto.randomUUID();
            await put(type, row);
          }
          const sourceItems = Array.isArray(row.items) && row.items.length ? row.items :
            (type === 'purchases' ? [{productId:row.productId, name:row.product, quantity:row.quantity, unitPrice:row.cost}] : []);
          if (!sourceItems.length) throw new Error(type + ' transaction ' + (row.receipt || row.cloudTransactionId) + ' has no item details.');
          const items = sourceItems.map(item => {
            const product = productByLocalId.get(String(item.productId));
            if (!product || !product.cloudClientRecordId || product.cloudSyncedFor !== activeBusiness.id) {
              throw new Error('A product in ' + type + ' ' + (row.receipt || row.cloudTransactionId) + ' is not synced to this workspace. Sync products first.');
            }
            return {
              product_client_record_id:product.cloudClientRecordId,
              product_name:item.name || product.name || 'Product',
              quantity:Number(item.quantity || 0), apply_stock:!!(row.createdAt && product.cloudSyncedAt && row.createdAt > product.cloudSyncedAt),
              ...(type === 'sales' ? {unit_price:Number(item.unitPrice ?? product.price ?? 0)} : {unit_cost:Number(item.unitCost ?? item.cost ?? row.cost ?? product.cost ?? 0)})
            };
          });
          const payload = {
            client_transaction_id:row.cloudTransactionId,
            receipt:row.receipt || null,
            transaction_date:row.date || new Date().toISOString().slice(0,10),
            customer_name:row.customer || null,
            supplier_name:row.supplier || null,
            payment_method:row.payment || 'cash',
            total:Number(row.total || 0),
            items
          };
          const {data,error} = await client.rpc('sync_branch_transaction', {
            p_business_id:activeBusiness.id,
            p_branch_id:row.branchId,
            p_event_id:type + ':' + row.cloudTransactionId,
            p_transaction_type:type,
            p_transaction:payload
          });
          if (error) throw new Error(type + ' transaction ' + (row.receipt || row.cloudTransactionId) + ': ' + error.message);
          const {data: receipt, error: receiptError} = await client.from('offline_sync_receipts')
            .select('event_id,record_type,record_count')
            .eq('business_id', activeBusiness.id)
            .eq('event_id', type + ':' + row.cloudTransactionId)
            .maybeSingle();
          if (receiptError) throw new Error('Could not verify cloud receipt for ' + (row.receipt || row.cloudTransactionId) + ': ' + receiptError.message);
          if (!receipt) throw new Error('The cloud RPC returned but no sync receipt was found for ' + (row.receipt || row.cloudTransactionId) + '. The local transaction is still pending.');
          row.cloudSyncedFor = activeBusiness.id;
          row.cloudSyncedAt = new Date().toISOString();
          row.cloudSyncResult = data?.status || 'synced';
          await put(type,row);
          transactionTotal++;
        }
      }
      syncStatus('Sync complete: ' + total + ' master/expense records and ' + transactionTotal + ' transactions uploaded or confirmed.');
      say('Cloud sync completed: ' + total + ' records and ' + transactionTotal + ' transactions.');
    } catch (error) {
      syncStatus('Sync paused: ' + error.message + '. Local records are preserved; retry when ready.');
    } finally {
      if (button) { button.disabled = false; button.textContent = 'Sync local records'; }
      await updateSyncStatus();
    }
  }
  window.addEventListener('online', () => {
    if (activeBusiness) syncStatus('Internet restored. Tap Sync local records to upload pending records and transactions.');
  });

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
        getActiveBusiness: () => activeBusiness,
        getSelectedBranch: () => selectedBranch,
        getBranches: () => (window.__wlBranches || []).filter(b => b.is_active)
      };
      window.dispatchEvent(new CustomEvent('whiteLionCloudReady'));
    } catch (error) {
      say(error.message || 'Cloud connection could not be initialised.');
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();