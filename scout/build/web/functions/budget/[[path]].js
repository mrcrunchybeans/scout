// Cloudflare Pages Function to proxy /budget/* to Actual Budget server

export async function onRequest(context) {
  const url = new URL(context.request.url);
  
  // Extract the path after /budget/
  const budgetPath = context.params.path ? context.params.path.join('/') : '';
  
  // Proxy to Actual Budget server via tunnel
  const targetUrl = `https://budget.littleempathy.com/${budgetPath}${url.search}`;
  
  // Build request options
  const requestOptions = {
    method: context.request.method,
    headers: context.request.headers,
  };
  
  // Only include body for methods that support it
  if (context.request.method !== 'GET' && context.request.method !== 'HEAD') {
    requestOptions.body = context.request.body;
  }
  
  // Forward the request
  const response = await fetch(targetUrl, requestOptions);
  
  // Clone headers and ensure CORS/security headers are set
  const newHeaders = new Headers(response.headers);
  
  // Ensure SharedArrayBuffer headers are present for same-origin
  newHeaders.set('Cross-Origin-Embedder-Policy', 'require-corp');
  newHeaders.set('Cross-Origin-Opener-Policy', 'same-origin');
  
  // Only rewrite text-based content (HTML, JS, CSS)
  const contentType = response.headers.get('content-type') || '';
  const isTextContent = contentType.includes('text/html') || 
                        contentType.includes('application/javascript') ||
                        contentType.includes('text/javascript') ||
                        contentType.includes('text/css');
  
  // Skip rewriting for binary content (fonts, images, etc.)
  const isBinary = contentType.includes('font') ||
                   contentType.includes('image') ||
                   contentType.includes('woff') ||
                   contentType.includes('ttf') ||
                   contentType.includes('octet-stream');
  
  if (isTextContent && !isBinary) {
    let content = await response.text();
    // Rewrite absolute paths to be relative to /budget/
    content = content.replace(/href="\//g, 'href="/budget/');
    content = content.replace(/src="\//g, 'src="/budget/');
    content = content.replace(/url\(\//g, 'url(/budget/');
    // Also handle JavaScript fetch/import calls
    content = content.replace(/fetch\("\/(?!budget)/g, 'fetch("/budget/');
    content = content.replace(/import\("\/(?!budget)/g, 'import("/budget/');
    content = content.replace(/"\/static\//g, '"/budget/static/');
    content = content.replace(/'\/static\//g, '\'/budget/static/');
    
    return new Response(content, {
      status: response.status,
      statusText: response.statusText,
      headers: newHeaders,
    });
  }
  
  // For binary/other content, pass through unchanged
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: newHeaders,
  });
}
