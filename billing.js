/* White Lion SME — subscription plans, invoices and payment verification UI. */
(() => {
  'use strict';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  const money = (amount, currency) => { try { return new Intl.NumberFormat(currency === 'USD' ? 'en-US' : 'en-SL', { style:'currency', currency, maximumFractionDigits: currency === 'SLE' ? 0 : 2 }).format(Number(amount || 0)); } catch (_) { return (currency === 'USD' ? 'US$' : 'SLE ') + Number(amount || 0).toLocaleString(); } };
  const plansFallback = [
    {code:'starter',name:'Starter',description:'Essential tools for a small business',sle_monthly:250,sle_annual:2500,usd_monthly:10,usd_annual:100,max_users:2,max_branches:1,features:['Sales and POS','Products and basic inventory','Purchases and suppliers','Basic business reports','Offline working']},
    {code:'professional',name:'Professional',description:'More control for a growing business',sle_monthly:600,sle_annual:6000,usd_monthly:25,usd_annual:250,max_users:5,max_branches:1,features:['Everything in Starter','Advanced inventory and purchasing','Finance and performance reports','Customer and supplier management','Offline working and cloud sync']},
    {code:'enterprise',name:'Enterprise',description:'Multi-location operations and advanced controls',sle_monthly:1200,sle_annual:12000,usd_monthly:50,usd_annual:500,max_users:15,max_branches:5,features:['Everything in Professional','Multi-branch operations','Branch stock transfers','Advanced administration','Priority support']}
  ];
  let billingOpen = false;
  let selectedCurrency = 'SLE';
  let selectedCycle = 'monthly';
  let lastWorkspaceId = null;
  const orangeMoneyNumber = '075075818';

  const style = document.createElement('style');
  style.textContent = `
    .wl-billing-hero{padding:23px;border-radius:18px;background:linear-gradient(120deg,#14243d,#203b5c);color:#fff;margin-bottom:18px}
    .wl-billing-hero h1{margin:0 0 7px;font-size:25px}.wl-billing-hero p{margin:0;color:#d6dfeb;max-width:760px;font-size:12px;line-height:1.6}
    .wl-billing-controls{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:16px 0}
    .wl-billing-controls select{border:1px solid #dfe5ee;border-radius:9px;background:#fff;padding:10px 12px;color:#24334a}
    .wl-plan-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;margin:15px 0 20px}
    .wl-plan{background:#fff;border:1px solid #e4e9f0;border-radius:16px;padding:18px;box-shadow:0 8px 22px rgba(18,34,57,.05);display:flex;flex-direction:column;min-width:0}
    .wl-plan.featured{border:2px solid #c9a253;box-shadow:0 12px 30px rgba(201,162,83,.12)}
    .wl-plan h3{margin:0 0 5px;font-size:16px}.wl-plan p{margin:0;color:#758196;font-size:11px;min-height:34px}
    .wl-plan-price{font-size:27px;font-weight:850;letter-spacing:-.7px;margin:14px 0 3px;color:#17243a}
    .wl-plan-price small{font-size:11px;color:#748197;font-weight:600;letter-spacing:0}
    .wl-plan ul{padding-left:17px;margin:13px 0 17px;color:#536177;font-size:11px;line-height:1.8;flex:1}
    .wl-plan .btn{width:100%;margin-top:auto}
    .wl-billing-note{padding:12px 14px;background:#fff8e8;border:1px solid #f0dfb8;border-radius:11px;color:#74571e;font-size:11px;line-height:1.6;margin:12px 0}
    .wl-billing-status{display:inline-block;padding:5px 9px;border-radius:20px;background:#edf3fa;color:#52637a;font-size:10px;font-weight:800;text-transform:uppercase}
    .wl-billing-status.active,.wl-billing-status.paid,.wl-billing-status.verified,.wl-billing-status.trial{background:#e7f6ed;color:#167247}
.wl-billing-status.grace_period{background:#fff3dd;color:#956710}
    .wl-billing-status.pending,.wl-billing-status.pending_payment,.wl-billing-status.awaiting_verification{background:#fff3dd;color:#956710}
    .wl-billing-status.expired,.wl-billing-status.rejected,.wl-billing-status.suspended{background:#fdebed;color:#a53b46}
    .wl-pay-form{display:grid;grid-template-columns:1fr 1.2fr 1fr auto;gap:7px;align-items:end;min-width:520px}
    .wl-pay-form label{display:grid;gap:4px;font-size:10px;color:#657187;font-weight:700}
    .wl-pay-form input,.wl-pay-form select{width:100%;min-width:0;padding:9px;border:1px solid #dfe5ee;border-radius:8px;background:#fff;color:#24334a}
    .wl-billing-metrics{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px;margin:13px 0}
    .wl-billing-metric{background:#f7f9fc;border:1px solid #e8edf4;border-radius:12px;padding:13px}
    .wl-billing-metric small{display:block;color:#718096;font-size:10px}.wl-billing-metric strong{display:block;margin-top:6px;font-size:19px;color:#17243a}
    .wl-review-row{display:flex;gap:12px;justify-content:space-between;align-items:center;padding:12px 0;border-top:1px solid #e9edf3}
    .wl-review-row small{display:block;color:#778397;font-size:10px;margin-top:3px}
    .wl-orange-money{padding:12px 14px;background:#fff8e8;border:1px solid #f0dfb8;border-radius:11px;color:#74571e;font-size:12px;line-height:1.6;margin:10px 0}
    .wl-orange-money strong{color:#49350e}
    @media(max-width:900px){.wl-plan-grid{grid-template-columns:1fr 1fr}.wl-billing-metrics{grid-template-columns:1fr 1fr}}
    @media(max-width:600px){.wl-plan-grid{grid-template-columns:1fr}.wl-billing-hero h1{font-size:21px}.wl-billing-metrics{grid-template-columns:1fr 1fr}.wl-review-row{align-items:flex-start;flex-direction:column}.wl-pay-form{grid-template-columns:1fr;min-width:0}.wl-pay-form button{width:100%}}
  `;
  document.head.appendChild(style);

  function client() { return window.whiteLionCloud?.getClient?.() || null; }
  function business() { return window.whiteLionCloud?.getActiveBusiness?.() || null; }
  function toast(message) { if (typeof window.toast === 'function') window.toast(message); else alert(message); }
  function statusPill(value) {
    const v=String(value||'unknown').toLowerCase();
    return '<span class="wl-billing-status '+esc(v)+'">'+esc(v.replaceAll('_',' '))+'</span>';
  }
  function setActiveNav() {
    document.querySelectorAll('[data-page]').forEach(button => {
      const active=button.dataset.page==='billing';
      button.classList.toggle('active',active);
      if(active)button.setAttribute('aria-current','page');else button.removeAttribute('aria-current');
    });
    const crumb=document.getElementById('crumb'); if(crumb)crumb.textContent='Plans & Billing';
    document.getElementById('sidebar')?.classList.remove('open');
  }
  function renderCataloguePreview(view, message) {
    const currency=selectedCurrency,cycle=selectedCycle;
    view.innerHTML=`
      <div class="wl-billing-hero"><h1>Plans & Billing</h1><p>Compare White Lion SME plans before setting up your business. Choose SLE or USD and monthly or annual pricing.</p></div>
      <div class="panel"><h3>Subscription plans</h3><p class="panel-sub">${esc(message)}</p>
        <div class="wl-billing-controls"><label>Currency <select id="wlBillCurrency"><option value="SLE" ${currency==='SLE'?'selected':''}>SLE · Sierra Leone Leone</option><option value="USD" ${currency==='USD'?'selected':''}>USD · US Dollar</option></select></label><label>Billing period <select id="wlBillCycle"><option value="monthly" ${cycle==='monthly'?'selected':''}>Monthly</option><option value="annual" ${cycle==='annual'?'selected':''}>Annual · 2 months free</option></select></label></div>
        <div class="wl-plan-grid">${plansFallback.map(p=>{
          const amount=currency==='SLE'?(cycle==='annual'?p.sle_annual:p.sle_monthly):(cycle==='annual'?p.usd_annual:p.usd_monthly);
          return `<article class="wl-plan ${p.code==='professional'?'featured':''}"><h3>${esc(p.name)}</h3><p>${esc(p.description)}</p><div class="wl-plan-price">${money(amount,currency)} <small>/ ${cycle==='annual'?'year':'month'}</small></div><div class="panel-sub">${p.max_users} employees · ${p.max_branches} branch(es)</div><ul>${p.features.map(f=>'<li>'+esc(f)+'</li>').join('')}</ul><button class="btn primary" type="button" disabled>Set up business to subscribe</button></article>`;
        }).join('')}</div>
        <div class="wl-billing-note">Eligible accounts receive one free 7-day Professional trial for their first business workspace. Each account can claim the trial only once; additional workspaces require a paid subscription. No payment details are required to start the trial.</div>
        <div class="wl-orange-money"><strong>Pay by Orange Money</strong><br>Send your subscription payment to <strong>${orangeMoneyNumber}</strong>. After paying, keep your transaction ID so you can submit it with your invoice. Payments are manually checked before subscription activation.</div>
      </div>`;
    document.getElementById('wlBillCurrency').onchange=e=>{selectedCurrency=e.target.value;renderCataloguePreview(view,message)};
    document.getElementById('wlBillCycle').onchange=e=>{selectedCycle=e.target.value;renderCataloguePreview(view,message)};
  }
  async function render() {
    const view=document.getElementById('view'); if(!view)return;
    billingOpen=true;setActiveNav();
    const sb=client(), active=business();
    if(!sb) {
      renderCataloguePreview(view,'You are not signed in. Plans are visible for comparison, but you must sign in and create a business workspace before requesting an invoice.');
      return;
    }
    if(!active) {
      renderCataloguePreview(view,'No business workspace is selected yet. You can compare prices now; create or select a business workspace to request an invoice.');
      return;
    }
    view.innerHTML='<div class="panel"><p class="panel-sub">Loading subscription information…</p></div>';
    try {
      const accessResult=await sb.rpc('get_business_subscription_access',{p_business_id:active.id});
      if(accessResult.error)throw accessResult.error;
      const access=accessResult.data||{};
      const [planResult,subResult,invoiceResult]=await Promise.all([
        sb.from('subscription_plans').select('*').eq('is_active',true).order('display_order'),
        sb.from('business_subscriptions').select('*').eq('business_id',active.id).maybeSingle(),
        sb.from('subscription_invoices').select('*').eq('business_id',active.id).order('created_at',{ascending:false}).limit(12)
      ]);
      if(planResult.error)throw planResult.error;
      if(subResult.error)throw subResult.error;
      if(invoiceResult.error)throw invoiceResult.error;
      const plans=planResult.data?.length?planResult.data:plansFallback;
      const sub=subResult.data, invoices=invoiceResult.data||[];
      const currency=selectedCurrency,cycle=selectedCycle;
      const trialEndsAt=sub?.status==='trial'&&sub.trial_ends_at?new Date(sub.trial_ends_at):null;
      const trialDaysLeft=trialEndsAt?Math.max(0,Math.ceil((trialEndsAt.getTime()-Date.now())/86400000)):0;
      const graceEndsAt=sub?.status==='grace_period'&&sub.grace_until?new Date(sub.grace_until):null;
      const periodEndsAt=sub?.current_period_end?new Date(sub.current_period_end):null;
      const accessUntil=trialEndsAt||graceEndsAt||periodEndsAt;
      const accessLabel=sub?.status==='trial'?'Free trial ends':sub?.status==='grace_period'?'Grace period ends':'Access until';
      const daysRemaining=accessUntil?Math.max(0,Math.ceil((accessUntil.getTime()-Date.now())/86400000)):null;
      const accessState=access.allowed===false?'Online access blocked':sub?.status==='grace_period'?'Online access allowed during grace':sub?.status==='trial'?'Free trial access active':sub?.status==='active'?'Paid subscription active':sub?.status==='pending_payment'?'Awaiting payment verification':access.status==='grandfathered'?'Existing workspace access preserved':'Check subscription status';
      view.innerHTML=`
        <div class="wl-billing-hero"><h1>Plans & Billing</h1><p>Manage the White Lion SME subscription for <b>${esc(active.name)}</b>. Select SLE or USD pricing and choose monthly or annual billing. Annual subscriptions are priced at ten monthly payments.</p></div>
        <div class="panel">
          <div class="panel-head"><div><h3>Current subscription</h3><div class="panel-sub">Subscription status and access period for this workspace</div></div>${sub?statusPill(sub.status):statusPill('not subscribed')}</div>
          ${sub?`<div class="report-cards"><div class="report-box"><small>Current plan</small><b>${esc(plans.find(p=>p.code===sub.plan_code)?.name||sub.plan_code)}</b></div><div class="report-box"><small>Billing currency / cycle</small><b>${esc(sub.currency_code)} · ${esc(sub.billing_cycle)}</b></div><div class="report-box"><small>${esc(accessLabel)}</small><b>${accessUntil?accessUntil.toLocaleDateString():'Awaiting activation'}</b></div></div>`:'<p class="panel-sub">No subscription is recorded for this workspace. Eligible accounts receive one 7-day Professional trial for their first business workspace; additional workspaces require a paid subscription.</p>'}
        </div>
        <div class="panel">
          <div class="panel-head"><div><h3>Access and renewal status</h3><div class="panel-sub">Live status returned by the subscription access check</div></div>${statusPill(access.status||sub?.status||'unknown')}</div>
          <div class="report-cards">
            <div class="report-box"><small>Workspace access</small><b>${esc(accessState)}</b></div>
            <div class="report-box"><small>${sub?.status==='trial'?'Free trial ends':sub?.status==='grace_period'?'Grace period ends':'Next renewal / expiry'}</small><b>${accessUntil?accessUntil.toLocaleString():'Not scheduled'}</b></div>
            <div class="report-box"><small>Days remaining</small><b>${daysRemaining===null?'—':daysRemaining+' day(s)'}</b></div>
          </div>
          ${sub?.status==='grace_period'?'<div class="wl-billing-note">Your seven-day renewal grace period is active. Online access remains available until the deadline shown above. Renew before it ends to avoid interruption.</div>':''}
          ${sub?.status==='expired'||access.allowed===false?'<div class="wl-billing-note" style="background:#fdebed;border-color:#f3c9ce;color:#8c303b">Online access is blocked. Your business records are retained. Request a renewal invoice below; access is restored after payment verification.</div>':''}
          ${sub?.status==='trial'?'<div class="wl-billing-note">Your seven-day Professional trial is active. No payment is required during the trial. A seven-day renewal grace period starts automatically after the trial ends.</div>':''}
        </div>
        <div class="panel">
          <div class="panel-head"><div><h3>Choose your plan</h3><div class="panel-sub">Illustrative launch prices — review before public commercial launch.</div></div></div>
          <div class="wl-billing-controls"><label>Currency <select id="wlBillCurrency"><option value="SLE" ${currency==='SLE'?'selected':''}>SLE · Sierra Leone Leone</option><option value="USD" ${currency==='USD'?'selected':''}>USD · US Dollar</option></select></label><label>Billing period <select id="wlBillCycle"><option value="monthly" ${cycle==='monthly'?'selected':''}>Monthly</option><option value="annual" ${cycle==='annual'?'selected':''}>Annual · 2 months free</option></select></label></div>
          <div class="wl-plan-grid">${plans.map(p=>{
            const amount=currency==='SLE'?(cycle==='annual'?p.sle_annual:p.sle_monthly):(cycle==='annual'?p.usd_annual:p.usd_monthly);
            return `<article class="wl-plan ${p.code==='professional'?'featured':''}"><h3>${esc(p.name)}</h3><p>${esc(p.description)}</p><div class="wl-plan-price">${money(amount,currency)} <small>/ ${cycle==='annual'?'year':'month'}</small></div><div class="panel-sub">${Number(p.max_users)} employees · ${Number(p.max_branches)} branch(es)</div><ul>${(Array.isArray(p.features)?p.features:[]).map(f=>'<li>'+esc(f)+'</li>').join('')}</ul><button class="btn ${p.code==='professional'?'gold':'primary'}" data-request-plan="${esc(p.code)}">Request invoice</button></article>`;
          }).join('')}</div>
          <div class="wl-billing-note">${sub?.status==='trial'?'You are using the free Professional trial. '+trialDaysLeft+' day(s) remain. No payment is required during the trial.':sub?.status==='grace_period'?'You are in the seven-day renewal grace period. '+(daysRemaining??0)+' day(s) remain.':'A plan request creates an invoice only. Paid access is activated after White Lion verifies the payment. Payment screenshots or references do not automatically activate subscriptions.'}</div>
        </div>
        <div class="panel"><div class="panel-head"><div><h3>Invoices and payment records</h3><div class="panel-sub">Your workspace's subscription invoices and submitted payment references</div></div></div>
          ${invoices.length?invoices.map(inv=>`<div class="panel" style="box-shadow:none;border:1px solid #e9edf3;margin:10px 0;padding:14px"><div class="panel-head"><div><b>${esc(inv.invoice_number)}</b><div class="panel-sub">${esc(inv.plan_code)} · ${esc(inv.billing_cycle)} · due ${new Date(inv.due_at).toLocaleDateString()}</div></div><div style="text-align:right"><b>${money(inv.amount_due,inv.currency_code)}</b><div>${statusPill(inv.status)}</div></div></div>${['pending','awaiting_verification'].includes(inv.status)?`<div class="wl-orange-money"><strong>Orange Money payment instructions</strong><br>1. Send <strong>${money(inv.amount_due,inv.currency_code)}</strong> to <strong>${orangeMoneyNumber}</strong> using Orange Money.<br>2. Enter the transaction reference and exact amount below.<br>3. Submit the reference. White Lion will verify it manually before activating your subscription.</div><form class="wl-pay-form" data-pay-invoice="${esc(inv.id)}"><label>Payment method<select name="provider" required><option value="Orange Money">Orange Money · 075075818</option><option>Afrimoney</option><option>Bank transfer</option><option>Cash / manual</option></select></label><label>Transaction reference<input name="reference" required minlength="3" placeholder="Enter Orange Money transaction ID"></label><label>Exact amount<input name="amount" required type="number" min="0.01" step="0.01" value="${esc(inv.amount_due)}"></label><button class="btn primary" type="submit">Submit reference</button></form>`:'<div class="panel-sub">No payment action is required for this invoice.</div>'}</div>`).join(''):'<div class="empty">No subscription invoices have been created for this business.</div>'}
        </div>
        <div id="wlBillingDeveloper"></div>`;
      document.getElementById('wlBillCurrency').onchange=e=>{selectedCurrency=e.target.value;render()};
      document.getElementById('wlBillCycle').onchange=e=>{selectedCycle=e.target.value;render()};
      view.querySelectorAll('[data-request-plan]').forEach(button=>button.onclick=()=>requestPlan(button.dataset.requestPlan,active.id));
      view.querySelectorAll('[data-pay-invoice]').forEach(form=>form.onsubmit=async e=>{
        e.preventDefault();const data=Object.fromEntries(new FormData(form).entries());
        const amount=Number(data.amount);
        if(!Number.isFinite(amount)||amount<=0){toast('Enter a valid payment amount.');return}
        const {error}=await sb.rpc('submit_subscription_payment',{p_invoice_id:form.dataset.payInvoice,p_provider:data.provider,p_payment_reference:data.reference,p_amount:amount});
        if(error){toast('Payment reference not submitted: '+error.message);return}
        toast('Payment reference submitted for verification. Your plan is not activated yet.');render();
      });
      await renderDeveloperOverview(sb);
    } catch(error) {
      renderCataloguePreview(view,'The plan catalogue is available. Sign in and select a business workspace to use subscription and invoice actions.');
      const notice=document.createElement('div');
      notice.className='wl-billing-note';
      notice.textContent='Workspace billing details could not be loaded: '+(error.message||String(error))+'. You can still compare the plans above.';
      view.appendChild(notice);
    }
  }
  async function requestPlan(code,businessId) {
    const sb=client();if(!sb)return;
    const button=document.querySelector('[data-request-plan="'+CSS.escape(code)+'"]');
    if(button){button.disabled=true;button.textContent='Creating invoice…'}
    const {data,error}=await sb.rpc('request_business_subscription',{
      p_business_id:businessId,p_plan_code:code,p_currency_code:selectedCurrency,p_billing_cycle:selectedCycle
    });
    if(error){toast('Could not create invoice: '+error.message);if(button){button.disabled=false;button.textContent='Request invoice'}return}
    toast('Invoice '+(data?.invoice_number||'created')+'. Submit the payment reference below.');await render();
  }
  async function renderDeveloperOverview(sb) {
    const host=document.getElementById('wlBillingDeveloper');if(!host)return;
    const {data,error}=await sb.rpc('get_platform_billing_overview');
    if(error)return;
    const d=data||{};
    host.innerHTML=`<div class="panel"><div class="panel-head"><div><h3>White Lion developer billing console</h3><div class="panel-sub">Platform-wide subscription and payment monitoring</div></div><span class="wl-billing-status active">Developer</span></div>
      <div class="wl-billing-metrics"><div class="wl-billing-metric"><small>Active subscriptions</small><strong>${Number(d.active_subscriptions||0)}</strong></div><div class="wl-billing-metric"><small>Pending payments</small><strong>${Number(d.pending_payments||0)}</strong></div><div class="wl-billing-metric"><small>Pending invoices</small><strong>${Number(d.pending_invoices||0)}</strong></div><div class="wl-billing-metric"><small>Verified SLE revenue</small><strong>${money(d.paid_sle,'SLE')}</strong></div><div class="wl-billing-metric"><small>Verified USD revenue</small><strong>${money(d.paid_usd,'USD')}</strong></div></div>
      <h3 style="margin:15px 0 5px">Pending payment verification</h3>
      ${(d.pending||[]).length?(d.pending||[]).map(p=>`<div class="wl-review-row"><div><b>${esc(p.business_name)}</b><small>${esc(p.invoice_number)} · ${esc(p.plan_code)} · ${esc(p.provider)} · Ref: ${esc(p.reference)}</small><small>${money(p.amount,p.currency_code)} · submitted ${new Date(p.submitted_at).toLocaleString()}</small></div><div><button class="btn primary small" data-review-payment="${esc(p.payment_id)}" data-approve="true">Verify & activate</button> <button class="btn danger small" data-review-payment="${esc(p.payment_id)}" data-approve="false">Reject</button></div></div>`).join(''):'<div class="empty">No payment references are awaiting verification.</div>'}
      <p class="panel-sub">Revenue totals include only payments marked verified. Payment-provider APIs are not connected in this release; verification is manual.</p>
    </div>`;
    host.querySelectorAll('[data-review-payment]').forEach(button=>button.onclick=async()=>{
      const approve=button.dataset.approve==='true';
      const notes=prompt(approve?'Optional verification note:':'Reason for rejecting this payment:','') ;
      if(notes===null)return;
      const {data:result,error:reviewError}=await sb.rpc('review_subscription_payment',{
        p_payment_id:button.dataset.reviewPayment,p_approve:approve,p_notes:notes
      });
      if(reviewError){toast('Review failed: '+reviewError.message);return}
      toast(approve?'Payment verified and subscription activated.':'Payment rejected.');await render();
    });
  }

  document.addEventListener('click',event=>{
    const target=event.target.closest('[data-page]');
    if(target&&target.dataset.page!=='billing'&&billingOpen)billingOpen=false;
  });
  window.addEventListener('whiteLionWorkspaceChanged',event=>{
    const id=event.detail?.business?.id;
    if(id!==lastWorkspaceId){lastWorkspaceId=id;if(billingOpen)render();}
  });
  window.addEventListener('whiteLionCloudReady',()=>{if(billingOpen)render()});
  window.whiteLionBilling={render};
  document.addEventListener('DOMContentLoaded',()=>{
    const nav=document.querySelector('.sidebar .nav-label:last-of-type');
    const adminNav=Array.from(document.querySelectorAll('.sidebar nav.nav')).at(-1);
    if(adminNav&&!adminNav.querySelector('[data-page="billing"]')){
      const button=document.createElement('button');button.type='button';button.dataset.page='billing';
      button.innerHTML='<span class="ico">＄</span>Plans & Billing';adminNav.appendChild(button);
    }
  });
})();
