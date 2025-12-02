// Service Worker for Budget proxy - rewrites relative fetch URLs to go through /budget/
const BUDGET_PREFIX = '/budget';

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  
  // Only intercept same-origin requests that start with /budget path
  if (!url.pathname.startsWith(BUDGET_PREFIX)) {
    return;
  }
  
  // For requests within /budget context, if they try to load root resources,
  // rewrite them to go through the proxy
  // e.g., /favicon.ico -> /budget/favicon.ico
  // e.g., /app.js -> /budget/app.js
  
  let newPath = url.pathname;
  
  // If the request is for a root resource (starts with / but not /budget),
  // and we're in a /budget context, rewrite it
  if (!newPath.startsWith(BUDGET_PREFIX) && newPath.startsWith('/')) {
    newPath = BUDGET_PREFIX + newPath;
    url.pathname = newPath;
  }
  
  // Create new request with rewritten URL
  const newRequest = new Request(url.toString(), {
    method: event.request.method,
    headers: event.request.headers,
    body: event.request.body,
    mode: event.request.mode,
    credentials: event.request.credentials,
    cache: event.request.cache,
    redirect: event.request.redirect,
    referrer: event.request.referrer,
  });
  
  event.respondWith(fetch(newRequest));
});
