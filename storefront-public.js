(() => {
'use strict';
const SUPABASE_URL='https://nclncqlgnxnijlumznnt.supabase.co';
const SUPABASE_KEY='sb_publishable_iPIsAysPnlvPCAoqntoNRg_dKcSZxKX';
const $=id=>document.getElementById(id);
const esc=v=>String(v==null?'':v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=v=>new Intl.NumberFormat('en-US',{style:'currency',currency:'SLE',maximumFractionDigits:2}).format(Number(v||0));
let sb,store,items=[],cart=new Map();
function message(text,kind){$('message').className=kind||'';$('message').textContent=text}
function drawCart(){
 const entries=Array.from(cart.values());
 $('cart').innerHTML=entries.length?entries.map(x=>'<div class="cart-row"><div><b>'+esc(x.name)+'</b><div class="muted">'+money(x.price)+' each</div><div class="qty"><button type="button" data-minus="'+esc(x.id)+'">−</button><span>'+x.quantity+'</span><button type="button" data-plus="'+esc(x.id)+'">+</button></div></div><b>'+money(x.price*x.quantity)+'</b></div>').join(''):'<p class="muted">Your basket is empty.</p>';
 $('cartTotal').textContent=money(entries.reduce((n,x)=>n+x.price*x.quantity,0));
 document.querySelectorAll('[data-minus]').forEach(b=>b.onclick=()=>changeQty(b.dataset.minus,-1));
 document.querySelectorAll('[data-plus]').forEach(b=>b.onclick=()=>changeQty(b.dataset.plus,1));
}
function changeQty(id,delta){const x=cart.get(id);if(!x)return;x.quantity+=delta;if(x.quantity<=0)cart.delete(id);drawCart()}
function drawProducts(){
 $('products').innerHTML=items.length?items.map(p=>{
  const stock=Number(p.stock_available||0),existing=cart.get(p.product_id);
  return '<article class="product"><div class="sku">'+esc(p.sku||p.category||'PRODUCT')+'</div><h3>'+esc(p.name)+'</h3><div class="muted">'+esc(p.description||'')+'</div><div class="price">'+money(p.price)+'</div><div class="muted">'+(stock>0?'Available: '+stock+' '+esc(p.unit||'units'):'Currently out of stock')+'</div><button class="primary" type="button" data-add="'+esc(p.product_id)+'" '+(stock<=0?'disabled':'')+'>Add to basket</button></article>';
 }).join(''):'<p class="muted">No products are currently published in this store.</p>';
 document.querySelectorAll('[data-add]').forEach(b=>b.onclick=()=>{
  const p=items.find(x=>x.product_id===b.dataset.add);if(!p)return;
  const entry=cart.get(p.product_id)||{id:p.product_id,name:p.name,price:Number(p.price),quantity:0,max:Number(p.stock_available||0)};
  if(entry.quantity+1>entry.max){message('The displayed stock limit has been reached. Contact the business for availability.','error');return}
  entry.quantity++;cart.set(p.product_id,entry);drawCart();message('');
 });
}
async function start(){
 try{
  if(!window.supabase?.createClient)throw new Error('The storefront service could not load. Refresh this page.');
  sb=window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
  const slug=new URLSearchParams(location.search).get('store');
  if(!slug)throw new Error('This storefront link is incomplete. Ask the business for its store link.');
  const {data,error}=await sb.rpc('get_public_storefront',{p_slug:slug});
  if(error)throw error;
  if(!data||data.status!=='success')throw new Error(data?.message||'This storefront is unavailable.');
  store=data.storefront;items=data.products||[];
  document.title=store.display_name+' | Online Store';
  $('storeName').textContent=store.display_name;
  $('storeDescription').textContent=store.description||'Browse products and place an order with this business.';
  if(store.contact_phone||store.contact_email){
   const contact=document.createElement('p');contact.className='muted';contact.textContent=[store.contact_phone,store.contact_email].filter(Boolean).join(' · ');$('storeDescription').after(contact);
  }
  if(!store.accepts_orders){message('This store is currently not accepting online orders.','error');$('checkout').hidden=true}
  drawProducts();drawCart();
 }catch(e){message(e.message||String(e),'error');$('products').innerHTML='<p class="muted">Storefront could not be loaded.</p>';$('checkout').hidden=true}
}
$('checkout').addEventListener('submit',async e=>{
 e.preventDefault();
 if(!store||!store.accepts_orders){message('This store is not accepting orders.','error');return}
 const basket=Array.from(cart.values()).map(x=>({product_id:x.id,quantity:x.quantity}));
 if(!basket.length){message('Add at least one product to your basket.','error');return}
 const fd=new FormData(e.currentTarget),button=$('submitOrder');button.disabled=true;button.textContent='Submitting…';
 try{
  const {data,error}=await sb.rpc('submit_public_store_order',{
   p_slug:store.slug,
   p_customer_name:fd.get('customer_name'),
   p_customer_phone:fd.get('customer_phone'),
   p_delivery_address:fd.get('delivery_address'),
   p_items:basket,
   p_customer_email:fd.get('customer_email')||null,
   p_customer_notes:fd.get('customer_notes')||null
  });
  if(error)throw error;
  cart.clear();drawCart();e.currentTarget.reset();
  message('Order received. Your order number is '+data.order_number+'. The business will contact you to confirm the next steps.','success');
 }catch(err){message(err.message||String(err),'error')}
 finally{button.disabled=false;button.textContent='Place order'}
});
start();
})();