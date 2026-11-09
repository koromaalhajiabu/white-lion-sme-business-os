const CACHE_NAME='white-lion-sme-v83';
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

  // Stale-while-revalidate for everything: serve an already-cached copy
  // instantly (so the app never hangs waiting on a slow/unreliable mobile
  // connection), and refresh the cache quietly in the background for next
  // time. Only reaches the network synchronously when nothing is cached yet.
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request);
    const network = fetch(request).then(response => {
      if (response && response.ok) cache.put(request, response.clone()).catch(() => {});
      return response;
    }).catch(() => null);

    if (cached) {
      network.catch(() => {});
      return cached;
    }
    const response = await network;
    if (response) return response;
    if (request.mode === 'navigate') {
      const fallback = await cache.match('./index.html');
      if (fallback) return fallback;
    }
    return Response.error();
  })());
});
