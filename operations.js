/* White Lion SME OS — branch transfers, finance registers and advanced inventory controls. */
(() => {
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let api,client,business,scannerStream=null,products=[];
  const css=document.createElement('style');
  css.textContent=`
    #wlOpsPanel{margin-top:12px;padding:14px;background:#14233b;border:1px solid #52627b;border-radius:12px;color:#fff;font-size:12px}
    #wlOpsPanel h3{color:#f0d28b;font-size:14px;margin:0 0 8px}
    #wlOpsPanel h4{margin:12px 0 6px;color:#f0d28b}
    #wlOpsPanel input,#wlOpsPanel select,#wlOpsPanel textarea{width:100%;min-width:0;padding:9px;margin:4px 0;border:1px solid #52627b;border-radius:8px;background:#101b31;color:#fff}
    #wlOpsPanel button{border:0;border-radius:8px;padding:8px 10px;margin:4px 4px 4px 0;background:#d6ad57;color:#152238;font-weight:700}
    #wlOpsPanel button:disabled{opacity:.5}
    #wlOpsPanel .ops-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:7px}
    #wlOpsPanel .ops-muted{color:#bac6d8;font-size:10px;overflow-wrap:anywhere}
    #wlOpsPanel .ops-row{padding:8px 0;border-top:1px solid #40516d}
    #wlOpsPanel .ops-summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:6px;margin:8px 0}
    #wlOpsPanel .ops-tile{background:#203653;border-radius:8px;padding:8px}
    #wlOpsPanel .ops-tile strong{display:block;font-size:14px;color:#f0d28b}
    #wlOpsPanel video{width:100%;max-height:210px;background:#080f1b;border-radius:8px}
    @media(max-width:560px){#wlOpsPanel .ops-grid{grid-template-columns:1fr}#wlOpsPanel .ops-summary{grid-template-columns:1fr 1fr}}
  `;
  document.head.appendChild(css);
  const money=n=>'SLE '+Number(n||0).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2});
  function host(){
    if(document.getElementById('wlOpsPanel'))return;
    const work=document.getElementById('wlCloudWork');if(!work)return;
    const box=document.createElement('section');box.id='wlOpsPanel';
    box.innerHTML=`
      <h3>OPERATIONS CONTROL CENTRE</h3>
      <div id="wlOpsStatus" class="ops-muted">Connect a business workspace to load operations.</div>
      <details open><summary>Stock transfers & approvals</summary>
        <div class="ops-grid"><select id="wlOpsSource"></select><select id="wlOpsDestination"></select><select id="wlOpsProduct"></select><input id="wlOpsTransferQty" type="number" min="0.001" step="0.001" placeholder="Quantity"></div>
        <input id="wlOpsTransferNote" placeholder="Transfer note (optional)"><button id="wlOpsTransferCreate">Submit transfer request</button>
        <div id="wlOpsTransfers" class="ops-muted"></div>
      </details>
      <details><summary>Financial management & accounting</summary>
        <div id="wlOpsFinanceSummary" class="ops-summary"></div>
        <h4>Cashbook entry</h4>
        <div class="ops-grid"><select id="wlOpsCashType"><option value="income">Income</option><option value="expense">Expense</option></select><input id="wlOpsCashCategory" placeholder="Category"></div>
        <input id="wlOpsCashDescription" placeholder="Description"><div class="ops-grid"><input id="wlOpsCashAmount" type="number" min="0.01" step="0.01" placeholder="Amount (SLE)"><select id="wlOpsCashPayment"><option>cash</option><option>mobile money</option><option>bank transfer</option><option>card</option></select></div>
        <div class="ops-grid"><input id="wlOpsCashDate" type="date"><button id="wlOpsCashSave">Save cashbook entry</button></div>
        <h4>Receivables & payables</h4>
        <div class="ops-grid"><select id="wlOpsObligationType"><option value="receivable">Customer owes us</option><option value="payable">We owe supplier</option></select><input id="wlOpsParty" placeholder="Customer / supplier name"></div>
        <input id="wlOpsObligationDesc" placeholder="Description / reference"><div class="ops-grid"><input id="wlOpsObligationAmount" type="number" min="0.01" step="0.01" placeholder="Amount (SLE)"><input id="wlOpsDueDate" type="date"></div>
        <button id="wlOpsObligationSave">Save receivable / payable</button><div id="wlOpsObligations" class="ops-muted"></div>
        <div class="ops-muted">Finance overview is business-wide. Trading balance is a simple sales-minus-purchases-minus-expenses estimate, not audited profit or a formal accrual P&L. Cashbook entries remain separate to avoid double-counting.</div>
      </details>
      <details><summary>Advanced inventory, barcode & expiry</summary>
        <div class="ops-grid"><input id="wlOpsBarcode" placeholder="Scan or enter product barcode"><button id="wlOpsBarcodeFind">Find product</button></div><div class="ops-grid"><select id="wlOpsBarcodeProduct"></select><button id="wlOpsBarcodeSave">Save barcode to product</button></div>
        <button id="wlOpsScanStart">Open camera scanner</button><button id="wlOpsScanStop">Stop scanner</button><video id="wlOpsVideo" playsinline hidden></video><div id="wlOpsBarcodeResult" class="ops-muted"></div>
        <h4>Receive batch / expiry tracking</h4>
        <select id="wlOpsBatchProduct"></select><div class="ops-grid"><input id="wlOpsBatchNo" placeholder="Batch / lot number"><input id="wlOpsExpiry" type="date"></div>
        <div class="ops-grid"><input id="wlOpsBatchQty" type="number" min="0.001" step="0.001" placeholder="Quantity"><input id="wlOpsBatchCost" type="number" min="0" step="0.01" placeholder="Unit cost"></div>
        <button id="wlOpsBatchSave">Receive batch and add stock</button><div id="wlOpsBatches" class="ops-muted"></div>
        <h4>Stock adjustment request</h4>
        <div class="ops-grid"><select id="wlOpsAdjustProduct"></select><select id="wlOpsAdjustType"><option value="increase">Increase stock</option><option value="decrease">Decrease stock</option></select></div>
        <div class="ops-grid"><input id="wlOpsAdjustQty" type="number" min="0.001" step="0.001" placeholder="Quantity"><input id="wlOpsAdjustReason" placeholder="Reason"></div>
        <button id="wlOpsAdjustRequest">Submit adjustment for approval</button><div id="wlOpsAdjustments" class="ops-muted"></div>
      </details>
    `;
    work.appendChild(box);
    const bind=(id,fn)=>document.getElementById(id).addEventListener('click',fn);
    bind('wlOpsTransferCreate',createTransfer);bind('wlOpsCashSave',saveCashbook);
    bind('wlOpsObligationSave',saveObligation);bind('wlOpsBarcodeFind',findBarcode);bind('wlOpsBarcodeSave',saveBarcode);
    bind('wlOpsScanStart',startScanner);bind('wlOpsScanStop',stopScanner);
    bind('wlOpsBatchSave',receiveBatch);bind('wlOpsAdjustRequest',requestAdjustment);
    document.getElementById('wlOpsSource').addEventListener('change',renderTransferStock);
  }
  function say(msg,bad=false){const el=document.getElementById('wlOpsStatus');if(el){el.textContent=msg;el.style.color=bad?'#ffb4b4':'#f0d28b';}}
  async function init(){
    api=window.whiteLionCloud;client=api?.getClient?.();business=api?.getActiveBusiness?.();
    if(!client||!business)return;
    host();say('Loading branch operations…');
    const branchRows=api.getBranches?.()||[];
    const [p,b]=await Promise.all([
      client.from('products').select('id,name,sku,barcode,client_record_id').eq('business_id',business.id).eq('is_active',true).order('name'),
      client.from('branches').select('id,name,is_active').eq('business_id',business.id).eq('is_active',true).order('created_at')
    ]);
    if(p.error)return say(p.error.message,true);if(b.error)return say(b.error.message,true);
    products=p.data||[];
    const branches=b.data||branchRows;
    const opts=branches.map(x=>'<option value="'+esc(x.id)+'">'+esc(x.name)+'</option>').join('');
    ['wlOpsSource','wlOpsDestination'].forEach(id=>document.getElementById(id).innerHTML=opts);
    const current=api.getSelectedBranch?.()?.id;
    if(current)document.getElementById('wlOpsSource').value=current;
    if(branches.length>1)document.getElementById('wlOpsDestination').value=branches.find(x=>x.id!==document.getElementById('wlOpsSource').value)?.id||'';
    const prodOpts=products.map(x=>'<option value="'+esc(x.id)+'">'+esc(x.name)+(x.sku?' · '+esc(x.sku):'')+'</option>').join('');
    ['wlOpsProduct','wlOpsBatchProduct','wlOpsAdjustProduct','wlOpsBarcodeProduct'].forEach(id=>document.getElementById(id).innerHTML=prodOpts||'<option value="">No products synced</option>');
    document.getElementById('wlOpsCashDate').value=new Date().toISOString().slice(0,10);
    await Promise.all([renderTransfers(),renderFinance(),renderBatches(),renderAdjustments()]);
    say('Operations controls loaded for '+business.name+'.');
  }
  async function createTransfer(){
    const source=document.getElementById('wlOpsSource').value,dest=document.getElementById('wlOpsDestination').value;
    const product=products.find(p=>p.id===document.getElementById('wlOpsProduct').value),qty=Number(document.getElementById('wlOpsTransferQty').value);
    if(!source||!dest||source===dest||!product||!product.client_record_id||!Number.isFinite(qty)||qty<=0)return say('Choose different branches, a product and a positive quantity.',true);
    const {error}=await client.rpc('request_branch_stock_transfer',{p_business_id:business.id,p_source_branch_id:source,p_destination_branch_id:dest,p_items:[{product_client_record_id:product.client_record_id,quantity:qty}],p_note:document.getElementById('wlOpsTransferNote').value.trim()||null});
    if(error)return say(error.message,true);
    document.getElementById('wlOpsTransferQty').value='';document.getElementById('wlOpsTransferNote').value='';
    say('Transfer request submitted. Stock changes only after approval.');await renderTransfers();
  }
  async function renderTransfers(){
    const el=document.getElementById('wlOpsTransfers');if(!el)return;
    const {data,error}=await client.from('branch_stock_transfers').select('id,source_branch_id,destination_branch_id,status,requested_at,note').eq('business_id',business.id).order('requested_at',{ascending:false}).limit(40);
    if(error){el.textContent=error.message;return;}
    const branches=api.getBranches?.()||[];
    const names=new Map(branches.map(b=>[b.id,b.name]));
    el.innerHTML=(data||[]).map(t=>'<div class="ops-row"><strong>'+esc(names.get(t.source_branch_id)||'Source')+' → '+esc(names.get(t.destination_branch_id)||'Destination')+'</strong><div class="ops-muted">'+esc(t.status)+' · '+new Date(t.requested_at).toLocaleString()+' · '+esc(t.note||'')+'</div>'+(t.status==='pending'?'<button data-ops-approve="'+esc(t.id)+'">Approve</button><button data-ops-reject="'+esc(t.id)+'">Reject</button><button data-ops-cancel="'+esc(t.id)+'">Cancel</button>':'')+'</div>').join('')||'No transfer requests.';
    el.querySelectorAll('[data-ops-approve]').forEach(b=>b.onclick=()=>transferDecision(b.dataset.opsApprove,'approve'));
    el.querySelectorAll('[data-ops-reject]').forEach(b=>b.onclick=()=>transferDecision(b.dataset.opsReject,'reject'));
    el.querySelectorAll('[data-ops-cancel]').forEach(b=>b.onclick=()=>transferDecision(b.dataset.opsCancel,'cancel'));
  }
  async function transferDecision(id,action){
    let r;if(action==='approve')r=await client.rpc('approve_branch_stock_transfer',{p_transfer_id:id});
    else if(action==='cancel')r=await client.rpc('cancel_branch_stock_transfer',{p_transfer_id:id});
    else{const reason=prompt('Reason for rejecting this transfer:');if(reason===null)return;r=await client.rpc('reject_branch_stock_transfer',{p_transfer_id:id,p_reason:reason});}
    if(r.error)return say(r.error.message,true);say('Transfer '+action+' completed.');await renderTransfers();
  }
  async function saveCashbook(){
    const amount=Number(document.getElementById('wlOpsCashAmount').value),category=document.getElementById('wlOpsCashCategory').value.trim(),description=document.getElementById('wlOpsCashDescription').value.trim();
    if(!Number.isFinite(amount)||amount<=0||!category||!description)return say('Enter a category, description and positive amount.',true);
    const {error}=await client.from('cashbook_entries').insert({business_id:business.id,branch_id:api.getSelectedBranch?.()?.id||null,entry_type:document.getElementById('wlOpsCashType').value,category,description,amount,payment_method:document.getElementById('wlOpsCashPayment').value,entry_date:document.getElementById('wlOpsCashDate').value||new Date().toISOString().slice(0,10)});
    if(error)return say(error.message,true);document.getElementById('wlOpsCashAmount').value='';say('Cashbook entry saved.');await renderFinance();
  }
  async function saveObligation(){
    const party=document.getElementById('wlOpsParty').value.trim(),description=document.getElementById('wlOpsObligationDesc').value.trim(),amount=Number(document.getElementById('wlOpsObligationAmount').value);
    if(!party||!description||!Number.isFinite(amount)||amount<=0)return say('Enter a party, description and positive amount.',true);
    const {error}=await client.from('financial_obligations').insert({business_id:business.id,branch_id:api.getSelectedBranch?.()?.id||null,obligation_type:document.getElementById('wlOpsObligationType').value,party_name:party,description,amount,due_date:document.getElementById('wlOpsDueDate').value||null});
    if(error)return say(error.message,true);document.getElementById('wlOpsObligationAmount').value='';say('Financial obligation saved.');await renderFinance();
  }
  async function recordPayment(id,balance){
    const raw=prompt('Enter payment amount in SLE. Outstanding: '+money(balance));
    if(raw===null)return;const amount=Number(raw);if(!Number.isFinite(amount)||amount<=0||amount>balance)return say('Enter a valid payment not exceeding the outstanding balance.',true);
    const method=prompt('Payment method (cash, mobile money, bank transfer, card):','cash');if(method===null)return;
    const {error}=await client.rpc('record_obligation_payment',{p_obligation_id:id,p_amount:amount,p_payment_method:method,p_payment_date:new Date().toISOString().slice(0,10),p_reference:null});
    if(error)return say(error.message,true);say('Payment recorded and posted to cashbook.');await renderFinance();
  }
  async function renderFinance(){
    const summary=document.getElementById('wlOpsFinanceSummary'),list=document.getElementById('wlOpsObligations');if(!summary||!list)return;
    const [cash,ob,sales,purchases,expenses]=await Promise.all([client.from('cashbook_entries').select('entry_type,amount').eq('business_id',business.id),client.from('financial_obligations').select('id,obligation_type,party_name,description,amount,amount_paid,due_date,status').eq('business_id',business.id).order('created_at',{ascending:false}).limit(30),client.from('offline_sales').select('total').eq('business_id',business.id),client.from('offline_purchases').select('total').eq('business_id',business.id),client.from('expenses').select('amount').eq('business_id',business.id)]);
    if(cash.error)return say(cash.error.message,true);if(ob.error)return say(ob.error.message,true);if(sales.error)return say(sales.error.message,true);if(purchases.error)return say(purchases.error.message,true);if(expenses.error)return say(expenses.error.message,true);
    const income=(cash.data||[]).filter(x=>x.entry_type==='income').reduce((a,x)=>a+Number(x.amount),0),expense=(cash.data||[]).filter(x=>x.entry_type==='expense').reduce((a,x)=>a+Number(x.amount),0);
    const recv=(ob.data||[]).filter(x=>x.obligation_type==='receivable'&&x.status!=='void').reduce((a,x)=>a+Number(x.amount)-Number(x.amount_paid),0);
    const pay=(ob.data||[]).filter(x=>x.obligation_type==='payable'&&x.status!=='void').reduce((a,x)=>a+Number(x.amount)-Number(x.amount_paid),0);
    const revenue=(sales.data||[]).reduce((a,x)=>a+Number(x.total||0),0),purchasesTotal=(purchases.data||[]).reduce((a,x)=>a+Number(x.total||0),0),operatingExpenses=(expenses.data||[]).reduce((a,x)=>a+Number(x.amount||0),0),tradingBalance=revenue-purchasesTotal-operatingExpenses;
    summary.innerHTML=[['Sales revenue',revenue],['Purchases',purchasesTotal],['Recorded expenses',operatingExpenses],['Trading balance estimate',tradingBalance],['Cashbook net',income-expense],['Receivables',recv],['Payables',pay]].map(x=>'<div class="ops-tile"><span class="ops-muted">'+x[0]+'</span><strong>'+money(x[1])+'</strong></div>').join('');
    list.innerHTML=(ob.data||[]).map(x=>'<div class="ops-row"><strong>'+esc(x.party_name)+' · '+esc(x.obligation_type)+'</strong><div class="ops-muted">'+esc(x.description)+' · '+money(Number(x.amount)-Number(x.amount_paid))+' outstanding · '+esc(x.status)+(x.due_date?' · Due '+esc(x.due_date):'')+'</div></div>').join('')||'No receivables or payables recorded.';
  }
  async function findBarcode(){
    const code=document.getElementById('wlOpsBarcode').value.trim();if(!code)return say('Enter or scan a barcode.',true);
    const p=products.find(x=>x.barcode===code||x.sku===code);
    document.getElementById('wlOpsBarcodeResult').textContent=p?'Found: '+p.name+' · SKU '+(p.sku||'—')+' · Barcode '+(p.barcode||'—'):'No product matched that barcode or SKU.';
    if(p){document.getElementById('wlOpsBatchProduct').value=p.id;document.getElementById('wlOpsBarcodeProduct').value=p.id;}
  }
  async function saveBarcode(){
    const productId=document.getElementById('wlOpsBarcodeProduct').value,code=document.getElementById('wlOpsBarcode').value.trim();
    if(!productId||!code)return say('Choose a product and enter a barcode.',true);
    const {error}=await client.from('products').update({barcode:code}).eq('id',productId).eq('business_id',business.id);
    if(error)return say(error.message,true);
    const p=products.find(x=>x.id===productId);if(p)p.barcode=code;
    say('Barcode saved to product.');document.getElementById('wlOpsBarcodeResult').textContent='Barcode '+code+' is now assigned to '+(p?.name||'the selected product')+'.';
  }
  async function startScanner(){
    if(!('BarcodeDetector'in window))return say('This browser does not support camera barcode detection. Enter the barcode manually.',true);
    try{
      const supported=await BarcodeDetector.getSupportedFormats();const formats=['ean_13','ean_8','code_128','code_39','upc_a','upc_e','qr_code'].filter(x=>supported.includes(x));if(!formats.length)return say('No supported barcode formats were found in this browser.',true);const detector=new BarcodeDetector({formats});
      scannerStream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'}},audio:false});
      const video=document.getElementById('wlOpsVideo');video.srcObject=scannerStream;video.hidden=false;await video.play();
      const scan=async()=>{if(!scannerStream)return;try{const codes=await detector.detect(video);if(codes.length){document.getElementById('wlOpsBarcode').value=codes[0].rawValue;await findBarcode();stopScanner();return;}}catch(e){}requestAnimationFrame(scan);};
      requestAnimationFrame(scan);say('Camera scanner active. Hold the barcode in view.');
    }catch(e){say('Camera unavailable: '+e.message,true);}
  }
  function stopScanner(){if(scannerStream){scannerStream.getTracks().forEach(t=>t.stop());scannerStream=null;}const v=document.getElementById('wlOpsVideo');if(v){v.pause();v.srcObject=null;v.hidden=true;}}
  async function receiveBatch(){
    const productId=document.getElementById('wlOpsBatchProduct').value,batch=document.getElementById('wlOpsBatchNo').value.trim(),qty=Number(document.getElementById('wlOpsBatchQty').value),cost=Number(document.getElementById('wlOpsBatchCost').value);
    if(!productId||!batch||!Number.isFinite(qty)||qty<=0||!Number.isFinite(cost)||cost<0)return say('Enter a product, batch number, positive quantity and valid unit cost.',true);
    const {error}=await client.rpc('receive_product_batch',{p_business_id:business.id,p_branch_id:api.getSelectedBranch?.()?.id,p_product_id:productId,p_batch_number:batch,p_expiry_date:document.getElementById('wlOpsExpiry').value||null,p_quantity:qty,p_unit_cost:cost});
    if(error)return say(error.message,true);document.getElementById('wlOpsBatchQty').value='';say('Batch received and branch stock increased atomically.');await renderBatches();
  }
  async function renderBatches(){
    const el=document.getElementById('wlOpsBatches');if(!el)return;
    const branch=api.getSelectedBranch?.();if(!branch){el.textContent='Select a branch to view batches.';return;}
    const {data,error}=await client.from('product_batches').select('batch_number,expiry_date,quantity_on_hand,unit_cost,product_id').eq('business_id',business.id).eq('branch_id',branch.id).order('expiry_date',{ascending:true}).limit(50);
    if(error){el.textContent=error.message;return;}
    const names=new Map(products.map(p=>[p.id,p.name]));
    el.innerHTML=(data||[]).map(x=>{const days=x.expiry_date?Math.ceil((new Date(x.expiry_date+'T00:00:00')-new Date(new Date().toISOString().slice(0,10)+'T00:00:00'))/86400000):null;const alert=days===null?'':days<0?' · EXPIRED':days<=30?' · EXPIRING SOON':'';return '<div class="ops-row">'+esc(names.get(x.product_id)||'Product')+' · '+esc(x.batch_number)+' · Qty '+Number(x.quantity_on_hand).toLocaleString()+' · Expiry '+esc(x.expiry_date||'Not set')+'<strong>'+alert+'</strong></div>';}).join('')||'No batch records for this branch.';
  }
  async function requestAdjustment(){
    const productId=document.getElementById('wlOpsAdjustProduct').value,type=document.getElementById('wlOpsAdjustType').value,qty=Number(document.getElementById('wlOpsAdjustQty').value),reason=document.getElementById('wlOpsAdjustReason').value.trim();
    if(!productId||!Number.isFinite(qty)||qty<=0||reason.length<3)return say('Select a product, enter a positive quantity and a reason.',true);
    const {error}=await client.rpc('request_stock_adjustment',{p_business_id:business.id,p_branch_id:api.getSelectedBranch?.()?.id,p_product_id:productId,p_adjustment_type:type,p_quantity:qty,p_reason:reason});
    if(error)return say(error.message,true);document.getElementById('wlOpsAdjustQty').value='';document.getElementById('wlOpsAdjustReason').value='';say('Adjustment submitted for manager approval.');await renderAdjustments();
  }
  async function renderAdjustments(){
    const el=document.getElementById('wlOpsAdjustments');if(!el)return;
    const branch=api.getSelectedBranch?.();if(!branch){el.textContent='Select a branch to view adjustments.';return;}
    const {data,error}=await client.from('stock_adjustments').select('id,product_id,adjustment_type,quantity,reason,status,created_at').eq('business_id',business.id).eq('branch_id',branch.id).order('created_at',{ascending:false}).limit(30);
    if(error){el.textContent=error.message;return;}
    const names=new Map(products.map(p=>[p.id,p.name]));
    el.innerHTML=(data||[]).map(x=>'<div class="ops-row"><strong>'+esc(names.get(x.product_id)||'Product')+' · '+esc(x.adjustment_type)+' '+Number(x.quantity).toLocaleString()+'</strong><div class="ops-muted">'+esc(x.reason)+' · '+esc(x.status)+'</div>'+(x.status==='pending'?'<button data-ops-adjust-approve="'+esc(x.id)+'">Approve</button><button data-ops-adjust-reject="'+esc(x.id)+'">Reject</button>':'')+'</div>').join('')||'No stock adjustments.';
    el.querySelectorAll('[data-ops-adjust-approve]').forEach(b=>b.onclick=()=>decideAdjustment(b.dataset.opsAdjustApprove,true));
    el.querySelectorAll('[data-ops-adjust-reject]').forEach(b=>b.onclick=()=>decideAdjustment(b.dataset.opsAdjustReject,false));
  }
  async function decideAdjustment(id,approve){
    const note=approve?'Approved by manager':(prompt('Reason for rejecting adjustment:')||'');
    if(!approve&&!note)return;
    const {error}=await client.rpc('decide_stock_adjustment',{p_adjustment_id:id,p_approve:approve,p_note:note});
    if(error)return say(error.message,true);say('Stock adjustment '+(approve?'approved':'rejected')+'.');await renderAdjustments();
  }
  window.addEventListener('whiteLionCloudReady',()=>init().catch(e=>say(e.message,true)));
  window.addEventListener('whiteLionWorkspaceChanged',()=>{stopScanner();setTimeout(()=>init().catch(e=>say(e.message,true)),0);});
  window.addEventListener('whiteLionBranchChanged',()=>{if(client&&business){renderBatches();renderAdjustments();}});
  window.addEventListener('whiteLionCloudDownloaded',()=>{if(client&&business)init().catch(e=>say(e.message,true));});
  window.addEventListener('pagehide',stopScanner);
})();