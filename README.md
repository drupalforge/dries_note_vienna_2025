# Driesnote Vienna 2025 - Drupal Forge Wrapper

This repository provides a Drupal Forge-compatible wrapper for running [FreelyGive/v2025demo](https://github.com/FreelyGive/v2025demo) with Milvus vector database and Attu management UI integrated into the environment. DDEV is used locally to replicate the Drupal Forge hosting environment.

**For the original demo documentation, setup instructions, and requirements, see the [FreelyGive/v2025demo repository](https://github.com/FreelyGive/v2025demo).**

## What this wrapper adds

This wrapper extends the original demo with Drupal Forge-specific configurations:

1. **Embedded Milvus Stack**: Milvus vector database, etcd, MinIO, and Attu run inside the web container via Supervisor (matching Drupal Forge architecture)
2. **Attu Web UI Access**: Access the Milvus management interface at `/attu` (Apache proxy with URL rewriting)
3. **Drupal Forge Compatibility**: Configuration designed to work on Drupal Forge hosting platform

## Running the demo (local development)
DDEV replicates the Drupal Forge environment locally:
```bash
cp .ddev/.env.template .ddev/.env  # Set your OpenAI API key
ddev start                          # Installs and configures everything
```

**Note:** Running `ddev start` automatically executes [`.devpanel/composer_setup.sh`](.devpanel/composer_setup.sh), which installs the FreelyGive/v2025demo repository and configures everything. Unlike the original demo, there is no separate `demo-setup` command.

## Attu (Milvus management UI)

Attu is available at `/attu` via Apache proxy with URL rewriting. This replaces the default port 8521 access method with a path-based approach compatible with Drupal Forge hosting.

### Technical implementation

The `/attu` path required several modifications to proxy the Node.js application running on port 3000:

#### 1. Apache Configuration ([`.ddev/apache/attu-proxy.conf`](.ddev/apache/attu-proxy.conf))
- Enabled `proxy_http`, `proxy_wstunnel`, `headers`, and `substitute` modules
- Configured ProxyPass with WebSocket upgrade support
- Injected `<base href="/attu/">` tag and JavaScript interceptor into HTML responses

#### 2. URL rewriting JavaScript ([`.devpanel/base-path-rewrite.js`](.devpanel/base-path-rewrite.js))
Intercepts all HTTP requests to rewrite paths for the `/attu` subpath:
- **fetch() API**: Rewrites relative and absolute URLs
- **XMLHttpRequest**: Rewrites AJAX requests
- **WebSocket**: Rewrites WebSocket connection URLs (critical for socket.io)
- **socket.io**: Intercepts Manager constructor and io() function

The JavaScript file is:
- Stored in [`.devpanel/base-path-rewrite.js`](.devpanel/base-path-rewrite.js) for version control
- Copied to `web/base-path-rewrite.js` via Drupal Scaffold on composer install/update
- Injected into the Attu HTML using Apache's Substitute filter

#### 3. Composer configuration
- [`.devpanel/composer_setup.sh`](.devpanel/composer_setup.sh): Defines scaffold mapping during project setup
- [`composer.json`](composer.json): Includes file-mapping entry for base-path-rewrite.js

#### 4. DDEV Docker configuration ([`.ddev/web-build/Dockerfile.attu`](.ddev/web-build/Dockerfile.attu))
- Installs Attu Node.js application
- Enables required Apache modules: `a2enmod proxy_http proxy_wstunnel headers substitute`

### Key technical challenges solved
1. **WebSocket connections**: Added WebSocket constructor interception to rewrite `wss://` URLs
2. **Socket.io path rewriting**: Intercepted both socket.io Manager and io() functions
3. **Base tag limitations**: JavaScript interception needed because `<base>` tag doesn't affect fetch/XHR/WebSocket
