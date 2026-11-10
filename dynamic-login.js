/* White Lion SME OS — interactive sign-in experience. No auth logic is changed. */
(function(){
 'use strict';
 function init(){
  var shell=document.getElementById('wlCloudBox');
  if(!shell||shell.dataset.wlDynamicReady)return;
  shell.dataset.wlDynamicReady='1';
  shell.insertAdjacentHTML('afterbegin','<canvas class="wl-dynamic-canvas" aria-hidden="true"></canvas><div class="wl-dynamic-grid" aria-hidden="true"></div>');
  var heading=shell.querySelector('.wl-auth-story h1 em');
  if(heading){
   var phrases=['with confidence.','with clarity.','with control.','with insight.'],index=0;
   heading.classList.add('wl-word-cycle');
   if(!window.matchMedia('(prefers-reduced-motion: reduce)').matches){
    window.setInterval(function(){
     heading.classList.add('wl-word-out');
     window.setTimeout(function(){index=(index+1)%phrases.length;heading.textContent=phrases[index];heading.classList.remove('wl-word-out')},260);
    },3200);
   }
  }
  var password=document.getElementById('wlCloudPassword');
  if(password&&!document.getElementById('wlPasswordReveal')){
   var toggle=document.createElement('button');
   toggle.type='button';toggle.id='wlPasswordReveal';toggle.className='wl-password-reveal';
   toggle.setAttribute('aria-label','Show password');toggle.textContent='Show';
   password.insertAdjacentElement('afterend',toggle);
   toggle.addEventListener('click',function(){
    var show=password.type==='password';password.type=show?'text':'password';
    toggle.textContent=show?'Hide':'Show';toggle.setAttribute('aria-label',show?'Hide password':'Show password');
   });
  }
  var canvas=shell.querySelector('.wl-dynamic-canvas'),ctx=canvas&&canvas.getContext('2d');
  var reduced=window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if(!ctx||reduced)return;
  var points=[],width=0,height=0,raf=0;
  function resize(){
   var rect=shell.getBoundingClientRect(),dpr=Math.min(window.devicePixelRatio||1,1.5);
   width=rect.width;height=rect.height;canvas.width=Math.round(width*dpr);canvas.height=Math.round(height*dpr);
   canvas.style.width=width+'px';canvas.style.height=height+'px';ctx.setTransform(dpr,0,0,dpr,0,0);
   var count=Math.min(34,Math.max(16,Math.floor(width/30)));
   points=Array.from({length:count},function(){return{x:Math.random()*width,y:Math.random()*height,vx:(Math.random()-.5)*.28,vy:(Math.random()-.5)*.28,r:1+Math.random()*1.5}});
  }
  function draw(){
   ctx.clearRect(0,0,width,height);
   for(var i=0;i<points.length;i++){
    var p=points[i];p.x+=p.vx;p.y+=p.vy;
    if(p.x<0||p.x>width)p.vx*=-1;if(p.y<0||p.y>height)p.vy*=-1;
    ctx.beginPath();ctx.arc(p.x,p.y,p.r,0,Math.PI*2);ctx.fillStyle='rgba(175,235,190,.72)';ctx.fill();
    for(var j=i+1;j<points.length;j++){
     var q=points[j],dx=p.x-q.x,dy=p.y-q.y,dist=Math.sqrt(dx*dx+dy*dy);
     if(dist<115){ctx.beginPath();ctx.moveTo(p.x,p.y);ctx.lineTo(q.x,q.y);ctx.strokeStyle='rgba(32,168,93,'+(0.13*(1-dist/115))+')';ctx.lineWidth=.7;ctx.stroke()}
    }
   }
   raf=requestAnimationFrame(draw);
  }
  resize();draw();
  if('ResizeObserver'in window){new ResizeObserver(resize).observe(shell)}else window.addEventListener('resize',resize);
  document.addEventListener('visibilitychange',function(){if(document.hidden){cancelAnimationFrame(raf);raf=0}else if(!raf)draw()});
  var card=shell.querySelector('.wl-auth-card');
  if(card&&window.matchMedia('(hover:hover) and (pointer:fine)').matches){
   shell.addEventListener('pointermove',function(e){
    var r=card.getBoundingClientRect(),x=(e.clientX-r.left)/r.width-.5,y=(e.clientY-r.top)/r.height-.5;
    card.style.setProperty('--wl-tilt-x',(-y*2.2)+'deg');card.style.setProperty('--wl-tilt-y',(x*2.2)+'deg');
   });
   shell.addEventListener('pointerleave',function(){card.style.setProperty('--wl-tilt-x','0deg');card.style.setProperty('--wl-tilt-y','0deg')});
  }
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
