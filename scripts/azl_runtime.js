#!/usr/bin/env node
/*
  AZL Runtime Executor - Production sysproxy bridge (long-term TCP mode)
  - Connects directly to sysproxy over TCP (SYSPROXY_TCP or HOST/PORT)
  - Robust auto-reconnect with backoff; no FIFO fallback
  - Performs listen/accept over sysproxy, routes health endpoints
  - Integrates with systemd notify/Watchdog when available
*/
const fs = require('fs');
const path = require('path');
const net = require('net');
const readline = require('readline');
const { spawn } = require('child_process');

const PORT = parseInt(process.env.AZL_BUILD_API_PORT || '8080', 10);
const NODE_HTTP_ENABLED = String(process.env.AZL_NODE_HTTP || '1') === '1';
const LOCAL = String(process.env.AZL_LOCAL_MODE || '1') === '1';
const BIND_HOST = LOCAL ? '127.0.0.1' : (process.env.AZL_BIND_HOST || '127.0.0.1');
const API_TOKEN = LOCAL ? '' : (process.env.AZL_API_TOKEN || '');
const STRICT = String(process.env.AZL_STRICT || '').toLowerCase();
const serverStartMs = Date.now();
const tcpSpec = process.env.SYSPROXY_TCP || null; // e.g. 127.0.0.1:9099
const tcpHost = process.env.SYSPROXY_HOST || (tcpSpec ? tcpSpec.split(':')[0] : '127.0.0.1');
const tcpPort = parseInt(process.env.SYSPROXY_PORT || (tcpSpec ? tcpSpec.split(':')[1] : '9099'), 10);
const acceptWorkers = parseInt(process.env.AZL_ACCEPT_WORKERS || '16', 10);

let nextId = 1;
const pending = new Map();

function log(msg) { console.log(`[runtime] ${msg}`); }
function err(msg) { console.error(`[runtime:err] ${msg}`); }

// systemd notify helpers
let watchdogTimer = null;
function sdNotifyReady() {
  try { spawn('systemd-notify', ['--ready'], { stdio: 'ignore' }); } catch {}
}
function sdNotifyStatusAndWatchdog(statusMsg) {
  const envWd = process.env.WATCHDOG_USEC;
  if (!envWd) return;
  const usec = parseInt(envWd, 10);
  if (!Number.isFinite(usec) || usec <= 0) return;
  const intervalMs = Math.max(1000, Math.floor(usec / 2 / 1000));
  if (watchdogTimer) clearInterval(watchdogTimer);
  watchdogTimer = setInterval(() => {
    try { spawn('systemd-notify', ['--status', statusMsg, '--watchdog'], { stdio: 'ignore' }); } catch {}
  }, intervalMs);
}

// Metrics
const metrics = {
  totalConnections: 0,
  healthz: 0,
  readyz: 0,
  status: 0,
  notFound: 0,
  cacheHits: 0,
  cacheMisses: 0,
  error4xx: 0,
  error5xx: 0,
};
// Simple per-path rate limiter
const RL_WINDOW_MS = Number(process.env.AZL_HTTP_RATELIMIT_WINDOW_MS || 1000);
const RL_MAX = Number(process.env.AZL_HTTP_RATELIMIT_MAX || 200);
const rlCounters = new Map(); // path -> { start, count }
function rateLimited(path) {
  const now = Date.now();
  const ent = rlCounters.get(path) || { start: now, count: 0 };
  if (now - ent.start > RL_WINDOW_MS) { ent.start = now; ent.count = 0; }
  ent.count += 1;
  rlCounters.set(path, ent);
  return ent.count > RL_MAX;
}

// Simple endpoint latency tracking (per-process, in-memory)
const LAT = new Map(); // path -> { n, min, max, sum }
function recordLatency(path, ms) {
  const e = LAT.get(path) || { n: 0, min: Infinity, max: 0, sum: 0 };
  e.n += 1; e.sum += ms; if (ms < e.min) e.min = ms; if (ms > e.max) e.max = ms;
  LAT.set(path, e);
}
function latencyMetricsText() {
  let out = '';
  for (const [k, v] of LAT.entries()) {
    const avg = v.n ? (v.sum / v.n) : 0;
    out += `azl_runtime_endpoint_latency_ms{path="${k}"} ${avg.toFixed(2)}\n`;
    out += `azl_runtime_endpoint_latency_ms_count{path="${k}"} ${v.n}\n`;
    out += `azl_runtime_endpoint_latency_ms_min{path="${k}"} ${Number.isFinite(v.min)?v.min:0}\n`;
    out += `azl_runtime_endpoint_latency_ms_max{path="${k}"} ${v.max}\n`;
  }
  return out.trim();
}
function metricsText() {
  const info = [
    '# HELP azl_runtime_info Build/runtime info',
    '# TYPE azl_runtime_info gauge',
    `azl_runtime_info{version="${process.env.AZL_VERSION || 'unknown'}"} 1`
  ].join('\n');
  return [
    info,
    '# HELP azl_runtime_connections_total Total connections handled',
    '# TYPE azl_runtime_connections_total counter',
    `azl_runtime_connections_total ${metrics.totalConnections}`,
    '# HELP azl_runtime_healthz_total Total /healthz requests',
    '# TYPE azl_runtime_healthz_total counter',
    `azl_runtime_healthz_total ${metrics.healthz}`,
    '# HELP azl_runtime_readyz_total Total /readyz requests',
    '# TYPE azl_runtime_readyz_total counter',
    `azl_runtime_readyz_total ${metrics.readyz}`,
    '# HELP azl_runtime_status_total Total /status requests',
    '# TYPE azl_runtime_status_total counter',
    `azl_runtime_status_total ${metrics.status}`,
    '# HELP azl_runtime_not_found_total Total 404 requests',
    '# TYPE azl_runtime_not_found_total counter',
    `azl_runtime_not_found_total ${metrics.notFound}`,
    '# HELP azl_runtime_endpoint_latency_ms Endpoint latency (not persisted, current process only)',
    '# TYPE azl_runtime_endpoint_latency_ms summary',
    `${latencyMetricsText()}`,
    '# HELP azl_runtime_cache_hits_total Total cache hits',
    '# TYPE azl_runtime_cache_hits_total counter',
    `azl_runtime_cache_hits_total ${metrics.cacheHits}`,
    '# HELP azl_runtime_cache_misses_total Total cache misses',
    '# TYPE azl_runtime_cache_misses_total counter',
    `azl_runtime_cache_misses_total ${metrics.cacheMisses}`,
    '# HELP azl_build_cache_hits_total Build cache hits (daemon snapshot)',
    '# TYPE azl_build_cache_hits_total counter',
    `${snapshotMetric('hits')}`,
    '# HELP azl_build_cache_misses_total Build cache misses (daemon snapshot)',
    '# TYPE azl_build_cache_misses_total counter',
    `${snapshotMetric('misses')}`,
    '# HELP azl_runtime_errors_4xx_total Total 4xx responses',
    '# TYPE azl_runtime_errors_4xx_total counter',
    `azl_runtime_errors_4xx_total ${metrics.error4xx}`,
    '# HELP azl_runtime_errors_5xx_total Total 5xx responses',
    '# TYPE azl_runtime_errors_5xx_total counter',
    `azl_runtime_errors_5xx_total ${metrics.error5xx}`,
    '# HELP azl_snapshot_age_seconds Snapshot age in seconds (negative if unknown)',
    '# TYPE azl_snapshot_age_seconds gauge',
    `${snapshotAgeSeconds()}`,
    '# HELP azl_build_active_total Active builds (from snapshot)',
    '# TYPE azl_build_active_total gauge',
    `${buildActiveTotal()}`,
    '# HELP azl_event_buffer_size Event buffer size (from snapshot)',
    '# TYPE azl_event_buffer_size gauge',
    `${eventBufferSize()}`
  ].join('\n');
}

function snapshotMetric(key) {
  try {
    const obj = readSnapshot();
    const buildCache = ((obj || {}).build_cache) || {};
    const val = Number(buildCache[key] || 0);
    return Number.isFinite(val) ? val : 0;
  } catch { return 0; }
}
function readSnapshot() {
  const snapPath = process.env.AZL_DAEMON_STATUS_PATH || '.azl/daemon_status.json';
  const s = fs.readFileSync(snapPath, 'utf8');
  return JSON.parse(s);
}
function snapshotAgeSeconds() {
  try { const obj = readSnapshot(); const ts = Number(obj.snapshot_ts || 0); if (!ts) return -1; return Math.max(0, Math.floor((Date.now() - ts)/1000)); } catch { return -1; }
}
function buildActiveTotal() {
  try { const obj = readSnapshot(); const ab = obj.active_builds || {}; return Object.keys(ab).length; } catch { return 0; }
}
function eventBufferSize() {
  try { const obj = readSnapshot(); const ev = obj.events || []; return Array.isArray(ev)? ev.length : 0; } catch { return 0; }
}

// Global hardening against benign socket resets
process.on('uncaughtException', (e) => {
  if (e && (e.code === 'ECONNRESET' || String(e).includes('Interface') || String(e).includes('read ECONNRESET'))) {
    err(`uncaught benign error: ${e.message || e}`);
    return; // swallow known benign resets
  }
  err(`uncaught fatal error: ${e && e.stack ? e.stack : e}`);
});
process.on('unhandledRejection', (e) => {
  if (e && (e.code === 'ECONNRESET' || String(e).includes('read ECONNRESET'))) {
    err(`unhandled benign rejection: ${e.message || e}`);
    return;
  }
  err(`unhandled rejection: ${e && e.stack ? e.stack : e}`);
});

// Transport state
let mode = 'unknown'; // 'tcp'
let tcpSock = null;
let tcpRl = null;
let connecting = false;
let reconnectTimer = null;
let reconnectBackoffMs = 250; // capped exponential backoff

let listenFd = null;
let acceptLoopsStarted = false;

function flushPending(error) {
  for (const [id, entry] of pending.entries()) {
    pending.delete(id);
    try { entry.reject(error); } catch {}
  }
}

function handleDisconnect(cause) {
  err(`tcp disconnect: ${cause && cause.message ? cause.message : String(cause)}`);
  mode = 'unknown';
  listenFd = null;
  if (watchdogTimer) { clearInterval(watchdogTimer); watchdogTimer = null; }
  // Close RL first to avoid emitting 'error' without a handler
  if (tcpRl) {
    const rlRef = tcpRl;
    tcpRl = null;
    try { rlRef.close(); } catch {}
    try { rlRef.removeAllListeners(); } catch {}
  }
  if (tcpSock) {
    const s = tcpSock;
    tcpSock = null;
    try { s.removeAllListeners(); } catch {}
    try { s.destroy(); } catch {}
  }
  flushPending(new Error('sysproxy disconnected'));
  scheduleReconnect();
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectLoop();
  }, reconnectBackoffMs);
  reconnectBackoffMs = Math.min(reconnectBackoffMs * 2, 3000);
}

function setupTcp() {
  return new Promise((resolve, reject) => {
    const sock = net.createConnection({ host: tcpHost, port: tcpPort });
    let settled = false;

    function settleOk() { if (!settled) { settled = true; resolve(); } }
    function settleErr(e) { if (!settled) { settled = true; reject(e); } }

    sock.once('connect', () => {
      tcpSock = sock;
      mode = 'tcp';
      const rl = readline.createInterface({ input: sock });
      tcpRl = rl;
      rl.on('line', (line) => {
    if (!line) return;
        try {
          const obj = JSON.parse(line.trim());
          dispatchSysproxyResponse(obj);
        } catch {}
      });
      rl.on('close', () => handleDisconnect(new Error('rl_close')));
      rl.on('error', (e) => handleDisconnect(e));
      sock.on('error', (e) => handleDisconnect(e));
      sock.on('end', () => handleDisconnect(new Error('end')));
      sock.on('close', () => handleDisconnect(new Error('close')));
      settleOk();
    });

    sock.once('error', (e) => settleErr(e));
  });
}

function connectLoop() {
  if (connecting) return;
  connecting = true;
  setupTcp()
    .then(() => {
      connecting = false;
      reconnectBackoffMs = 250;
      log(`connected to sysproxy tcp ${tcpHost}:${tcpPort}`);
      ensureListening();
      if (!acceptLoopsStarted) startAcceptLoops();
    })
    .catch((e) => {
      connecting = false;
      err(`tcp connect failed: ${e.message}`);
      scheduleReconnect();
    });
}

function dispatchSysproxyResponse(obj) {
      const id = obj && obj.id;
  if (obj && typeof obj.conn === 'number') {
    handleConn(obj.conn).catch(e => err(`conn err: ${e.message}`));
    return;
  }
      if (id && pending.has(id)) {
        const { resolve } = pending.get(id);
        pending.delete(id);
        resolve(obj);
      }
}

function sendSysproxy(op, args = {}, timeoutMs = 1500) {
  const id = nextId++;
  const payload = { id, op, ...args };
  if (!(mode === 'tcp' && tcpSock)) {
    return Promise.reject(new Error('transport not ready'));
  }
  try {
    tcpSock.write(JSON.stringify(payload) + '\n');
  } catch (e) {
    err(`write failed: ${e.message}`);
  }
  return new Promise((resolve, reject) => {
    const to = setTimeout(() => {
      if (pending.has(id)) { pending.delete(id); reject(new Error(`timeout ${op} id=${id}`)); }
    }, timeoutMs);
    pending.set(id, { resolve: (val) => { clearTimeout(to); resolve(val); }, reject, ts: Date.now(), op });
  });
}

function parsePath(requestLine) {
  try {
    const parts = requestLine.split(' ');
    if (parts.length >= 2) return parts[1];
  } catch {}
  return '/';
}
async function clientIp(fd) {
  try {
    const r = await sendSysproxy('peer', { fd }, 500);
    if (r && r.ok && r.ip) return r.ip;
  } catch {}
  return 'unknown';
}

// Small in-memory response cache for GETs
const RESP_CACHE = new Map();
const RESP_CACHE_TTL_MS = Number(process.env.AZL_HTTP_CACHE_TTL_MS || 5000);
const RESP_CACHE_CAP = Number(process.env.AZL_HTTP_CACHE_CAP || 256);
function getCachedResponse(path) {
  const now = Date.now();
  const ent = RESP_CACHE.get(path);
  if (!ent) { metrics.cacheMisses++; return null; }
  if (now - ent.ts > RESP_CACHE_TTL_MS) { RESP_CACHE.delete(path); metrics.cacheMisses++; return null; }
  metrics.cacheHits++;
  return ent;
}
function putCachedResponse(path, body, contentType) {
  if (RESP_CACHE.size >= RESP_CACHE_CAP) {
    const k = RESP_CACHE.keys().next().value; // FIFO eviction
    if (k !== undefined) RESP_CACHE.delete(k);
  }
  RESP_CACHE.set(path, { body, contentType, ts: Date.now() });
}

async function handleConn(conn) {
  metrics.totalConnections += 1;
  let reqData = '';
  try {
    const r = await sendSysproxy('read', { fd: conn, max: 8192 }, 800);
    if (r && r.data) reqData = r.data;
  } catch {}
  const firstLine = (reqData.split('\r\n')[0] || '').trim();
  const path = parsePath(firstLine);

  // Extract Authorization header (Bearer ...)
  let authHeader = '';
  try {
    const lines = reqData.split(/\r?\n/);
    for (let i = 1; i < lines.length; i++) {
      const ln = lines[i];
      if (!ln) break;
      const idx = ln.indexOf(':');
      if (idx > 0) {
        const k = ln.substring(0, idx).trim().toLowerCase();
        const v = ln.substring(idx + 1).trim();
        if (k === 'authorization') { authHeader = v; break; }
      }
    }
  } catch {}
  const bearerToken = authHeader.toLowerCase().startsWith('bearer ')
    ? authHeader.substring(7).trim()
    : '';

  const enrich = (base) => ({
    status: base,
    pid: process.pid,
    uptime_sec: Math.max(0, Math.floor((Date.now() - serverStartMs) / 1000)),
    strict: STRICT === '1' || STRICT === 'true',
  });

  let status = '200 OK';
  let contentType = 'application/json';
  let headersExtra = [];
  let body;
  const t0 = Date.now();
  // Apply rate-limits to heavier endpoints
  if (path === '/events' || path === '/history' || path === '/builds') {
    if (rateLimited(path) || rateLimited('ip:' + (await clientIp(conn)))) {
      status = '429 Too Many Requests';
      body = JSON.stringify({ error: 'rate_limited' });
      const resp429 = [
        `HTTP/1.1 ${status}`,
        `Content-Type: application/json`,
        `Content-Length: ${Buffer.byteLength(body)}`,
        'Connection: close',
        '',
        body
      ].join('\r\n');
      try { await sendSysproxy('write', { fd: conn, data: resp429 }, 600); } catch {}
      try { await sendSysproxy('close', { fd: conn }, 300); } catch {}
      return;
    }
  }
  if (path === '/healthz') { metrics.healthz += 1; const c = getCachedResponse(path); if (c) { body = c.body; contentType = c.contentType; } else { body = JSON.stringify(enrich('healthy')); putCachedResponse(path, body, contentType); } }
  else if (path === '/readyz') {
    metrics.readyz += 1;
    if (!LOCAL && API_TOKEN && bearerToken !== API_TOKEN) { status = '401 Unauthorized'; headersExtra = ['WWW-Authenticate: Bearer']; body = JSON.stringify({ error: 'unauthorized' }); }
    else {
      // Staleness gate: require recent snapshot
      const stalenessSec = Number(process.env.AZL_SNAPSHOT_STALE_SEC || 10);
      try {
        const snapPath = process.env.AZL_DAEMON_STATUS_PATH || '.azl/daemon_status.json';
        const s = fs.readFileSync(snapPath, 'utf8');
        const obj = JSON.parse(s);
        const ts = Number(obj.snapshot_ts || 0);
        if (ts && (Date.now() - ts) <= stalenessSec * 1000) {
          body = JSON.stringify(enrich('ready'));
        } else {
          status = '503 Service Unavailable';
          body = JSON.stringify({ error: 'stale_snapshot' });
        }
      } catch {
        status = '503 Service Unavailable';
        body = JSON.stringify({ error: 'no_snapshot' });
      }
    }
  }
  else if (path === '/status') {
    metrics.status += 1;
    if (!LOCAL && API_TOKEN && bearerToken !== API_TOKEN) { status = '401 Unauthorized'; headersExtra = ['WWW-Authenticate: Bearer']; body = JSON.stringify({ error: 'unauthorized' }); }
    else {
      // Prefer live daemon snapshot if present
      try {
        const snapPath = process.env.AZL_DAEMON_STATUS_PATH || '.azl/daemon_status.json';
        const s = fs.readFileSync(snapPath, 'utf8');
        const obj = JSON.parse(s);
        body = JSON.stringify({ status: 'ok', pid: process.pid, uptime_sec: Math.floor(process.uptime()), strict: STRICT === '1' || STRICT === 'true', daemon: obj });
      } catch {
        const c = getCachedResponse(path);
        if (c) { body = c.body; contentType = c.contentType; }
        else { body = JSON.stringify(enrich('ok')); putCachedResponse(path, body, contentType); }
      }
    }
  }
  else if (path === '/builds' || path === '/history') {
    const strictOn = (STRICT === '1' || STRICT === 'true');
    if (!LOCAL && API_TOKEN && bearerToken !== API_TOKEN) { status = '401 Unauthorized'; headersExtra = ['WWW-Authenticate: Bearer']; body = JSON.stringify({ error: 'unauthorized' }); }
    else {
      try {
        const snapPath = process.env.AZL_DAEMON_STATUS_PATH || '.azl/daemon_status.json';
        const s = fs.readFileSync(snapPath, 'utf8');
        const obj = JSON.parse(s);
        const deadline = Date.now() + 1000;
        if (Date.now() > deadline) throw new Error('timeout');
        if (path === '/builds') body = JSON.stringify({ status: 'ok', active_builds: obj.active_builds || {} });
        else body = JSON.stringify({ status: 'ok', build_history: obj.build_history || [] });
      } catch {
        status = '503 Service Unavailable';
        body = JSON.stringify({ error: 'no_snapshot' });
      }
    }
  }
  else if (path === '/events') {
    if (!LOCAL && API_TOKEN && bearerToken !== API_TOKEN) { status = '401 Unauthorized'; headersExtra = ['WWW-Authenticate: Bearer']; body = JSON.stringify({ error: 'unauthorized' }); }
    else {
      try {
        const snapPath = process.env.AZL_DAEMON_STATUS_PATH || '.azl/daemon_status.json';
        const s = fs.readFileSync(snapPath, 'utf8');
        const obj = JSON.parse(s);
        const events = Array.isArray(obj.events) ? obj.events.slice(-50) : [];
        body = JSON.stringify({ status: 'ok', events });
      } catch {
        status = '503 Service Unavailable';
        body = JSON.stringify({ error: 'no_snapshot' });
      }
    }
  }
  else if (path === '/metrics') {
    const strictOn = (STRICT === '1' || STRICT === 'true');
    if (strictOn && !LOCAL && API_TOKEN && bearerToken !== API_TOKEN) { status = '401 Unauthorized'; headersExtra = ['WWW-Authenticate: Bearer']; body = JSON.stringify({ error: 'unauthorized' }); }
    else { body = metricsText(); contentType = 'text/plain; version=0.0.4'; }
  }
  else if (path === '/analytics') {
    if (!LOCAL && API_TOKEN && bearerToken !== API_TOKEN) { status = '401 Unauthorized'; headersExtra = ['WWW-Authenticate: Bearer']; body = JSON.stringify({ error: 'unauthorized' }); }
    else {
      body = JSON.stringify({
        connections: metrics.totalConnections,
        healthz: metrics.healthz,
        readyz: metrics.readyz,
        status: metrics.status,
        not_found: metrics.notFound,
        cache: { hits: metrics.cacheHits, misses: metrics.cacheMisses }
      });
    }
  }
  else if (path === '/shutdown') {
    if (!LOCAL && API_TOKEN && bearerToken !== API_TOKEN) { status = '401 Unauthorized'; headersExtra = ['WWW-Authenticate: Bearer']; body = JSON.stringify({ error: 'unauthorized' }); }
    else {
      status = '202 Accepted';
      body = JSON.stringify({ status: 'shutting_down' });
      // defer shutdown slightly to allow response to flush
      setTimeout(() => { try { process.exit(0); } catch {} }, 200);
    }
  }
  else if (path === '/build') {
    if (!LOCAL && API_TOKEN && bearerToken !== API_TOKEN) { status = '401 Unauthorized'; headersExtra = ['WWW-Authenticate: Bearer']; body = JSON.stringify({ error: 'unauthorized' }); }
    else {
      // Basic request body parse (JSON) from reqData
      let reqJson = {};
      try {
        const sep = '\r\n\r\n';
        const idx = reqData.indexOf(sep);
        if (idx >= 0) {
          const b = reqData.substring(idx + sep.length);
          reqJson = JSON.parse(b);
        }
      } catch {}
      // Accept and snapshot intent
      try {
        const snapPath = process.env.AZL_DAEMON_STATUS_PATH || '.azl/daemon_status.json';
        let obj = {};
        try { obj = JSON.parse(fs.readFileSync(snapPath, 'utf8')); } catch {}
        obj.active_builds = obj.active_builds || {};
        const buildId = String(Date.now());
        obj.active_builds[buildId] = { requested_at: Date.now(), spec: reqJson };
        obj.snapshot_ts = Date.now();
        fs.mkdirSync(path.join('.', '.azl'), { recursive: true });
        fs.writeFileSync(snapPath, JSON.stringify(obj));
      } catch {}
      status = '202 Accepted';
      body = JSON.stringify({ status: 'accepted' });
    }
  }
  else if (path === '/events.html') {
    // Simple HTML viewer for /events with token prompt stored in localStorage
    const html = `<!doctype html><html><head><meta charset="utf-8"/><title>AZL Events</title>
<style>body{font-family:system-ui,Segoe UI,Roboto,Ubuntu,Arial,sans-serif;margin:16px;} .ev{padding:6px 8px;border-bottom:1px solid #eee} .ts{color:#666;margin-right:8px} .type{font-weight:600} pre{margin:4px 0;white-space:pre-wrap;word-break:break-word;background:#fafafa;border:1px solid #eee;padding:8px;border-radius:6px}</style>
</head><body>
<h3>AZL Daemon Events</h3>
<div>
  <label>API Token: <input id="tok" type="password" style="width:320px"></label>
  <button id="save">Save</button>
  <button id="refresh">Refresh</button>
</div>
<div id="root"></div>
<script>
const tokEl = document.getElementById('tok');
tokEl.value = localStorage.getItem('azl_api_token') || '';
document.getElementById('save').onclick = () => { localStorage.setItem('azl_api_token', tokEl.value || ''); fetchEv(); };
document.getElementById('refresh').onclick = () => fetchEv();
async function fetchEv(){
  const t = localStorage.getItem('azl_api_token')||'';
  const res = await fetch('/events', { headers: t? { Authorization: 'Bearer '+t } : {} });
  const j = await res.json().catch(()=>({error:'bad_json'}));
  const root = document.getElementById('root');
  root.innerHTML = '';
  if(!j || !Array.isArray(j.events)) { root.textContent = 'No events'; return; }
  for(const ev of j.events){
    const d = document.createElement('div'); d.className='ev';
    const ts = document.createElement('span'); ts.className='ts'; ts.textContent = '['+ev.ts+']';
    const tp = document.createElement('span'); tp.className='type'; tp.textContent = ev.type;
    d.appendChild(ts); d.appendChild(tp);
    if (ev.data) { const pre=document.createElement('pre'); pre.textContent = JSON.stringify(ev.data); d.appendChild(pre);} 
    root.appendChild(d);
  }
}
fetchEv(); setInterval(fetchEv, 3000);
</script>
</body></html>`;
    body = html;
    contentType = 'text/html; charset=utf-8';
  } else { metrics.notFound += 1; status = '404 Not Found'; body = JSON.stringify({ error: 'not found' }); }

        const resp = [
    `HTTP/1.1 ${status}`,
    `Content-Type: ${contentType}`,
    `Content-Length: ${Buffer.byteLength(body)}`,
    ...headersExtra,
          'Connection: close',
          '',
          body
        ].join('\r\n');
  try { await sendSysproxy('write', { fd: conn, data: resp }, 1500); } catch {}
  try { await sendSysproxy('close', { fd: conn }, 600); } catch {}
  recordLatency(path, Date.now() - t0);
  log(`responded ${status} to ${path} and closed conn=${conn}`);
}

async function ensureListening() {
  if (!(mode === 'tcp')) return;
  if (!NODE_HTTP_ENABLED) { sdNotifyReady(); return; }
  listenFd = null;
  try {
    const lr = await sendSysproxy('listen', { host: BIND_HOST, port: PORT, backlog: 256 }, 3000);
    if (lr && lr.ok) {
      listenFd = lr.fd || lr.socket || lr.listenfd;
      log(`listening on ${BIND_HOST}:${PORT} fd=${listenFd}`);
      sdNotifyReady();
      sdNotifyStatusAndWatchdog(`listening on ${BIND_HOST}:${PORT}`);
    } else err(`listen not ok: ${JSON.stringify(lr)}`);
  } catch (e) { err(`listen error: ${e.message}`); }
}

function startAcceptLoops() {
  acceptLoopsStarted = true;
  for (let i = 0; i < acceptWorkers; i++) acceptLoop(i + 1);
}

async function acceptLoop(loopId) {
  try {
    if (!(mode === 'tcp') || !listenFd) { setTimeout(() => acceptLoop(loopId), 50); return; }
    const acc = await sendSysproxy('accept', { socket: listenFd }, 1000);
    if (acc && acc.ok && typeof acc.conn === 'number') {
      handleConn(acc.conn).catch(e => err(`conn err: ${e.message}`));
    }
  } catch {}
  setImmediate(() => acceptLoop(loopId));
}

async function run() {
  log('Starting runtime');
  connectLoop();
}

run().catch(e => { err(`fatal: ${e.message}`); process.exit(1); });

