/* White Lion SME OS — Supabase workspace, master-data and atomic transaction sync. */
(() => {
  const SUPABASE_URL = 'https://nclncqlgnxnijlumznnt.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_iPIsAysPnlvPCAoqntoNRg_dKcSZxKX';
  const $ = (id) => document.getElementById(id);
  let client = null, session = null, activeBusiness = null, selectedBranch = null;

  const style = document.createElement('style');
  style.textContent = `
    #wlCloudBox{background:linear-gradient(135deg,#fff 0%,#f5faf6 100%);border:1px solid #dcebe1;border-radius:16px;padding:16px;color:#203b2b;font-size:12px;box-shadow:0 8px 24px rgba(7,91,53,.06)}
    #wlCloudBox>div:first-child{color:#075b35;letter-spacing:.7px;font-size:12px}
    #wlCloudBox button{border:1px solid #087a43;border-radius:9px;padding:9px 12px;background:linear-gradient(135deg,#087a43,#075b35);color:#fff;font-weight:750;margin:5px 5px 0 0}
    #wlCloudBox button:hover{filter:brightness(1.05)}
    #wlCloudBox input,#wlCloudBox select{width:100%;min-width:0;box-sizing:border-box;padding:10px 11px;border:1px solid #dce8df;border-radius:9px;background:#fff;color:#203b2b;margin:5px 0}
    #wlCloudBox .muted{color:#718078;font-size:10px;line-height:1.55}#wlCloudBox .cloud-actions{display:flex;flex-wrap:wrap;gap:5px}
    #wlCloudBox .cloud-status{margin:8px 0;color:#087a43;overflow-wrap:anywhere;line-height:1.5}
    #wlCloudBox details{margin-top:10px;padding:10px 12px;border:1px solid #e2ece5;border-radius:12px;background:rgba(255,255,255,.8)}
    #wlCloudBox summary{cursor:pointer;color:#075b35;font-weight:800}
    #wlCloudBox .branch-stock{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px;padding:9px 2px;border-bottom:1px solid #e8f0ea;color:#31483a}
    #wlCloudBox .branch-note{color:#718078;font-size:10px;margin:7px 0;overflow-wrap:anywhere}
    #wlCloudBox .branch-create-grid{display:grid;grid-template-columns:1fr 1.4fr auto;gap:7px;align-items:center;margin:10px 0}
    #wlCloudBox .branch-create-grid input{margin:0}
    #wlCloudBox .branch-create-grid button{margin:0;white-space:nowrap}
    @media(max-width:620px){#wlCloudBox{padding:13px;border-radius:13px}#wlCloudBox .branch-create-grid{grid-template-columns:1fr}#wlCloudBox .branch-create-grid button{width:100%;min-height:42px}#wlCloudBox .cloud-actions button{flex:1 1 auto}}
    #wlDeveloperBox{margin-top:14px;background:#111d32;border:1px solid #b58c3d;border-radius:13px;padding:15px;color:#fff;font-size:12px}
    #wlDeveloperBox h3{margin:0 0 8px;color:#f0d28b;font-size:15px}
    #wlDeveloperBox button{border:0;border-radius:8px;padding:8px 10px;background:#d6ad57;color:#152238;font-weight:700;margin:5px 5px 5px 0}
    #wlDeveloperBox button.danger{background:#d86b70;color:#fff}
    #wlDeveloperBox .dev-row{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:9px 0;border-top:1px solid #34435b}
    #wlDeveloperBox .dev-meta{color:#bac6d8;font-size:10px}
    #wlDeveloperBox .dev-actions{display:flex;flex-wrap:wrap;gap:4px}
    #wlDeveloperBox .dev-role-manager{margin:14px 0;padding:14px;border:1px solid #657b99;border-radius:12px;background:#192a43}
    #wlDeveloperBox .dev-role-grid{display:grid;grid-template-columns:1fr 1fr;gap:9px}
    #wlDeveloperBox .dev-role-manager label{display:block;color:#d9e4f2;font-size:10px;font-weight:800;margin:5px 0}
    #wlDeveloperBox .dev-role-manager select{width:100%;box-sizing:border-box;padding:10px;border:1px solid #64748b;border-radius:8px;background:#fff;color:#17243a;margin:0}
    #wlDeveloperBox .dev-role-manager button{margin-top:10px}
    #wlDeveloperBox .dev-role-help{color:#bac6d8;font-size:10px;line-height:1.55;margin-top:8px}
    @media(max-width:620px){#wlDeveloperBox .dev-role-grid{grid-template-columns:1fr}#wlDeveloperBox .dev-row{align-items:flex-start;flex-direction:column}#wlDeveloperBox .dev-actions{width:100%}}
    .app.wl-public-mode{display:block;min-height:100vh;background:radial-gradient(circle at 12% 8%,rgba(30,181,58,.10),transparent 34%),linear-gradient(135deg,#f5faf6 0%,#fff 58%,#edf7f0 100%)}
    .wl-public-mode .sidebar,.wl-public-mode .topbar,.wl-public-mode #wlInstallBanner,.wl-public-mode #appearanceBar,.wl-public-mode .content,.wl-public-mode .footer{display:none!important}
    .wl-public-mode .main{min-height:100vh;width:100%;padding:clamp(14px,3vw,34px);display:flex;flex-direction:column;align-items:center;justify-content:center}
    .wl-public-mode #wlCloudBox{width:min(1080px,100%);margin:0!important;padding:clamp(20px,4vw,46px)!important;border:1px solid #dcebe1;border-radius:26px;background:#fff;box-shadow:0 28px 90px rgba(7,91,53,.12);color:#203b2b}
    .wl-public-mode #wlCloudBox .wl-public-brand{display:flex;align-items:center;gap:11px;margin-bottom:clamp(22px,4vw,42px)}
    .wl-public-mode #wlCloudBox .wl-public-mark{width:46px;height:46px;display:grid;place-items:center;border-radius:15px;background:linear-gradient(145deg,#1eb53a 0 38%,#fff 38% 66%,#0072c6 66% 100%);border:1px solid #dcebe1;color:#075b35;font-size:21px;font-weight:900}
    .wl-public-mode #wlCloudBox .wl-public-brand strong{display:block;font-size:13px;letter-spacing:1.6px;color:#075b35}
    .wl-public-mode #wlCloudBox .wl-public-brand small{display:block;color:#829187;font-size:9px;letter-spacing:1.5px}
    .wl-public-mode #wlCloudBox .wl-public-grid{display:grid;grid-template-columns:minmax(0,1.15fr) minmax(280px,.85fr);gap:clamp(24px,5vw,64px);align-items:center}
    .wl-public-mode #wlCloudBox .wl-public-kicker{color:#087a43;font-size:10px;font-weight:850;letter-spacing:2px;text-transform:uppercase}
    .wl-public-mode #wlCloudBox .wl-public-copy h1{font-size:clamp(30px,5vw,54px);line-height:1.06;letter-spacing:-1.8px;color:#123b27;margin:12px 0 15px}
    .wl-public-mode #wlCloudBox .wl-public-copy p{font-size:14px;line-height:1.8;color:#66776d;max-width:570px;margin:0}
    .wl-public-mode #wlCloudBox .wl-public-features{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-top:25px}
    .wl-public-mode #wlCloudBox .wl-public-feature{padding:13px;border:1px solid #e4eee7;border-radius:13px;background:#f8fcf9}
    .wl-public-mode #wlCloudBox .wl-public-feature b{display:block;color:#17452e;font-size:12px;margin-bottom:4px}
    .wl-public-mode #wlCloudBox .wl-public-feature span{display:block;color:#718078;font-size:10px;line-height:1.55}
    .wl-public-mode #wlCloudBox .wl-public-auth{padding:clamp(18px,3vw,28px);border:1px solid #e2ece5;border-radius:19px;background:linear-gradient(160deg,#fbfefc,#f4faf6)}
    .wl-public-mode #wlCloudBox .wl-public-auth h2{font-size:21px;color:#173d29;margin:0 0 6px}
    .wl-public-mode #wlCloudBox .wl-public-auth .wl-public-auth-note{font-size:11px;line-height:1.6;color:#738278;margin:0 0 15px}
    .wl-public-mode #wlCloudBox input{padding:13px 12px;margin:6px 0;border-color:#d9e7dd;border-radius:10px;font-size:13px}
    .wl-public-mode #wlCloudBox .cloud-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:12px}
    .wl-public-mode #wlCloudBox .cloud-actions button{min-height:45px;margin:0;border-radius:10px;font-size:12px}
    .wl-public-mode #wlCloudBox #wlSignUp{background:#fff;color:#075b35}
    .wl-public-mode #wlCloudBox .wl-public-privacy{font-size:10px;line-height:1.6;color:#819087;margin:13px 0 0}
    .wl-public-mode #wlCloudBox .cloud-status{font-size:11px;min-height:17px}
    .wl-public-mode .main:after{content:"Designed by Alhaji Abu Koroma · White Lion Tech Solutions";display:block;text-align:center;color:#8a9a90;font-size:10px;margin:20px 0 0}
    @media(max-width:760px){.wl-public-mode .main{padding:12px;justify-content:flex-start}.wl-public-mode #wlCloudBox{padding:21px!important;border-radius:19px;margin:8px 0!important}.wl-public-mode #wlCloudBox .wl-public-grid{grid-template-columns:1fr;gap:22px}.wl-public-mode #wlCloudBox .wl-public-copy h1{font-size:34px;letter-spacing:-1.2px}.wl-public-mode #wlCloudBox .wl-public-brand{margin-bottom:24px}.wl-public-mode #wlCloudBox .wl-public-features{gap:8px}.wl-public-mode #wlCloudBox .wl-public-feature{padding:11px}.wl-public-mode #wlCloudBox .wl-public-auth{padding:17px}}
    @media(prefers-reduced-motion:no-preference){.wl-public-mode #wlCloudBox{animation:wlWelcomeIn .45s ease-out both}@keyframes wlWelcomeIn{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}}
  `;
  style.textContent = style.textContent.replace(/#wlCloudBox/g, '#wlCloudBox:not(.wl-auth-shell)');
  style.textContent += `
    .wl-auth-shell #wlCloudWork{margin-top:18px;padding-top:16px;border-top:1px solid #e7edf2;color:#344258;max-height:62vh;overflow:auto}
    .wl-auth-shell #wlCloudWork select,.wl-auth-shell #wlCloudWork input{width:100%;min-width:0;box-sizing:border-box;padding:10px 11px;border:1px solid #dfe5ee;border-radius:9px;background:#fff;color:#24334a;margin:5px 0}
    .wl-auth-shell #wlCloudWork .cloud-actions{display:flex;flex-wrap:wrap;gap:7px;margin:10px 0}
    .wl-auth-shell #wlCloudWork button{border:1px solid #173d34;border-radius:9px;padding:9px 12px;background:linear-gradient(135deg,#1b7658,#124b3d);color:#fff;font-weight:750;margin:0}
    .wl-auth-shell #wlCloudWork button:hover{filter:brightness(1.06)}
    .wl-auth-shell #wlCloudWork .cloud-status{margin:8px 0;color:#526477;font-size:11px;line-height:1.5;overflow-wrap:anywhere}
    .wl-auth-shell #wlCloudWork details{margin-top:10px;padding:10px 12px;border:1px solid #e2e8ef;border-radius:11px;background:#f8fafc}
    .wl-auth-shell #wlCloudWork summary{cursor:pointer;color:#244b40;font-weight:800}
    .wl-auth-shell #wlCloudWork .muted{color:#718096;font-size:10px;line-height:1.55}
    .wl-auth-shell #wlCloudWork .branch-create-grid{display:grid;grid-template-columns:1fr 1.4fr auto;gap:7px;align-items:center;margin:10px 0}
    @media(max-width:620px){.wl-auth-shell #wlCloudWork .branch-create-grid{grid-template-columns:1fr}.wl-auth-shell #wlCloudWork .branch-create-grid button{width:100%;min-height:42px}}
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
    if (!host || !anchor) return;
    const box = $('wlCloudBox') || document.createElement('section');
    box.id = 'wlCloudBox';
    if (box.classList.contains('wl-auth-shell') && $('wlCloudAuth') && $('wlCloudWork')) {
      // Keep the premium login markup from index.html; only hydrate the authenticated workspace.
      $('wlCloudWork').innerHTML = `
        <select id="wlBusinessSelect" aria-label="Choose business"></select>
        <div class="cloud-actions"><button id="wlCreateBusiness">＋ New business</button><button id="wlSyncNow">Upload local records</button><button id="wlDiagnoseData" type="button">Check local/cloud data</button><div id="wlDataDiagnostic" class="cloud-status" role="status" aria-live="polite">Diagnostic has not been run. This check will not upload, delete or modify records.</div><button id="wlDownloadNow">Download cloud records</button><button id="wlSignOut">Sign out</button></div><div id="wlSyncStatus" class="cloud-status">Local records are not yet synced.</div>
        <details id="wlBranchManager" open><summary>Branch management</summary>
          <div class="muted" style="margin:7px 0">Manage outlets, choose the active working location, assign staff and review stock by branch.</div>
          <label class="muted" for="wlBranchSelect">Active working branch</label>
          <select id="wlBranchSelect" aria-label="Select active branch"><option value="">Loading branches…</option></select>
          <div class="branch-create-grid">
            <input id="wlNewBranchName" type="text" maxlength="100" placeholder="New branch name" aria-label="New branch name">
            <input id="wlNewBranchAddress" type="text" maxlength="240" placeholder="Branch address (optional)" aria-label="Branch address">
            <button id="wlCreateBranch" type="button">＋ Add branch</button>
          </div>
          <div class="cloud-actions"><button id="wlRefreshBranches" type="button">Refresh branch list</button></div>
          <div id="wlBranchStatus" class="cloud-status">Select a business to load its branches.</div>
          <div id="wlBranchInventory" class="muted"></div>
          <details><summary>Assign staff to this branch</summary>
            <select id="wlBranchMemberSelect" aria-label="Select business member"><option value="">Load business members…</option></select>
            <div class="cloud-actions"><button id="wlAssignBranchMember">Assign staff</button><button id="wlRemoveBranchMember">Deactivate assignment</button></div>
            <div id="wlBranchMembers" class="muted"></div>
          </details>
        </details>
        <details><summary>Business modules</summary><div id="wlModules" class="muted">Select a business to view modules.</div></details>
`;
    } else {
      // Backward-compatible fallback for pages that do not contain the premium login shell.
      box.innerHTML = `

      <div class="wl-public-brand"><span class="wl-public-mark" aria-hidden="true">W</span><span><strong>WHITE LION</strong><small>BUSINESS SYSTEMS · SME BUSINESS OS</small></span></div>
      <div id="wlCloudAuth" class="wl-public-grid">
        <div class="wl-public-copy">
          <div class="wl-public-kicker">One platform. Your whole business.</div>
          <h1>Run your business with clarity and confidence.</h1>
          <p>Manage sales, stock, purchases, customers, branches and business performance in one connected workspace. Start with your own account and set up your business when you are ready.</p>
          <div class="wl-public-features">
            <div class="wl-public-feature"><b>Sales &amp; inventory</b><span>Keep daily transactions and stock activity organised.</span></div>
            <div class="wl-public-feature"><b>Finance &amp; reports</b><span>Understand business activity with useful records and insights.</span></div>
            <div class="wl-public-feature"><b>Multi-branch operations</b><span>Manage outlets and staff from one business workspace.</span></div>
            <div class="wl-public-feature"><b>Online &amp; offline-ready</b><span>Continue working locally and sync records when connected.</span></div>
          </div>
        </div>
        <div class="wl-public-auth">
          <h2>Get started</h2>
          <p class="wl-public-auth-note">Create your account to set up your own business workspace, or sign in if you already have one.</p>
          <input id="wlCloudEmail" type="email" autocomplete="email" placeholder="Email address" aria-label="Email address">
          <input id="wlCloudPassword" type="password" autocomplete="current-password" placeholder="Password (minimum 8 characters)" aria-label="Password">
          <div class="cloud-actions"><button id="wlSignUp" type="button">Create your account</button><button id="wlSignIn" type="button">Sign in</button></div>
          <p class="wl-public-privacy">Your account is separate from other businesses. You only see workspaces you are authorised to access. Email confirmation may be required before your first sign-in.</p>
        </div>
      </div>
      <div id="wlCloudStatus" class="cloud-status" role="status" aria-live="polite">Connecting securely…</div>
      <div id="wlCloudWork" hidden>
        <select id="wlBusinessSelect" aria-label="Choose business"></select>
        <div class="cloud-actions"><button id="wlCreateBusiness">＋ New business</button><button id="wlSyncNow">Upload local records</button><button id="wlDiagnoseData" type="button">Check local/cloud data</button><div id="wlDataDiagnostic" class="cloud-status" role="status" aria-live="polite">Diagnostic has not been run. This check will not upload, delete or modify records.</div><button id="wlDownloadNow">Download cloud records</button><button id="wlSignOut">Sign out</button></div><div id="wlSyncStatus" class="cloud-status">Local records are not yet synced.</div>
        <details id="wlBranchManager" open><summary>Branch management</summary>
          <div class="muted" style="margin:7px 0">Manage outlets, choose the active working location, assign staff and review stock by branch.</div>
          <label class="muted" for="wlBranchSelect">Active working branch</label>
          <select id="wlBranchSelect" aria-label="Select active branch"><option value="">Loading branches…</option></select>
          <div class="branch-create-grid">
            <input id="wlNewBranchName" type="text" maxlength="100" placeholder="New branch name" aria-label="New branch name">
            <input id="wlNewBranchAddress" type="text" maxlength="240" placeholder="Branch address (optional)" aria-label="Branch address">
            <button id="wlCreateBranch" type="button">＋ Add branch</button>
          </div>
          <div class="cloud-actions"><button id="wlRefreshBranches" type="button">Refresh branch list</button></div>
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
    }
    anchor.insertAdjacentElement('afterend', box);
    const dev = document.createElement('section');
    dev.id = 'wlDeveloperBox';
    dev.hidden = true;
    dev.innerHTML = `
      <h3>WHITE LION · PRIVATE DEVELOPER CONSOLE</h3>
      <div id="wlDevIdentity" class="dev-meta">Verifying developer permissions…</div>
      <div id="wlDevStatus" class="cloud-status">Loading secure platform controls…</div>
      <div id="wlDevStats" class="dev-meta"></div>
      <div id="wlDevAlertSettingsPanel" style="display:block;visibility:visible;margin:14px 0;padding:14px;border:2px solid #4f8a5b;border-radius:12px;background:#152a1e;color:#fff;position:relative;z-index:2">
        <h3 style="margin:0 0 8px;color:#9fe3ae;font-size:16px">EMAIL ALERTS</h3>
        <div style="color:#bac6d8;font-size:11px;margin-bottom:8px">Get an email the moment someone registers a new account or submits a payment. Requires a one-time Resend API key setup (see below).</div>
        <div class="dev-role-grid">
          <div><label for="wlDevAlertEmail">Alert email address</label><input id="wlDevAlertEmail" type="email" placeholder="you@example.com" style="width:100%;box-sizing:border-box;padding:10px;border:1px solid #64748b;border-radius:8px;background:#fff;color:#17243a"></div>
          <div><label for="wlDevAlertEnabled">Alerts</label><select id="wlDevAlertEnabled"><option value="true" selected>Enabled</option><option value="false">Paused</option></select></div>
        </div>
        <button id="wlDevAlertSave" type="button">Save alert settings</button>
        <button id="wlDevAlertRefresh" type="button">Refresh</button>
        <div id="wlDevAlertStatus" class="dev-meta" style="margin-top:6px">Loading alert settings…</div>
      </div>
      <div id="wlDevCustomerRegistrationPanel" style="display:block;visibility:visible;margin:14px 0;padding:14px;border:2px solid #d6ad57;border-radius:12px;background:#192a43;color:#fff;position:relative;z-index:2"><h3 style="margin:0 0 8px;color:#f0d28b;font-size:16px">NEW CUSTOMER REGISTRATIONS</h3><div style="color:#bac6d8;font-size:11px;margin-bottom:8px">New platform accounts and their email addresses appear here.</div><button id="wlDevRegistrationsRefresh" type="button">Refresh customer registrations</button><div id="wlDevRegistrations" class="dev-meta" style="display:block;visibility:visible;min-height:28px">Customer registration notifications load after developer verification.</div></div>
      <section class="dev-role-manager" id="wlDevRoleManager">
        <h3 style="margin:0 0 5px;color:#f0d28b">Assign or change a user's business role</h3>
        <div class="dev-role-help">Select a business workspace and a registered account. This grants or updates that person's access to the selected business only.</div>
        <div class="dev-role-grid">
          <div><label for="wlDevRoleBusiness">Business workspace</label><select id="wlDevRoleBusiness"><option value="">Loading business workspaces…</option></select></div>
          <div><label for="wlDevRoleAccount">Registered user</label><select id="wlDevRoleAccount"><option value="">Loading registered accounts…</option></select></div>
          <div><label for="wlDevRoleValue">Business role</label><select id="wlDevRoleValue"><option value="admin">Administrator</option><option value="manager" selected>Manager</option><option value="cashier">Cashier</option><option value="storekeeper">Storekeeper</option><option value="accountant">Accountant</option><option value="viewer">Viewer</option></select></div>
          <div><label for="wlDevRoleStatus">Membership access</label><select id="wlDevRoleStatus"><option value="true" selected>Active</option><option value="false">Inactive</option></select></div>
        </div>
        <button id="wlDevRoleSave" type="button">Assign / update business role</button>
        <div id="wlDevRoleStatus" class="dev-role-help">Choose a business and registered account to continue.</div>
      </section>
      <section class="dev-role-manager" id="wlDevRegistrationLimitManager">
        <h3 style="margin:0 0 5px;color:#f0d28b">Multiple business registration permissions</h3>
        <div class="dev-role-help">Ordinary accounts can register one business by default. Select a registered user and set a higher maximum. Set the limit to 1 to revoke the exception. This does not grant Developer access.</div>
        <div class="dev-role-grid">
          <div><label for="wlDevRegistrationUser">Registered user</label><select id="wlDevRegistrationUser"><option value="">Loading registered accounts…</option></select></div>
          <div><label for="wlDevRegistrationMax">Maximum businesses</label><input id="wlDevRegistrationMax" type="number" min="2" max="1000" step="1" value="2" style="width:100%;box-sizing:border-box;padding:10px;border:1px solid #64748b;border-radius:8px;background:#fff;color:#17243a"></div>
        </div>
        <button id="wlDevRegistrationLimitSave" type="button">Grant / update permission</button>
        <button id="wlDevRegistrationLimitRefresh" type="button">Refresh permissions</button>
        <div id="wlDevRegistrationLimitStatus" class="dev-role-help">No additional-business permissions loaded yet.</div>
        <div id="wlDevRegistrationLimits" class="dev-meta">Loading permissions…</div>
      </section>
      <div class="dev-actions">
        <button id="wlDevRefresh">Refresh dashboard</button>
        <button id="wlDevFreeze">Freeze platform</button>
        <button id="wlDevAssign">Manage business access</button>
      </div>
      <div style="margin:14px 0;padding:12px;border:1px solid #b85d63;border-radius:10px;background:#351f2b">
        <h3 style="color:#ffd0d0;margin:0 0 6px">Clear demonstration data</h3>
        <div class="dev-meta">Permanently removes all business workspaces and their cloud records, then clears this device's local business records. Your developer sign-in, platform controls and audit history are preserved. Other accounts are disabled immediately and queued for deletion after the existing 30-day recovery period.</div>
        <button id="wlDevResetData" class="danger">Reset all business data</button>
      </div>
      <div id="wlDevBusinesses"></div>
<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin-top:15px"><h3 style="margin:0">New business registrations</h3><button id="wlDevBusinessRegistrationsRefresh" type="button">Refresh businesses</button></div><div id="wlDevBusinessRegistrations" class="dev-meta">Business registration notifications load after developer verification.</div><section class="dev-role-manager" id="wlDevAccountInvitePanel"><h3 style="margin:0 0 6px;color:#f0d28b">Invite administrator account</h3><div class="dev-role-help">Send a secure email invitation and grant access to one selected business workspace. The invited person sets their own password.</div><div class="dev-role-grid"><div><label for="wlDevInviteName">Full name</label><input id="wlDevInviteName" type="text" autocomplete="name" placeholder="Administrator full name"></div><div><label for="wlDevInviteEmail">Email address</label><input id="wlDevInviteEmail" type="email" autocomplete="email" placeholder="admin@example.com"></div><div><label for="wlDevInviteBusiness">Business workspace</label><select id="wlDevInviteBusiness"><option value="">Loading workspaces…</option></select></div><div><label for="wlDevInviteRole">Business role</label><select id="wlDevInviteRole"><option value="admin" selected>Administrator</option><option value="manager">Manager</option><option value="accountant">Accountant</option><option value="storekeeper">Storekeeper</option><option value="cashier">Cashier</option><option value="viewer">Viewer</option></select></div></div><button id="wlDevInviteSubmit" type="button">Send administrator invitation</button><div id="wlDevInviteStatus" class="dev-role-help">Invitation is sent through Supabase Auth. No password is created or displayed here.</div></section><div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin-top:15px"><h3 style="margin:0">Registered accounts</h3><button id="wlDevAccountsRefresh">Refresh accounts</button></div>
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
    $('wlDevAssign').onclick = () => $('wlDevRoleManager')?.scrollIntoView({behavior:'smooth',block:'center'});
    $('wlDevRoleSave').onclick = saveDeveloperBusinessRole;
    $('wlDevRegistrationLimitSave').onclick = saveDeveloperRegistrationLimit;
    $('wlDevRegistrationLimitRefresh').onclick = loadDeveloperRegistrationLimits;
    $('wlDevResetData').onclick = resetDeveloperBusinessData;
    $('wlDevAccountsRefresh').onclick = loadDeveloperAccounts;
    $('wlDevInviteSubmit').onclick = inviteDeveloperAccount;
    $('wlDevRegistrationsRefresh').onclick = loadDeveloperRegistrations;
    $('wlDevBusinessRegistrationsRefresh').onclick = loadDeveloperBusinessRegistrations;
    $('wlDevAlertSave').onclick = saveDeveloperAlertSettings;
    $('wlDevAlertRefresh').onclick = loadDeveloperAlertSettings;
    $('wlDevDeletionRefresh').onclick = loadDeveloperDeletionRequests;
    $('wlDevAuditRefresh').onclick = loadDeveloperActivity;
    $('wlDevAuditSearch').oninput = renderDeveloperActivity;
    $('wlSignIn').onclick = () => authenticate(false);
    $('wlSignUp').onclick = () => authenticate(true);
    $('wlSignOut').onclick = async () => { await client.auth.signOut(); session = null; activeBusiness = null; $('wlDeveloperBox').hidden = true; showSignedOut(); };
    $('wlCreateBusiness').onclick = createBusiness;
    $('wlSyncNow').onclick = syncLocalRecords;
    $('wlDiagnoseData').onclick = diagnoseData;
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
    document.querySelector('.app')?.classList.add('wl-public-mode');
    $('wlCloudAuth').hidden = false; $('wlCloudWork').hidden = true;
    $('wlCloudStatus').textContent = 'Not signed in. Create an account or sign in to continue.';
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
    // Once we know there is a session, the sign-in form must not stay visible —
    // even if the workspace query below fails or returns nothing — otherwise a
    // genuinely signed-in person (e.g. a developer account with no business
    // membership) is stuck looking "not signed in".
    $('wlCloudAuth').hidden = true; $('wlCloudWork').hidden = false;
    const { data: memberships, error } = await client.from('business_members')
      .select('business_id,role,is_active,businesses(id,name,industry,currency_code)')
      .eq('user_id', session.user.id).eq('is_active', true);
    if (error) return say('Could not load workspaces: ' + error.message);
    document.querySelector('.app')?.classList.remove('wl-public-mode');
    const businesses = (memberships || []).map(m => ({...m.businesses, role:m.role})).filter(b => b.id);
    window.__wlBusinesses = businesses;
    $('wlBusinessSelect').innerHTML = businesses.length
      ? businesses.map(b => `<option value="${b.id}">${esc(b.name)} — ${esc(b.role)}</option>`).join('')
      : '<option value="">No business workspace yet</option>';
    if (businesses.length) await selectBusiness(businesses[0]);
    else say('Signed in. Create your first business workspace.');
  }
  async function createBranch() {
    if (!activeBusiness) return say('Select a business workspace first.');
    const name = $('wlNewBranchName')?.value.trim() || '';
    const address = $('wlNewBranchAddress')?.value.trim() || '';
    if (name.length < 2) {
      $('wlBranchStatus').textContent = 'Enter a branch name containing at least two characters.';
      $('wlNewBranchName')?.focus();
      return;
    }
    $('wlCreateBranch').disabled = true;
    $('wlBranchStatus').textContent = 'Creating branch securely…';
    const {data,error} = await client.rpc('create_business_branch', {
      p_business_id:activeBusiness.id,p_name:name,p_address:address || null
    });
    $('wlCreateBranch').disabled = false;
    if (error) { $('wlBranchStatus').textContent = 'Could not create branch: ' + error.message; return; }
    $('wlNewBranchName').value = '';
    $('wlNewBranchAddress').value = '';
    $('wlBranchStatus').textContent = 'Branch created successfully. It is now selected as the working branch.';
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
      ? active.map(b => '<option value="' + esc(b.id) + '">' + esc(b.name) + (b.address ? ' · ' + esc(b.address) : '') + '</option>').join('')
      : '<option value="">No active branches — create one</option>';
    selectedBranch = active.find(b => b.id === (preferredId || selectedBranch?.id)) || active[0] || null;
    $('wlBranchSelect').value = selectedBranch?.id || '';
    window.dispatchEvent(new CustomEvent('whiteLionBranchChanged', {detail:{branch:selectedBranch,branches:active}}));
    $('wlBranchStatus').textContent = active.length + ' active branch(es) available. Branch selection is active for branch stock, sales, purchases and cloud transaction posting.';
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
      $('wlBranchInventory').innerHTML = '<div class="branch-note"><strong>Stock at ' + esc(selectedBranch.name) + '</strong></div>' +
        (rows.map(row => '<div class="branch-stock"><span>' + esc(row.products?.name || row.product_id) + '</span><strong>' + Number(row.quantity_on_hand || 0).toLocaleString() + ' ' + esc(row.products?.unit || '') + '</strong></div>').join('') || '<div class="branch-note">No stock records in this branch yet.</div>');
    }
    if (memberResult.error) $('wlBranchMemberSelect').innerHTML = '<option value="">Members unavailable</option>';
    else {
      const members = memberResult.data || [];
      $('wlBranchMemberSelect').innerHTML = '<option value="">Choose a business member…</option>' +
        members.map(m => '<option value="' + esc(m.user_id) + '">' + esc(m.user_id) + ' · ' + esc(m.role) + '</option>').join('');
    }
    if (assignmentResult.error) $('wlBranchMembers').textContent = 'Assignments unavailable: ' + assignmentResult.error.message;
    else {
      const assignments = assignmentResult.data || [];
      const memberMap = new Map((memberResult.data || []).map(m => [m.user_id,m]));
      $('wlBranchMembers').innerHTML = '<div class="branch-note"><strong>Branch assignments</strong></div>' +
        (assignments.map(a => '<div class="branch-note">' + esc(a.user_id) + ' · ' + esc(memberMap.get(a.user_id)?.role || 'member') + ' · ' + (a.is_active ? 'ACTIVE' : 'INACTIVE') + '</div>').join('') || '<div class="branch-note">No staff assigned yet.</div>');
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
    if (!window.__wlRegistrationRefreshTimer) {
      window.__wlRegistrationRefreshTimer = setInterval(() => {
        if (session && session.user.email?.toLowerCase() === 'koromaalhajiabu0@gmail.com' && !document.hidden) {
          loadDeveloperRegistrations();
          loadDeveloperBusinessRegistrations();
        }
      }, 60000);
    }
  }
  async function loadDeveloperDashboard() {
    const status = $('wlDevStatus');
    if (!session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') return;
    status.textContent = 'Checking developer authorization and loading platform data…';
    const { data, error } = await client.rpc('get_platform_dashboard');
    if (error) { status.textContent = 'Developer database setup required: ' + error.message; return; }
    window.__wlPlatformBusinesses = Array.isArray(data.businesses) ? data.businesses : [];
    populateDeveloperInviteBusinesses();
    populateDeveloperRoleForm();
    const maintenance = data.maintenance || {enabled:false};
    $('wlDevStats').textContent = 'Businesses: ' + data.business_count + ' · Suspended: ' + data.suspended_count + ' · Registered accounts: ' + data.user_count + ' · Platform mode: ' + (maintenance.enabled ? 'MAINTENANCE' : 'LIVE');
    $('wlDevFreeze').textContent = maintenance.enabled ? 'Unfreeze platform' : 'Freeze platform';
    $('wlDevFreeze').className = maintenance.enabled ? '' : 'danger';
    $('wlDevBusinesses').innerHTML = (data.businesses || []).map(b => `
      <div class="dev-row">
        <div><strong>${esc(b.name)}</strong><div class="dev-meta">${esc(b.industry)} · Owner: ${esc(b.owner_email || 'Unknown')} · ${b.member_count} members</div><div class="dev-meta">${b.is_suspended ? 'SUSPENDED' : 'ACTIVE'} · ${esc(b.id)}</div></div>
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
    await loadDeveloperAlertSettings();
    await loadDeveloperRegistrations();
    await loadDeveloperBusinessRegistrations();
    await loadDeveloperAccounts();
    await loadDeveloperRegistrationLimits();
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
      return '<div class="dev-row"><div style="min-width:0"><strong>' + esc(String(event.action || 'Platform event').replaceAll('_',' ')) + '</strong><div class="dev-meta">' + esc(event.actor_email || 'System / unknown actor') + ' · ' + esc(when) + '</div><div class="dev-meta">' + esc(event.business_name || 'Platform-wide') + (event.entity_table ? ' · ' + esc(event.entity_table) : '') + (event.entity_id ? ' · ' + esc(event.entity_id) : '') + '</div>' + (details ? '<div class="dev-meta">' + esc(details) + '</div>' : '') + '</div></div>';
    }).join('') || '<div class="dev-meta">No matching audit events found in the latest 150 records.</div>';
  }
  function populateDeveloperRoleForm() {
    const businessSelect = $('wlDevRoleBusiness');
    const accountSelect = $('wlDevRoleAccount');
    if (businessSelect) {
      const selected = businessSelect.value;
      const businesses = window.__wlPlatformBusinesses || [];
      businessSelect.innerHTML = '<option value="">Choose a business workspace…</option>' +
        businesses.map(b => '<option value="' + esc(b.id) + '">' + esc(b.name) + ' · ' + esc(b.owner_email || 'Owner unknown') + '</option>').join('');
      if (businesses.some(b => b.id === selected)) businessSelect.value = selected;
    }
    if (accountSelect) {
      const selected = accountSelect.value;
      const accounts = window.__wlPlatformAccounts || [];
      accountSelect.innerHTML = '<option value="">Choose a registered account…</option>' +
        accounts.map(a => '<option value="' + esc(a.email || '') + '">' + esc(a.full_name || a.email || 'Unnamed account') + ' · ' + esc(a.email || '') + (a.is_active === false ? ' · SUSPENDED' : '') + '</option>').join('');
      if (accounts.some(a => a.email === selected)) accountSelect.value = selected;
    }
  }
  async function saveDeveloperBusinessRole() {
    const businessId = $('wlDevRoleBusiness')?.value || '';
    const email = $('wlDevRoleAccount')?.value || '';
    const role = $('wlDevRoleValue')?.value || '';
    const isActive = $('wlDevRoleStatus')?.value === 'true';
    const status = $('wlDevRoleStatus');
    const allowed = ['admin','manager','cashier','storekeeper','accountant','viewer'];
    if (!businessId || !email || !allowed.includes(role)) {
      if (status) status.textContent = 'Select a business, registered user and valid role.';
      return;
    }
    const account = (window.__wlPlatformAccounts || []).find(a => a.email?.toLowerCase() === email.toLowerCase());
    if (!account) { if (status) status.textContent = 'Choose an account from the refreshed registered account list.'; return; }
    if (account.is_active === false && isActive) {
      if (status) status.textContent = 'This platform account is suspended. Restore the account first in Registered accounts.';
      return;
    }
    const button = $('wlDevRoleSave');
    if (button) button.disabled = true;
    if (status) status.textContent = 'Saving business membership securely…';
    const {error} = await client.rpc('set_platform_member_access', {
      p_business_id:businessId,p_email:email.trim(),p_role:role,p_is_active:isActive
    });
    if (button) button.disabled = false;
    if (error) { if (status) status.textContent = 'Could not assign role: ' + error.message; return; }
    if (status) status.textContent = 'Role updated: ' + email + ' is now ' + role.toUpperCase() + ' for the selected business.';
    $('wlDevStatus').textContent = 'Business membership updated and recorded in the platform audit log.';
    await loadDeveloperDashboard();
  }
  function populateDeveloperRegistrationAccounts() {
    const select = $('wlDevRegistrationUser');
    if (!select) return;
    const selected = select.value;
    const accounts = (window.__wlPlatformAccounts || []).filter(a =>
      a.email && a.email.toLowerCase() !== 'koromaalhajiabu0@gmail.com'
    );
    select.innerHTML = '<option value="">Choose a registered account…</option>' +
      accounts.map(a => '<option value="' + esc(a.email) + '">' +
        esc(a.full_name || a.email) + ' · ' + esc(a.email) + '</option>').join('');
    if (accounts.some(a => a.email === selected)) select.value = selected;
  }

  async function loadDeveloperRegistrationLimits() {
    const host = $('wlDevRegistrationLimits');
    if (!host || !session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') return;
    host.textContent = 'Loading additional-business permissions…';
    const {data,error} = await client.rpc('get_platform_business_registration_limits');
    if (error) {
      host.textContent = 'Permission list unavailable: ' + error.message + '. Run migration 020 first.';
      return;
    }
    const limits = Array.isArray(data) ? data : [];
    window.__wlBusinessRegistrationLimits = limits;
    populateDeveloperRegistrationAccounts();
    host.innerHTML = limits.map(item =>
      '<div class="dev-row"><div style="min-width:0"><strong>' + esc(item.full_name || item.email) +
      '</strong><div class="dev-meta">' + esc(item.email) + '</div><div class="dev-meta">' +
      Number(item.business_count || 0) + ' owned business(es) · Limit: ' +
      Number(item.max_businesses) + '</div></div><div class="dev-actions">' +
      '<button class="danger" data-revoke-business-limit="' + esc(item.email) + '">Revoke exception</button></div></div>'
    ).join('') || '<div class="dev-meta">No users currently have additional-business permission. All ordinary users are limited to one business.</div>';
    host.querySelectorAll('[data-revoke-business-limit]').forEach(button => {
      button.onclick = async () => {
        const email = button.dataset.revokeBusinessLimit;
        if (!confirm('Revoke the additional-business permission for ' + email + '? Their limit will return to one business. Existing businesses will remain unchanged.')) return;
        button.disabled = true;
        const {data,error} = await client.rpc('set_platform_business_registration_limit', {
          p_email: email,
          p_max_businesses: 1
        });
        if (error) {
          $('wlDevRegistrationLimitStatus').textContent = 'Could not revoke permission: ' + error.message;
          button.disabled = false;
          return;
        }
        $('wlDevRegistrationLimitStatus').textContent = 'Additional-business permission revoked for ' + email + '. Existing businesses were preserved.';
        await loadDeveloperRegistrationLimits();
      };
    });
  }

  async function saveDeveloperRegistrationLimit() {
    const email = $('wlDevRegistrationUser')?.value || '';
    const max = Number($('wlDevRegistrationMax')?.value);
    const status = $('wlDevRegistrationLimitStatus');
    const button = $('wlDevRegistrationLimitSave');
    if (!email) { status.textContent = 'Choose a registered account first.'; return; }
    if (!Number.isInteger(max) || max < 2 || max > 1000) {
      status.textContent = 'Enter a whole-number limit between 2 and 1000.';
      return;
    }
    button.disabled = true;
    status.textContent = 'Saving permission securely…';
    const {data,error} = await client.rpc('set_platform_business_registration_limit', {
      p_email: email,
      p_max_businesses: max
    });
    button.disabled = false;
    if (error) { status.textContent = 'Could not save permission: ' + error.message; return; }
    status.textContent = 'Permission granted to ' + email + '. Maximum owned businesses: ' + max +
      '. Existing businesses: ' + Number(data?.existing_owned_businesses || 0) + '.';
    await loadDeveloperRegistrationLimits();
    await loadDeveloperAccounts();
  }

  async function loadDeveloperAlertSettings() {
    const host = $('wlDevAlertStatus');
    if (!host || !session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') return;
    host.textContent = 'Loading alert settings…';
    const {data,error} = await client.rpc('get_platform_alert_settings');
    if (error) { host.textContent = 'Alert settings unavailable: ' + error.message + '. Run migration 032 first.'; return; }
    const row = Array.isArray(data) ? data[0] : data;
    if (row) {
      $('wlDevAlertEmail').value = row.alert_email || '';
      $('wlDevAlertEnabled').value = row.alerts_enabled === false ? 'false' : 'true';
    }
    host.textContent = 'Alerts are sent by email whenever someone creates a new account or submits a payment. Make sure a Resend API key has been added (ask your assistant for the one-time setup steps if you have not done this yet).';
  }

  async function saveDeveloperAlertSettings() {
    const host = $('wlDevAlertStatus');
    if (!session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') return;
    const email = ($('wlDevAlertEmail').value || '').trim();
    const enabled = $('wlDevAlertEnabled').value === 'true';
    if (!email || !email.includes('@')) { host.textContent = 'Enter a valid email address first.'; return; }
    host.textContent = 'Saving…';
    const {error} = await client.rpc('set_platform_alert_settings', {p_alert_email:email, p_alerts_enabled:enabled});
    if (error) { host.textContent = 'Could not save: ' + error.message; return; }
    host.textContent = 'Saved. Alerts will be sent to ' + email + (enabled ? '.' : ', but are currently paused.');
  }

  async function loadDeveloperRegistrations() {
    const host = $('wlDevRegistrations');
    if (!host || !session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') return;
    host.textContent = 'Loading new registrations…';
    const {data,error} = await client.rpc('get_platform_registrations', {p_limit:200});
    if (error) {
      host.textContent = 'Registration notifications unavailable: ' + error.message + '. Run migration 028 first.';
      return;
    }
    const rows = Array.isArray(data) ? data : [];
    const unseen = rows.filter(x => !x.viewed_at).length;
    host.innerHTML = '<div class="dev-meta" style="margin:7px 0 10px">' +
      rows.length + ' registered account(s) · ' + unseen + ' not yet reviewed</div>' +
      rows.map(x => {
        const when = x.registered_at ? new Date(x.registered_at).toLocaleString() : 'Time unavailable';
        return '<div class="dev-row"><div style="min-width:0"><strong>' +
          esc(x.full_name || 'New customer') + '</strong><div class="dev-meta">' +
          esc(x.email || '') + '</div><div class="dev-meta">Registered: ' + esc(when) +
          ' · ' + (x.email_confirmed_at ? 'Email verified' : 'Email not verified') +
          (x.viewed_at ? ' · Reviewed' : ' · NEW REGISTRATION') +
          '</div></div></div>';
      }).join('') || '<div class="dev-meta">No registrations have been recorded yet.</div>';
    if (unseen) {
      const marked = await client.rpc('mark_platform_registrations_viewed');
      if (marked.error) host.insertAdjacentHTML('beforeend',
        '<div class="dev-meta">Could not mark notifications as reviewed: ' + esc(marked.error.message) + '</div>');
    }
  }

  async function loadDeveloperBusinessRegistrations() {
    const host = $('wlDevBusinessRegistrations');
    if (!host || !session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') return;
    host.textContent = 'Loading new business registrations…';
    const {data,error} = await client.rpc('get_platform_business_registrations', {p_limit:200});
    if (error) {
      host.textContent = 'Business registration notifications unavailable: ' + error.message + '. Run migration 029 first.';
      return;
    }
    const rows = Array.isArray(data) ? data : [];
    const unseen = rows.filter(x => !x.viewed_at).length;
    host.innerHTML = '<div class="dev-meta" style="margin:7px 0 10px">' +
      rows.length + ' business workspace(s) recorded · ' + unseen + ' not yet reviewed</div>' +
      rows.map(x => {
        const when = x.registered_at ? new Date(x.registered_at).toLocaleString() : 'Time unavailable';
        return '<div class="dev-row"><div style="min-width:0"><strong>' +
          esc(x.business_name || 'Unnamed business') + '</strong><div class="dev-meta">' +
          esc(x.industry || 'Industry not specified') + '</div><div class="dev-meta">Owner: ' +
          esc(x.owner_email || 'Email unavailable') + '</div><div class="dev-meta">Created: ' +
          esc(when) + (x.viewed_at ? ' · Reviewed' : ' · NEW BUSINESS') +
          '</div><div class="dev-meta">Business ID: ' + esc(x.business_id || '') +
          '</div></div></div>';
      }).join('') || '<div class="dev-meta">No business workspaces have been registered yet.</div>';
    if (unseen) {
      const marked = await client.rpc('mark_platform_business_registrations_viewed');
      if (marked.error) host.insertAdjacentHTML('beforeend',
        '<div class="dev-meta">Could not mark business notifications as reviewed: ' + esc(marked.error.message) + '</div>');
    }
  }

  function populateDeveloperInviteBusinesses() {
    const select = $('wlDevInviteBusiness');
    if (!select) return;
    const current = select.value;
    const businesses = window.__wlPlatformBusinesses || [];
    select.innerHTML = '<option value="">Choose a business workspace…</option>' + businesses.map(b => '<option value="' + esc(b.id) + '">' + esc(b.name) + ' · ' + esc(b.owner_email || 'Owner unknown') + '</option>').join('');
    if (businesses.some(b => b.id === current)) select.value = current;
  }

  async function inviteDeveloperAccount() {
    const name = $('wlDevInviteName')?.value.trim() || '';
    const email = $('wlDevInviteEmail')?.value.trim().toLowerCase() || '';
    const businessId = $('wlDevInviteBusiness')?.value || '';
    const role = $('wlDevInviteRole')?.value || 'admin';
    const status = $('wlDevInviteStatus');
    const button = $('wlDevInviteSubmit');
    if (!name || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !businessId) { if (status) status.textContent = 'Enter a full name, valid email and business workspace.'; return; }
    if (!confirm('Invite ' + name + ' (' + email + ') as ' + role.toUpperCase() + ' for the selected business?')) return;
    button.disabled = true; if (status) status.textContent = 'Sending secure invitation…';
    try {
      const {data,error} = await client.functions.invoke('manage-platform-accounts',{body:{action:'invite',email,full_name:name,business_id:businessId,role}});
      if (error) throw error; if (!data?.ok) throw new Error(data?.error || 'Invitation was not completed.');
      if (status) status.textContent = data.message || 'Invitation sent. Ask the administrator to check their email.';
      $('wlDevInviteName').value = ''; $('wlDevInviteEmail').value = '';
      await loadDeveloperAccounts(); await loadDeveloperActivity();
    } catch (error) { if (status) status.textContent = 'Invitation failed: ' + (error.message || 'Unknown error') + '. Confirm the manage-platform-accounts Edge Function is deployed.'; }
    finally { button.disabled = false; }
  }

  async function loadDeveloperAccounts() {
    const host = $('wlDevAccounts');
    if (!host || !session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') return;
    host.textContent = 'Loading registered accounts…';
    const {data,error} = await client.rpc('get_platform_accounts');
    if (error) { host.textContent = 'Account directory unavailable: ' + error.message + '. Run migration 006 first.'; return; }
    const accounts = Array.isArray(data) ? data : [];
    window.__wlPlatformAccounts = accounts;
    populateDeveloperRoleForm();
    populateDeveloperRegistrationAccounts();
    host.innerHTML = accounts.map(a => {
      const active = a.is_active !== false;
      const name = a.full_name || 'Name not provided';
      const last = a.last_sign_in_at ? new Date(a.last_sign_in_at).toLocaleString() : 'Never signed in';
      const protectedAccount = a.email?.toLowerCase() === 'koromaalhajiabu0@gmail.com';
      return '<div class="dev-row"><div style="min-width:0"><strong>' + esc(name) + '</strong><div class="dev-meta">' + esc(a.email || '') + '</div><div class="dev-meta">' + (active ? 'ACTIVE' : 'SUSPENDED') + ' · ' + (a.email_confirmed ? 'Email verified' : 'Email not verified') + ' · ' + Number(a.business_count || 0) + ' workspaces</div><div class="dev-meta">Last sign-in: ' + esc(last) + '</div></div><div class="dev-actions">' + (!protectedAccount ? '<button data-account-edit="' + esc(a.user_id) + '" data-account-name="' + esc(name) + '" data-account-email="' + esc(a.email || '') + '">Edit profile</button>' : '') + '<button data-account-user="' + esc(a.user_id) + '" data-account-active="' + (active ? 'true':'false') + '" ' + (protectedAccount ? 'disabled' : '') + '>' + (active ? 'Suspend access' : 'Restore access') + '</button>' + (!protectedAccount ? '<button class="danger" data-account-delete="' + esc(a.user_id) + '" data-account-email="' + esc(a.email || '') + '">Request deletion</button>' : '') + '</div></div>';
    }).join('') || '<div class="dev-meta">No registered accounts found.</div>';
    host.querySelectorAll('[data-account-edit]').forEach(button => {
      button.onclick = async () => {
        const userId = button.dataset.accountEdit;
        const oldName = button.dataset.accountName || '';
        const oldEmail = button.dataset.accountEmail || '';
        const fullName = prompt('Edit account full name:', oldName); if (fullName === null) return;
        const email = prompt('Edit account email address. A new address requires email confirmation:', oldEmail); if (email === null) return;
        if (!fullName.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) { say('Enter a valid full name and email. No changes were made.'); return; }
        if (!confirm('Save profile changes for ' + oldEmail + '? A changed email must be confirmed by the new address.')) return;
        button.disabled = true;
        const {data,error} = await client.functions.invoke('manage-platform-accounts',{body:{action:'update_profile',user_id:userId,full_name:fullName.trim(),email:email.trim().toLowerCase()}});
        if (error || !data?.ok) { say('Profile update failed: ' + (error?.message || data?.error || 'Unknown error')); button.disabled = false; return; }
        say(data.message || 'Account profile updated.'); await loadDeveloperAccounts(); await loadDeveloperActivity();
      };
    });
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
      return '<div class="dev-row"><div style="min-width:0"><strong>' + esc(d.target_email) + '</strong><div class="dev-meta">' + esc(d.status.toUpperCase()) + ' · ' + (pending && remaining > 0 ? remaining + ' days remaining' : pending ? 'Eligible for permanent deletion' : 'Closed') + '</div><div class="dev-meta">Scheduled: ' + esc(dueLabel) + '</div><div class="dev-meta">Request: ' + esc(d.id) + '</div>' + (d.failure_note ? '<div class="dev-meta">Note: ' + esc(d.failure_note) + '</div>' : '') + '</div><div class="dev-actions">' + (pending && remaining > 0 ? '<button data-cancel-deletion="' + esc(d.id) + '">Cancel &amp; restore</button>' : '') + (pending && remaining <= 0 ? '<button class="danger" data-process-deletion="' + esc(d.id) + '">Permanently delete</button>' : '') + '</div></div>';
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
  async function clearLocalBusinessData() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open('whiteLionSME', 3);
      request.onerror = () => reject(request.error || new Error('Could not open local business database.'));
      request.onsuccess = () => {
        const database = request.result;
        const names = ['products','sales','purchases','returns','customers','suppliers','expenses','employees','branchInventory','settings'];
        const available = names.filter(name => database.objectStoreNames.contains(name));
        if (!available.length) { database.close(); resolve(); return; }
        const tx = database.transaction(available, 'readwrite');
        available.forEach(name => tx.objectStore(name).clear());
        tx.oncomplete = () => { database.close(); resolve(); };
        tx.onerror = () => { const error = tx.error || new Error('Could not clear local business records.'); database.close(); reject(error); };
        tx.onabort = () => { const error = tx.error || new Error('Local data reset was cancelled.'); database.close(); reject(error); };
      };
    });
  }

  async function resetDeveloperBusinessData() {
    if (!session || session.user.email?.toLowerCase() !== 'koromaalhajiabu0@gmail.com') {
      return say('Only the registered private developer account can reset business data.');
    }
    const confirmation = prompt(
      'This permanently deletes ALL business workspaces and cloud business records, and clears this device’s local business records. Your developer login and platform audit history are preserved. Other accounts will be disabled and queued for deletion after 30 days.\n\nType RESET WHITE LION to continue:',
      ''
    );
    if (confirmation !== 'RESET WHITE LION') return say('Reset cancelled. No records were changed.');
    const button = $('wlDevResetData');
    button.disabled = true;
    button.textContent = 'Resetting business data…';
    try {
      const {data,error} = await client.rpc('reset_platform_business_data');
      if (error) throw new Error(error.message);
      await clearLocalBusinessData();
      activeBusiness = null;
      selectedBranch = null;
      window.__wlBusinesses = [];
      await loadBusinesses();
      $('wlDevStatus').textContent = 'Business reset completed. Developer login preserved. Deleted workspaces: ' + Number(data?.deleted_business_workspaces || 0) + '. Other accounts queued for 30-day deletion: ' + Number(data?.accounts_queued_for_30_day_deletion || 0) + '.';
      say('Business records cleared. Your developer account remains signed in.');
    } catch (error) {
      $('wlDevStatus').textContent = 'Reset incomplete: ' + error.message + '. Do not sync old local records; contact the developer console before continuing.';
      say('Reset did not complete: ' + error.message);
    } finally {
      button.disabled = false;
      button.textContent = 'Reset all business data';
    }
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
  const WL_INDUSTRY_GROUPS = [
    {label:"Retail and trading", modules:["sales_pos","inventory","purchasing","customers","suppliers","expenses","accounting"], items:["Supermarket","Mini-market","Grocery shop","Provision store","Wholesale shop","Retail store","Boutique / clothing shop","Shoe shop","Electronics shop","Mobile phone shop","Computer and accessories shop","Furniture shop","Building materials shop","Hardware store","Paint shop","Electrical supply shop","Plumbing supply shop","Automotive spare-parts shop","Agricultural supply shop","Stationery and bookshop"]},
    {label:"Food, hospitality and entertainment", modules:["sales_pos","inventory","purchasing","customers","suppliers","expenses","accounting","restaurant","appointments"], items:["Restaurant","Fast-food outlet","Cafeteria","Bakery","Pastry shop","Bar or lounge","Hotel","Guesthouse","Lodge","Catering business","Ice cream or beverage shop","Event and entertainment business"]},
    {label:"Healthcare and pharmaceutical", modules:["sales_pos","inventory","purchasing","customers","suppliers","expenses","accounting","pharmacy","healthcare","compliance"], items:["Pharmacy","Medical supply store","Medical equipment supplier","Optical shop","Dental supply business","Healthcare product retailer"]},
    {label:"Automotive and transport", modules:["sales_pos","inventory","purchasing","customers","suppliers","expenses","accounting","transport","fleet","services"], items:["Fuel station","Car dealership","Vehicle spare-parts dealer","Auto repair workshop","Tyre shop","Car wash business","Vehicle rental company","Transport and logistics company","Delivery business"]},
    {label:"Construction and industrial", modules:["sales_pos","inventory","purchasing","customers","suppliers","expenses","accounting","manufacturing","projects"], items:["Construction company","Building contractor","Hardware wholesaler","Cement distributor","Sand and gravel supplier","Steel and iron merchant","Furniture manufacturer","Manufacturing company","Industrial equipment supplier","Welding and fabrication workshop"]},
    {label:"Professional and personal services", modules:["sales_pos","customers","suppliers","expenses","employees","accounting","services","appointments","projects"], items:["Hair salon","Barbershop","Beauty salon","Spa","Laundry and dry-cleaning business","Cleaning company","Security service company","Repair and maintenance company","Computer repair shop","Printing business","Photography studio","Consultancy firm","Marketing and advertising agency"]},
    {label:"Mobile device and unlocking services", modules:["customers","expenses","employees","accounting","services","phone_unlocking"], items:["Phone unlocking service business","Mobile phone repair and unlocking shop","Device diagnostics and software services"]},
    {label:"Education and training", modules:["sales_pos","inventory","purchasing","customers","suppliers","expenses","employees","accounting","school"], items:["Private school","Training centre","Vocational institution","Computer training centre","Driving school","Educational supply shop","Bookshop and learning-material distributor"]},
    {label:"Agriculture and fisheries", modules:["sales_pos","inventory","purchasing","customers","suppliers","expenses","accounting","manufacturing"], items:["Farm business","Poultry farm","Livestock business","Fish farm","Fishing supply business","Agricultural produce wholesaler","Food processing business"]},
    {label:"Property and rental", modules:["customers","suppliers","expenses","accounting","property","projects","services"], items:["Real estate agency","Property management company","Equipment rental business","Vehicle hire business","Event equipment rental company","Property maintenance company"]},
    {label:"Financial and administrative services", modules:["customers","expenses","employees","accounting","compliance","services"], items:["Accounting and bookkeeping firm","Insurance agency","Microfinance business","Cooperative society","Business administration service provider"]},
    {label:"Sports and local league management", modules:["sports_league","expenses","employees","accounting","customers","suppliers"], items:["Sports club / football club","Sports academy","Local / community league organiser","League / competition organiser","Sports association / federation","Sports event organiser"]},
    {label:"General and multi-industry", modules:["sales_pos","inventory","purchasing","customers","suppliers","expenses","employees","accounting","services","projects"], items:["General business","Multi-industry business","Other / not listed"]}
  ];

  function showBusinessSetupDialog() {
    return new Promise(resolve => {
      const existing = document.getElementById('wlIndustrySetupModal');
      if (existing) existing.remove();
      const modal = document.createElement('div');
      modal.id = 'wlIndustrySetupModal';
      modal.style.cssText = 'position:fixed;inset:0;z-index:10000;background:rgba(7,17,32,.72);display:flex;align-items:center;justify-content:center;padding:14px;font-family:inherit';
      const groups = WL_INDUSTRY_GROUPS.map(group =>
        '<optgroup label="' + esc(group.label) + '">' +
        group.items.map(item => '<option value="' + esc(item) + '">' + esc(item) + '</option>').join('') +
        '</optgroup>'
      ).join('');
      modal.innerHTML = '<form id="wlIndustrySetupForm" style="width:min(520px,100%);max-height:92vh;overflow:auto;background:#fff;color:#17243a;border-radius:18px;padding:22px;box-shadow:0 25px 80px #0005">' +
        '<div style="display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:5px"><h2 style="margin:0;font-size:19px">Register a business</h2><button type="button" id="wlIndustrySetupClose" aria-label="Close" style="border:0;border-radius:8px;padding:7px 11px;background:#eef1f5;font-size:18px">×</button></div>' +
        '<p style="margin:0 0 16px;color:#748197;font-size:12px">Choose the business type. White Lion SME will activate the recommended modules for this workspace.</p>' +
        '<label style="display:block;font-size:11px;font-weight:700;margin:12px 0 6px">Business / organisation name</label><input id="wlIndustryBusinessName" required minlength="2" maxlength="120" placeholder="Enter business name" style="width:100%;box-sizing:border-box;padding:12px;border:1px solid #dfe5ee;border-radius:10px">' +
        '<label style="display:block;font-size:11px;font-weight:700;margin:14px 0 6px">Industry / business type</label><select id="wlIndustryBusinessType" required style="width:100%;box-sizing:border-box;padding:12px;border:1px solid #dfe5ee;border-radius:10px;background:#fff">' + groups + '</select>' +
        '<label style="display:block;font-size:11px;font-weight:700;margin:14px 0 6px">Default currency code</label><input id="wlIndustryCurrency" required maxlength="3" value="SLE" style="width:100%;box-sizing:border-box;padding:12px;border:1px solid #dfe5ee;border-radius:10px;text-transform:uppercase">' +
        '<div id="wlIndustryModulePreview" style="margin-top:13px;padding:11px;border-radius:10px;background:#f5f7fa;color:#65738a;font-size:11px;line-height:1.6"></div>' +
        '<div style="display:flex;justify-content:flex-end;gap:8px;margin-top:18px"><button type="button" id="wlIndustrySetupCancel" style="border:1px solid #dfe5ee;background:#fff;border-radius:9px;padding:10px 14px">Cancel</button><button type="submit" style="border:0;background:#14243d;color:#fff;border-radius:9px;padding:10px 16px;font-weight:700">Create workspace</button></div></form>';
      document.body.appendChild(modal);
      const form = modal.querySelector('#wlIndustrySetupForm');
      const type = modal.querySelector('#wlIndustryBusinessType');
      const preview = modal.querySelector('#wlIndustryModulePreview');
      const updatePreview = () => {
        const group = WL_INDUSTRY_GROUPS.find(g => g.items.includes(type.value));
        const modules = ['core', ...(group?.modules || [])];
        preview.innerHTML = '<strong>Modules to activate</strong><br>' + modules.map(esc).join(' · ') +
          '<br><span style="color:#8a6d36">Specialized workflows may still require configuration and testing.</span>';
      };
      const close = value => { modal.remove(); resolve(value); };
      type.addEventListener('change', updatePreview);
      updatePreview();
      modal.querySelector('#wlIndustrySetupClose').onclick = () => close(null);
      modal.querySelector('#wlIndustrySetupCancel').onclick = () => close(null);
      modal.addEventListener('click', e => { if (e.target === modal) close(null); });
      form.addEventListener('submit', e => {
        e.preventDefault();
        const group = WL_INDUSTRY_GROUPS.find(g => g.items.includes(type.value));
        close({
          name: modal.querySelector('#wlIndustryBusinessName').value.trim(),
          industry: type.value,
          currency: modal.querySelector('#wlIndustryCurrency').value.trim().toUpperCase(),
          modules: ['core', ...(group?.modules || [])]
        });
      });
      modal.querySelector('#wlIndustryBusinessName').focus();
    });
  }

  async function createBusiness() {
    const setup = await showBusinessSetupDialog();
    if (!setup) return;
    if (setup.name.length < 2 || !/^[A-Z]{3}$/.test(setup.currency)) {
      return say('Enter a business name and a valid three-letter currency code.');
    }
    say('Creating business workspace…');
    const { data, error } = await client.rpc('create_business', {
      p_name: setup.name, p_industry: setup.industry, p_currency_code: setup.currency
    });
    if (error) return say('Could not create workspace: ' + error.message);
    const { data: subscription, error: subscriptionError } = await client.from('business_subscriptions')
      .select('status,trial_ends_at')
      .eq('business_id', data)
      .maybeSingle();
    const { error: moduleError } = await client.from('business_industry_modules')
      .update({ is_enabled: true })
      .eq('business_id', data)
      .in('module_key', setup.modules);
    await loadBusinesses();
    const created = (window.__wlBusinesses || []).find(b => b.id === data);
    if (created) await selectBusiness(created);
    if (moduleError) {
      say('Workspace created, but industry modules could not be activated: ' + moduleError.message + '. Ask the developer to verify the module permissions.');
      return;
    }
    const subscriptionNotice = subscriptionError
      ? 'Check Plans & Billing to confirm the subscription status.'
      : subscription?.status === 'trial'
        ? 'Your one-time 7-day Professional trial has started.'
        : 'This account has already used its free trial. Open Plans & Billing and request an invoice to activate this additional workspace.';
    say('Business workspace created. ' + setup.modules.length + ' industry modules activated. ' + subscriptionNotice);
  }

  function syncStatus(message) {
    const el = $('wlSyncStatus');
    if (el) el.textContent = message;
  }
  async function diagnoseData() {
    const button = $('wlDiagnoseData');
    const output = $('wlDataDiagnostic');
    if (button) { button.disabled = true; button.textContent = 'Checking…'; }
    if (output) output.textContent = 'Checking local device records and this signed-in account’s cloud workspace. No records will be changed.';
    try {
      const stores = ['products','sales','purchases','returns','customers','suppliers','expenses','employees','branchInventory'];
      const localCounts = {};
      const localIds = new Set();
      for (const store of stores) {
        try {
          const rows = await all(store);
          localCounts[store] = rows.length;
          rows.forEach(row => {
            if (row.localBusinessId) localIds.add(String(row.localBusinessId));
            if (row.cloudSyncedFor) localIds.add(String(row.cloudSyncedFor));
          });
        } catch (error) {
          localCounts[store] = 'unavailable';
        }
      }
      let cloudSummary = 'Not signed in; cloud membership check skipped.';
      if (client && session?.user?.id) {
        const { data, error } = await client.from('business_members')
          .select('business_id,role,is_active,businesses(id,name)')
          .eq('user_id', session.user.id);
        if (error) {
          cloudSummary = 'Cloud membership check failed: ' + error.message;
        } else {
          const memberships = (data || []).filter(row => row.businesses?.id);
          cloudSummary = memberships.length
            ? memberships.map(row => (row.businesses.name || 'Unnamed business') + ' (' + row.role + (row.is_active ? ', active' : ', inactive') + ')').join('; ')
            : 'No business memberships found for this signed-in account.';
        }
      }
      const localTotal = Object.values(localCounts).reduce((sum, value) => sum + (Number.isFinite(value) ? value : 0), 0);
      const detail = stores.map(name => name + ': ' + localCounts[name]).join(' · ');
      const identity = activeBusiness ? 'Selected workspace: ' + activeBusiness.name + ' (' + activeBusiness.id + ').' : 'No active business workspace selected.';
      const ids = localIds.size ? 'Business IDs attached to local records: ' + Array.from(localIds).join(', ') + '.' : 'No business IDs are attached to the inspected local records.';
      const report = 'READ-ONLY DIAGNOSTIC — Local records found: ' + localTotal + '. ' + detail + '. Cloud: ' + cloudSummary + ' ' + identity + ' ' + ids + ' Nothing was uploaded, deleted or modified.';
      if (output) output.textContent = report;
      say('Diagnostic complete. Review the local/cloud data report below the workspace buttons.');
    } catch (error) {
      if (output) output.textContent = 'Diagnostic could not complete: ' + (error.message || String(error)) + '. No records were changed.';
    } finally {
      if (button) { button.disabled = false; button.textContent = 'Check local/cloud data'; }
    }
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
    const returnPending = (await all('returns')).filter(row => row.cloudSyncedFor !== activeBusiness.id).length;
    syncStatus(pending + ' master/expense records, ' + txPending + ' sales/purchases and ' + returnPending + ' returns pending for this workspace.');
  }

  async function downloadCloudRecords() {
    if (!client || !activeBusiness) return say('Select a business before downloading cloud records.');
    const button=$('wlDownloadNow'); if(button)button.disabled=true;
    syncStatus('Downloading cloud records…');
    let added=0,updated=0,skipped=0,conflicts=0;
    try {
      const businessId=activeBusiness.id;
      const localProducts=await all('products'), localCustomers=await all('customers'),
        localSuppliers=await all('suppliers'), localExpenses=await all('expenses'),
        localSales=await all('sales'), localPurchases=await all('purchases'), localReturns=await all('returns');
      const [pRes,cRes,sRes,eRes]=await Promise.all([
        client.from('products').select('id,client_record_id,sku,name,category,unit,cost_price,selling_price,reorder_level,is_active,barcode,updated_at').eq('business_id',businessId),
        client.from('customers').select('id,client_record_id,name,phone,email,address,notes,updated_at').eq('business_id',businessId),
        client.from('suppliers').select('id,client_record_id,name,phone,email,address,notes,updated_at').eq('business_id',businessId),
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
        if(old&&((old.localBusinessId&&old.localBusinessId!==businessId)||(old.cloudSyncedFor&&old.cloudSyncedFor!==businessId))){skipped++;continue;}
        if(old)productMap.set(cloud.id,old.id);
        if(old&&old.cloudSyncedAt&&cloud.updated_at&&Date.parse(cloud.updated_at)>Date.parse(old.cloudSyncedAt)+1500){old.cloudConflictSnapshot={fields:{name:cloud.name,sku:cloud.sku||'',category:cloud.category||'',unit:cloud.unit||'unit',cost:Number(cloud.cost_price||0),price:Number(cloud.selling_price||0),reorder:Number(cloud.reorder_level||0),barcode:cloud.barcode||'',stock:selectedStock.get(cloud.id)||0},updatedAt:cloud.updated_at,branchId:selectedBranch?.id||null};old.cloudConflictAt=new Date().toISOString();await put('products',old);conflicts++;continue;}
        const row={...(old||{}),id:old?.id||('cloud-product-'+cloud.client_record_id),
          cloudClientRecordId:cloud.client_record_id,localBusinessId:businessId,cloudSyncedFor:businessId,cloudSyncedAt:new Date().toISOString(),
          name:cloud.name,sku:cloud.sku||'',category:cloud.category||'',unit:cloud.unit||'unit',
          cost:Number(cloud.cost_price||0),price:Number(cloud.selling_price||0),reorder:Number(cloud.reorder_level||0),
          stock:selectedStock.get(cloud.id)||0,active:cloud.is_active,barcode:cloud.barcode||''};
        await put('products',row);productMap.set(cloud.id,row.id);old?updated++:added++;
      }
      const syncSimple=async(type,rows,localRows,mapRow)=>{
        for(const cloud of rows||[]){
          const old=localRows.find(x=>x.cloudClientRecordId===cloud.client_record_id);
          if(old&&((old.localBusinessId&&old.localBusinessId!==businessId)||(old.cloudSyncedFor&&old.cloudSyncedFor!==businessId))){skipped++;continue;}
          if(old&&old.cloudSyncedAt&&cloud.updated_at&&Date.parse(cloud.updated_at)>Date.parse(old.cloudSyncedAt)+1500){old.cloudConflictSnapshot={fields:mapRow(cloud),updatedAt:cloud.updated_at};old.cloudConflictAt=new Date().toISOString();await put(type,old);conflicts++;continue;}
          const row={...(old||{}),id:old?.id||('cloud-'+type+'-'+cloud.client_record_id),
            cloudClientRecordId:cloud.client_record_id,localBusinessId:businessId,cloudSyncedFor:businessId,
            cloudSyncedAt:new Date().toISOString(),...mapRow(cloud)};
          await put(type,row);old?updated++:added++;
        }
      };
      await syncSimple('customers',cRes.data,localCustomers,r=>({name:r.name,phone:r.phone||'',email:r.email||'',address:r.address||'',notes:r.notes||''}));
      await syncSimple('suppliers',sRes.data,localSuppliers,r=>({name:r.name,phone:r.phone||'',email:r.email||'',address:r.address||'',notes:r.notes||''}));
      await syncSimple('expenses',eRes.data,localExpenses,r=>({category:r.category,description:r.description,amount:Number(r.amount||0),payment:r.payment_method||'cash',date:r.expense_date}));
      const [saleRes,purchaseRes]=await Promise.all([
        client.from('offline_sales').select('id,client_transaction_id,receipt,transaction_date,customer_name,payment_method,subtotal,discount,tax,total,branch_id').eq('business_id',businessId),
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
          if(old&&((old.localBusinessId&&old.localBusinessId!==businessId)||(old.cloudSyncedFor&&old.cloudSyncedFor!==businessId))){skipped++;continue;}
          const items=itemRows.filter(i=>i[type==='sales'?'sale_id':'purchase_id']===cloud.id).map(i=>({
            productId:productMap.get(i.product_id)||('cloud-product-id-'+i.product_id),
            name:i.product_name,quantity:Number(i.quantity),
            ...(type==='sales'?{unitPrice:Number(i.unit_price)}:{unitCost:Number(i.unit_cost),cost:Number(i.unit_cost)})
          }));
          const row={...(old||{}),id:old?.id||('cloud-'+type+'-'+cloud.client_transaction_id),
            cloudTransactionId:cloud.client_transaction_id,localBusinessId:businessId,cloudSyncedFor:businessId,
            cloudSyncedAt:new Date().toISOString(),branchId:cloud.branch_id||null,
            receipt:cloud.receipt||('PUR-'+cloud.client_transaction_id.slice(0,10)),
            date:cloud.transaction_date,customer:cloud.customer_name||'',supplier:cloud.supplier_name||'',
            payment:cloud.payment_method||'cash',subtotal:Number(cloud.subtotal??cloud.total??0),discount:Number(cloud.discount||0),tax:Number(cloud.tax||0),total:Number(cloud.total||0),items};
          await put(type,row);old?updated++:added++;
        }
      };
      await importTransactions('sales',saleRes.data,saleItemsRes.data||[]);
      await importTransactions('purchases',purchaseRes.data,purchaseItemsRes.data||[]);
      const [returnRes,returnItemsRes]=await Promise.all([
        client.from('offline_sale_returns').select('id,sale_id,branch_id,client_return_id,reason,refund_method,refund_total,created_at').eq('business_id',businessId),
        client.from('offline_sale_return_items').select('return_id,product_id,product_name,quantity,unit_price,refund_amount,restocked').eq('business_id',businessId)
      ]);
      if(returnRes.error)throw new Error('Could not download returns: '+returnRes.error.message);
      if(returnItemsRes.error)throw new Error('Could not download return items: '+returnItemsRes.error.message);
      const cloudSaleById=new Map((saleRes.data||[]).map(x=>[x.id,x]));
      const localSalesAfterImport=await all('sales');
      for(const cloud of returnRes.data||[]){
        const old=localReturns.find(x=>x.clientReturnId===cloud.client_return_id);
        if(old&&((old.localBusinessId&&old.localBusinessId!==businessId)||(old.cloudSyncedFor&&old.cloudSyncedFor!==businessId))){skipped++;continue;}
        const sale=cloudSaleById.get(cloud.sale_id);
        const localSale=localSalesAfterImport.find(x=>x.cloudTransactionId===sale?.client_transaction_id);
        const items=(returnItemsRes.data||[]).filter(x=>x.return_id===cloud.id).map(x=>({
          productId:productMap.get(x.product_id)||('cloud-product-id-'+x.product_id),
          name:x.product_name,quantity:Number(x.quantity),unitPrice:Number(x.unit_price),
          refundAmount:Number(x.refund_amount),restock:!!x.restocked
        }));
        const row={...(old||{}),id:old?.id||cloud.client_return_id,clientReturnId:cloud.client_return_id,
          cloudReturnId:cloud.id,saleId:old?.saleId||localSale?.id||('cloud-sale-'+(sale?.client_transaction_id||cloud.sale_id)),
          saleCloudTransactionId:sale?.client_transaction_id||old?.saleCloudTransactionId||null,
          saleReceipt:sale?.receipt||old?.saleReceipt||'',branchId:cloud.branch_id,localBusinessId:businessId,
          cloudSyncedFor:businessId,reason:cloud.reason,method:cloud.refund_method,
          refundTotal:Number(cloud.refund_total||0),items,date:(cloud.created_at||'').slice(0,10),
          createdAt:cloud.created_at,restock:items.some(x=>x.restock)};
        await put('returns',row);old?updated++:added++;
      }
      syncStatus('Download complete: '+added+' new, '+updated+' refreshed, '+skipped+' local unsynced records preserved, '+conflicts+' conflicts awaiting your choice.');
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
    if (!confirm('Upload this device’s local products, customers, suppliers, expenses, sales, purchases and returns into “' + activeBusiness.name + '”? Continue only if ALL these local records belong in this workspace.')) return;
    const button = $('wlSyncNow');
    if (button) { button.disabled = true; button.textContent = 'Syncing…'; }
    const types = ['products','customers','suppliers','expenses'];
    let total = 0, transactionTotal = 0;
    try {
      const localBranchStocks = await all('branchInventory');
      for (const type of types) {
        const rows = await all(type);
        for (const row of rows) {
          const localId = String(row.id);
          if ((row.localBusinessId && row.localBusinessId !== activeBusiness.id) || (row.cloudSyncedFor && row.cloudSyncedFor !== activeBusiness.id)) {
            throw new Error(type + ' record ' + localId + ' is linked to a different business workspace. Export a separate copy before importing it elsewhere.');
          }
          let stableId = row.cloudClientRecordId;
          if (!stableId) {
            stableId = crypto.randomUUID();
            row.cloudClientRecordId = stableId;
            await put(type, row);
          }
          if (row.cloudSyncedFor === activeBusiness.id) { if (!row.localBusinessId) { row.localBusinessId=activeBusiness.id; await put(type,row); } continue; }
          if (type === 'products' && !selectedBranch?.id) throw new Error('Select an active branch before syncing product opening stock.');
          const localBranchStock = type === 'products' ? localBranchStocks.find(x => String(x.productId)===String(row.id) && (!x.businessId || x.businessId===activeBusiness.id) && (x.branchId===selectedBranch.id || x.branchId==='local-main')) : null;
          const openingStock = localBranchStock ? Number(localBranchStock.quantity||0) : Number(row.stock||0);
          const payload = type === 'products' ? {
            branch_id:selectedBranch.id,
            client_record_id:stableId, sku:row.sku || null, barcode:row.barcode || null, name:row.name || 'Unnamed product',
            category:row.category || null, unit:row.unit || 'unit',
            cost_price:Number(row.cost || 0), selling_price:Number(row.price || 0),
            reorder_level:Number(row.reorder || 0), quantity_on_hand:openingStock
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
          row.localBusinessId = activeBusiness.id;
          row.cloudSyncedFor = activeBusiness.id;
          row.cloudSyncedAt = new Date().toISOString();
          await put(type,row);
          if(type==='products'&&selectedBranch?.id){await put('branchInventory',{id:String(selectedBranch.id)+'|'+String(row.id),businessId:activeBusiness.id,branchId:selectedBranch.id,productId:row.id,quantity:openingStock});}
          total++;
        }
      }
      // Transactions are posted only after master data, especially products, has cloud IDs.
      const productRows = await all('products');
      const productByLocalId = new Map(productRows.map(p => [String(p.id), p]));
      for (const type of ['sales','purchases']) {
        const rows = await all(type);
        for (const row of rows) {
          if ((row.localBusinessId && row.localBusinessId !== activeBusiness.id) || (row.cloudSyncedFor && row.cloudSyncedFor !== activeBusiness.id)) {
            throw new Error(type + ' transaction ' + (row.receipt || row.id) + ' belongs to a different business workspace.');
          }
          if (row.cloudSyncedFor === activeBusiness.id) { if (!row.localBusinessId) { row.localBusinessId=activeBusiness.id; await put(type,row); } continue; }
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
            subtotal:type === 'sales' ? Number(row.subtotal ?? items.reduce((sum,item) => sum + Math.round(Number(item.quantity || 0) * Number(item.unit_price || 0) * 100) / 100, 0)) : Number(row.total || 0),
            discount:type === 'sales' ? Number(row.discount || 0) : 0,
            tax:type === 'sales' ? Number(row.tax || 0) : 0,
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
          row.localBusinessId = activeBusiness.id;
          row.cloudSyncedFor = activeBusiness.id;
          row.cloudSyncedAt = new Date().toISOString();
          row.cloudSyncResult = data?.status || 'synced';
          await put(type,row);
          transactionTotal++;
        }
      }
      // Upload returns only after the original sale and its products are in the cloud.
      const localSalesForReturns=await all('sales');
      const returnsToSync=await all('returns');
      let returnTotal=0;
      for(const row of returnsToSync){
        if(row.cloudSyncedFor===activeBusiness.id)continue;
        if((row.localBusinessId&&row.localBusinessId!==activeBusiness.id)||(row.cloudSyncedFor&&row.cloudSyncedFor!==activeBusiness.id))
          throw new Error('Return '+(row.clientReturnId||row.id)+' belongs to a different business workspace.');
        const sale=localSalesForReturns.find(s=>String(s.id)===String(row.saleId));
        const saleTransactionId=row.saleCloudTransactionId||sale?.cloudTransactionId;
        if(!saleTransactionId||sale?.cloudSyncedFor!==activeBusiness.id)
          throw new Error('Return '+(row.clientReturnId||row.id)+' is waiting for its original sale to sync first.');
        if(!row.branchId||row.branchId==='local-main')
          throw new Error('Return '+(row.clientReturnId||row.id)+' has no cloud branch. The original sale must be posted to a selected cloud branch.');
        const returnItems=(row.items||[]).map(item=>{
          const product=productByLocalId.get(String(item.productId));
          if(!product?.cloudClientRecordId||product.cloudSyncedFor!==activeBusiness.id)
            throw new Error('A returned product is not synced to this workspace.');
          return {product_client_record_id:product.cloudClientRecordId,product_name:item.name||product.name,
            quantity:Number(item.quantity||0),restock:!!item.restock};
        });
        const {data,error}=await client.rpc('sync_sale_return',{
          p_business_id:activeBusiness.id,p_branch_id:row.branchId,
          p_client_return_id:row.clientReturnId||String(row.id),
          p_sale_client_transaction_id:saleTransactionId,p_reason:row.reason||'Customer return',
          p_refund_method:row.method||'cash',p_items:returnItems
        });
        if(error)throw new Error('Return '+(row.clientReturnId||row.id)+': '+error.message);
        row.localBusinessId=activeBusiness.id;row.cloudSyncedFor=activeBusiness.id;
        row.cloudReturnId=data?.return_id||row.cloudReturnId;row.cloudSyncedAt=new Date().toISOString();
        await put('returns',row);returnTotal++;
      }
      syncStatus('Sync complete: ' + total + ' master/expense records, ' + transactionTotal + ' sales/purchases and ' + returnTotal + ' returns uploaded or confirmed.');

      say('Cloud sync completed: ' + total + ' records, ' + transactionTotal + ' sales/purchases and ' + returnTotal + ' returns.');
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
      client.auth.onAuthStateChange((event, nextSession) => {
        // Supabase fires an INITIAL_SESSION event the instant this listener is
        // registered, re-delivering the same state getSession() just handled
        // above. Reacting to it here can race with that already-in-flight
        // loadBusinesses() call and briefly (or wrongly) flip the UI back to
        // "signed out" even though the person is genuinely signed in.
        if (event === 'INITIAL_SESSION') return;
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