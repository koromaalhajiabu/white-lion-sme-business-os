const CACHE_NAME='white-lion-sme-v82';
const APP_SHELL=[
  './',
  './index.html',
  './manifest.webmanifest?v=43',
  './shared.js?v=2',
  './i18n.js?v=6',
  './cloud.js?v=34',
  './operations.js?v=17',
  './documents.js?v=3',
  './league.js?v=6',
  './icons/white-lion-icon.svg'
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    // Cache each resource independently so one optional asset cannot block app startup.
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
    await Promise.all(keys.filter(key => key.startsWith('white-lion-sme-') && key !== CACHE_NAME).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  const isAppCode = /\.(?:html|js|css|webmanifest)$/.test(url.pathname);
  if (request.mode === 'navigate' || isAppCode) {
    event.respondWith((async () => {
      try {
        const response = await fetch(request, {cache:'no-cache'});
        if (response && response.ok) {
          const cache = await caches.open(CACHE_NAME);
          cache.put(request, response.clone()).catch(() => {});
        }
        return response;
      } catch (_) {
        const cached = await caches.match(request) || await caches.match('./index.html');
        return cached || Response.error();
      }
    })());
    return;
  }

  event.respondWith((async () => {
    const cached = await caches.match(request);
    if (cached) return cached;
    try {
      const response = await fetch(request);
      if (response && response.ok) {
        const cache = await caches.open(CACHE_NAME);
        cache.put(request, response.clone()).catch(() => {});
      }
      return response;
    } catch (_) {
      return Response.error();
    }
  })());
});
