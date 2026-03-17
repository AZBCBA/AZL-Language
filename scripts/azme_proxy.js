#!/usr/bin/env node
// AZME Proxy bridging to provider
// Ports: proxy 5001 (AZME_PROXY_PORT), provider 5000 (AZME_API_URL)

const http = require('http');
const url = require('url');

const PROXY_PORT = parseInt(process.env.AZME_PROXY_PORT || '5001', 10);
const API_URL = process.env.AZME_API_URL || 'http://127.0.0.1:5000';
const PM = { total: 0, health: 0, passthrough: 0 };
const RATE_WINDOW_MS = parseInt(process.env.AZME_PROXY_RATE_WINDOW_MS || '500', 10);
const RATE_MAX = parseInt(process.env.AZME_PROXY_RATE_MAX || '2', 10);
const hits = new Map();
function shouldRateLimit(ip) {
  const now = Date.now();
  const cutoff = now - RATE_WINDOW_MS;
  const arr = hits.get(ip) || [];
  const filtered = arr.filter((t) => t >= cutoff);
  filtered.push(now);
  hits.set(ip, filtered);
  return filtered.length > RATE_MAX;
}

function json(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

function proxy(req, res) {
  const parsed = url.parse(req.url || '/', true);
  PM.total += 1;
  if (req.method === 'GET' && parsed.pathname === '/health') { PM.health += 1; return json(res, 200, { status: 'ok' }); }
  if (req.method === 'GET' && parsed.pathname === '/metrics') {
    const lines = [
      '# HELP azme_proxy_requests_total Total requests',
      '# TYPE azme_proxy_requests_total counter',
      `azme_proxy_requests_total ${PM.total}`,
      '# HELP azme_proxy_requests_health_total Health requests',
      '# TYPE azme_proxy_requests_health_total counter',
      `azme_proxy_requests_health_total ${PM.health}`,
      '# HELP azme_proxy_passthrough_total Passthrough requests to provider',
      '# TYPE azme_proxy_passthrough_total counter',
      `azme_proxy_passthrough_total ${PM.passthrough}`,
    ].join('\n');
    res.writeHead(200, { 'Content-Type': 'text/plain; version=0.0.4' });
    return res.end(lines);
  }

  // Simple local endpoints
  if (req.method === 'GET' && parsed.pathname === '/api/llm-providers') {
    return json(res, 200, [{ name: 'azme-quantum-ai', models: ['azme-llama3:latest', 'azme-qwen-72b:latest'] }]);
  }
  if (req.method === 'GET' && parsed.pathname === '/api/system') {
    return json(res, 200, { status: 'ok', proxy: true, api: API_URL });
  }

  // Rate limit
  const ip = req.socket && req.socket.remoteAddress ? req.socket.remoteAddress : 'local';
  if (shouldRateLimit(ip)) {
    res.writeHead(429, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ error: 'rate_limited' }));
  }
  const target = new url.URL(parsed.pathname || '/', API_URL);
  const options = {
    method: req.method,
    headers: req.headers,
    hostname: target.hostname,
    port: target.port,
    path: target.pathname + (target.search || ''),
  };
  PM.passthrough += 1;
  const out = http.request(options, (r) => {
    const chunks = [];
    r.on('data', (c) => chunks.push(c));
    r.on('end', () => {
      const body = Buffer.concat(chunks);
      res.writeHead(r.statusCode || 502, r.headers);
      res.end(body);
    });
  });
  req.on('data', (c) => out.write(c));
  req.on('end', () => out.end());
  req.on('error', () => json(res, 502, { error: 'proxy request error' }));
}

http.createServer(proxy).listen(PROXY_PORT, '127.0.0.1', () => {
  // eslint-disable-next-line no-console
  console.log(`[azme-proxy] listening on 127.0.0.1:${PROXY_PORT} api=${API_URL}`);
});

process.on('uncaughtException', (e) => {
  console.error(`[azme-proxy] uncaught: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
});
process.on('unhandledRejection', (e) => {
  console.error(`[azme-proxy] unhandled: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
});


