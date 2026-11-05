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
    #wlBranchPanel .wl-transfer-box{margin-top:12px;padding-top:10px;border-top:1px solid #52627b}
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
      <div class="wl-transfer-box">
        <h4>STOCK TRANSFERS</h4>
        <div class="wl-muted">Request stock movement between branches. A manager, admin or owner must approve before stock changes.</div>
        <div class="wl-branch-grid">
          <select id="wlTransferSource"></select><select id="wlTransferDestination"></select>
          <select id="wlTransferProduct"></select><input id="wlTransferQty" type="number" min="0.001" step="0.001" placeholder="Quantity">
        </div>
        <input id="wlTransferNote" maxlength="240" placeholder="Transfer note (optional)">
        <button id="wlRequestTransfer">＋ Request transfer</button>
        <div id="wlTransferList" class="wl-muted"></div>
      </div>
      <div class="wl-muted" style="margin-top:8px">Sales and purchases are being connected to explicit branch selection. Older unsynced transactions without a branch will need deliberate assignment before cloud sync.</div>
    `;
    work.appendChild(section);
    document.getElementById('wlCreateBranch').addEventListener('click', createBranch);
    document.getElementById('wlAssignBranchMember').addEventListener('click', assignMember);
    document.getElementById('wlRequestTransfer').addEventListener('click', requestTransfer);
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
    const productResult = await client.from('products').select('id,client_record_id,name,sku').eq('business_id',business.id).eq('is_active',true).order('name');
    if (productResult.error) return status('Could not load products for transfers: ' + productResult.error.message,true);
    window.__wlTransferProducts = productResult.data || [];
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
    renderTransferOptions();
    await renderBranchList();
    await renderTransfers();
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
    host.innerHTML = '<div class="wl-branch-row"><strong>' + esc(branch.name) + '</strong><div class="wl-muted">' + esc(branch.address || 'No address recorded') + ' · ' + (branch.is_active?'Active':'Inactive') + '</div>' +
      assignments.map(x=>'<div style="display:flex;justify-content:space-between;gap:8px;align-items:center;margin-top:5px"><span>'+esc(names.get(x.user_id)||'Member')+' · '+esc(x.user_id)+' · '+(x.is_active?'Active':'Inactive')+'</span>'+(x.is_active?'<button data-wl-deactivate="'+esc(x.user_id)+'">Remove access</button>':'')+'</div>').join('') +
      (assignments.length?'':'<div class="wl-muted">No branch assignments yet.</div>')+'</div>';
    host.querySelectorAll('[data-wl-deactivate]').forEach(btn=>btn.addEventListener('click',()=>changeAssignment(btn.dataset.wlDeactivate,false)));
  }

  function renderTransferOptions() {
    const branches=window.__wlBranchRows||[], products=window.__wlTransferProducts||[];
    const source=document.getElementById('wlTransferSource'), dest=document.getElementById('wlTransferDestination'), product=document.getElementById('wlTransferProduct');
    if(!source||!dest||!product)return;
    const opts=branches.filter(b=>b.is_active).map(b=>'<option value="'+esc(b.id)+'">'+esc(b.name)+'</option>').join('');
    source.innerHTML=opts; dest.innerHTML=opts;
    if(selectedBranch)source.value=selectedBranch;
    if(source.value===dest.value&&branches.length>1)dest.value=branches.find(b=>b.is_active&&b.id!==source.value)?.id||'';
    product.innerHTML=products.map(p=>'<option value="'+esc(p.client_record_id||'')+'">'+esc(p.name)+(p.sku?' · '+esc(p.sku):'')+'</option>').join('');
    if(!products.length)product.innerHTML='<option value="">No cloud products available</option>';
  }
  async function changeAssignment(userId,isActive) {
    const branchId=document.getElementById('wlBranchSelect').value;
    const {error}=await client.rpc('set_branch_member_access',{p_business_id:business.id,p_branch_id:branchId,p_user_id:userId,p_is_active:isActive});
    if(error)return status('Could not update branch access: '+error.message,true);
    status(isActive?'Branch access restored.':'Branch access removed.');
    await renderBranchList();
  }
  async function requestTransfer() {
    const source=document.getElementById('wlTransferSource').value;
    const destination=document.getElementById('wlTransferDestination').value;
    const product=document.getElementById('wlTransferProduct').value;
    const quantity=Number(document.getElementById('wlTransferQty').value);
    if(!source||!destination||source===destination)return status('Choose two different active branches.',true);
    if(!product||!Number.isFinite(quantity)||quantity<=0)return status('Choose a product and enter a valid quantity.',true);
    const {data,error}=await client.rpc('request_branch_stock_transfer',{
      p_business_id:business.id,p_source_branch_id:source,p_destination_branch_id:destination,
      p_items:[{product_client_record_id:product,quantity}],
      p_note:document.getElementById('wlTransferNote').value.trim()||null
    });
    if(error)return status('Transfer request failed: '+error.message,true);
    document.getElementById('wlTransferQty').value='';
    document.getElementById('wlTransferNote').value='';
    status('Transfer request submitted for approval.');
    await renderTransfers();
  }
  async function renderTransfers() {
    const host=document.getElementById('wlTransferList');if(!host||!client||!business)return;
    const {data,error}=await client.from('branch_stock_transfers').select('id,source_branch_id,destination_branch_id,status,requested_at,note,requested_by').eq('business_id',business.id).order('requested_at',{ascending:false}).limit(30);
    if(error){host.textContent='Could not load transfers: '+error.message;return;}
    const branches=new Map((window.__wlBranchRows||[]).map(b=>[b.id,b.name]));
    const rows=data||[];
    host.innerHTML=rows.length?rows.map(t=>'<div class="wl-branch-row"><strong>'+esc(branches.get(t.source_branch_id)||'Source')+' → '+esc(branches.get(t.destination_branch_id)||'Destination')+'</strong><div class="wl-muted">'+esc(t.status.toUpperCase())+' · '+new Date(t.requested_at).toLocaleString()+' · '+esc(t.note||'No note')+'</div><div>'+ (t.status==='pending'?
      '<button data-wl-transfer-approve="'+esc(t.id)+'">Approve</button><button data-wl-transfer-reject="'+esc(t.id)+'">Reject</button><button data-wl-transfer-cancel="'+esc(t.id)+'">Cancel</button>':'')+'</div></div>').join(''):'<div class="wl-branch-row">No stock transfer requests yet.</div>';
    host.querySelectorAll('[data-wl-transfer-approve]').forEach(b=>b.addEventListener('click',()=>decideTransfer(b.dataset.wlTransferApprove,'approve')));
    host.querySelectorAll('[data-wl-transfer-reject]').forEach(b=>b.addEventListener('click',()=>decideTransfer(b.dataset.wlTransferReject,'reject')));
    host.querySelectorAll('[data-wl-transfer-cancel]').forEach(b=>b.addEventListener('click',()=>decideTransfer(b.dataset.wlTransferCancel,'cancel')));
  }
  async function decideTransfer(id,action) {
    let result;
    if(action==='approve')result=await client.rpc('approve_branch_stock_transfer',{p_transfer_id:id});
    else if(action==='cancel')result=await client.rpc('cancel_branch_stock_transfer',{p_transfer_id:id});
    else {const reason=prompt('Reason for rejecting this transfer:');if(reason===null)return;result=await client.rpc('reject_branch_stock_transfer',{p_transfer_id:id,p_reason:reason});}
    if(result.error)return status('Transfer action failed: '+result.error.message,true);
    status('Transfer '+action+' action completed.');
    await renderTransfers();
  }
  window.addEventListener('whiteLionCloudReady', () => { load().catch(e => status(e.message,true)); });
  window.addEventListener('whiteLionWorkspaceChanged', () => { selectedBranch = null; setTimeout(() => load().catch(e => status(e.message,true)),0); });
})();
