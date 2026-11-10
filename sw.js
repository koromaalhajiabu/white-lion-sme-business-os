/* White Lion SME OS — network-first application updates with offline fallback. */
const CACHE_NAME='white-lion-sme-v118';
const APP_SHELL=[
  './',
  './index.html',
  './manifest.webmanifest?v=46',
  './shared.js?v=2',
  './i18n.js?v=11',
  './cloud.js?v=42',
  './operations.js?v=22',
  './documents.js?v=3',
  './icons/white-lion-icon.svg',
  './icons/white-lion-192.png',
  './icons/white-lion-512.png',
  './league.js?v=2',
  './billing.js?v=9',
  './executive-intelligence.js?v=1',
  './action-centre.js?v=3',
  './public-leagues.html'
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await Promise.all(APP_SHELL.map(async path => {
      try {
        const response = await fetch(path, {cache:'reload'});
        if (response && response.ok) await cache.put(path, response);
      } catch (_) {}
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter(key => key.startsWith('white-lion-sme-') && key !== CACHE_NAME)
      .map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  const path = url.pathname.toLowerCase();
  const isAppCode = request.mode === 'navigate' ||
    /\.(html|js|css|webmanifest)$/.test(path);

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    if (isAppCode) {
      // Always try the deployed version first. Use the cached copy only offline.
      try {
        const fresh = await fetch(request, {cache:'no-store'});
        if (fresh && fresh.ok) {
          await cache.put(request, fresh.clone());
          return fresh;
        }
        if (fresh) return fresh;
      } catch (_) {}
      const cached = await cache.match(request) ||
        (request.mode === 'navigate' ? await cache.match('./index.html') : null);
      return cached || Response.error();
    }

    // Static media can be served from cache immediately.
    const cached = await cache.match(request);
    if (cached) return cached;
    try {
      const fresh = await fetch(request);
      if (fresh && fresh.ok) await cache.put(request, fresh.clone());
      return fresh;
    } catch (_) {
      return Response.error();
    }
  })());
});
