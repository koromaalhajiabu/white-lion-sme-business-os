/* White Lion SME Executive Action Centre — offline-first with secure Supabase sync. */
(function(){
'use strict';
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const makeId=()=> 'wla_'+Date.now().toString(36)+'_'+Math.random().toString(36).slice(2,9);
let activeChannel=null,activeScope='',syncBusy=false,lastData=null;
function detect(d){
 const now=Date.now(),recent=d.sales.filter(x=>{const t=Date.parse(x.date||x.createdAt||x.created_at||'');return t>=now-30*864e5&&t<=now}),prior=d.sales.filter(x=>{const t=Date.parse(x.date||x.createdAt||x.created_at||'');return t>=now-60*864e5&&t<now-30*864e5});
 const total=a=>a.reduce((s,x)=>s+(Number(x.total)||0),0),a=[];
 if(total(prior)>0&&total(recent)<total(prior)*.85)a.push({id:'sales_decline',kind:'alert',type:'Sales',priority:'High',title:'Sales have declined',detail:'Recorded sales are down '+((1-total(recent)/total(prior))*100).toFixed(1)+'% against the previous 30 days.',recommendation:'Review sales by day, product availability and customer activity.'});
 const ex=d.expenses.filter(x=>{const t=Date.parse(x.date||x.expense_date||x.createdAt||'');return t>=now-30*864e5&&t<=now}).reduce((s,x)=>s+(Number(x.amount)||0),0);
 if(total(recent)>0&&ex>total(recent))a.push({id:'expense_sales',kind:'alert',type:'Finance',priority:'High',title:'Expenses exceed recorded sales',detail:'30-day expenses exceed recorded gross sales.',recommendation:'Review expense entries and confirm all sales have been recorded.'});
 d.products.filter(p=>Number(p.stock||0)<=0).slice(0,12).forEach(p=>a.push({id:'stock_'+p.id,kind:'alert',type:'Inventory',priority:'Urgent',title:'Out of stock: '+(p.name||'Product'),detail:'No available stock is recorded.',recommendation:'Verify physical stock and arrange replenishment if needed.'}));
 d.products.filter(p=>Number(p.stock||0)>0&&Number(p.minStock||p.reorderLevel||0)>0&&Number(p.stock)<=Number(p.minStock||p.reorderLevel)).slice(0,12).forEach(p=>a.push({id:'low_'+p.id,kind:'alert',type:'Inventory',priority:'High',title:'Low stock: '+(p.name||'Product'),detail:'Stock is '+Number(p.stock)+'; reorder threshold is '+Number(p.minStock||p.reorderLevel)+'.',recommendation:'Review demand and supplier lead time.'}));
 return a;
}
function eventFor(r,event,userId){
 r.history=r.history||[];
 r.history.unshift({event_id:makeId(),at:new Date().toISOString(),event,actor_user_id:userId||null});
 r.updatedAt=new Date().toISOString();
}
function render(d){
 lastData=d;
 const host=document.getElementById('view');if(!host)return;
 let records=Array.isArray(d.records)?d.records.slice():[];
 let addedAlert=false;
 detect(d).forEach(a=>{const old=records.find(x=>x.id===a.id);if(old)Object.assign(old,a);else{const now=new Date().toISOString();records.unshift({...a,status:'Open',assignee:'',assigneeUserId:null,createdAt:now,updatedAt:now,history:[{event_id:makeId(),at:now,event:'System alert created',actor_user_id:d.userId||null}]});addedAlert=true}});
 if(addedAlert)Promise.resolve(d.saveRecords(records)).catch(()=>{});
 const canManage=['owner','admin','manager'].includes(String(d.role||'').toLowerCase());
 const members=Array.isArray(d.members)?d.members:[];
 const memberOptions=(selected)=>'<option value="">Unassigned</option>'+members.map(m=>'<option value="'+esc(m.user_id)+'" '+(String(selected||'')===String(m.user_id)?'selected':'')+'>'+esc(m.full_name||'Business employee')+' · '+esc(m.role||'staff')+'</option>').join('');
 const setStatus=(message,good)=>{const el=host.querySelector('#wlaSyncStatus');if(el){el.textContent=message;el.style.color=good?'#16865b':'#9b6a10'}};
 const saveLocal=async()=>d.saveRecords(records);
 const syncPush=async(remoteRows)=>{
  const client=d.cloudClient,bid=d.businessId,uid=d.userId;
  if(!client||!bid||!uid||navigator.onLine===false)return {ok:false,offline:true};
  const remoteByClient=new Map((remoteRows||[]).map(x=>[String(x.client_id),x]));
  const actionIds=new Map();
  for(const r of records){
   const remote=remoteByClient.get(String(r.id));
   const allowed=canManage||String(r.assigneeUserId||'')===String(uid);
   if(!allowed)continue;
   const localTime=Date.parse(r.updatedAt||r.createdAt||0)||0,remoteTime=Date.parse(remote?.updated_at||0)||0;
   if(remote&&remoteTime>=localTime){actionIds.set(r.id,remote.id);continue}
   const row={business_id:bid,branch_id:r.branchId??d.branchId??null,client_id:String(r.id),kind:r.kind==='alert'?'alert':'task',action_type:r.type||'Management task',title:String(r.title||'Action').slice(0,160),detail:String(r.detail||r.description||''),priority:['Normal','High','Urgent'].includes(r.priority)?r.priority:'Normal',status:['Open','Acknowledged','Resolved','Completed'].includes(r.status)?r.status:'Open',assignee_user_id:r.assigneeUserId||null,assignee_label:r.assignee||'',due_date:r.due||null,payload:{recommendation:r.recommendation||''},updated_by:uid,updated_at:r.updatedAt||new Date().toISOString()};
   const result=await client.from('executive_actions').upsert(row,{onConflict:'business_id,client_id'}).select('id,client_id').single();
   if(result.error){setStatus('Cloud sync needs attention: '+result.error.message,false);return {ok:false,error:result.error}}
   actionIds.set(r.id,result.data.id);
  }
  const eventRows=[];
  for(const r of records){
   const actionId=actionIds.get(r.id);if(!actionId)continue;
   (r.history||[]).forEach(h=>{
    if(!h.event_id)h.event_id=makeId();
    if(!h._cloudSynced)eventRows.push({business_id:bid,action_id:actionId,client_event_id:String(h.event_id),actor_user_id:uid,event:String(h.event||'Action updated').slice(0,240),details:{record_title:r.title||''},created_at:h.at||new Date().toISOString()});
   });
  }
  if(eventRows.length){
   const ev=await client.from('executive_action_events').upsert(eventRows,{onConflict:'business_id,client_event_id',ignoreDuplicates:true});
   if(ev.error){setStatus('Actions saved, but audit history sync needs attention: '+ev.error.message,false);return {ok:false,error:ev.error}}
   records.forEach(r=>(r.history||[]).forEach(h=>{h._cloudSynced=true}));
   await saveLocal();
  }
  return {ok:true};
 };
 let cloudSync=async()=>{
  if(syncBusy)return;syncBusy=true;
  try{
   const client=d.cloudClient,bid=d.businessId;
   if(!client||!bid||!d.userId){setStatus('Offline/local workspace. Sign in and select a business to share actions.',false);return}
   if(navigator.onLine===false){setStatus('Offline — changes are saved on this device and will sync when connection returns.',false);return}
   const remoteResult=await client.from('executive_actions').select('*').eq('business_id',bid).order('updated_at',{ascending:false}).limit(500);
   if(remoteResult.error){setStatus('Cloud setup pending. Run migration 031 in Supabase: '+remoteResult.error.message,false);return}
   const remoteRows=remoteResult.data||[];
   const ids=remoteRows.map(x=>x.id);
   let events=[];
   if(ids.length){
    const ev=await client.from('executive_action_events').select('action_id,client_event_id,actor_user_id,event,created_at').eq('business_id',bid).order('created_at',{ascending:false}).limit(2000);
    if(!ev.error)events=ev.data||[];
   }
   const eventsByAction=new Map();
   events.forEach(e=>{const a=eventsByAction.get(e.action_id)||[];a.push({event_id:e.client_event_id,at:e.created_at,event:e.event,actor_user_id:e.actor_user_id,_cloudSynced:true});eventsByAction.set(e.action_id,a)});
   let remoteRecords=remoteRows.filter(x=>!d.branchId||!x.branch_id||String(x.branch_id)===String(d.branchId)).map(x=>({id:x.client_id,remoteId:x.id,kind:x.kind,type:x.action_type,title:x.title,detail:x.detail,priority:x.priority,status:x.status,assigneeUserId:x.assignee_user_id,assignee:x.assignee_label||'',branchId:x.branch_id||null,due:x.due_date||'',recommendation:x.payload?.recommendation||'',createdAt:x.created_at,updatedAt:x.updated_at,history:eventsByAction.get(x.id)||[]}));
   const map=new Map(records.map(r=>[String(r.id),r]));
   remoteRecords.forEach(remote=>{
    const local=map.get(String(remote.id));
    if(!local){map.set(String(remote.id),remote);return}
    const lt=Date.parse(local.updatedAt||local.createdAt||0)||0,rt=Date.parse(remote.updatedAt||remote.createdAt||0)||0;
    const chosen=rt>lt?{...local,...remote}:{...remote,...local};
    const history=new Map();
    [...(remote.history||[]),...(local.history||[])].forEach(h=>history.set(String(h.event_id||h.at+'|'+h.event),h));
    chosen.history=[...history.values()].sort((a,b)=>Date.parse(b.at)-Date.parse(a.at));
    map.set(String(remote.id),chosen);
   });
   const merged=[...map.values()];
   const changed=JSON.stringify(merged)!==JSON.stringify(records);
   records=merged;
   if(changed){await saveLocal();render({...d,records,_skipCloudLoad:true})}
   const push=await syncPush(remoteRows);
   if(push.ok)setStatus('☁ Synced — shared with authorised members of this business. Last sync '+new Date().toLocaleTimeString(),true);
  }catch(err){setStatus('Cloud sync unavailable: '+(err.message||String(err)),false)}
  finally{syncBusy=false}
 };
 const alerts=records.filter(x=>x.kind!=='task'&&x.status!=='Resolved');
 const tasks=records.filter(x=>x.kind==='task');
 const openTasks=tasks.filter(x=>x.status!=='Completed');
 const card=r=>'<article class="wla-item"><div class="wla-row"><div><b>'+esc(r.title)+'</b><div class="wla-muted">'+esc(r.type||'Task')+' · '+esc(r.priority||'Normal')+'</div></div><span class="wla-pill '+(r.status==='Resolved'||r.status==='Completed'?'done':r.priority==='Urgent'?'urgent':'')+'">'+esc(r.status||'Open')+'</span></div><p>'+esc(r.detail||r.description||'')+'</p>'+(r.assignee?'<div class="wla-muted">Assigned to: '+esc(r.assignee)+'</div>':'')+(r.due?'<div class="wla-muted">Due: '+esc(r.due)+'</div>':'')+'<div class="wla-actions">'+(r.status==='Resolved'||r.status==='Completed'?'<button data-act="reopen" data-id="'+esc(r.id)+'">Reopen</button>':'<button data-act="ack" data-id="'+esc(r.id)+'">Acknowledge</button><button data-act="resolve" data-id="'+esc(r.id)+'">'+(r.kind==='task'?'Complete':'Resolve')+'</button>')+(canManage?'<select data-assignee-select="'+esc(r.id)+'" aria-label="Assign employee">'+memberOptions(r.assigneeUserId)+'</select><button data-act="assign" data-id="'+esc(r.id)+'">Assign</button>':'')+'<button data-act="history" data-id="'+esc(r.id)+'">History</button></div><div class="wla-history" id="hist_'+esc(r.id)+'" hidden></div></article>';
 host.innerHTML='<style>#wlAction{display:grid;gap:13px}#wlAction .wla-head,#wlAction .wla-row{display:flex;justify-content:space-between;align-items:flex-start;gap:10px;flex-wrap:wrap}#wlAction .wla-stats{display:grid;grid-template-columns:repeat(4,1fr);gap:9px}#wlAction .wla-stat,#wlAction .wla-panel{background:var(--white);border:1px solid var(--line);border-radius:14px;padding:14px;min-width:0}#wlAction .wla-stat small,#wlAction .wla-muted{font-size:11px;color:var(--muted)}#wlAction .wla-stat strong{display:block;font-size:24px;margin-top:5px}#wlAction .wla-columns{display:grid;grid-template-columns:1fr 1fr;gap:12px}#wlAction h3{font-size:14px;margin:0 0 4px}#wlAction .wla-list{display:grid;gap:8px;margin-top:10px}#wlAction .wla-item{border:1px solid var(--line);border-radius:10px;padding:11px;background:var(--bg)}#wlAction .wla-item b{font-size:12px}#wlAction .wla-item p{font-size:11px;color:var(--muted);margin:5px 0;line-height:1.5}#wlAction .wla-pill{font-size:9px;font-weight:800;padding:4px 7px;border-radius:14px;background:#fff1d8;color:#805500}#wlAction .wla-pill.done{background:#e7f6ed;color:#176b43}#wlAction .wla-pill.urgent{background:#fdebed;color:#a22e39}#wlAction .wla-actions{display:flex;gap:6px;flex-wrap:wrap;margin-top:8px}#wlAction button,#wlAction select{border:1px solid var(--line);border-radius:8px;background:var(--white);padding:6px 9px;font-size:10px;color:var(--ink)}#wlAction .wla-form{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}#wlAction .wla-form .full{grid-column:1/-1}#wlAction input,#wlAction select,#wlAction textarea{width:100%;border:1px solid var(--line);border-radius:8px;padding:9px;background:var(--white);color:var(--ink);font:inherit;font-size:12px}#wlAction .wla-empty{padding:16px;text-align:center;color:var(--muted);font-size:11px}#wlAction .wla-history{font-size:10px;color:var(--muted);margin-top:7px}@media(max-width:740px){#wlAction .wla-stats{grid-template-columns:1fr 1fr}#wlAction .wla-columns,#wlAction .wla-form{grid-template-columns:1fr}#wlAction .wla-form .full{grid-column:auto}}</style><div id="wlAction"><div class="wla-head"><div><div class="eyebrow">White Lion · Management</div><h1 style="margin:5px 0">Executive Action Centre</h1><div class="wla-muted">'+esc(d.businessName)+' · '+esc(d.branchName)+' · Offline-first shared workspace</div><div id="wlaSyncStatus" class="wla-muted" role="status" aria-live="polite">Checking cloud connection…</div></div><button id="wlaRefresh">↻ Sync & refresh</button></div><div class="wla-stats"><div class="wla-stat"><small>Open alerts</small><strong>'+alerts.length+'</strong></div><div class="wla-stat"><small>High / urgent</small><strong>'+alerts.filter(x=>x.priority==='High'||x.priority==='Urgent').length+'</strong></div><div class="wla-stat"><small>Outstanding tasks</small><strong>'+openTasks.length+'</strong></div><div class="wla-stat"><small>Resolved / completed</small><strong>'+records.filter(x=>x.status==='Resolved'||x.status==='Completed').length+'</strong></div></div><div class="wla-columns"><section class="wla-panel"><h3>Management alerts</h3><div class="wla-muted">Acknowledge, assign and resolve operational issues.</div><div class="wla-list">'+(alerts.length?alerts.map(card).join(''):'<div class="wla-empty">No open alerts detected.</div>')+'</div></section><section class="wla-panel"><h3>Management tasks</h3><div class="wla-muted">Assign corrective actions and monitor completion.</div>'+(canManage?'<form id="wlaForm" class="wla-form"><input name="title" class="full" required maxlength="100" placeholder="Task title"><select name="assignee_user_id" aria-label="Assign to employee">'+memberOptions('')+'</select><select name="priority"><option>Normal</option><option>High</option><option>Urgent</option></select><input name="due" type="date"><textarea name="description" class="full" rows="2" placeholder="Task details"></textarea><button class="full" type="submit">＋ Create task</button></form>':'<div class="wla-muted">You can update tasks assigned to your account. Managers create and assign tasks.</div>')+'<div class="wla-list">'+(tasks.length?tasks.map(card).join(''):'<div class="wla-empty">No management tasks created yet.</div>')+'</div></section></div><section class="wla-panel"><h3>Executive activity & audit history</h3><div class="wla-list">'+(records.flatMap(r=>(r.history||[]).map(h=>({title:r.title,...h}))).sort((a,b)=>Date.parse(b.at)-Date.parse(a.at)).slice(0,30).map(h=>'<div class="wla-item"><b>'+esc(h.event)+'</b><p>'+esc(h.title)+' · '+esc(new Date(h.at).toLocaleString())+'</p></div>').join('')||'<div class="wla-empty">No management activity recorded yet.</div>')+'</div></section></div>';
 if(canManage&&host.querySelector('#wlaForm'))host.querySelector('#wlaForm').addEventListener('submit',async e=>{e.preventDefault();const f=new FormData(e.currentTarget),title=String(f.get('title')||'').trim();if(!title)return;const uid=String(f.get('assignee_user_id')||''),member=members.find(m=>String(m.user_id)===uid),now=new Date().toISOString();const r={id:makeId(),kind:'task',type:'Management task',title,detail:String(f.get('description')||''),assignee:member?.full_name||'',assigneeUserId:uid||null,priority:String(f.get('priority')||'Normal'),due:String(f.get('due')||''),status:'Open',createdAt:now,updatedAt:now,history:[]};eventFor(r,'Task created',d.userId);records.unshift(r);await saveLocal();await cloudSync();render({...d,records,_skipCloudLoad:true})});
 host.querySelector('#wlaRefresh').onclick=async()=>{await cloudSync();render({...d,records,_skipCloudLoad:true})};
 host.onclick=async e=>{const b=e.target.closest('[data-act]');if(!b)return;const r=records.find(x=>x.id===b.dataset.id);if(!r)return;const act=b.dataset.act;if(act==='history'){const el=host.querySelector('#hist_'+r.id);el.hidden=!el.hidden;el.textContent=(r.history||[]).map(h=>new Date(h.at).toLocaleString()+' — '+h.event).join(' · ');return}if(act==='assign'){const select=host.querySelector('[data-assignee-select="'+r.id+'"]');const uid=select?.value||'';const member=members.find(m=>String(m.user_id)===uid);r.assigneeUserId=uid||null;r.assignee=member?.full_name||'';eventFor(r,'Assigned to '+(r.assignee||'unassigned'),d.userId)}if(act==='ack'){r.status='Acknowledged';eventFor(r,'Acknowledged',d.userId)}if(act==='resolve'){r.status=r.kind==='task'?'Completed':'Resolved';eventFor(r,r.status,d.userId)}if(act==='reopen'){r.status='Open';eventFor(r,'Reopened',d.userId)}await saveLocal();await cloudSync();render({...d,records,_skipCloudLoad:true})};
 if(d.cloudClient&&d.businessId&&d.userId){
  const scope=String(d.businessId)+'|'+String(d.branchId||'all');
  if(activeScope!==scope){
   if(activeChannel){try{await d.cloudClient.removeChannel(activeChannel)}catch(_){}activeChannel=null}
   activeScope=scope;
   activeChannel=d.cloudClient.channel('wl-executive-actions-'+scope.replace(/[^a-zA-Z0-9]/g,'-'))
    .on('postgres_changes',{event:'*',schema:'public',table:'executive_actions',filter:'business_id=eq.'+d.businessId},()=>{if(!syncBusy)cloudSync()})
    .on('postgres_changes',{event:'*',schema:'public',table:'executive_action_events',filter:'business_id=eq.'+d.businessId},()=>{if(!syncBusy)cloudSync()})
    .subscribe();
  }
  window.removeEventListener('online',window.__wlActionOnline||(()=>{}));
  window.__wlActionOnline=()=>cloudSync();window.addEventListener('online',window.__wlActionOnline);
 }
 if(!d._skipCloudLoad)cloudSync();
}
window.WhiteLionActionCentre={render,detect};
})();