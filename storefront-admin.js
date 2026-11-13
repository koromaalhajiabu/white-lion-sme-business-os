/* White Lion SME — Online Storefront and Order Desk */
(() => {
  'use strict';
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money = (v) => new Intl.NumberFormat('en-US',{style:'currency',currency:'SLE',maximumFractionDigits:2}).format(Number(v||0));
  const cloud = () => window.whiteLionCloud || {};
  const client = () => cloud().getClient && cloud().getClient();
  const business = () => cloud().getActiveBusiness && cloud().getActiveBusiness();
  const branches = () => cloud().getBranches ? cloud().getBranches() : [];
  let currentTab = 'orders';
  let currentStore = null;
  let products = [];
  let storeProducts = [];
  let orders = [];

  function notify(message) {
    const toast = document.getElementById('toast');
    if (toast) { toast.textContent = message; toast.classList.add('show'); setTimeout(() => toast.classList.remove('show'), 3200); }
    else alert(message);
  }
  function setActiveNav() {
    document.querySelectorAll('[data-page]').forEach((b) => b.classList.toggle('active', b.dataset.page === 'storefront'));
    const link = document.getElementById('storefrontNavLink');
    if (link) link.classList.add('active');
    const crumb = document.getElementById('crumb');
    if (crumb) crumb.textContent = 'Online Store';
    document.getElementById('sidebar')?.classList.remove('open');
  }
  function openPage() {
    if (typeof state !== 'undefined') state.page = 'storefront';
    setActiveNav();
    render();
  }
  async function loadData() {
    const sb = client(), biz = business();
    if (!sb || !biz?.id) throw new Error('Sign in and select an active business workspace first.');
    const [storeResult, productResult, listingResult, orderResult] = await Promise.all([
      sb.from('online_storefronts').select('*').eq('business_id', biz.id).maybeSingle(),
      sb.from('products').select('id,name,sku,selling_price,is_active').eq('business_id', biz.id).eq('is_active', true).order('name'),
      sb.from('online_store_products').select('product_id,is_published,online_price,description').eq('business_id', biz.id),
      sb.from('online_store_orders').select('*').eq('business_id', biz.id).order('created_at',{ascending:false}).limit(100)
    ]);
    if (storeResult.error) throw storeResult.error;
    if (productResult.error) throw productResult.error;
    if (listingResult.error) throw listingResult.error;
    if (orderResult.error) throw orderResult.error;
    currentStore = storeResult.data || null;
    products = productResult.data || [];
    storeProducts = listingResult.data || [];
    orders = orderResult.data || [];
  }
  function tabButton(key,label) {
    return '<button class="btn '+(currentTab===key?'primary':'')+'" type="button" data-store-tab="'+key+'">'+label+'</button>';
  }
  function shell(body) {
    const biz = business();
    return '<div class="welcome"><div><div class="eyebrow">Commerce channel</div><h1>Online Store</h1><p>Publish products, receive customer orders and manage fulfilment from this business workspace.</p></div><button class="btn" id="storeRefresh" type="button">↻ Refresh</button></div>'+
      '<div class="notice">Customer orders are created through the secure Supabase order functions. Stock is checked and deducted only when staff fulfil an order from a selected branch.</div>'+
      '<div class="toolbar" style="margin-bottom:16px">'+tabButton('orders','Customer orders')+tabButton('catalogue','Store catalogue')+tabButton('settings','Store settings')+'</div>'+
      '<div id="storeTabContent">'+body+'</div>';
  }
  function renderSettings() {
    const s = currentStore || {};
    const publicUrl = s.slug ? new URL('storefront.html?store='+encodeURIComponent(s.slug), location.href).href : '';
    return '<div class="panel"><div class="panel-head"><div><h3>Store identity and publishing</h3><div class="panel-sub">Set the public address customers will use to browse and place orders.</div></div><span class="pill '+(s.is_published?'':'warn')+'">'+(s.is_published?'Published':'Not published')+'</span></div>'+
      '<form id="storeSettingsForm"><div class="form-grid">'+
      '<div class="field"><label>Store display name</label><input name="display_name" required maxlength="100" value="'+esc(s.display_name || bizName())+'"></div>'+
      '<div class="field"><label>Store web address (slug)</label><input name="slug" required pattern="[a-z0-9][a-z0-9-]{2,59}" maxlength="60" placeholder="e.g. my-business" value="'+esc(s.slug||'')+'"><small>Use lowercase letters, numbers and hyphens. At least 3 characters.</small></div>'+
      '<div class="field full"><label>Store description</label><textarea name="description" rows="3">'+esc(s.description||'')+'</textarea></div>'+
      '<div class="field"><label>Customer contact phone</label><input name="contact_phone" value="'+esc(s.contact_phone||'')+'"></div>'+
      '<div class="field"><label>Customer contact email</label><input name="contact_email" type="email" value="'+esc(s.contact_email||'')+'"></div>'+
      '<div class="field"><label><input style="width:auto;min-height:0" type="checkbox" name="is_published" '+(s.is_published?'checked':'')+'> Publish storefront</label></div>'+
      '<div class="field"><label><input style="width:auto;min-height:0" type="checkbox" name="accepts_orders" '+(s.accepts_orders?'checked':'')+'> Accept customer orders</label></div>'+
      '</div><div class="modal-actions"><button class="btn primary" type="submit">Save store settings</button></div></form>'+
      (publicUrl?'<div class="notice" style="margin-top:15px"><b>Public storefront link</b><br><a href="'+esc(publicUrl)+'" target="_blank" rel="noopener">'+esc(publicUrl)+'</a><br><div class="toolbar" style="margin-top:9px"><button class="btn small" type="button" id="copyStoreLink">Copy link</button><button class="btn small" type="button" id="shareStoreWhatsApp">WhatsApp</button><button class="btn small" type="button" id="shareStoreFacebook">Facebook</button><button class="btn small" type="button" id="shareStoreSMS">SMS</button><button class="btn small" type="button" id="shareStoreEmail">Email</button><button class="btn small" type="button" id="shareStoreNative">More sharing options</button></div><small>Share this address with customers through WhatsApp, Facebook, SMS, email or your phone sharing menu.</small></div>':'')+
      '</div>';
  }
  function bizName() { return business()?.name || 'My Business'; }
  function renderCatalogue() {
    const mapped = new Map(storeProducts.map(x=>[String(x.product_id),x]));
    const rows = products.map(p=>{
      const entry = mapped.get(String(p.id)) || {};
      const onlinePrice = entry.online_price == null ? p.selling_price : entry.online_price;
      return '<tr><td><b>'+esc(p.name)+'</b><br><small>'+esc(p.sku||'')+'</small></td><td>'+money(p.selling_price)+'</td><td><input aria-label="Online price for '+esc(p.name)+'" type="number" min="0" step="0.01" style="width:115px" data-online-price="'+esc(p.id)+'" value="'+esc(onlinePrice==null?'':onlinePrice)+'"></td><td><label><input type="checkbox" data-publish-product="'+esc(p.id)+'" '+(entry.is_published?'checked':'')+'> Show online</label></td><td><button class="btn small" type="button" data-save-product="'+esc(p.id)+'">Save</button></td></tr>';
    }).join('');
    return '<div class="panel"><div class="panel-head"><div><h3>Products available to customers</h3><div class="panel-sub">Choose which active business products appear in your public store and set their online prices.</div></div><span class="pill">'+products.length+' products</span></div>'+
      (products.length?'<div class="table-wrap"><table><thead><tr><th>Product</th><th>Business price</th><th>Online price</th><th>Published</th><th>Action</th></tr></thead><tbody>'+rows+'</tbody></table></div>':'<div class="empty">No active products found. Add products to your business catalogue first.</div>')+
      '</div>';
  }
  function statusPill(status) {
    const warning = ['pending','cancelled','failed'].includes(String(status));
    return '<span class="pill '+(warning?'warn':'')+'">'+esc(String(status||'').replaceAll('_',' '))+'</span>';
  }
  function renderOrders() {
    const branchList = branches();
    const rows = orders.map(o=>{
      const next = o.order_status==='pending' ? '<button class="btn small primary" data-order-status="'+esc(o.id)+'" data-next="confirmed">Confirm</button>' :
        o.order_status==='confirmed' ? '<button class="btn small" data-order-status="'+esc(o.id)+'" data-next="processing">Processing</button><button class="btn small" data-order-status="'+esc(o.id)+'" data-next="ready">Ready</button>' :
        o.order_status==='processing' ? '<button class="btn small" data-order-status="'+esc(o.id)+'" data-next="ready">Ready</button>' : '';
      const fulfil = ['confirmed','processing','ready'].includes(o.order_status) && !o.fulfilled_sale_id ?
        '<div class="field" style="min-width:155px"><select data-branch-for="'+esc(o.id)+'"><option value="">Choose branch…</option>'+branchList.map(b=>'<option value="'+esc(b.id)+'">'+esc(b.name)+'</option>').join('')+'</select><button class="btn small primary" type="button" data-fulfil-order="'+esc(o.id)+'">Fulfil order</button></div>' : '';
      return '<tr><td><b>'+esc(o.order_number)+'</b><br><small>'+new Date(o.created_at).toLocaleString()+'</small></td><td>'+esc(o.customer_name)+'<br><small>'+esc(o.customer_phone||'')+'</small></td><td>'+money(o.total_amount)+'</td><td>'+statusPill(o.order_status)+'<br>'+statusPill(o.payment_status)+'</td><td>'+next+' '+fulfil+(o.fulfilled_sale_id?'<small>Sale recorded: '+esc(o.fulfilled_sale_id)+'</small>':'')+'</td></tr>';
    }).join('');
    return '<div class="stats"><div class="stat"><div class="stat-head">All orders</div><strong>'+orders.length+'</strong></div><div class="stat"><div class="stat-head">Awaiting confirmation</div><strong>'+orders.filter(o=>o.order_status==='pending').length+'</strong></div><div class="stat"><div class="stat-head">Ready to fulfil</div><strong>'+orders.filter(o=>['confirmed','processing','ready'].includes(o.order_status)&&!o.fulfilled_sale_id).length+'</strong></div><div class="stat"><div class="stat-head">Fulfilled</div><strong>'+orders.filter(o=>!!o.fulfilled_sale_id).length+'</strong></div></div>'+
      '<div class="panel"><div class="panel-head"><div><h3>Customer orders</h3><div class="panel-sub">Review incoming orders, update progress and fulfil against a branch.</div></div><button class="btn small" type="button" id="refreshOrders">Refresh orders</button></div>'+
      (orders.length?'<div class="table-wrap"><table><thead><tr><th>Order</th><th>Customer</th><th>Total</th><th>Status / payment</th><th>Actions</th></tr></thead><tbody>'+rows+'</tbody></table></div>':'<div class="empty">No online orders have arrived yet. Publish your store and share its link with customers.</div>')+
      '</div>';
  }
  async function render() {
    const view = document.getElementById('view');
    if (!view) return;
    view.innerHTML = '<div class="panel"><h3>Loading Online Store…</h3><p class="panel-sub">Connecting to your active business workspace.</p></div>';
    try {
      await loadData();
      const body = currentTab==='settings' ? renderSettings() : currentTab==='catalogue' ? renderCatalogue() : renderOrders();
      view.innerHTML = shell(body);
      bind();
    } catch (e) {
      view.innerHTML = '<div class="panel"><h2>Online Store could not load</h2><p class="panel-sub">'+esc(e.message||e)+'</p><p class="panel-sub">Check that you are signed in and your account has an active business role. Store settings require owner, admin or manager access; order management also supports cashiers.</p><button class="btn primary" id="storeRetry" type="button">Try again</button></div>';
      document.getElementById('storeRetry')?.addEventListener('click',render);
    }
  }
  function bind() {
    document.querySelectorAll('[data-store-tab]').forEach(b=>b.addEventListener('click',()=>{currentTab=b.dataset.storeTab;render()}));
    document.getElementById('storeRefresh')?.addEventListener('click',render);
    document.getElementById('refreshOrders')?.addEventListener('click',render);
    document.getElementById('storeSettingsForm')?.addEventListener('submit',async e=>{
      e.preventDefault();
      const form=e.currentTarget, fd=new FormData(form), biz=business();
      const slug=String(fd.get('slug')||'').trim().toLowerCase();
      if(!/^[a-z0-9][a-z0-9-]{2,59}$/.test(slug)){notify('Use a valid store slug: 3–60 lowercase letters, numbers or hyphens.');return}
      const payload={business_id:biz.id,slug,display_name:String(fd.get('display_name')||'').trim(),description:String(fd.get('description')||'').trim()||null,contact_phone:String(fd.get('contact_phone')||'').trim()||null,contact_email:String(fd.get('contact_email')||'').trim()||null,is_published:fd.get('is_published')==='on',accepts_orders:fd.get('accepts_orders')==='on',updated_at:new Date().toISOString()};
      const {error}=await client().from('online_storefronts').upsert(payload,{onConflict:'business_id'});
      if(error){notify(error.message);return}
      notify('Store settings saved.');
      await render();
    });
    const storeShareUrl=()=>new URL('storefront.html?store='+encodeURIComponent(currentStore.slug),location.href).href;
    const storeShareText=()=> 'Shop online at '+(currentStore.display_name||bizName())+': '+storeShareUrl();
    document.getElementById('shareStoreWhatsApp')?.addEventListener('click',()=>window.open('https://wa.me/?text='+encodeURIComponent(storeShareText()),'_blank','noopener'));
    document.getElementById('shareStoreFacebook')?.addEventListener('click',()=>window.open('https://www.facebook.com/sharer/sharer.php?u='+encodeURIComponent(storeShareUrl()),'_blank','noopener'));
    document.getElementById('shareStoreSMS')?.addEventListener('click',()=>location.href='sms:?body='+encodeURIComponent(storeShareText()));
    document.getElementById('shareStoreEmail')?.addEventListener('click',()=>location.href='mailto:?subject='+encodeURIComponent('Shop online at '+(currentStore.display_name||bizName()))+'&body='+encodeURIComponent(storeShareText()));
    document.getElementById('shareStoreNative')?.addEventListener('click',async()=>{const data={title:currentStore.display_name||bizName(),text:storeShareText(),url:storeShareUrl()};if(navigator.share){try{await navigator.share(data)}catch(e){}}else{try{await navigator.clipboard.writeText(storeShareText());notify('Store link copied.')}}});
    document.getElementById('copyStoreLink')?.addEventListener('click',async()=>{
      const url=storeShareUrl();
      try{await navigator.clipboard.writeText(url);notify('Storefront link copied.')}catch(e){notify(url)}
    });
    document.querySelectorAll('[data-save-product]').forEach(b=>b.addEventListener('click',async()=>{
      const id=b.dataset.saveProduct, price=document.querySelector('[data-online-price="'+id+'"]')?.value, published=document.querySelector('[data-publish-product="'+id+'"]')?.checked;
      if(price!==''&&(!Number.isFinite(Number(price))||Number(price)<0)){notify('Enter a valid online price.');return}
      const {error}=await client().from('online_store_products').upsert({business_id:business().id,product_id:id,is_published:!!published,online_price:price===''?null:Number(price)},{onConflict:'business_id,product_id'});
      if(error){notify(error.message);return}
      notify('Product online settings saved.');
      await render();
    }));
    document.querySelectorAll('[data-order-status]').forEach(b=>b.addEventListener('click',async()=>{
      b.disabled=true;
      const {data,error}=await client().rpc('update_online_store_order_status',{p_order_id:b.dataset.orderStatus,p_new_status:b.dataset.next,p_internal_notes:null});
      if(error){notify(error.message);b.disabled=false;return}
      notify('Order updated: '+b.dataset.next);
      await render();
    }));
    document.querySelectorAll('[data-fulfil-order]').forEach(b=>b.addEventListener('click',async()=>{
      const id=b.dataset.fulfilOrder, branchId=document.querySelector('[data-branch-for="'+id+'"]')?.value;
      if(!branchId){notify('Select the branch that will fulfil this order.');return}
      if(!confirm('Fulfil this order from the selected branch? This will deduct stock and create a business sale.'))return;
      b.disabled=true;
      const {data,error}=await client().rpc('fulfil_online_store_order',{p_order_id:id,p_branch_id:branchId});
      if(error){notify(error.message);b.disabled=false;return}
      notify(data?.status==='already_fulfilled'?'This order was already fulfilled.':'Order fulfilled and sale recorded.');
      await render();
    }));
  }
  window.whiteLionStorefront = {open:openPage,render};
  function attachStorefrontNavigation(){
    const nav=document.getElementById('nav');
    if(!nav)return;
    let button=document.getElementById('storefrontNavLink');
    if(!button){
      button=document.createElement('button');
      button.id='storefrontNavLink';button.type='button';button.innerHTML='<span class="ico">🛍</span>Online Store';
      nav.appendChild(button);
    }
    if(button.dataset.storefrontBound!=='yes'){
      button.dataset.storefrontBound='yes';
      button.addEventListener('click',openPage);
    }
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',attachStorefrontNavigation);
  else attachStorefrontNavigation();
  window.addEventListener('whiteLionCloudReady',()=>{if(typeof state!=='undefined'&&state.page==='storefront')render()});
  window.addEventListener('whiteLionWorkspaceChanged',()=>{if(typeof state!=='undefined'&&state.page==='storefront')render()});
})();