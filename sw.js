const CACHE_NAME='white-lion-sme-v77';
const APP_SHELL=[
  './',
  './index.html',
  './manifest.webmanifest?v=43',
  './shared.js?v=1',
  './i18n.js?v=5',
  './cloud.js?v=32',
  './operations.js?v=16',
  './documents.js?v=2',
  './league.js?v=5',
  './icons/white-lion-icon.svg'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key => key.startsWith('white-lion-sme-') && key !== CACHE_NAME)
          .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    const isAppShell = url.pathname === self.registration.scope.replace(self.location.origin, '') ||
      url.pathname.endsWith('/index.html');
    event.respondWith(
      fetch(request).then(response => {
        if (isAppShell && response && response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put('./index.html', copy));
        }
        return response;
      }).catch(() => isAppShell ? caches.match('./index.html') : caches.match(request))
    );
    return;
  }

  event.respondWith(
    caches.match(request).then(cached => {
      if (cached) return cached;
      return fetch(request).then(response => {
        if (response && response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(request, copy));
        }
        return response;
      });
    })
  );
});
