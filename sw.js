const SHELL_CACHE = 'shell-v1';
const API_CACHE   = 'api-v1';

const SHELL_FILES = [
  '/recipes-blog/index.html',
  '/recipes-blog/recipe.html',
  '/recipes-blog/fridge.html',
  '/recipes-blog/config.js',
  '/recipes-blog/manifest.json',
  '/recipes-blog/icon-192.png',
];

// ── Install: cache shell ──────────────────────────────────────────────────────
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(SHELL_CACHE)
      .then(c => c.addAll(SHELL_FILES))
      .then(() => self.skipWaiting())
  );
});

// ── Activate: clear old caches ────────────────────────────────────────────────
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys
        .filter(k => k !== SHELL_CACHE && k !== API_CACHE)
        .map(k => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

// ── Fetch ─────────────────────────────────────────────────────────────────────
self.addEventListener('fetch', e => {
  // Skip non-http(s) requests (chrome-extension://, etc.)
  if (!e.request.url.startsWith('http')) return;

  const url = new URL(e.request.url);

  // API calls: network first, cache fallback (GET only)
  if (url.hostname.includes('railway.app') && e.request.method === 'GET') {
    e.respondWith(networkFirstAPI(e.request));
    return;
  }

  // Shell / static: cache first, network fallback
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
      const cache = await caches.open(SHELL_CACHE);
      cache.put(req, res.clone());
    }
    return res;
  } catch {
    // If navigating to recipe.html offline, serve cached shell
    if (req.mode === 'navigate') {
      return caches.match('/recipes-blog/index.html');
    }
    return new Response('Offline', { status: 503 });
  }
}
