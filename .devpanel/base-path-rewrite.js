/**
 * Base Path Rewriter
 * Intercepts fetch, XMLHttpRequest, and socket.io to rewrite URLs based on <base> tag
 */
(function() {
  const baseTag = document.querySelector('base');
  if (!baseTag) return;
  
  const h = location.host;
  const basePath = baseTag.getAttribute('href')?.replace(/\/$/, '') || '';
  if (!basePath) return;
  
  // Helper function to rewrite URLs
  function rewriteUrl(url) {
    if (typeof url !== 'string') return url;
    
    // Handle relative paths starting with /
    if (url.startsWith('/')) {
      return basePath + url;
    }
    
    // Handle full URLs with current host (any protocol)
    const m = url.match(/^([a-z][a-z0-9+.-]*:\/\/[^\/]+)(\/.*)/);
    if (m && m[1].includes(h)) {
      return m[1] + basePath + m[2];
    }
    
    return url;
  }
  
  // Intercept fetch API
  const origFetch = window.fetch;
  window.fetch = function(url, opts) {
    return origFetch(rewriteUrl(url), opts);
  };
  
  // Intercept XMLHttpRequest
  const origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    return origOpen.call(this, method, rewriteUrl(url), ...rest);
  };
  
  // Intercept WebSocket constructor
  const OriginalWebSocket = window.WebSocket;
  window.WebSocket = function(url, protocols) {
    return new OriginalWebSocket(rewriteUrl(url), protocols);
  };
  window.WebSocket.prototype = OriginalWebSocket.prototype;
  
  // Intercept socket.io Manager constructor
  if (window.io && window.io.Manager) {
    const OriginalManager = window.io.Manager;
    window.io.Manager = function(uri, opts) {
      // Rewrite the URI for socket.io
      const rewrittenUri = rewriteUrl(uri || location.pathname);
      return new OriginalManager(rewrittenUri, opts);
    };
    // Copy static properties
    Object.setPrototypeOf(window.io.Manager, OriginalManager);
    window.io.Manager.prototype = OriginalManager.prototype;
  }
  
  // Also intercept io() function directly
  if (window.io) {
    const origIo = window.io;
    window.io = function(uri, opts) {
      return origIo(rewriteUrl(uri || location.pathname), opts);
    };
    // Copy all properties from original io
    Object.keys(origIo).forEach(key => {
      window.io[key] = origIo[key];
    });
  }
})();
