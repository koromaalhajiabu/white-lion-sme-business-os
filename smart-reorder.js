/* White Lion SME — Smart Reorder & Low-Stock Forecasting.
   Read-only demand and stock planning from the active workspace's local-first records. */
(function(){
'use strict';
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const n=v=>{const x=Number(v);return Number.isFinite(x)?x:0};
const dateOf=x=>{const d=new Date(x?.date||x?.createdAt||x?.created_at||'');return Number.isNaN(d.getTime())?null:d};
const money=(v,c)=>{try{return new Intl.NumberFormat(undefined,{style:'currency',currency:c||'SLE',maximumFractionDigits:2}).format(n(v))}catch(_){return (c||'SLE')+' '+n(v).toFixed(2)}};
const qty=v=>Number(n(v).toFixed(3));
const daysText=v=>v===null?'No demand data':v<=0?'Now':v<1?'<1 day':Math.floor(v)+' days';
function analyse(data){
 const now=new Date(),t7=now.getTime()-7*86400000,t30=now.getTime()-30*86400000;
 const sales=(data.sales||[]).map(s=>({row:s,date:dateOf(s)})).filter(x=>x.date&&x.date<=now&&x.date.getTime()>=t30);
 const units7={},units30={};
 sales.forEach(({row,date})=>(row.items||[]).forEach(item=>{
  const p=(data.products||[]).find(x=>String(x.id)===String(item.productId)||String(x.name||'').trim().toLowerCase()===String(item.name||'').trim().toLowerCase());
  if(!p)return;const q=Math.max(0,n(item.quantity));if(!q)return;
  units30[p.id]=(units30[p.id]||0)+q;if(date.getTime()>=t7)units7[p.id]=(units7[p.id]||0)+q;
 }));
 const rows=(data.products||[]).map(p=>{
  const productStock=(data.stockRows||[]).filter(x=>String(x.productId)===String(p.id));
  const branchRow=productStock.find(x=>String(x.branchId||'local-main')===String(data.branchId||'local-main'));
  const stock=branchRow?n(branchRow.quantity):productStock.length?0:n(p.stock);
  const u7=units7[p.id]||0,u30=units30[p.id]||0;
  const d30=u30/30,d7=u7/7;
  const daily=u30>0?(d30*.7+d7*.3):d7;
  const hasHistory=u30>0;
  const lead=Math.max(0,n(p.leadTimeDays)||7),cover=Math.max(0,n(p.minCoverDays)||14),reorder=Math.max(0,n(p.reorder));
  const target=hasHistory?Math.ceil(daily*(lead+cover)):reorder;
  const order=qty(Math.max(0,target-stock));
  const coverDays=daily>0?stock/daily:null;
  const stockout=coverDays===null?null:new Date(now.getTime()+Math.max(0,coverDays)*86400000);
  let priority='healthy',reason='Stock position is above the planning threshold';
  if(stock<=0){priority='out';reason='No available stock';}
  else if(!hasHistory){priority=stock<=reorder?'reorder':'unknown';reason=stock<=reorder?'At or below saved reorder level':'No recent sales history; set a reorder level or record sales';}
  else if(coverDays<=lead){priority='urgent';reason='Estimated stock cover does not reach supplier lead time';}
  else if(stock<=reorder||coverDays<=lead+cover){priority='reorder';reason='Replenishment is due within lead time plus target cover';}
  else if(coverDays<=lead+cover+7){priority='watch';reason='Stock cover is approaching the reorder horizon';}
  return {p,stock,u7,u30,daily,lead,cover,reorder,target,order,coverDays,stockout,priority,reason,hasHistory};
 }).sort((a,b)=>({out:0,urgent:1,reorder:2,watch:3,unknown:4,healthy:5}[a.priority]-({out:0,urgent:1,reorder:2,watch:3,unknown:4,healthy:5}[b.priority])||a.stock-b.stock));
 return {rows,transactions:sales.length,counts:Object.fromEntries(['out','urgent','reorder','watch','unknown','healthy'].map(k=>[k,rows.filter(x=>x.priority===k).length])),now};
}
function csv(rows){
 const cols=['Product','SKU','Category','Available stock','Unit','Units sold 7d','Units sold 30d','Blended daily demand','Stock cover days','Estimated stockout date','Supplier lead days','Target cover days','Target stock','Suggested reorder quantity','Saved reorder level','Priority','Planning note'];
 const cell=v=>{let s=String(v??'');if(/^[=+\-@]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"';};
 const lines=rows.map(x=>[x.p.name,x.p.sku,x.p.category,x.stock,x.p.unit||'units',qty(x.u7),qty(x.u30),qty(x.daily),x.coverDays===null?'':qty(x.coverDays),x.stockout?x.stockout.toISOString().slice(0,10):'',x.lead,x.cover,x.target,x.order,x.reorder,x.priority,x.reason].map(cell).join(','));
 const url=URL.createObjectURL(new Blob(['\ufeff',cols.map(cell).join(','),'\r\n',lines.join('\r\n')],{type:'text/csv;charset=utf-8'}));
 const a=document.createElement('a');a.href=url;a.download='white-lion-smart-reorder-'+new Date().toISOString().slice(0,10)+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function styles(){
 if(document.getElementById('wlreorder-style'))return;
 const s=document.createElement('style');s.id='wlreorder-style';
 s.textContent="#wlReorder{display:grid;gap:14px;color:var(--ink)}#wlReorder .wr-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap}#wlReorder .wr-muted{font-size:11px;color:var(--muted);line-height:1.55}#wlReorder .wr-actions,#wlReorder .wr-filters{display:flex;gap:8px;flex-wrap:wrap;align-items:center}#wlReorder .wr-grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px}#wlReorder .wr-card,#wlReorder .wr-panel{background:var(--white);border:1px solid var(--line);border-radius:15px;padding:15px;min-width:0;box-shadow:var(--shadow)}#wlReorder .wr-card small{font-size:10px;color:var(--muted)}#wlReorder .wr-card strong{display:block;font-size:25px;margin:7px 0;color:var(--ink)}#wlReorder .wr-card.alert strong{color:#b84b4b}#wlReorder .wr-card.warn strong{color:#a87522}#wlReorder h3{font-size:14px;margin:0 0 5px}#wlReorder .wr-panel-head{display:flex;justify-content:space-between;align-items:flex-start;gap:10px;flex-wrap:wrap}#wlReorder .wr-table{overflow:auto;margin-top:11px}#wlReorder table{width:100%;border-collapse:collapse;white-space:nowrap;font-size:11px}#wlReorder th,#wlReorder td{text-align:left;padding:10px 9px;border-bottom:1px solid var(--line)}#wlReorder th{font-size:9px;text-transform:uppercase;letter-spacing:.7px;color:var(--muted);background:var(--bg)}#wlReorder tr:last-child td{border-bottom:0}#wlReorder .wr-status{display:inline-flex;border-radius:20px;padding:5px 8px;font-size:9px;font-weight:800;background:#edf5ef;color:#17633d}#wlReorder .wr-status.out{background:#fdebed;color:#a52e3b}#wlReorder .wr-status.urgent,#wlReorder .wr-status.reorder{background:#fff2dc;color:#8b5d0b}#wlReorder .wr-status.watch{background:#eaf1fc;color:#315f9b}#wlReorder .wr-status.unknown{background:#eef0f4;color:#667085}#wlReorder input,#wlReorder select{border:1px solid var(--line);border-radius:9px;padding:9px 10px;background:var(--white);color:var(--ink);min-width:0}#wlReorder .wr-note{padding:12px;border:1px solid var(--line);border-radius:11px;background:var(--bg);font-size:11px;line-height:1.6}#wlReorder .wr-empty{padding:20px;text-align:center;color:var(--muted)}@media(max-width:900px){#wlReorder .wr-grid{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:620px){#wlReorder .wr-grid{grid-template-columns:repeat(2,minmax(0,1fr))}#wlReorder .wr-card{padding:12px}#wlReorder .wr-card strong{font-size:21px}#wlReorder .wr-filters input{flex:1;width:100%}}@media print{#wlReorder .wr-actions,#wlReorder .wr-filters{display:none!important}#wlReorder .wr-card,#wlReorder .wr-panel{box-shadow:none;break-inside:avoid}}";
 document.head.appendChild(s);
}
function render(data){
 styles();const host=document.getElementById('view');if(!host)return;
 const d=analyse(data),cur=data.currency||'SLE';let filter='all',search='';
 const labels={out:'Out of stock',urgent:'Urgent',reorder:'Reorder now',watch:'Watch',unknown:'No sales history',healthy:'Healthy'};
 const fmtDate=x=>x?x.toLocaleDateString():'—';
 const rowHtml=x=>'<tr><td><b>'+esc(x.p.name||'Unnamed product')+'</b><div class="wr-muted">'+esc(x.p.sku||x.p.barcode||x.p.category||'No item code')+'</div></td><td><b>'+qty(x.stock)+'</b> '+esc(x.p.unit||'units')+'</td><td>'+qty(x.u7)+'</td><td>'+qty(x.u30)+'</td><td>'+qty(x.daily)+'</td><td>'+(x.coverDays===null?'—':daysText(x.coverDays))+'</td><td>'+fmtDate(x.stockout)+'</td><td>'+x.lead+' days</td><td><b>'+x.order+'</b> '+esc(x.p.unit||'units')+'</td><td><span class="wr-status '+x.priority+'">'+labels[x.priority]+'</span></td></tr>';
 const cards=[['Out of stock',d.counts.out,'Immediate replenishment review','alert'],['Urgent',d.counts.urgent,'May run out before lead time','alert'],['Reorder now',d.counts.reorder,'Within target replenishment horizon','warn'],['Watch list',d.counts.watch,'Approaching reorder horizon',''],['Healthy',d.counts.healthy,'Above current planning threshold','']];
 host.innerHTML='<div id="wlReorder"><div class="wr-head"><div><div class="eyebrow">White Lion · Inventory Planning</div><h1 style="margin:5px 0">Smart Reorder Planner</h1><div class="wr-muted">'+esc(data.businessName||'Selected workspace')+' · '+esc(data.branchName||'Selected branch')+' · Updated '+esc(d.now.toLocaleString())+'</div></div><div class="wr-actions"><button class="btn" id="wrRefresh">↻ Refresh</button><button class="btn primary" id="wrExport">Export reorder plan</button><button class="btn" id="wrPrint">Print plan</button></div></div>'+
 '<div class="wr-grid">'+cards.map(c=>'<div class="wr-card '+c[3]+'"><small>'+c[0]+'</small><strong>'+c[1]+'</strong><div class="wr-muted">'+c[2]+'</div></div>').join('')+'</div>'+
 '<section class="wr-panel"><div class="wr-panel-head"><div><h3>Demand forecast & reorder queue</h3><div class="wr-muted">Demand estimate blends 70% of the 30-day daily average with 30% of the 7-day daily average. The target covers supplier lead time plus each product’s saved extra-cover days.</div></div><span class="wr-status watch">'+d.transactions+' sales in last 30 days</span></div>'+
 '<div class="wr-filters" style="margin-top:12px"><input id="wrSearch" type="search" placeholder="Search product, SKU or category"><select id="wrPriority"><option value="all">All priorities</option><option value="out">Out of stock</option><option value="urgent">Urgent</option><option value="reorder">Reorder now</option><option value="watch">Watch</option><option value="unknown">No sales history</option><option value="healthy">Healthy</option></select><span class="wr-muted" id="wrCount">'+d.rows.length+' products</span></div>'+
 '<div class="wr-table"><table><thead><tr><th>Product</th><th>Available</th><th>Sold 7d</th><th>Sold 30d</th><th>Avg/day</th><th>Stock cover</th><th>Est. stockout</th><th>Lead time</th><th>Suggested order</th><th>Priority</th></tr></thead><tbody id="wrRows">'+(d.rows.map(rowHtml).join('')||'<tr><td colspan="10" class="wr-empty">No products in this business catalogue yet. Add products to start forecasting.</td></tr>')+'</tbody></table></div></section>'+
 '<section class="wr-panel"><h3>How to read this plan</h3><div class="wr-note"><b>Estimated stockout:</b> available quantity divided by blended daily demand. It is a projection, not a guaranteed date. <b>Suggested order:</b> target stock less available quantity, never below zero. For products without recent sales, the planner does not invent demand; it uses the saved reorder level and marks the row “No sales history”.</div><div class="wr-note" style="margin-top:9px"><b>Important:</b> This is planning guidance only. It does not place purchase orders, contact suppliers, reserve stock or alter inventory. Confirm supplier lead times, open purchase orders, seasonality and physical stock before ordering.</div></section></div>';
 const apply=()=>{const q=(document.getElementById('wrSearch').value||'').trim().toLowerCase(),p=document.getElementById('wrPriority').value;const rows=d.rows.filter(x=>(p==='all'||x.priority===p)&&[x.p.name,x.p.sku,x.p.category,x.p.barcode].join(' ').toLowerCase().includes(q));document.getElementById('wrRows').innerHTML=rows.map(rowHtml).join('')||'<tr><td colspan="10" class="wr-empty">No products match this filter.</td></tr>';document.getElementById('wrCount').textContent=rows.length+' of '+d.rows.length+' products';};
 document.getElementById('wrSearch').addEventListener('input',apply);document.getElementById('wrPriority').addEventListener('change',apply);
 document.getElementById('wrRefresh').onclick=()=>window.setPage('reorder');document.getElementById('wrPrint').onclick=()=>window.print();document.getElementById('wrExport').onclick=()=>csv(d.rows);
}
window.WhiteLionSmartReorder={analyse,render};
})();