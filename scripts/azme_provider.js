#!/usr/bin/env node
// AZME Provider HTTP server (AnythingLLM/OpenAI-compatible) with GPU backend forwarding
// Ports: default 5000 (AZME_PROVIDER_PORT)
// Backends:
// - OpenAI-compatible (e.g., vLLM): set AZME_OPENAI_BASE_URL and optional AZME_OPENAI_API_KEY
// - Ollama: set AZME_OLLAMA_URL (default http://127.0.0.1:11434)
// Select via AZME_BACKEND=openai|ollama (auto-detects if not set)

const http = require('http');
const https = require('https');
const url = require('url');

const PORT = parseInt(process.env.AZME_PROVIDER_PORT || '5000', 10);
const MAX_BYTES = parseInt(process.env.AZME_PROVIDER_MAX_BYTES || process.env.AZL_HTTP_MAX_REQUEST_SIZE || '7340032', 10); // 7MB default

const OPENAI_BASE = (process.env.AZME_OPENAI_BASE_URL || '').trim();
const OPENAI_KEY = (process.env.AZME_OPENAI_API_KEY || '').trim();
const OLLAMA_URL = (process.env.AZME_OLLAMA_URL || 'http://127.0.0.1:11434').trim();
const DEFAULT_MODEL = (process.env.AZME_MODEL || 'llama3:latest').trim();
const BACKEND = (process.env.AZME_BACKEND || (OPENAI_BASE ? 'openai' : (OLLAMA_URL ? 'ollama' : 'none'))).toLowerCase();

function json(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}
function text(res, code, body, contentType = 'text/plain; charset=utf-8') {
  res.writeHead(code, { 'Content-Type': contentType, 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}
function notFound(res) { json(res, 404, { error: 'not found' }); }

function parseBody(req, res) {
  return new Promise((resolve) => {
    let size = 0;
    const chunks = [];
    let tooLarge = false;
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BYTES) { tooLarge = true; }
      else chunks.push(c);
    });
    req.on('end', () => {
      if (tooLarge) {
        res.writeHead(413);
        res.end();
        return resolve(null);
      }
      const data = Buffer.concat(chunks).toString('utf8');
      try { resolve(data ? JSON.parse(data) : {}); } catch { resolve({}); }
    });
    req.on('error', () => resolve({}));
  });
}

function httpJson(method, base, pathname, body, headers = {}) {
  return new Promise((resolve) => {
    let u;
    try { u = new url.URL(pathname, base); } catch { return resolve({ ok: false, status: 500, body: { error: 'bad_url' } }); }
    const isHttps = u.protocol === 'https:';
    const opts = {
      method,
      hostname: u.hostname,
      port: u.port ? Number(u.port) : (isHttps ? 443 : 80),
      path: u.pathname + (u.search || ''),
      headers: { 'Content-Type': 'application/json', ...headers },
      timeout: 60_000,
    };
    const req = (isHttps ? https : http).request(opts, (r) => {
      const arr = [];
      r.on('data', (c) => arr.push(c));
      r.on('end', () => {
        const buf = Buffer.concat(arr).toString('utf8');
        let parsed = null;
        try { parsed = buf ? JSON.parse(buf) : {}; } catch { parsed = { raw: buf }; }
        resolve({ ok: (r.statusCode >= 200 && r.statusCode < 300), status: r.statusCode || 0, headers: r.headers, body: parsed });
      });
    });
    req.on('error', () => resolve({ ok: false, status: 502, body: { error: 'upstream_error' } }));
    try { if (body != null) req.write(JSON.stringify(body)); } catch {}
    req.end();
  });
}

// OpenAI-compatible helpers
async function openaiListModels() {
  if (!OPENAI_BASE) return { object: 'list', data: [] };
  const h = OPENAI_KEY ? { Authorization: `Bearer ${OPENAI_KEY}` } : {};
  const r = await httpJson('GET', OPENAI_BASE, '/v1/models', null, h);
  if (!r.ok && r.status === 404) return { object: 'list', data: [] };
  return r.body || { object: 'list', data: [] };
}
async function openaiChatCompletions(payload) {
  const h = OPENAI_KEY ? { Authorization: `Bearer ${OPENAI_KEY}` } : {};
  return httpJson('POST', OPENAI_BASE, '/v1/chat/completions', payload, h);
}
async function openaiEmbeddings(payload) {
  const h = OPENAI_KEY ? { Authorization: `Bearer ${OPENAI_KEY}` } : {};
  return httpJson('POST', OPENAI_BASE, '/v1/embeddings', payload, h);
}

// Ollama helpers
async function ollamaListModels() {
  const r = await httpJson('GET', OLLAMA_URL, '/api/tags', null, {});
  if (!r.ok) return { models: [] };
  // Normalize to OpenAI-like list
  const data = r.body || {};
  const out = Array.isArray(data.models) ? data.models.map((m) => ({ id: `azme-${m.name}`, object: 'model', owned_by: 'ollama' })) : [];
  return { object: 'list', data: out };
}
function buildPromptFromMessages(messages) {
  if (!Array.isArray(messages)) return '';
  return messages.map((m) => `${m.role || 'user'}: ${String(m.content || '')}`).join('\n');
}
async function ollamaChatCompletions(body) {
  const model = (body.model || DEFAULT_MODEL).replace(/^azme-/, '');
  const prompt = body.messages ? buildPromptFromMessages(body.messages) : (body.prompt || '');
  const options = (body.temperature || body.top_p || body.max_tokens) ? {
    temperature: body.temperature,
    top_p: body.top_p,
    num_predict: body.max_tokens,
  } : undefined;
  const r = await httpJson('POST', OLLAMA_URL, '/api/generate', { model, prompt, stream: false, options }, {});
  if (!r.ok) return r;
  const text = (r.body && (r.body.response || r.body.message || r.body.text)) || '';
  return {
    ok: true,
    status: 200,
    body: {
      id: 'chatcmpl_' + Math.random().toString(36).slice(2),
      object: 'chat.completion',
      created: Math.floor(Date.now() / 1000),
      model: `azme-${model}`,
      choices: [{ index: 0, message: { role: 'assistant', content: text }, finish_reason: 'stop' }],
    }
  };
}
async function ollamaEmbeddings(body) {
  const model = (body.model || DEFAULT_MODEL).replace(/^azme-/, '');
  const input = Array.isArray(body.input) ? body.input.join('\n') : String(body.input || '');
  const r = await httpJson('POST', OLLAMA_URL, '/api/embeddings', { model, prompt: input }, {});
  if (!r.ok) return r;
  const vec = (r.body && r.body.embedding) || [];
  return { ok: true, status: 200, body: { data: [{ embedding: vec, index: 0 }], model: `azme-${model}`, object: 'list' } };
}

// Simple metrics
const METRICS = { total: 0, health: 0, models: 0, modelDetail: 0, chat: 0, embeddings: 0, completions: 0 };

const server = http.createServer(async (req, res) => {
  METRICS.total += 1;
  const { pathname } = url.parse(req.url || '/', true);
  if (req.method === 'GET' && pathname === '/health') {
    METRICS.health += 1;
    return json(res, 200, { status: 'ok', backend: BACKEND });
  }
  if (req.method === 'GET' && pathname === '/metrics') {
    const lines = [
      '# HELP azme_provider_requests_total Total requests',
      '# TYPE azme_provider_requests_total counter',
      `azme_provider_requests_total ${METRICS.total}`,
      '# HELP azme_provider_requests_by_route Total requests by route',
      '# TYPE azme_provider_requests_by_route counter',
      `azme_provider_requests_by_route{route="/health"} ${METRICS.health}`,
      `azme_provider_requests_by_route{route="/v1/models"} ${METRICS.models}`,
      `azme_provider_requests_by_route{route="/v1/models/:id"} ${METRICS.modelDetail}`,
      `azme_provider_requests_by_route{route="/v1/chat/completions"} ${METRICS.chat}`,
      `azme_provider_requests_by_route{route="/v1/embeddings"} ${METRICS.embeddings}`,
      `azme_provider_requests_by_route{route="/v1/completions"} ${METRICS.completions}`,
    ].join('\n');
    return text(res, 200, lines, 'text/plain; version=0.0.4');
  }
  if (req.method === 'GET' && pathname === '/v1/models') {
    METRICS.models += 1;
    if (BACKEND === 'openai') {
      const out = await openaiListModels().catch(() => ({ object: 'list', data: [] }));
      return json(res, 200, out);
    }
    if (BACKEND === 'ollama') {
      const out = await ollamaListModels().catch(() => ({ object: 'list', data: [] }));
      return json(res, 200, out);
    }
    // Fallback static
    return json(res, 200, { object: 'list', data: [{ id: 'azme-gpu-model', object: 'model' }] });
  }
  if (req.method === 'GET' && pathname.startsWith('/v1/models/')) {
    METRICS.modelDetail += 1;
    const id = decodeURIComponent(pathname.substring('/v1/models/'.length));
    return json(res, 200, { id, object: 'model', owned_by: BACKEND || 'azme' });
  }
  if (req.method === 'POST' && pathname === '/v1/chat/completions') {
    METRICS.chat += 1;
    const body = await parseBody(req, res); if (body === null) return; // 413 already sent
    try {
      if (BACKEND === 'openai') {
        const r = await openaiChatCompletions(body);
        return json(res, r.status || 500, r.body || { error: 'upstream_error' });
      }
      if (BACKEND === 'ollama') {
        const r = await ollamaChatCompletions(body);
        return json(res, r.status || 500, r.body || { error: 'upstream_error' });
      }
      return json(res, 500, { error: 'no_backend_configured' });
    } catch (e) {
      return json(res, 502, { error: 'backend_failure', detail: String(e && e.message || e) });
    }
  }
  if (req.method === 'POST' && pathname === '/v1/embeddings') {
    METRICS.embeddings += 1;
    const body = await parseBody(req, res); if (body === null) return;
    try {
      if (BACKEND === 'openai') {
        const r = await openaiEmbeddings(body);
        return json(res, r.status || 500, r.body || { error: 'upstream_error' });
      }
      if (BACKEND === 'ollama') {
        const r = await ollamaEmbeddings(body);
        return json(res, r.status || 500, r.body || { error: 'upstream_error' });
      }
      return json(res, 500, { error: 'no_backend_configured' });
    } catch (e) {
      return json(res, 502, { error: 'backend_failure', detail: String(e && e.message || e) });
    }
  }
  // Legacy text completions (optional): map to chat
  if (req.method === 'POST' && pathname === '/v1/completions') {
    METRICS.completions += 1;
    const body = await parseBody(req, res); if (body === null) return;
    const prompt = String(body.prompt || '');
    const mapped = { model: body.model || DEFAULT_MODEL, messages: [{ role: 'user', content: prompt }], max_tokens: body.max_tokens, temperature: body.temperature, top_p: body.top_p };
    try {
      if (BACKEND === 'openai') {
        const r = await openaiChatCompletions(mapped);
        return json(res, r.status || 500, r.body || { error: 'upstream_error' });
      }
      if (BACKEND === 'ollama') {
        const r = await ollamaChatCompletions(mapped);
        return json(res, r.status || 500, r.body || { error: 'upstream_error' });
      }
      return json(res, 500, { error: 'no_backend_configured' });
    } catch (e) {
      return json(res, 502, { error: 'backend_failure', detail: String(e && e.message || e) });
    }
  }
  return notFound(res);
});

server.listen(PORT, '127.0.0.1', () => {
  // eslint-disable-next-line no-console
  console.log(`[azme-provider] listening on 127.0.0.1:${PORT} backend=${BACKEND}${BACKEND==='openai' ? ` base=${OPENAI_BASE}` : (BACKEND==='ollama' ? ` base=${OLLAMA_URL}` : '')}`);
});

server.on('error', (e) => {
  console.error(`[azme-provider] server error: ${e && e.message ? e.message : e}`);
  process.exit(1);
});

process.on('uncaughtException', (e) => {
  console.error(`[azme-provider] uncaught: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
});
process.on('unhandledRejection', (e) => {
  console.error(`[azme-provider] unhandled: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
});


 