#!/usr/bin/env node
/*
  AZL Runtime Executor - Production sysproxy bridge
  - Opens engine.out (FIFO) for @sysproxy writes
  - Opens engine.in (FIFO) to receive @sysproxy.response lines
  - Performs listen/accept over sysproxy, responds 200 OK to healthz
  - Robust logging and error handling
*/
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const ENGINE_OUT = path.resolve('.azl/engine.out');
const ENGINE_IN = path.resolve('.azl/engine.in');
const PORT = parseInt(process.env.AZL_BUILD_API_PORT || '8080', 10);

let nextId = 1;
const pending = new Map();

function now() { return new Date().toISOString(); }

function log(msg) { console.log(`[runtime] ${msg}`); }
function err(msg) { console.error(`[runtime:err] ${msg}`); }

function openFifos() {
  const out = fs.createWriteStream(ENGINE_OUT, { flags: 'a' });
  out.on('error', e => err(`engine.out error: ${e.message}`));

  const inStream = fs.createReadStream(ENGINE_IN, { encoding: 'utf8' });
  inStream.on('error', e => err(`engine.in error: ${e.message}`));

  const rl = readline.createInterface({ input: inStream });
  rl.on('line', line => {
    if (!line) return;
    log(`resp line: ${line}`);
    const idx = line.indexOf('@sysproxy.response');
    let jsonPart = idx >= 0 ? line.substring(idx + '@sysproxy.response'.length).trim() : line.trim();
    try {
      const obj = JSON.parse(jsonPart);
      log(`resp json: ${JSON.stringify(obj)}`);
      const id = obj && obj.id;
      if (id && pending.has(id)) {
        const { resolve } = pending.get(id);
        pending.delete(id);
        resolve(obj);
      }
    } catch (e) {
      err(`resp parse error: ${e.message}`);
    }
  });

  return { out };
}

function sendSysproxy(out, op, args = {}, timeoutMs) {
  const id = nextId++;
  const payload = { id, op, ...args };
  const line = `@sysproxy ${JSON.stringify(payload)}\n`;
  log(`send ${line.trim()}`);
  return new Promise((resolve, reject) => {
    const effectiveTimeout = (timeoutMs !== undefined)
      ? timeoutMs
      : (op === 'accept' ? 0 : (op === 'read' ? 5000 : 2000));
    let to = null;
    if (effectiveTimeout > 0) {
      to = setTimeout(() => {
        if (pending.has(id)) {
          pending.delete(id);
          reject(new Error(`sysproxy timeout for op=${op} id=${id}`));
        }
      }, effectiveTimeout);
    }
    pending.set(id, { resolve: (val) => { if (to) clearTimeout(to); resolve(val); }, reject, ts: Date.now(), op });
    try { out.write(line); } catch (e) { if (to) clearTimeout(to); pending.delete(id); reject(e); }
  });
}

async function run() {
  log(`Starting runtime at ${now()}`);
  if (!fs.existsSync(ENGINE_OUT) || !fs.existsSync(ENGINE_IN)) {
    err(`FIFOs not found: ${ENGINE_OUT} / ${ENGINE_IN}`);
    process.exit(2);
  }

  const { out } = openFifos();

  try { const r = await sendSysproxy(out, 'keepalive', {}, 2000); log(`keepalive ok pid=${r && r.pid}`); } catch {}

  let listenFd = null;
  try {
    const listenResp = await sendSysproxy(out, 'listen', { host: '0.0.0.0', port: PORT, backlog: 128 }, 3000);
    log(`listenResp raw: ${JSON.stringify(listenResp)}`);
    if (listenResp && listenResp.ok) { listenFd = listenResp.fd || listenResp.socket || listenResp.listenfd; log(`listening on :${PORT} fd=${listenFd}`); }
  } catch {}
  if (!listenFd) { setTimeout(() => process.exit(3), 2000); return; }

  async function acceptLoop(loopId) {
    try {
      const acc = await sendSysproxy(out, 'accept', { socket: listenFd }, 0);
      if (acc && acc.ok && acc.conn != null) {
        const conn = acc.conn;
        log(`accepted conn=${conn} (loop=${loopId})`);
        // Read once to consume request
        try { await sendSysproxy(out, 'read', { fd: conn, max: 8192 }, 5000); } catch {}
        const body = 'OK';
        const resp = [ 'HTTP/1.1 200 OK', 'Content-Type: text/plain', `Content-Length: ${body.length}`, 'Connection: close', '', body ].join('\r\n');
        await sendSysproxy(out, 'write', { fd: conn, data: resp }, 3000);
        await sendSysproxy(out, 'close', { fd: conn }, 2000);
        log(`responded 200 and closed conn=${conn} (loop=${loopId})`);
        setImmediate(() => acceptLoop(loopId));
      } else {
        setTimeout(() => acceptLoop(loopId), 5);
      }
    } catch (e) {
      err(`accept loop error: ${e.message} (loop=${loopId})`);
      setTimeout(() => acceptLoop(loopId), 20);
    }
  }

  acceptLoop(1);
}

run().catch(e => { err(`fatal: ${e.message}`); process.exit(1); });

