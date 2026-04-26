const CACHE_NAME = 'recipes-v' + Date.now();
const API_CACHE  = 'api-v1';

self.addEventListener('install', e => {
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME && k !== API_CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  if (!e.request.url.startsWith('http')) return;

  const url = new URL(e.request.url);

  // API calls: network first, cache fallback (GET only)
  if (url.hostname.includes('railway.app') && e.request.method === 'GET') {
    e.respondWith(networkFirstAPI(e.request));
    return;
  }

  // HTML documents: network first (always fresh)
  if (e.request.destination === 'document') {
    e.respondWith(
      fetch(e.request)
        .then(res => {
          const clone = res.clone();
          caches.open(CACHE_NAME).then(c => c.put(e.request, clone));
          return res;
        })
        .catch(() => caches.match(e.request))
    );
    return;
  }

  // Static assets: cache first, network fallback
  if (e.request.method === 'GET') {
    e.respondWith(cacheFirst(e.request));
  }
});

async function networkFirstAPI(req) {
  try {
    const res = await fetch(req);
    if (res.ok) {
      const cache = await caches.open(API_CACHE);
      cache.put(req, res.clone());
    }
    return res;
  } catch {
    const cached = await caches.match(req);
    return cached || new Response(JSON.stringify({ error: 'offline' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

async function cacheFirst(req) {
  const cached = await caches.match(req);
  if (cached) return cached;
  try {
    const res = await fetch(req);
    if (res.ok) {
      const cache = await caches.open(CACHE_NAME);
      cache.put(req, res.clone());
    }
    return res;
  } catch {
    if (req.mode === 'navigate') {
      return caches.match('/recipes-blog/index.html');
    }
    return new Response('Offline', { status: 503 });
  }
}
