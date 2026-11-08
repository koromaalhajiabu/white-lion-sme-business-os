/* White Lion SME OS — branch transfers, finance registers and advanced inventory controls. */
(() => {
  let api,client,business,memberRole=null,scannerStream=null,products=[],branchesCache=[];
  const css=document.createElement('style');
  css.textContent=`
    #wlOpsPanel{margin-top:16px;padding:20px;background:#fff;border:1px solid #e2ebe5;border-radius:16px;color:#203b2b;font-size:12px;box-shadow:0 8px 26px rgba(12,55,34,.055)}
    #wlOpsPanel h3{color:#075b35;font-size:15px;font-weight:800;letter-spacing:.2px;margin:0 0 10px}
    #wlOpsPanel h4{margin:18px 0 8px;color:#075b35;font-size:12px;font-weight:800;letter-spacing:.15px}
    #wlOpsPanel summary{cursor:pointer;list-style:none;padding:13px 15px;margin:8px 0;border:1px solid #e3ebe5;border-radius:11px;background:linear-gradient(110deg,#f5faf6,#fff);color:#17432b;font-weight:800;font-size:12px}
    #wlOpsPanel summary::-webkit-details-marker{display:none}
    #wlOpsPanel summary:after{content:'+';float:right;color:#0072c6;font-size:16px;line-height:12px}
    #wlOpsPanel details[open]>summary:after{content:'−'}
    #wlOpsPanel details[open]>summary{border-color:#cfe5d5;background:#eff8f1}
    #wlOpsPanel input,#wlOpsPanel select,#wlOpsPanel textarea{width:100%;min-width:0;padding:10px 11px;margin:4px 0;border:1px solid #dce8df;border-radius:9px;background:#fff;color:#203b2b;font:inherit}
    #wlOpsPanel input:focus,#wlOpsPanel select:focus,#wlOpsPanel textarea:focus{outline:0;border-color:#62b77b;box-shadow:0 0 0 3px rgba(30,181,58,.11)}
    #wlOpsPanel button{border:1px solid #087a43;border-radius:9px;padding:9px 12px;margin:5px 5px 5px 0;background:linear-gradient(135deg,#087a43,#075b35);color:#fff;font-weight:750;font-size:11px;box-shadow:0 4px 10px rgba(8,122,67,.12)}
    #wlOpsPanel button:hover{filter:brightness(1.04);transform:translateY(-1px)}
    #wlOpsPanel button:disabled{opacity:.5;cursor:not-allowed;transform:none}
    #wlOpsPanel .ops-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
    #wlOpsPanel .ops-muted{color:#718078;font-size:10px;line-height:1.55;overflow-wrap:anywhere}
    #wlOpsPanel .ops-row{padding:11px 2px;border-top:1px solid #e8eee9;color:#31483a;line-height:1.55}
    #wlOpsPanel .ops-summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;margin:10px 0}
    #wlOpsPanel .ops-tile{background:#f1f8f3;border:1px solid #e0eee4;border-radius:10px;padding:11px;color:#617467}
    #wlOpsPanel .ops-tile strong{display:block;font-size:15px;color:#075b35;margin-top:4px}
    #wlOpsPanel video{width:100%;max-height:210px;background:#102c1d;border-radius:10px}
    #wlOpsPanel .ops-row button{padding:6px 9px}
    #wlOwnerDashboard{margin:12px 0 16px;padding:15px;border:1px solid #cfe5d5;border-radius:14px;background:linear-gradient(135deg,#f5fbf6,#fff)}
    #wlOwnerDashboard h4{margin:0 0 5px;font-size:14px}
    #wlOwnerDashboard .owner-toolbar{display:flex;gap:8px;align-items:center;justify-content:space-between;flex-wrap:wrap;margin:12px 0}
    #wlOwnerDashboard .owner-toolbar select{max-width:190px;margin:0}
    #wlOwnerDashboard .owner-kpis{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px}
    #wlOwnerDashboard .owner-kpi{min-width:0;padding:11px;border:1px solid #e0eee4;border-radius:10px;background:#fff}
    #wlOwnerDashboard .owner-kpi span{display:block;color:#718078;font-size:10px}
    #wlOwnerDashboard .owner-kpi strong{display:block;color:#075b35;font-size:14px;margin-top:5px;overflow-wrap:anywhere}
    #wlOwnerDashboard .owner-table-wrap{overflow-x:auto;margin-top:12px}
    #wlOwnerDashboard table{width:100%;min-width:650px;border-collapse:collapse;font-size:11px}
    #wlOwnerDashboard th,#wlOwnerDashboard td{text-align:right;padding:10px 8px;border-bottom:1px solid #e5eee7;white-space:nowrap}
    #wlOwnerDashboard th:first-child,#wlOwnerDashboard td:first-child{text-align:left}
    #wlOwnerDashboard th{color:#64776b;font-weight:800;background:#f4f9f5}
    #wlOwnerDashboard td:first-child{font-weight:750;color:#17432b}
    #wlOwnerDashboard .owner-foot{margin-top:10px;color:#718078;font-size:10px;line-height:1.5}
    @media(max-width:760px){#wlOwnerDashboard .owner-kpis{grid-template-columns:repeat(2,minmax(0,1fr))}#wlOwnerDashboard .owner-toolbar select{max-width:none;flex:1}}
    @media(max-width:560px){#wlOpsPanel{padding:14px;border-radius:14px}#wlOpsPanel .ops-grid{grid-template-columns:1fr}#wlOpsPanel .ops-summary{grid-template-columns:1fr 1fr}#wlOpsPanel summary{padding:12px}}
  `;
  document.head.appendChild(css);
  const money=n=>(business?.currency_code||'SLE')+' '+Number(n||0).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2});
  function host(){
    if(document.getElementById('wlOpsPanel'))return;
    const work=document.getElementById('wlCloudWork');if(!work)return;
    const box=document.createElement('section');box.id='wlOpsPanel';
    box.innerHTML=`
      <h3>OPERATIONS CONTROL CENTRE</h3>
      <div id="wlOpsStatus" class="ops-muted">Connect a business workspace to load operations.</div>
      <section id="wlOwnerDashboard" hidden aria-live="polite">
        <h4>OWNER · MULTI-BRANCH PERFORMANCE</h4>
        <div class="ops-muted">One consolidated view of every active branch in this business workspace.</div>
        <div class="owner-toolbar"><span id="wlOwnerPeriodLabel" class="ops-muted">Loading consolidated performance…</span><div style="display:flex;gap:7px;flex-wrap:wrap;flex:1;justify-content:flex-end"><select id="wlOwnerPeriod" aria-label="Dashboard reporting period"><option value="7">Last 7 days</option><option value="30" selected>Last 30 days</option><option value="90">Last 90 days</option><option value="365">Last 12 months</option><option value="all">All available records</option></select><button id="wlOwnerRefresh" type="button">Refresh dashboard</button></div></div>
        <div id="wlOwnerKpis" class="owner-kpis"></div>
        <div class="owner-table-wrap"><div id="wlOwnerBranchRows" class="ops-muted">Branch results will appear here.</div></div>
        <div class="owner-foot">Sales are shown after recorded refunds. Purchases and expenses are recorded values, not verified cash payments. Cashbook is displayed separately. These management indicators are not audited profit or bank reconciliation.</div>
      </section>
      <details><summary>Cloud sync conflicts</summary><div id="wlOpsConflicts" class="ops-muted">No conflicts loaded.</div></details>
      <details open><summary>Stock transfers & approvals</summary>
        <div class="ops-grid"><select id="wlOpsSource"></select><select id="wlOpsDestination"></select><select id="wlOpsProduct"></select><input id="wlOpsTransferQty" type="number" min="0.001" step="0.001" placeholder="Quantity"></div>
        <input id="wlOpsTransferNote" placeholder="Transfer note (optional)"><button id="wlOpsTransferCreate">Submit transfer request</button>
        <div id="wlOpsTransferStock" class="ops-muted"></div><div id="wlOpsTransfers" class="ops-muted"></div><h4>Assign older offline transactions</h4><div class="ops-muted">Use this only when you know which branch handled transactions recorded before signing in. This does not change their totals.</div><select id="wlOpsPendingBranch"></select><button id="wlOpsAssignPending">Assign unassigned pending transactions</button><div id="wlOpsPendingCount" class="ops-muted"></div>
      </details>
      <details id="wlOpsFinance"><summary>Financial management & accounting</summary>
        <div id="wlOpsFinanceSummary" class="ops-summary"></div>
        <h4>Cashbook entry</h4>
        <div class="ops-grid"><select id="wlOpsCashType"><option value="income">Income</option><option value="expense">Expense</option></select><input id="wlOpsCashCategory" placeholder="Category"></div>
        <input id="wlOpsCashDescription" placeholder="Description"><div class="ops-grid"><input id="wlOpsCashAmount" type="number" min="0.01" step="0.01" placeholder="Amount (SLE)"><select id="wlOpsCashPayment"><option>cash</option><option>mobile money</option><option>bank transfer</option><option>card</option></select></div>
        <select id="wlOpsCashBankAccount"><option value="">Not linked to a bank / mobile-money account</option></select>
        <div class="ops-grid"><input id="wlOpsCashDate" type="date"><button id="wlOpsCashSave">Save cashbook entry</button></div>
        <h4>Cashbook register</h4><div class="ops-muted">Review recorded cash movements. This register does not connect to bank or mobile-money provider statements.</div>
        <div class="ops-grid"><select id="wlOpsCashbookPeriod"><option value="7">Last 7 days</option><option value="30" selected>Last 30 days</option><option value="90">Last 90 days</option><option value="365">Last 12 months</option><option value="all">All available records</option></select><select id="wlOpsCashbookType"><option value="all">All movement types</option><option value="income">Income only</option><option value="expense">Expenses only</option></select></div>
        <div class="ops-grid"><select id="wlOpsCashbookBranch"><option value="all">All branches</option></select><input id="wlOpsCashbookSearch" placeholder="Search description, category or reference"></div>
        <button id="wlOpsCashbookExport">Export filtered cashbook CSV</button><div id="wlOpsCashbookSummary" class="ops-summary"></div><div id="wlOpsCashbookRows" class="ops-muted">Loading cashbook entries…</div>
        <h4>Bank & mobile-money reconciliation</h4>
        <div class="ops-muted">Create an account, import a CSV statement, then match statement rows to cashbook entries. CSV columns required: transaction_date, description, reference, amount, direction (debit/credit). This is a manual import; it does not connect directly to a provider.</div>
        <div class="ops-grid"><input id="wlOpsBankName" maxlength="100" placeholder="Account name"><input id="wlOpsBankInstitution" maxlength="120" placeholder="Bank / mobile-money provider"></div>
        <div class="ops-grid"><select id="wlOpsBankType"><option value="bank">Bank account</option><option value="mobile_money">Mobile-money account</option><option value="cash_clearing">Cash clearing account</option><option value="other">Other</option></select><input id="wlOpsBankLast4" inputmode="numeric" maxlength="4" placeholder="Last 4 digits (optional)"></div>
        <button id="wlOpsBankCreate">Add account</button>
        <div class="ops-grid"><select id="wlOpsBankImportAccount"><option value="">Select account for statement import</option></select><input id="wlOpsBankCsv" type="file" accept=".csv,text/csv"></div>
        <button id="wlOpsBankImport">Import CSV statement</button><button id="wlOpsBankRefresh">Refresh reconciliation</button>
        <div id="wlOpsBankRows" class="ops-muted">Bank accounts and statement lines will appear here after migration 017 is installed.</div>
        <h4>General ledger & financial statements</h4>
        <div class="ops-muted">Double-entry accounting for new synced sales, purchases, expenses, returns and receivable/payable payments. Historical transactions are not backdated automatically. Inventory cost-of-goods-sold is not yet recognised because historical cost layers are not tracked.</div>
        <button id="wlLedgerInit" type="button">Prepare chart of accounts</button>
        <div id="wlLedgerAccounts" class="ops-muted">Chart of accounts will load after migration 018.</div>
        <div class="ops-grid"><input id="wlLedgerFrom" type="date"><input id="wlLedgerTo" type="date"></div>
        <div class="ops-grid"><button id="wlLedgerTrial" type="button">Trial balance</button><button id="wlLedgerIncome" type="button">Profit & loss</button></div>
        <div class="ops-grid"><button id="wlLedgerBalance" type="button">Balance sheet</button><button id="wlLedgerCash" type="button">Cash flow</button></div>
        <div id="wlLedgerReport" class="ops-muted">Choose a financial report to view posted ledger entries.</div>
        <h4>Manual journal entry</h4>
        <div class="ops-muted">Two-line journal entry. Debits and credits must balance. Posted journals are locked; corrections require a reversing journal.</div>
        <input id="wlLedgerMemo" maxlength="500" placeholder="Journal description">
        <div class="ops-grid"><select id="wlLedgerDebitAccount"></select><input id="wlLedgerDebit" type="number" min="0.01" step="0.01" placeholder="Debit amount"></div>
        <div class="ops-grid"><select id="wlLedgerCreditAccount"></select><input id="wlLedgerCredit" type="number" min="0.01" step="0.01" placeholder="Credit amount"></div>
        <button id="wlLedgerPost" type="button">Post balanced journal</button>
        <h4>Receivables & payables</h4>
        <div class="ops-grid"><select id="wlOpsObligationType"><option value="receivable">Customer owes us</option><option value="payable">We owe supplier</option></select><input id="wlOpsParty" placeholder="Customer / supplier name"></div>
        <input id="wlOpsObligationDesc" placeholder="Description / reference"><div class="ops-grid"><input id="wlOpsObligationAmount" type="number" min="0.01" step="0.01" placeholder="Amount (SLE)"><input id="wlOpsDueDate" type="date"></div>
        <button id="wlOpsObligationSave">Save receivable / payable</button><div id="wlOpsObligations" class="ops-muted"></div>
        <div class="ops-muted">Finance overview is business-wide. Trading balance is a simple sales-minus-purchases-minus-expenses estimate, not audited profit or a formal accrual P&L. Cashbook entries remain separate to avoid double-counting.</div>
      </details>
      <details id="wlOpsAudit" hidden><summary>Audit trail & compliance</summary>
        <div class="ops-muted">Business-scoped activity history. Only authorised management roles can view this panel. Events are read from the protected audit log; this screen cannot edit or delete audit records.</div>
        <div class="ops-grid"><input id="wlOpsAuditSearch" placeholder="Filter by action, record or actor"><button id="wlOpsAuditRefresh">Refresh audit trail</button></div>
        <div class="ops-grid"><select id="wlOpsAuditPeriod"><option value="7">Last 7 days</option><option value="30" selected>Last 30 days</option><option value="90">Last 90 days</option><option value="all">All available history</option></select><button id="wlOpsAuditExport">Export visible events (CSV)</button></div>
        <div id="wlOpsAuditSummary" class="ops-muted"></div><div id="wlOpsAuditRows" class="ops-muted">Loading audit events…</div>
      </details>
      <details><summary>Advanced inventory, barcode & expiry</summary>
        <div class="ops-grid"><input id="wlOpsBarcode" placeholder="Scan or enter product barcode"><button id="wlOpsBarcodeFind">Find product</button></div><div class="ops-grid"><select id="wlOpsBarcodeProduct"></select><button id="wlOpsBarcodeSave">Save barcode to product</button></div>
        <button id="wlOpsScanStart">Open camera scanner</button><button id="wlOpsScanStop">Stop scanner</button><video id="wlOpsVideo" playsinline hidden></video><div id="wlOpsBarcodeResult" class="ops-muted"></div>
        <h4>Receive batch / expiry tracking</h4><div class="ops-muted">Tracked batches are consumed first-expiring-first-out when synced sales, stock reductions or transfers are posted. Offline activity updates cloud batch balances after sync.</div>
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
    bind('wlOpsTransferCreate',createTransfer);bind('wlOwnerRefresh',renderOwnerDashboard);
    document.getElementById('wlOwnerPeriod').addEventListener('change',renderOwnerDashboard);bind('wlOpsAssignPending',assignPendingTransactions);bind('wlOpsCashSave',saveCashbook);
    bind('wlLedgerInit',initializeLedger);bind('wlLedgerTrial',()=>loadLedgerReport('trial'));bind('wlLedgerIncome',()=>loadLedgerReport('income'));bind('wlLedgerBalance',()=>loadLedgerReport('balance'));bind('wlLedgerCash',()=>loadLedgerReport('cash'));bind('wlLedgerPost',postLedgerJournal);
    bind('wlOpsObligationSave',saveObligation);bind('wlOpsCashbookExport',exportCashbook);bind('wlOpsBankCreate',createBankAccount);bind('wlOpsBankImport',importBankStatement);bind('wlOpsBankRefresh',renderBankReconciliation);document.getElementById('wlOpsBankRows').addEventListener('click',handleBankMatch);bind('wlOpsBarcodeFind',findBarcode);bind('wlOpsBarcodeSave',saveBarcode);
    bind('wlOpsScanStart',startScanner);bind('wlOpsScanStop',stopScanner);
    bind('wlOpsBatchSave',receiveBatch);bind('wlOpsAdjustRequest',requestAdjustment);
    bind('wlOpsAuditRefresh',renderAuditLog);bind('wlOpsAuditExport',exportAuditLog);
    document.getElementById('wlOpsAuditSearch').addEventListener('input',filterAuditLog);
    document.getElementById('wlOpsAuditPeriod').addEventListener('change',renderAuditLog);
    ['wlOpsCashbookPeriod','wlOpsCashbookType','wlOpsCashbookBranch'].forEach(id=>document.getElementById(id).addEventListener('change',renderCashbookRegister));
    document.getElementById('wlOpsCashbookSearch').addEventListener('input',renderCashbookRegister);
    document.getElementById('wlOpsSource').addEventListener('change',renderTransferStock);
  }
  function say(msg,bad=false){const el=document.getElementById('wlOpsStatus');if(el){el.textContent=msg;el.style.color=bad?'#ffb4b4':'#f0d28b';}}
  async function init(){
    api=window.whiteLionCloud;client=api?.getClient?.();business=api?.getActiveBusiness?.();
    if(!client||!business)return;
    host();say('Loading branch operations…');
    const branchRows=api.getBranches?.()||[];
    const {data:membership,error:membershipError}=await client.from('business_members').select('role').eq('business_id',business.id).eq('user_id',api.getSession?.()?.user?.id).eq('is_active',true).maybeSingle();
    if(membershipError)return say(membershipError.message,true);memberRole=membership?.role||null;
    const finance=document.getElementById('wlOpsFinance');if(finance)finance.hidden=!['owner','admin','manager','accountant'].includes(memberRole);
    const audit=document.getElementById('wlOpsAudit');if(audit)audit.hidden=!['owner','admin','manager','accountant'].includes(memberRole);

    const [p,b]=await Promise.all([
      client.from('products').select('id,name,sku,barcode,client_record_id').eq('business_id',business.id).eq('is_active',true).order('name'),
      client.from('branches').select('id,name,is_active').eq('business_id',business.id).eq('is_active',true).order('created_at')
    ]);
    if(p.error)return say(p.error.message,true);if(b.error)return say(b.error.message,true);
    if(document.getElementById('wlOpsAudit')&&!document.getElementById('wlOpsAudit').hidden)await renderAuditLog();
    products=p.data||[];
    const branches=b.data||branchRows;branchesCache=branches;
    document.getElementById('wlOpsCashbookBranch').innerHTML='<option value="all">All branches</option>'+branches.map(x=>'<option value="'+esc(x.id)+'">'+esc(x.name)+'</option>').join('');
    const opts=branches.map(x=>'<option value="'+esc(x.id)+'">'+esc(x.name)+'</option>').join('');document.getElementById('wlOpsPendingBranch').innerHTML=opts;
    ['wlOpsSource','wlOpsDestination'].forEach(id=>document.getElementById(id).innerHTML=opts);
    const current=api.getSelectedBranch?.()?.id;
    if(current)document.getElementById('wlOpsSource').value=current;
    if(branches.length>1)document.getElementById('wlOpsDestination').value=branches.find(x=>x.id!==document.getElementById('wlOpsSource').value)?.id||'';
    const prodOpts=products.map(x=>'<option value="'+esc(x.id)+'">'+esc(x.name)+(x.sku?' · '+esc(x.sku):'')+'</option>').join('');
    ['wlOpsProduct','wlOpsBatchProduct','wlOpsAdjustProduct','wlOpsBarcodeProduct'].forEach(id=>document.getElementById(id).innerHTML=prodOpts||'<option value="">No products synced</option>');
    document.getElementById('wlOpsCashDate').value=new Date().toISOString().slice(0,10);
    const ownerDashboard=document.getElementById('wlOwnerDashboard');
    if(ownerDashboard)ownerDashboard.hidden=!['owner','admin'].includes(memberRole);
    const ledgerFrom=document.getElementById('wlLedgerFrom'),ledgerTo=document.getElementById('wlLedgerTo');
    if(ledgerFrom)ledgerFrom.value=new Date(new Date().getFullYear(),new Date().getMonth(),1).toISOString().slice(0,10);
    if(ledgerTo)ledgerTo.value=new Date().toISOString().slice(0,10);
    await loadLedgerAccounts();
    await renderBankReconciliation();
    await Promise.all([renderTransfers(),renderFinance(),renderCashbookRegister(),renderBatches(),renderAdjustments(),renderPendingCount(),renderConflicts(),renderOwnerDashboard()]);
    say('Operations controls loaded for '+business.name+'.');
  }
  async function initializeLedger(){
    if(!['owner','admin','accountant'].includes(memberRole))return say('Only owners, administrators or accountants can prepare the chart of accounts.',true);
    const {data,error}=await client.rpc('initialize_accounting',{p_business_id:business.id});
    if(error)return say('Accounting setup failed: '+error.message,true);
    say('Chart of accounts ready ('+(data?.account_count??'')+' accounts).');await loadLedgerAccounts();
  }
  async function loadLedgerAccounts(){
    const box=document.getElementById('wlLedgerAccounts');if(!box||!client||!business)return;
    const {data,error}=await client.from('chart_of_accounts').select('id,account_code,account_name,account_type,normal_balance,is_active').eq('business_id',business.id).eq('is_active',true).order('account_code');
    if(error){box.textContent='Ledger not installed or unavailable: '+error.message;return;}
    const accounts=data||[];
    const options=accounts.map(a=>'<option value="'+esc(a.account_code)+'">'+esc(a.account_code)+' · '+esc(a.account_name)+'</option>').join('');
    ['wlLedgerDebitAccount','wlLedgerCreditAccount'].forEach(id=>{const el=document.getElementById(id);if(el)el.innerHTML=options||'<option value="">No accounts available</option>';});
    box.innerHTML=accounts.map(a=>'<div class="ops-row"><strong>'+esc(a.account_code)+' · '+esc(a.account_name)+'</strong><div class="ops-muted">'+esc(a.account_type)+' · Normal '+esc(a.normal_balance)+'</div></div>').join('')||'No chart accounts found. Use Prepare chart of accounts.';
  }
  function ledgerTable(rows,columns){
    if(!rows?.length)return '<div class="ops-row">No posted entries for this period.</div>';
    return '<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;min-width:420px"><thead><tr>'+columns.map(c=>'<th style="text-align:left;padding:8px;border-bottom:1px solid #dce8df">'+esc(c.label)+'</th>').join('')+'</tr></thead><tbody>'+rows.map(row=>'<tr>'+columns.map(c=>'<td style="padding:8px;border-bottom:1px solid #e8eee9">'+esc(c.format?c.format(row[c.key]):row[c.key]??'')+'</td>').join('')+'</tr>').join('')+'</tbody></table></div>';
  }
  async function loadLedgerReport(kind){
    const box=document.getElementById('wlLedgerReport');if(!box)return;
    box.textContent='Loading report…';
    const from=document.getElementById('wlLedgerFrom').value||null,to=document.getElementById('wlLedgerTo').value||new Date().toISOString().slice(0,10);
    let rpc,args,columns;
    if(kind==='trial'){rpc='accounting_trial_balance';args={p_business_id:business.id,p_from:from,p_to:to};columns=[{key:'account_code',label:'Code'},{key:'account_name',label:'Account'},{key:'account_type',label:'Type'},{key:'total_debit',label:'Debit',format:money},{key:'total_credit',label:'Credit',format:money},{key:'net_balance',label:'Balance',format:money}];}
    else if(kind==='income'){rpc='accounting_income_statement';args={p_business_id:business.id,p_from:from,p_to:to};columns=[{key:'account_code',label:'Code'},{key:'account_name',label:'Account'},{key:'account_type',label:'Type'},{key:'amount',label:'Amount',format:money}];}
    else if(kind==='balance'){rpc='accounting_balance_sheet';args={p_business_id:business.id,p_as_of:to};columns=[{key:'account_code',label:'Code'},{key:'account_name',label:'Account'},{key:'account_type',label:'Type'},{key:'amount',label:'Balance',format:money}];}
    else{rpc='accounting_cash_flow';args={p_business_id:business.id,p_from:from,p_to:to};columns=[{key:'account_name',label:'Cash account'},{key:'cash_in',label:'Cash in',format:money},{key:'cash_out',label:'Cash out',format:money},{key:'net_cash_flow',label:'Net cash flow',format:money}];}
    const {data,error}=await client.rpc(rpc,args);
    if(error){box.textContent='Report unavailable: '+error.message;return;}
    const rows=data||[];
    if(kind==='trial'){
      const debit=rows.reduce((n,x)=>n+Number(x.total_debit||0),0),credit=rows.reduce((n,x)=>n+Number(x.total_credit||0),0);
      box.innerHTML='<div class="ops-summary"><div class="ops-tile"><span>Total debits</span><strong>'+money(debit)+'</strong></div><div class="ops-tile"><span>Total credits</span><strong>'+money(credit)+'</strong></div><div class="ops-tile"><span>Difference</span><strong>'+money(debit-credit)+'</strong></div></div>'+ledgerTable(rows,columns);
    }else box.innerHTML=ledgerTable(rows,columns);
  }
  async function postLedgerJournal(){
    if(!['owner','admin','accountant'].includes(memberRole))return say('Only owners, administrators or accountants can post manual journals.',true);
    const memo=document.getElementById('wlLedgerMemo').value.trim(),debitCode=document.getElementById('wlLedgerDebitAccount').value,creditCode=document.getElementById('wlLedgerCreditAccount').value,debit=Number(document.getElementById('wlLedgerDebit').value),credit=Number(document.getElementById('wlLedgerCredit').value);
    if(memo.length<2||!debitCode||!creditCode||!Number.isFinite(debit)||!Number.isFinite(credit)||debit<=0||credit<=0)return say('Enter a description, two accounts and positive debit and credit amounts.',true);
    if(Math.abs(debit-credit)>0.005)return say('The journal is not balanced. Debit and credit must be equal.',true);
    const lines=[{code:debitCode,debit,credit:0,description:memo},{code:creditCode,debit:0,credit,description:memo}];
    const {data,error}=await client.rpc('post_general_journal',{p_business_id:business.id,p_journal_date:new Date().toISOString().slice(0,10),p_memo:memo,p_lines:lines});
    if(error)return say('Journal not posted: '+error.message,true);
    document.getElementById('wlLedgerMemo').value='';document.getElementById('wlLedgerDebit').value='';document.getElementById('wlLedgerCredit').value='';
    say('Journal posted and locked: '+String(data).slice(0,8));await loadLedgerReport('trial');
  }
  async function fetchBusinessRows(table,columns,orderColumn){
    const rows=[],pageSize=1000;let offset=0;
    while(true){
      const {data,error}=await client.from(table).select(columns).eq('business_id',business.id).order(orderColumn,{ascending:true}).range(offset,offset+pageSize-1);
      if(error)throw error;
      rows.push(...(data||[]));
      if(!data||data.length<pageSize)break;
      offset+=pageSize;
    }
    return rows;
  }
  async function renderOwnerDashboard(){
    const panel=document.getElementById('wlOwnerDashboard');if(!panel||panel.hidden||!client||!business)return;
    const kpis=document.getElementById('wlOwnerKpis'),table=document.getElementById('wlOwnerBranchRows'),label=document.getElementById('wlOwnerPeriodLabel');
    if(!kpis||!table||!label)return;
    label.textContent='Updating consolidated figures…';table.textContent='Loading branch records…';
    try{
      const period=document.getElementById('wlOwnerPeriod')?.value||'30';
      const today=new Date().toISOString().slice(0,10),cutoffDate=new Date();cutoffDate.setHours(0,0,0,0);
      if(period!=='all')cutoffDate.setDate(cutoffDate.getDate()-Number(period)+1);
      const cutoff=period==='all'?'0000-01-01':cutoffDate.toISOString().slice(0,10);
      const [sales,purchases,expenses,returns,cashbook,transfers,stock]=await Promise.all([
        fetchBusinessRows('offline_sales','branch_id,total,transaction_date','transaction_date'),
        fetchBusinessRows('offline_purchases','branch_id,total,transaction_date','transaction_date'),
        fetchBusinessRows('expenses','branch_id,amount,expense_date','expense_date'),
        fetchBusinessRows('offline_sale_returns','branch_id,refund_total,created_at','created_at'),
        fetchBusinessRows('cashbook_entries','branch_id,entry_type,amount,entry_date','entry_date'),
        fetchBusinessRows('branch_stock_transfers','source_branch_id,destination_branch_id,status,requested_at','requested_at'),
        fetchBusinessRows('branch_inventory','branch_id,quantity_on_hand','branch_id')
      ]);
      const inRange=(value)=>{const d=String(value||'').slice(0,10);return d&&d>=cutoff&&d<=today;};
      const branches=(branchesCache||[]).filter(x=>x.is_active!==false);
      const rows=new Map(branches.map(b=>[String(b.id),{id:String(b.id),name:b.name,sales:0,refunds:0,purchases:0,expenses:0,cashIncome:0,cashExpense:0,stockUnits:0}]));
      const getRow=id=>{const key=id?String(id):'unassigned';if(!rows.has(key))rows.set(key,{id:key,name:'Unassigned / business-wide',sales:0,refunds:0,purchases:0,expenses:0,cashIncome:0,cashExpense:0,stockUnits:0});return rows.get(key);};
      sales.filter(x=>inRange(x.transaction_date)).forEach(x=>getRow(x.branch_id).sales+=Number(x.total||0));
      returns.filter(x=>inRange(x.created_at)).forEach(x=>getRow(x.branch_id).refunds+=Number(x.refund_total||0));
      purchases.filter(x=>inRange(x.transaction_date)).forEach(x=>getRow(x.branch_id).purchases+=Number(x.total||0));
      expenses.filter(x=>inRange(x.expense_date)).forEach(x=>getRow(x.branch_id).expenses+=Number(x.amount||0));
      cashbook.filter(x=>inRange(x.entry_date)).forEach(x=>{const r=getRow(x.branch_id);if(x.entry_type==='income')r.cashIncome+=Number(x.amount||0);else if(x.entry_type==='expense')r.cashExpense+=Number(x.amount||0);});
      stock.forEach(x=>getRow(x.branch_id).stockUnits+=Number(x.quantity_on_hand||0));
      const activeTransfers=transfers.filter(x=>x.status==='pending');
      const visibleRows=[...rows.values()].map(r=>({...r,netSales:r.sales-r.refunds,cashNet:r.cashIncome-r.cashExpense})).sort((a,b)=>b.netSales-a.netSales);
      const totals=visibleRows.reduce((a,r)=>{a.sales+=r.sales;a.refunds+=r.refunds;a.purchases+=r.purchases;a.expenses+=r.expenses;a.cashNet+=r.cashNet;return a;},{sales:0,refunds:0,purchases:0,expenses:0,cashNet:0});
      const fmt=n=>money(n);
      const tile=(name,value)=>'<div class="owner-kpi"><span>'+name+'</span><strong>'+value+'</strong></div>';
      kpis.innerHTML=tile('Active branches',branches.length.toLocaleString())+tile('Net sales after refunds',fmt(totals.sales-totals.refunds))+tile('Purchases recorded',fmt(totals.purchases))+tile('Operating expenses',fmt(totals.expenses))+tile('Pending stock transfers',activeTransfers.length.toLocaleString());
      const periodText=period==='all'?'All available records':'Last '+period+' days';
      label.textContent=periodText+' · Updated '+new Date().toLocaleTimeString();
      const body=visibleRows.map(r=>'<tr><td>'+esc(r.name)+'</td><td>'+fmt(r.netSales)+'</td><td>'+fmt(r.purchases)+'</td><td>'+fmt(r.expenses)+'</td><td>'+fmt(r.cashNet)+'</td><td>'+r.stockUnits.toLocaleString(undefined,{maximumFractionDigits:3})+'</td></tr>').join('');
      table.innerHTML=visibleRows.length?'<table><thead><tr><th>Branch</th><th>Net sales</th><th>Purchases</th><th>Expenses</th><th>Cashbook net</th><th>Stock units</th></tr></thead><tbody>'+body+'</tbody><tfoot><tr><th>Business total</th><th>'+fmt(totals.sales-totals.refunds)+'</th><th>'+fmt(totals.purchases)+'</th><th>'+fmt(totals.expenses)+'</th><th>'+fmt(totals.cashNet)+'</th><th>—</th></tr></tfoot></table>':'No branch performance records are available yet.';
    }catch(error){
      label.textContent='Dashboard could not be refreshed.';
      table.textContent='Could not load consolidated branch data: '+(error?.message||String(error));
    }
  }
  async function renderConflicts(){
    const el=document.getElementById('wlOpsConflicts');if(!el)return;
    const rows=[];
    for(const type of ['products','customers','suppliers','expenses']){
      for(const row of await all(type))if(row.cloudConflictSnapshot)rows.push({type,row});
    }
    el.innerHTML=rows.length?rows.map(x=>'<div class="ops-row"><strong>'+esc(x.type.slice(0,-1))+' · '+esc(x.row.name||x.row.description||x.row.sku||x.row.id)+'</strong><div class="ops-muted">Cloud record changed after this device last synced it. Choose which copy to keep.</div><button data-conflict-cloud="'+esc(x.row.id)+'" data-conflict-type="'+esc(x.type)+'">Use cloud copy</button><button data-conflict-local="'+esc(x.row.id)+'" data-conflict-type="'+esc(x.type)+'">Keep this device copy</button></div>').join(''):'No unresolved cloud conflicts.';
    el.querySelectorAll('[data-conflict-cloud]').forEach(b=>b.onclick=()=>resolveConflict(b.dataset.conflictType,b.dataset.conflictCloud,'cloud'));
    el.querySelectorAll('[data-conflict-local]').forEach(b=>b.onclick=()=>resolveConflict(b.dataset.conflictType,b.dataset.conflictLocal,'local'));
  }
  async function resolveConflict(type,id,choice){
    const rows=await all(type),row=rows.find(x=>String(x.id)===String(id));if(!row||!row.cloudConflictSnapshot)return;
    if(choice==='cloud'){
      Object.assign(row,row.cloudConflictSnapshot.fields||{});
      if(type==='products'&&row.cloudConflictSnapshot.branchId){
        const branchId=row.cloudConflictSnapshot.branchId;
        await put('branchInventory',{id:String(branchId)+'|'+String(row.id),businessId:business.id,branchId,productId:row.id,quantity:Number(row.stock||0)});
      }
      row.cloudSyncedFor=business.id;row.cloudSyncedAt=new Date().toISOString();
    }else{
      row.cloudSyncedFor=null;
      row.cloudSyncResult='local_copy_selected_for_upload';
    }
    delete row.cloudConflictSnapshot;delete row.cloudConflictAt;
    await put(type,row);
    say(choice==='cloud'?'Cloud copy accepted.':'Local copy selected; upload it to replace the cloud version.');
    await renderConflicts();
  }
  async function renderPendingCount(){
    const [sales,purchases]=await Promise.all([all('sales'),all('purchases')]);
    const eligible=row=>!row.cloudSyncedFor&&(!row.localBusinessId||row.localBusinessId===business?.id);
    const pending=[...sales.filter(x=>eligible(x)&&!x.branchId),...purchases.filter(x=>eligible(x)&&!x.branchId)];
    const localMain=[...sales.filter(x=>eligible(x)&&x.branchId==='local-main'),...purchases.filter(x=>eligible(x)&&x.branchId==='local-main')];
    const el=document.getElementById('wlOpsPendingCount');if(el)el.textContent=pending.length+' unassigned and '+localMain.length+' local-main pending transaction(s).';
  }
  async function assignPendingTransactions(){
    const branchId=document.getElementById('wlOpsPendingBranch').value;if(!branchId)return say('Choose the destination branch first.',true);
    if(!confirm('Assign all unassigned and local-main unsynced sales and purchases to this branch?'))return;
    let changed=0;
    for(const type of ['sales','purchases'])for(const row of await all(type)){
      if(!row.cloudSyncedFor&&(!row.localBusinessId||row.localBusinessId===business.id)&&(!row.branchId||row.branchId==='local-main')){row.branchId=branchId;row.localBusinessId=business.id;await put(type,row);changed++;}
    }
    say(changed+' pending transaction(s) assigned to the selected branch.');await renderPendingCount();
  }
  async function renderTransferStock(){
    const el=document.getElementById('wlOpsTransferStock');if(!el||!client||!business)return;
    const branchId=document.getElementById('wlOpsSource')?.value;
    if(!branchId){el.textContent='Select a source branch to inspect available stock.';return;}
    const {data,error}=await client.from('branch_inventory').select('product_id,quantity_on_hand').eq('business_id',business.id).eq('branch_id',branchId).order('updated_at',{ascending:false});
    if(error){el.textContent='Source stock unavailable: '+error.message;return;}
    const names=new Map(products.map(p=>[p.id,p.name]));
    el.innerHTML='<div class="ops-muted">Available source stock</div>'+((data||[]).map(x=>'<div class="ops-row">'+esc(names.get(x.product_id)||x.product_id)+' · '+Number(x.quantity_on_hand||0).toLocaleString()+' available</div>').join('')||'<div class="ops-muted">No stock is recorded at this source branch.</div>');
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
    const ids=(data||[]).map(t=>t.id);const itemRes=ids.length?await client.from('branch_stock_transfer_items').select('transfer_id,product_name,quantity').in('transfer_id',ids):{data:[],error:null};if(itemRes.error){el.textContent=itemRes.error.message;return;}const items=new Map();(itemRes.data||[]).forEach(x=>{const arr=items.get(x.transfer_id)||[];arr.push(x.product_name+' × '+Number(x.quantity).toLocaleString());items.set(x.transfer_id,arr)});
    el.innerHTML=(data||[]).map(t=>'<div class="ops-row"><strong>'+esc(names.get(t.source_branch_id)||'Source')+' → '+esc(names.get(t.destination_branch_id)||'Destination')+'</strong><div class="ops-muted">'+esc(t.status)+' · '+new Date(t.requested_at).toLocaleString()+' · '+esc(t.note||'')+'</div><div class="ops-muted">'+esc((items.get(t.id)||[]).join(', ')||'No item details')+'</div>'+(t.status==='pending'?(['owner','admin','manager'].includes(memberRole)?'<button data-ops-approve="'+esc(t.id)+'">Approve</button><button data-ops-reject="'+esc(t.id)+'">Reject</button>':'')+'<button data-ops-cancel="'+esc(t.id)+'">Cancel</button>':'')+'</div>').join('')||'No transfer requests.';
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
  async function renderCashbookRegister(){
    const summary=document.getElementById('wlOpsCashbookSummary'),list=document.getElementById('wlOpsCashbookRows');if(!summary||!list||!client||!business)return;
    list.textContent='Loading cashbook entries…';
    const {data,error}=await client.from('cashbook_entries').select('id,branch_id,entry_type,category,description,amount,payment_method,entry_date,reference,created_at').eq('business_id',business.id).order('entry_date',{ascending:false}).order('created_at',{ascending:false}).limit(1000);
    if(error){list.textContent='Cashbook could not be loaded: '+error.message;return;}
    const period=document.getElementById('wlOpsCashbookPeriod').value,type=document.getElementById('wlOpsCashbookType').value,branch=document.getElementById('wlOpsCashbookBranch').value,q=document.getElementById('wlOpsCashbookSearch').value.trim().toLowerCase();
    const cutoff=new Date();cutoff.setHours(0,0,0,0);if(period!=='all')cutoff.setDate(cutoff.getDate()-Number(period));
    const rows=(data||[]).filter(x=>(period==='all'||String(x.entry_date||'')>=cutoff.toISOString().slice(0,10))&&(type==='all'||x.entry_type===type)&&(branch==='all'||String(x.branch_id||'')===branch)&&[x.description,x.category,x.reference,x.payment_method].join(' ').toLowerCase().includes(q));
    const income=rows.filter(x=>x.entry_type==='income').reduce((n,x)=>n+Number(x.amount||0),0),out=rows.filter(x=>x.entry_type==='expense').reduce((n,x)=>n+Number(x.amount||0),0),net=income-out;
    summary.innerHTML=[['Income',income],['Expenses',out],['Period net',net]].map(x=>'<div class="ops-tile"><span class="ops-muted">'+x[0]+'</span><strong>'+money(x[1])+'</strong></div>').join('');
    const names=new Map(branchesCache.map(x=>[String(x.id),x.name]));
    list.innerHTML=rows.length?rows.map(x=>'<div class="ops-row"><div style="display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap"><strong>'+esc(x.entry_date)+' · '+esc(x.category)+'</strong><strong style="color:'+(x.entry_type==='income'?'#9be7b0':'#ffb4b4')+'">'+(x.entry_type==='income'?'+ ':'− ')+money(x.amount)+'</strong></div><div class="ops-muted">'+esc(x.description)+' · '+esc(x.entry_type)+' · '+esc(x.payment_method||'cash')+' · '+esc(names.get(String(x.branch_id))||'Unassigned / business-wide')+(x.reference?' · Ref '+esc(x.reference):'')+'</div></div>').join(''):'<div class="ops-row">No cashbook entries match these filters.</div>';
    list.insertAdjacentHTML('beforeend','<div class="ops-muted">Showing '+rows.length+' matching records'+((data||[]).length===1000?' · Latest 1,000 fetched; narrow the date range for older entries.':'')+'</div>');
  }
  async function exportCashbook(){
    const summary=document.getElementById('wlOpsCashbookSummary');if(!summary)return;
    const {data,error}=await client.from('cashbook_entries').select('id,branch_id,entry_type,category,description,amount,payment_method,entry_date,reference,created_at').eq('business_id',business.id).order('entry_date',{ascending:false}).order('created_at',{ascending:false}).limit(1000);
    if(error)return say('Cashbook export failed: '+error.message,true);
    const period=document.getElementById('wlOpsCashbookPeriod').value,type=document.getElementById('wlOpsCashbookType').value,branch=document.getElementById('wlOpsCashbookBranch').value,q=document.getElementById('wlOpsCashbookSearch').value.trim().toLowerCase(),cutoff=new Date();cutoff.setHours(0,0,0,0);if(period!=='all')cutoff.setDate(cutoff.getDate()-Number(period));
    const rows=(data||[]).filter(x=>(period==='all'||String(x.entry_date||'')>=cutoff.toISOString().slice(0,10))&&(type==='all'||x.entry_type===type)&&(branch==='all'||String(x.branch_id||'')===branch)&&[x.description,x.category,x.reference,x.payment_method].join(' ').toLowerCase().includes(q));
    const cell=v=>{let s=String(v??'');if(/^[=+@-]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"';};
    const headers=['Date','Type','Category','Description','Amount','Payment method','Branch','Reference'],branchNames=new Map(branchesCache.map(x=>[String(x.id),x.name]));
    const csv=[headers.join(','),...rows.map(x=>[x.entry_date,x.entry_type,x.category,x.description,Number(x.amount||0).toFixed(2),x.payment_method,branchNames.get(String(x.branch_id))||'Unassigned / business-wide',x.reference].map(cell).join(','))].join('\n');
    const blob=new Blob([csv],{type:'text/csv;charset=utf-8;'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='white-lion-cashbook-register.csv';a.click();URL.revokeObjectURL(url);say('Cashbook CSV exported.');
  }
  function parseStatementCsv(source){
    const rows=[];let row=[],field='',quoted=false;
    for(let i=0;i<source.length;i++){const ch=source[i];
      if(quoted){if(ch==='"'&&source[i+1]==='"'){field+='"';i++;}else if(ch==='"')quoted=false;else field+=ch;}
      else if(ch==='"')quoted=true;
      else if(ch===','){row.push(field);field='';}
      else if(ch==='\n'){row.push(field);rows.push(row);row=[];field='';}
      else if(ch!=='\r')field+=ch;
    }
    if(field.length||row.length){row.push(field);rows.push(row);}
    return rows;
  }
  async function createBankAccount(){
    const account_name=document.getElementById('wlOpsBankName').value.trim(),institution_name=document.getElementById('wlOpsBankInstitution').value.trim(),account_type=document.getElementById('wlOpsBankType').value,account_last4=document.getElementById('wlOpsBankLast4').value.trim()||null;
    if(account_name.length<2||institution_name.length<2)return say('Enter an account name and institution/provider.',true);
    if(account_last4&&!/^[0-9]{4}$/.test(account_last4))return say('Last four digits must contain exactly four numbers.',true);
    const {error}=await client.from('bank_accounts').insert({business_id:business.id,account_name,institution_name,account_type,account_last4,currency:business.currency_code||'SLE'});
    if(error)return say(error.message,true);
    document.getElementById('wlOpsBankName').value='';document.getElementById('wlOpsBankInstitution').value='';document.getElementById('wlOpsBankLast4').value='';
    say('Bank / mobile-money account added.');await renderBankReconciliation();
  }
  async function importBankStatement(){
    const account=document.getElementById('wlOpsBankImportAccount').value,file=document.getElementById('wlOpsBankCsv').files?.[0];
    if(!account||!file)return say('Select an account and a CSV statement file.',true);
    if(file.size>5*1024*1024)return say('CSV file must be 5 MB or smaller.',true);
    try{
      const rows=parseStatementCsv(await file.text());if(rows.length<2)throw Error('The CSV has no transaction rows.');
      const headers=rows.shift().map(x=>x.trim().toLowerCase().replace(/^\uFEFF/,''));
      const index=key=>headers.indexOf(key);
      const required=['transaction_date','description','amount','direction'];
      if(required.some(k=>index(k)<0))throw Error('CSV headers must include transaction_date, description, amount and direction. reference is optional.');
      const lines=rows.filter(r=>r.some(v=>String(v||'').trim())).map((r,n)=>{
        const amount=Number(String(r[index('amount')]||'').replace(/[, ]/g,''));
        const direction=String(r[index('direction')]||'').trim().toLowerCase();
        const date=String(r[index('transaction_date')]||'').trim();
        const description=String(r[index('description')]||'').trim();
        if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!description||!Number.isFinite(amount)||amount<=0||!['debit','credit'].includes(direction))throw Error('Invalid CSV row '+(n+2)+'. Use YYYY-MM-DD, positive amount and debit/credit.');
        return{transaction_date:date,description,reference:index('reference')>=0?String(r[index('reference')]||'').trim():null,amount,direction};
      });
      if(!lines.length)throw Error('No valid statement rows found.');
      const {data,error}=await client.rpc('import_bank_statement_lines',{p_bank_account_id:account,p_lines:lines});
      if(error)throw error;
      document.getElementById('wlOpsBankCsv').value='';say('Statement import complete: '+(data?.inserted_rows??0)+' new rows.');await renderBankReconciliation();
    }catch(e){say('Statement import failed: '+e.message,true);}
  }
  async function renderBankReconciliation(){
    const box=document.getElementById('wlOpsBankRows');if(!box||!client||!business)return;
    box.textContent='Loading bank accounts and statement lines…';
    const [accounts,lines,cash]=await Promise.all([
      client.from('bank_accounts').select('id,account_name,institution_name,account_type,account_last4,currency,is_active').eq('business_id',business.id).eq('is_active',true).order('account_name'),
      client.from('bank_statement_lines').select('id,bank_account_id,transaction_date,description,reference,amount,direction,status').eq('business_id',business.id).order('transaction_date',{ascending:false}).limit(500),
      client.from('cashbook_entries').select('id,bank_account_id,entry_type,category,description,amount,entry_date').eq('business_id',business.id).not('bank_account_id','is',null).order('entry_date',{ascending:false}).limit(1000)
    ]);
    const error=accounts.error||lines.error||cash.error;
    if(error){box.textContent='Reconciliation unavailable. Install migration 017 and confirm finance permissions. '+error.message;return;}
    const a=accounts.data||[],l=lines.data||[],c=cash.data||[];
    const opts='<option value="">Not linked to a bank / mobile-money account</option>'+a.map(x=>'<option value="'+esc(x.id)+'">'+esc(x.account_name)+' · '+esc(x.institution_name)+'</option>').join('');
    const importSelect=document.getElementById('wlOpsBankImportAccount');if(importSelect)importSelect.innerHTML='<option value="">Select account for statement import</option>'+a.map(x=>'<option value="'+esc(x.id)+'">'+esc(x.account_name)+' · '+esc(x.institution_name)+'</option>').join('');
    const cashSelect=document.getElementById('wlOpsCashBankAccount');if(cashSelect)cashSelect.innerHTML=opts;
    if(!a.length){box.innerHTML='<div class="ops-row">No bank or mobile-money accounts yet. Add one above to begin.</div>';return;}
    const names=new Map(a.map(x=>[x.id,x.account_name]));
    const unmatched=l.filter(x=>x.status==='unmatched');
    const lineHtml=unmatched.map(x=>{
      const candidates=c.filter(y=>y.bank_account_id===x.bank_account_id&&Math.abs(Number(y.amount)-Number(x.amount))<=0.01&&((x.direction==='credit'&&y.entry_type==='income')||(x.direction==='debit'&&y.entry_type==='expense')));
      const select='<select id="wlBankMatch_'+esc(x.id)+'"><option value="">Choose matching cashbook entry</option>'+candidates.map(y=>'<option value="'+esc(y.id)+'">'+esc(y.entry_date)+' · '+esc(y.description)+' · '+money(y.amount)+'</option>').join('')+'</select>';
      return '<div class="ops-row"><b>'+esc(x.transaction_date)+' · '+esc(x.direction.toUpperCase())+' · '+money(x.amount)+'</b><div class="ops-muted">'+esc(names.get(x.bank_account_id)||'Account')+' · '+esc(x.description)+(x.reference?' · Ref '+esc(x.reference):'')+'</div>'+select+'<button type="button" data-wl-bank-match="'+esc(x.id)+'" '+(candidates.length?'':'disabled')+'>Match cashbook entry</button></div>';
    }).join('');
    box.innerHTML='<div class="ops-summary"><div class="ops-tile"><span>Accounts</span><strong>'+a.length+'</strong></div><div class="ops-tile"><span>Unmatched statement lines</span><strong>'+unmatched.length+'</strong></div><div class="ops-tile"><span>Matched lines</span><strong>'+l.filter(x=>x.status==='matched').length+'</strong></div></div>'+
      '<div class="ops-muted">'+a.map(x=>esc(x.account_name)+' · '+esc(x.institution_name)+(x.account_last4?' · •••• '+esc(x.account_last4):'')).join('<br>')+'</div>'+
      (lineHtml||'<div class="ops-row">No unmatched statement lines. Import a CSV statement to start reconciliation.</div>');
  }
  async function handleBankMatch(event){
    const button=event.target.closest('[data-wl-bank-match]');if(!button)return;
    const id=button.getAttribute('data-wl-bank-match'),entry=document.getElementById('wlBankMatch_'+id)?.value;
    if(!entry)return say('Choose the matching cashbook entry first.',true);
    button.disabled=true;
    const {error}=await client.rpc('match_bank_statement_line',{p_statement_line_id:id,p_cashbook_entry_id:entry});
    if(error){button.disabled=false;return say(error.message,true);}
    say('Statement line reconciled successfully.');await renderBankReconciliation();
  }
  async function saveCashbook(){
    const amount=Number(document.getElementById('wlOpsCashAmount').value),category=document.getElementById('wlOpsCashCategory').value.trim(),description=document.getElementById('wlOpsCashDescription').value.trim();
    if(!Number.isFinite(amount)||amount<=0||!category||!description)return say('Enter a category, description and positive amount.',true);
    const {error}=await client.from('cashbook_entries').insert({business_id:business.id,branch_id:api.getSelectedBranch?.()?.id||null,bank_account_id:document.getElementById('wlOpsCashBankAccount').value||null,entry_type:document.getElementById('wlOpsCashType').value,category,description,amount,payment_method:document.getElementById('wlOpsCashPayment').value,entry_date:document.getElementById('wlOpsCashDate').value||new Date().toISOString().slice(0,10)});
    if(error)return say(error.message,true);document.getElementById('wlOpsCashAmount').value='';say('Cashbook entry saved.');await Promise.all([renderFinance(),renderCashbookRegister()]);
  }
  async function saveObligation(){
    const party=document.getElementById('wlOpsParty').value.trim(),description=document.getElementById('wlOpsObligationDesc').value.trim(),amount=Number(document.getElementById('wlOpsObligationAmount').value);
    if(!party||!description||!Number.isFinite(amount)||amount<=0)return say('Enter a party, description and positive amount.',true);
    const {error}=await client.from('financial_obligations').insert({business_id:business.id,branch_id:api.getSelectedBranch?.()?.id||null,obligation_type:document.getElementById('wlOpsObligationType').value,party_name:party,description,amount,due_date:document.getElementById('wlOpsDueDate').value||null});
    if(error)return say(error.message,true);document.getElementById('wlOpsObligationAmount').value='';say('Financial obligation saved.');await renderFinance();
  }
  async function recordPayment(id,balance){
    const raw=prompt('Enter payment amount in '+(business?.currency_code||'SLE')+'. Outstanding: '+money(balance));
    if(raw===null)return;const amount=Number(raw);if(!Number.isFinite(amount)||amount<=0||amount>balance)return say('Enter a valid payment not exceeding the outstanding balance.',true);
    const method=prompt('Payment method (cash, mobile money, bank transfer, card):','cash');if(method===null)return;
    const {error}=await client.rpc('record_obligation_payment',{p_obligation_id:id,p_amount:amount,p_payment_method:method,p_payment_date:new Date().toISOString().slice(0,10),p_reference:null});
    if(error)return say(error.message,true);say('Payment recorded and posted to cashbook.');await Promise.all([renderFinance(),renderCashbookRegister()]);
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
    list.innerHTML=(ob.data||[]).map(x=>'<div class="ops-row"><strong>'+esc(x.party_name)+' · '+esc(x.obligation_type)+'</strong><div class="ops-muted">'+esc(x.description)+' · '+money(Number(x.amount)-Number(x.amount_paid))+' outstanding · '+esc(x.status)+(x.due_date?' · Due '+esc(x.due_date):'')+'</div>'+(x.status!=='settled'&&x.status!=='void'?'<button data-ops-payment="'+esc(x.id)+'" data-ops-balance="'+(Number(x.amount)-Number(x.amount_paid))+'">Record payment</button>':'')+'</div>').join('')||'No receivables or payables recorded.';
    list.querySelectorAll('[data-ops-payment]').forEach(b=>b.onclick=()=>recordPayment(b.dataset.opsPayment,Number(b.dataset.opsBalance)));
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
    el.innerHTML=(data||[]).map(x=>'<div class="ops-row"><strong>'+esc(names.get(x.product_id)||'Product')+' · '+esc(x.adjustment_type)+' '+Number(x.quantity).toLocaleString()+'</strong><div class="ops-muted">'+esc(x.reason)+' · '+esc(x.status)+'</div>'+(x.status==='pending'&&['owner','admin','manager'].includes(memberRole)?'<button data-ops-adjust-approve="'+esc(x.id)+'">Approve</button><button data-ops-adjust-reject="'+esc(x.id)+'">Reject</button>':'')+'</div>').join('')||'No stock adjustments.';
    el.querySelectorAll('[data-ops-adjust-approve]').forEach(b=>b.onclick=()=>decideAdjustment(b.dataset.opsAdjustApprove,true));
    el.querySelectorAll('[data-ops-adjust-reject]').forEach(b=>b.onclick=()=>decideAdjustment(b.dataset.opsAdjustReject,false));
  }
  async function decideAdjustment(id,approve){
    const note=approve?'Approved by manager':(prompt('Reason for rejecting adjustment:')||'');
    if(!approve&&!note)return;
    const {error}=await client.rpc('decide_stock_adjustment',{p_adjustment_id:id,p_approve:approve,p_note:note});
    if(error)return say(error.message,true);say('Stock adjustment '+(approve?'approved':'rejected')+'.');await renderAdjustments();
  }

  let auditEvents=[];
  async function renderAuditLog(){
    const el=document.getElementById('wlOpsAuditRows'),summary=document.getElementById('wlOpsAuditSummary');if(!el||!summary)return;
    if(!['owner','admin','manager','accountant'].includes(memberRole)){el.textContent='You do not have permission to view this audit trail.';return;}
    el.textContent='Loading business activity…';
    const period=document.getElementById('wlOpsAuditPeriod')?.value||'30';
    let query=client.from('audit_logs').select('id,actor_user_id,action,entity_table,entity_id,details,created_at').eq('business_id',business.id).order('created_at',{ascending:false}).limit(250);
    if(period!=='all'){const since=new Date(Date.now()-Number(period)*86400000).toISOString();query=query.gte('created_at',since);}
    const {data,error}=await query;
    if(error){el.textContent='Audit trail unavailable: '+error.message;summary.textContent='No data was changed.';return;}
    auditEvents=data||[];
    summary.textContent=auditEvents.length+' event(s) loaded · Read-only · Business: '+(business.name||'Selected workspace');
    filterAuditLog();
  }
  function filterAuditLog(){
    const el=document.getElementById('wlOpsAuditRows');if(!el)return;
    const q=(document.getElementById('wlOpsAuditSearch')?.value||'').trim().toLowerCase();
    const rows=auditEvents.filter(x=>!q||[x.action,x.entity_table,x.entity_id,x.actor_user_id,JSON.stringify(x.details||{})].join(' ').toLowerCase().includes(q));
    el.innerHTML=rows.map(x=>{
      const detail=JSON.stringify(x.details||{});
      return '<div class="ops-row"><strong>'+esc(String(x.action||'Activity').replace(/_/g,' '))+'</strong><div class="ops-muted">'+esc(x.entity_table||'Record')+' · '+esc(x.entity_id||'—')+' · '+esc(new Date(x.created_at).toLocaleString())+'</div><div class="ops-muted">Actor: '+esc(x.actor_user_id?String(x.actor_user_id).slice(0,8)+'…':'System')+'</div><details><summary>Event details</summary><pre style="white-space:pre-wrap;overflow-wrap:anywhere;font-size:11px">'+esc(detail)+'</pre></details></div>';
    }).join('')||'No audit events match this filter.';
  }
  function exportAuditLog(){
    const q=(document.getElementById('wlOpsAuditSearch')?.value||'').trim().toLowerCase();
    const rows=auditEvents.filter(x=>!q||[x.action,x.entity_table,x.entity_id,x.actor_user_id,JSON.stringify(x.details||{})].join(' ').toLowerCase().includes(q));
    if(!rows.length)return say('There are no visible audit events to export.',true);
    const keys=['created_at','action','entity_table','entity_id','actor_user_id','details'];
    const cell=v=>{let s=typeof v==='object'?JSON.stringify(v):String(v??'');if(/^[=+@\\-]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"';};
    const csv=[keys.join(','),...rows.map(r=>keys.map(k=>cell(r[k])).join(','))].join('\n');
    const blob=new Blob([csv],{type:'text/csv;charset=utf-8;'}),url=URL.createObjectURL(blob),a=document.createElement('a');
    a.href=url;a.download='white-lion-audit-trail-'+new Date().toISOString().slice(0,10)+'.csv';a.click();URL.revokeObjectURL(url);say(rows.length+' audit event(s) exported.');
  }

  window.addEventListener('whiteLionCloudReady',()=>init().catch(e=>say(e.message,true)));
  window.addEventListener('whiteLionWorkspaceChanged',()=>{stopScanner();setTimeout(()=>init().catch(e=>say(e.message,true)),0);});
  window.addEventListener('whiteLionBranchChanged',()=>{if(client&&business){const current=api?.getSelectedBranch?.()?.id;if(current&&document.getElementById('wlOpsSource'))document.getElementById('wlOpsSource').value=current;renderTransferStock();renderBatches();renderAdjustments();renderPendingCount();}});
  window.addEventListener('whiteLionCloudDownloaded',()=>{if(client&&business)init().catch(e=>say(e.message,true));});
  window.addEventListener('pagehide',stopScanner);
})();