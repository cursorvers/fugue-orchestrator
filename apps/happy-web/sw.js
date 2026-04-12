self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open("kernel-orchestration-shell-v1")
      .then((cache) =>
        cache.addAll([
          "./",
          "./index.html",
          "./styles.css",
          "./manifest.webmanifest",
          "./src/app.js",
          "./src/kernel-state.js",
          "./src/render.js",
        ])
      )
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => !key.startsWith("kernel-orchestration-shell-v1") && !key.startsWith("kernel-orchestration-runtime-v1"))
            .map((key) => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  );
});

async function networkFirst(request) {
  const cache = await caches.open("kernel-orchestration-runtime-v1");
  try {
    const response = await fetch(request);
    if (request.method === "GET" && response.ok) {
      cache.put(request, response.clone());
    }
    return response;
  } catch (_error) {
    const cached = await cache.match(request);
    if (cached) return cached;
    throw _error;
  }
}

async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (request.method === "GET" && response.ok) {
    const cache = await caches.open("kernel-orchestration-shell-v1");
    cache.put(request, response.clone());
  }
  return response;
}

self.addEventListener("fetch", (event) => {
  const requestUrl = new URL(event.request.url);
  if (event.request.method !== "GET" || requestUrl.origin !== self.location.origin) {
    return;
  }

  if (requestUrl.pathname.startsWith("/api/happy/")) {
    event.respondWith(networkFirst(event.request));
    return;
  }

  event.respondWith(cacheFirst(event.request));
});
