/* Boss Fridge service worker. Bump CACHE_NAME together with BF_VERSION in index.html. */
const CACHE_NAME = 'bf-v23';

const PRECACHE = [
  './',
  './index.html',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/apple-touch-icon.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(
        names
          .filter((name) => name.startsWith('bf-') && name !== CACHE_NAME)
          .map((name) => caches.delete(name))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  // Supabase, Google Fonts, the CDN and everything else cross-origin go straight to the network.
  if (url.origin !== self.location.origin) return;

  if (req.mode === 'navigate') {
    // Network first; offline falls back to the cached shell (which shows the napping screen).
    event.respondWith(
      fetch(req).catch(() =>
        caches.match('./index.html').then((cached) => cached || Response.error())
      )
    );
    return;
  }

  // Other same-origin assets: cache first.
  event.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((res) => {
        if (res && res.ok && res.type === 'basic') {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
        }
        return res;
      });
    })
  );
});

/* ---------- batch M: notifications ---------- */
self.addEventListener('push', (event) => {
  let d = {};
  try {
    d = event.data ? event.data.json() : {};
  } catch (e) {
    d = { body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(self.registration.showNotification(d.title || 'Boss Fridge', {
    body: d.body || '',
    tag: d.tag || 'bf',
    renotify: true,
    icon: './icons/icon-192.png',
    badge: './icons/icon-192.png',
    data: { url: d.url || './' }
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL((event.notification.data && event.notification.data.url) || './', self.registration.scope).href;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if ('focus' in c) {
          c.postMessage({ bf: 'open', url: url });
          return c.focus();
        }
      }
      return self.clients.openWindow(url);
    })
  );
});
