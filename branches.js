/* White Lion SME OS — Branch management UI (Migration 009). */
(() => {
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let client, business, selectedBranch = null;
  const style = document.createElement('style');
  style.textContent = `
    #wlBranchPanel{margin-top:12px;padding:13px;border:1px solid #40516d;border-radius:11px;background:#14233b;color:#fff;font-size:12px}
    #wlBranchPanel h4{margin:0 0 8px;color:#f0d28b;font-size:13px}
    #wlBranchPanel .wl-branch-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
    #wlBranchPanel input,#wlBranchPanel select{width:100%;min-width:0;padding:9px;border:1px solid #52627b;border-radius:8px;background:#101b31;color:#fff;margin:4px 0}
    #wlBranchPanel button{border:0;border-radius:8px;padding:8px 10px;background:#d6ad57;color:#152238;font-weight:700;margin:4px 4px 4px 0}
    #wlBranchPanel .wl-muted{color:#bac6d8;font-size:10px;overflow-wrap:anywhere}
    #wlBranchPanel .wl-branch-row{padding:8px 0;border-top:1px solid #34435b}
    #wlBranchPanel .wl-branch-row strong{display:block}
    @media(max-width:560px){#wlBranchPanel .wl-branch-grid{grid-template-columns:1fr}}
  `;
  document.head.appendChild(style);

  function status(message, bad=false) {
    const node = document.getElementById('wlBranchStatus');
    if (node) { node.textContent = message; node.style.color = bad ? '#ffb4b4' : '#f0d28b'; }
  }
  function panel() {
    if (document.getElementById('wlBranchPanel')) return;
    const work = document.getElementById('wlCloudWork');
    if (!work) return;
    const section = document.createElement('section');
    section.id = 'wlBranchPanel';
    section.innerHTML = `
      <h4>BRANCH MANAGEMENT</h4>
      <div class="wl-muted">Create business locations, review branches and assign existing workspace members.</div>
      <div id="wlBranchStatus" class="wl-muted" style="margin:7px 0">Loading branches…</div>
      <label class="wl-muted" for="wlBranchSelect">Branch workspace</label>
      <select id="wlBranchSelect" aria-label="Select branch"><option value="">Loading branches…</option></select>
      <div class="wl-branch-grid">
        <div><input id="wlNewBranchName" maxlength="100" placeholder="New branch name"><input id="wlNewBranchAddress" maxlength="240" placeholder="Branch address (optional)"><button id="wlCreateBranch">＋ Create branch</button></div>
        <div><select id="wlBranchMember"><option value="">Choose active business member</option></select><button id="wlAssignBranchMember">Assign member to selected branch</button></div>
      </div>
      <div id="wlBranchList" class="wl-muted"></div>
      <div class="wl-muted" style="margin-top:8px">Important: branch creation and staff assignment are connected. Sales, purchases and inventory syncing still use the existing first-active-branch sync process; branch-specific transaction selection is a separate integration step.</div>
    `;
    work.appendChild(section);
    document.getElementById('wlCreateBranch').addEventListener('click', createBranch);
    document.getElementById('wlAssignBranchMember').addEventListener('click', assignMember);
    document.getElementById('wlBranchSelect').addEventListener('change', e => {
      selectedBranch = e.target.value || null;
      renderBranchList();
    });
  }
  async function load() {
    const api = window.whiteLionCloud;
    client = api?.getClient?.();
    business = api?.getActiveBusiness?.();
    if (!client || !business) return;
    panel();
    status('Loading branches and active members…');
    const [branchesResult, membersResult] = await Promise.all([
      client.from('branches').select('id,name,address,is_active,created_at').eq('business_id',business.id).order('created_at'),
      client.from('business_members').select('user_id,role').eq('business_id',business.id).eq('is_active',true).order('role')
    ]);
    if (branchesResult.error) return status('Could not load branches: ' + branchesResult.error.message,true);
    if (membersResult.error) return status('Could not load business members: ' + membersResult.error.message,true);
    window.__wlBranchRows = branchesResult.data || [];
    window.__wlBranchMembers = membersResult.data || [];
    if (!selectedBranch || !window.__wlBranchRows.some(b => b.id === selectedBranch && b.is_active)) {
      selectedBranch = window.__wlBranchRows.find(b => b.is_active)?.id || null;
    }
    const select = document.getElementById('wlBranchSelect');
    select.innerHTML = window.__wlBranchRows.length
      ? window.__wlBranchRows.map(b => '<option value="' + esc(b.id) + '"' + (b.id===selectedBranch?' selected':'') + '>' + esc(b.name) + (b.is_active?'':' (inactive)') + '</option>').join('')
      : '<option value="">No branches created yet</option>';
    const memberSelect = document.getElementById('wlBranchMember');
    memberSelect.innerHTML = '<option value="">Choose active business member</option>' + window.__wlBranchMembers.filter(m => m.role !== 'owner').map(m =>
      '<option value="' + esc(m.user_id) + '">' + esc(m.role) + ' · ' + esc(m.user_id) + '</option>'
    ).join('');
    status(window.__wlBranchRows.length + ' branch(es) · ' + window.__wlBranchMembers.length + ' active workspace member(s).');
    await renderBranchList();
  }
  async function createBranch() {
    const name = document.getElementById('wlNewBranchName').value.trim();
    const address = document.getElementById('wlNewBranchAddress').value.trim();
    if (name.length < 2) return status('Enter a branch name with at least two characters.',true);
    const button = document.getElementById('wlCreateBranch');
    button.disabled = true;
    const {data,error} = await client.rpc('create_business_branch',{
      p_business_id:business.id,p_name:name,p_address:address || null
    });
    button.disabled = false;
    if (error) return status('Branch creation failed: ' + error.message,true);
    document.getElementById('wlNewBranchName').value = '';
    document.getElementById('wlNewBranchAddress').value = '';
    selectedBranch = data?.branch_id || null;
    status('Branch created successfully.');
    await load();
  }
  async function assignMember() {
    const branchId = document.getElementById('wlBranchSelect').value;
    const userId = document.getElementById('wlBranchMember').value;
    if (!branchId) return status('Create or select an active branch first.',true);
    if (!userId) return status('Choose an active workspace member first.',true);
    const button = document.getElementById('wlAssignBranchMember');
    button.disabled = true;
    const {error} = await client.rpc('set_branch_member_access',{
      p_business_id:business.id,p_branch_id:branchId,p_user_id:userId,p_is_active:true
    });
    button.disabled = false;
    if (error) return status('Staff assignment failed: ' + error.message,true);
    status('Member assigned to the selected branch.');
    await renderBranchList();
  }
  async function renderBranchList() {
    const host = document.getElementById('wlBranchList');
    if (!host || !client || !business) return;
    const rows = window.__wlBranchRows || [];
    if (!rows.length) { host.innerHTML = '<div class="wl-branch-row">No branches yet. Create your first location above.</div>'; return; }
    const branch = rows.find(b => b.id === selectedBranch);
    if (!branch) { host.innerHTML = ''; return; }
    const {data,error} = await client.from('branch_members').select('user_id,is_active').eq('business_id',business.id).eq('branch_id',branch.id).order('created_at');
    if (error) { host.innerHTML = '<div class="wl-branch-row">Could not load branch assignments: ' + esc(error.message) + '</div>'; return; }
    const assignments = data || [];
    const names = new Map((window.__wlBranchMembers || []).map(m => [m.user_id,m.role]));
    host.innerHTML = '<div class="wl-branch-row"><strong>' + esc(branch.name) + '</strong><div class="wl-muted">' + esc(branch.address || 'No address recorded') + ' · ' + (branch.is_active?'Active':'Inactive') + '</div><div class="wl-muted" style="margin-top:5px">Assigned staff: ' + assignments.filter(x=>x.is_active).map(x=>esc(names.get(x.user_id)||'Member') + ' (' + esc(x.user_id) + ')').join(', ') + (assignments.some(x=>x.is_active)?'':'None yet') + '</div></div>';
  }
  window.addEventListener('whiteLionCloudReady', () => { load().catch(e => status(e.message,true)); });
  window.addEventListener('whiteLionWorkspaceChanged', () => { selectedBranch = null; setTimeout(() => load().catch(e => status(e.message,true)),0); });
})();
