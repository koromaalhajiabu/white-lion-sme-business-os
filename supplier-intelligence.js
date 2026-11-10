/* White Lion SME — Supplier & Procurement Intelligence.
   Read-only analytics from the active workspace's recorded supplier and purchase data. */
(function(){
'use strict';
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const num=v=>{const x=Number(v);return Number.isFinite(x)?x:0};
const dateOf=x=>{const d=new Date(x?.date||x?.purchaseDate||x?.createdAt||x?.created_at||'');return Number.isNaN(d.getTime())?null:d};
const keyOf=v=>String(v??'').trim().toLowerCase().replace(/\s+/g,' ');
const money=(v,c)=>{try{return new Intl.NumberFormat(undefined,{style:'currency',currency:c||'SLE',maximumFractionDigits:2}).format(num(v))}catch(_){return (c||'SLE')+' '+num(v).toFixed(2)}};
const sum=(rows,fn)=>rows.reduce((a,x)=>a+num(fn(x)),0);
const pct=(a,b)=>b>0?((a-b)/b)*100:null;
function analyse(data){
 const now=new Date(),start=new Date(now.getTime()-90*86400000),priorStart=new Date(now.getTime()-180*86400000);
 const valid=(data.purchases||[]).map(p=>({...p,_date:dateOf(p),_supplier:String(p.supplier||p.supplierName||p.supplier_name||'').trim(),_total:num(p.total??(num(p.quantity)*num(p.cost))),_qty:num(p.quantity),_unit:num(p.cost)}));
 const recent=valid.filter(p=>p._date&&p._date>=start&&p._date<=now),prior=valid.filter(p=>p._date&&p._date>=priorStart&&p._date<start);
 const groups=new Map();
 (data.suppliers||[]).forEach(s=>{const k=keyOf(s.name);if(k&&!groups.has(k))groups.set(k,{name:s.name,phone:s.phone||'',email:s.email||'',registered:true,rows:[]})});
 valid.forEach(p=>{const k=keyOf(p._supplier)||'__unassigned__';if(!groups.has(k))groups.set(k,{name:p._supplier||'Unassigned supplier',phone:'',email:'',registered:false,rows:[]});groups.get(k).rows.push(p)});
 const vendors=[...groups.values()].map(v=>{
  const r=v.rows.filter(x=>x._date&&x._date>=start&&x._date<=now),old=v.rows.filter(x=>x._date&&x._date>=priorStart&&x._date<start);
  const spend=sum(r,x=>x._total),oldSpend=sum(old,x=>x._total),dates=v.rows.map(x=>x._date).filter(Boolean).sort((a,b)=>b-a);
  return {...v,entries:r.length,spend,oldSpend,change:pct(spend,oldSpend),average:r.length?spend/r.length:0,last:dates[0]||null,share:0};
 }).sort((a,b)=>b.spend-a.spend);
 const total=sum(recent,x=>x._total),oldTotal=sum(prior,x=>x._total);
 vendors.forEach(v=>v.share=total?v.spend/total*100:0);
 const productGroups=new Map();
 valid.filter(p=>p._qty>0&&p._unit>0).forEach(p=>{
  const k=String(p.productId||p.product_id||keyOf(p.product||p.productName||p.name));
  if(!k)return;const arr=productGroups.get(k)||[];arr.push(p);productGroups.set(k,arr);
 });
 const priceChanges=[];
 productGroups.forEach(rows=>{
  rows.sort((a,b)=>(a._date?.getTime()||0)-(b._date?.getTime()||0));
  if(rows.length<2)return;
  const prev=rows[rows.length-2],last=rows[rows.length-1],change=pct(last._unit,prev._unit);
  if(change!==null&&Math.abs(change)>=5)priceChanges.push({product:last.product||last.productName||last.name||'Product',previous:prev._unit,latest:last._unit,change,supplier:last._supplier||'Unassigned supplier',date:last._date});
 });
 priceChanges.sort((a,b)=>Math.abs(b.change)-Math.abs(a.change));
 const top=vendors[0],unassigned=valid.filter(x=>!x._supplier);
 return {vendors,recent,prior,total,oldTotal,change:pct(total,oldTotal),active:vendors.filter(v=>v.entries>0).length,avg:recent.length?total/recent.length:0,top,topShare:top?.share||0,unassigned,priceChanges,registered:(data.suppliers||[]).length,entryCount:recent.length,now};
}
function csv(rows){
 const cols=[...new Set(rows.flatMap(x=>Object.keys(x)))],cell=v=>{let s=String(v??'');if(/^[=+\-@]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"';};
 const content=[cols.map(cell).join(','),...rows.map(r=>cols.map(k=>cell(r[k])).join(','))].join('\r\n');
 const url=URL.createObjectURL(new Blob(['\ufeff',content],{type:'text/csv;charset=utf-8'})),a=document.createElement('a');
 a.href=url;a.download='white-lion-supplier-intelligence-'+new Date().toISOString().slice(0,10)+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function styles(){
 if(document.getElementById('wlsi-style'))return;
 const s=document.createElement('style');s.id='wlsi-style';
 s.textContent="#wlSupplierIntel{display:grid;gap:14px;color:var(--ink)}#wlSupplierIntel .wlsi-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap}#wlSupplierIntel .wlsi-muted{font-size:11px;color:var(--muted);line-height:1.5}#wlSupplierIntel .wlsi-actions{display:flex;gap:7px;flex-wrap:wrap}#wlSupplierIntel .wlsi-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px}#wlSupplierIntel .wlsi-card,#wlSupplierIntel .wlsi-panel{background:var(--white);border:1px solid var(--line);border-radius:15px;padding:15px;min-width:0;box-shadow:var(--shadow)}#wlSupplierIntel .wlsi-card small{font-size:10px;color:var(--muted)}#wlSupplierIntel .wlsi-card strong{display:block;font-size:clamp(18px,2.7vw,25px);margin:7px 0;overflow-wrap:anywhere}#wlSupplierIntel .wlsi-two{display:grid;grid-template-columns:1.1fr .9fr;gap:12px}#wlSupplierIntel h3{font-size:14px;margin:0 0 5px}#wlSupplierIntel .wlsi-tablewrap{overflow:auto;margin-top:10px}#wlSupplierIntel table{width:100%;border-collapse:collapse;white-space:nowrap;font-size:11px}#wlSupplierIntel th,#wlSupplierIntel td{text-align:left;padding:10px 9px;border-bottom:1px solid var(--line)}#wlSupplierIntel th{font-size:9px;text-transform:uppercase;letter-spacing:.8px;color:var(--muted);background:var(--bg)}#wlSupplierIntel tr:last-child td{border-bottom:0}#wlSupplierIntel .wlsi-meter{height:7px;background:var(--bg);border-radius:8px;overflow:hidden;min-width:70px}#wlSupplierIntel .wlsi-meter i{display:block;height:100%;background:linear-gradient(90deg,#cda85d,#16865f);border-radius:8px}#wlSupplierIntel .wlsi-pill{display:inline-block;border-radius:20px;padding:4px 7px;background:#edf5ef;color:#17633d;font-size:9px;font-weight:800}#wlSupplierIntel .wlsi-pill.warn{background:#fff2dc;color:#8b5d0b}#wlSupplierIntel .wlsi-empty{padding:18px;text-align:center;color:var(--muted);font-size:11px}#wlSupplierIntel .wlsi-note{padding:11px;border:1px solid var(--line);border-radius:11px;background:var(--bg);font-size:11px;line-height:1.55;margin-top:9px}#wlSupplierIntel .wlsi-filter{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:10px}#wlSupplierIntel input{border:1px solid var(--line);border-radius:9px;padding:9px 11px;background:var(--white);color:var(--ink);min-width:190px}@media(max-width:820px){#wlSupplierIntel .wlsi-grid{grid-template-columns:repeat(2,minmax(0,1fr))}#wlSupplierIntel .wlsi-two{grid-template-columns:1fr}}@media print{#wlSupplierIntel .wlsi-actions,#wlSupplierIntel .wlsi-filter{display:none!important}#wlSupplierIntel .wlsi-card,#wlSupplierIntel .wlsi-panel{box-shadow:none;break-inside:avoid}}html[data-theme=dark] #wlSupplierIntel .wlsi-card,html[data-theme=dark] #wlSupplierIntel .wlsi-panel{background:#172235;border-color:#2a374a}html[data-theme=dark] #wlSupplierIntel .wlsi-note{background:#101a2a}";
 document.head.appendChild(s);
}
function render(data){
 styles();const host=document.getElementById('view');if(!host)return;
 const d=analyse(data),cur=data.currency||'SLE';
 const change=d.change===null?'Not enough comparison history':(d.change>=0?'▲ ':'▼ ')+Math.abs(d.change).toFixed(1)+'% vs previous 90 days';
 const card=(label,value,note)=>'<div class="wlsi-card"><small>'+label+'</small><strong>'+value+'</strong><div class="wlsi-muted">'+note+'</div></div>';
 const supplierRows=()=>d.vendors.filter(v=>v.entries>0).map(v=>'<tr><td><b>'+esc(v.name)+'</b><div class="wlsi-muted">'+(v.registered?'Registered supplier':'Purchase name · no supplier profile')+'</div></td><td>'+v.entries+'</td><td><b>'+money(v.spend,cur)+'</b></td><td>'+money(v.average,cur)+'</td><td>'+v.share.toFixed(1)+'%<div class="wlsi-meter"><i style="width:'+Math.min(100,v.share)+'%"></i></div></td><td>'+(v.last?esc(v.last.toLocaleDateString()):'—')+'</td><td>'+(v.change===null?'—':(v.change>=0?'+':'')+v.change.toFixed(1)+'%')+'</td></tr>').join('');
 const priceRows=d.priceChanges.slice(0,20).map(p=>'<tr><td><b>'+esc(p.product)+'</b></td><td>'+esc(p.supplier)+'</td><td>'+money(p.previous,cur)+'</td><td>'+money(p.latest,cur)+'</td><td><span class="wlsi-pill '+(p.change>0?'warn':'')+'">'+(p.change>0?'+':'')+p.change.toFixed(1)+'%</span></td><td>'+(p.date?esc(p.date.toLocaleDateString()):'—')+'</td></tr>').join('');
 const top=d.vendors.filter(v=>v.spend>0).slice(0,5);
 const concentration=top.length?top.map(v=>'<div style="display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px;align-items:center;margin:11px 0"><div><b style="font-size:11px">'+esc(v.name)+'</b><div class="wlsi-meter" style="margin-top:5px"><i style="width:'+Math.min(100,v.share)+'%"></i></div></div><b style="font-size:11px">'+v.share.toFixed(1)+'%</b></div>').join(''):'<div class="wlsi-empty">No purchase spend in the last 90 days.</div>';
 host.innerHTML='<div id="wlSupplierIntel"><div class="wlsi-head"><div><div class="eyebrow">White Lion · Procurement Suite</div><h1 style="margin:5px 0">Supplier Intelligence</h1><div class="wlsi-muted">'+esc(data.businessName||'Selected workspace')+' · '+esc(data.branchName||'All branches')+' · Last 90 days · '+esc(d.now.toLocaleString())+'</div></div><div class="wlsi-actions"><button class="btn" id="wlsiRefresh">↻ Refresh</button><button class="btn primary" id="wlsiExport">Export procurement CSV</button><button class="btn" id="wlsiPrint">Print report</button></div></div>'+
 '<div class="wlsi-grid">'+card('Purchase spend',money(d.total,cur),d.entryCount+' recorded purchase entries')+card('Active suppliers',String(d.active),d.registered+' supplier profiles in directory')+card('Average purchase entry',money(d.avg,cur),'90-day average per recorded entry')+card('Spend movement',d.change===null?'—':(d.change>=0?'+':'')+d.change.toFixed(1)+'%',change)+card('Top supplier share',d.top?d.topShare.toFixed(1)+'%':'—',d.top?esc(d.top.name)+' · '+money(d.top.spend,cur):'No recorded supplier spend')+card('Unassigned purchase entries',String(d.unassigned.length),'Entries without a supplier name')+card('Purchase price movements',String(d.priceChanges.length),'Product unit costs changed by at least 5%')+card('Supplier records',String(d.registered),'Registered supplier profiles')+'</div>'+
 '<div class="wlsi-two"><section class="wlsi-panel"><h3>Supplier spend concentration</h3><div class="wlsi-muted">Share of recorded purchase spend by supplier over the last 90 days.</div>'+concentration+'<div class="wlsi-note">'+(d.top&&d.topShare>=50?'One supplier accounts for at least half of recorded purchase spend. Consider reviewing supplier concentration and contingency options.':'Use this view to understand how concentrated procurement spend is across suppliers.')+'</div></section><section class="wlsi-panel"><h3>Procurement signals</h3><div class="wlsi-note"><b>90-day spend movement</b><br>'+esc(change)+'. The comparison uses the immediately preceding 90-day period.</div><div class="wlsi-note"><b>Unassigned purchases</b><br>'+d.unassigned.length+' purchase entries have no supplier name. Assigning suppliers improves traceability.</div><div class="wlsi-note"><b>Price watch</b><br>'+d.priceChanges.length+' product cost movements meet the 5% review threshold. Check quantities, units and supplier terms before making decisions.</div></section></div>'+
 '<section class="wlsi-panel"><h3>Supplier scorecard</h3><div class="wlsi-muted">Ranked by recorded 90-day spend. These are measured activity indicators, not subjective supplier quality ratings.</div><div class="wlsi-filter"><input id="wlsiSearch" type="search" placeholder="Search supplier name"><span class="wlsi-muted">'+d.vendors.filter(v=>v.entries>0).length+' suppliers with recorded purchases</span></div><div class="wlsi-tablewrap"><table><thead><tr><th>Supplier</th><th>Entries</th><th>Spend</th><th>Avg. entry</th><th>Spend share</th><th>Last purchase</th><th>Spend change</th></tr></thead><tbody id="wlsiSupplierRows">'+(supplierRows()||'<tr><td colspan="7" class="wlsi-empty">No supplier purchase records are available for this period.</td></tr>')+'</tbody></table></div></section>'+
 '<section class="wlsi-panel"><h3>Purchase price watch</h3><div class="wlsi-muted">Compares the two most recent recorded unit costs for the same product. Movements below 5% are hidden.</div><div class="wlsi-tablewrap"><table><thead><tr><th>Product</th><th>Latest supplier</th><th>Previous unit cost</th><th>Latest unit cost</th><th>Change</th><th>Latest date</th></tr></thead><tbody>'+(priceRows||'<tr><td colspan="6" class="wlsi-empty">Not enough comparable purchase history to show price movements.</td></tr>')+'</tbody></table></div></section>'+
 '<div class="wlsi-muted">Data scope: uses purchase entries and supplier profiles saved in this selected business and branch. It does not alter records, create purchase orders, verify delivery quality, or infer supplier reliability. Results depend on accurate supplier names, dates, quantities and unit costs.</div></div>';
 const filter=()=>{const q=(document.getElementById('wlsiSearch').value||'').toLowerCase();const rows=d.vendors.filter(v=>v.entries>0&&v.name.toLowerCase().includes(q));document.getElementById('wlsiSupplierRows').innerHTML=rows.map(v=>'<tr><td><b>'+esc(v.name)+'</b><div class="wlsi-muted">'+(v.registered?'Registered supplier':'Purchase name · no supplier profile')+'</div></td><td>'+v.entries+'</td><td><b>'+money(v.spend,cur)+'</b></td><td>'+money(v.average,cur)+'</td><td>'+v.share.toFixed(1)+'%<div class="wlsi-meter"><i style="width:'+Math.min(100,v.share)+'%"></i></div></td><td>'+(v.last?esc(v.last.toLocaleDateString()):'—')+'</td><td>'+(v.change===null?'—':(v.change>=0?'+':'')+v.change.toFixed(1)+'%')+'</td></tr>').join('')||'<tr><td colspan="7" class="wlsi-empty">No matching supplier records.</td></tr>'};
 document.getElementById('wlsiSearch').addEventListener('input',filter);
 document.getElementById('wlsiRefresh').onclick=()=>window.setPage('supplierintel');
 document.getElementById('wlsiPrint').onclick=()=>window.print();
 document.getElementById('wlsiExport').onclick=()=>csv([
  ...d.vendors.map(v=>({supplier:v.name,registered_supplier:v.registered,purchase_entries_90d:v.entries,spend_90d:v.spend,average_entry:v.average,spend_share_percent:v.share,last_purchase:v.last?.toISOString()||'',previous_90d_spend:v.oldSpend,spend_change_percent:v.change})),
  ...d.priceChanges.map(p=>({record_type:'unit_cost_change',product:p.product,supplier:p.supplier,previous_unit_cost:p.previous,latest_unit_cost:p.latest,change_percent:p.change,latest_purchase_date:p.date?.toISOString()||''}))
 ]);
}
window.WhiteLionSupplierIntelligence={render,analyse};
})();