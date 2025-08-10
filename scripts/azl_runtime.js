#!/usr/bin/env node
/*
  AZL Runtime Executor - Production sysproxy bridge
  - Opens engine.out (FIFO) for @sysproxy writes
  - Opens engine.in (FIFO) to receive @sysproxy.response lines
  - Performs listen/accept over sysproxy, responds 200 OK to healthz
*/
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const ENGINE_OUT = path.resolve('.azl/engine.out');
const ENGINE_IN = path.resolve('.azl/engine.in');
const PORT = parseInt(process.env.AZL_BUILD_API_PORT || '8080', 10);

let nextId = 1;
const pending = new Map();

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
    const idx = line.indexOf('@sysproxy.response');
    const jsonPart = idx >= 0 ? line.substring(idx + '@sysproxy.response'.length).trim() : line.trim();
    try {
      const obj = JSON.parse(jsonPart);
      const id = obj && obj.id;
      if (obj && typeof obj.conn === 'number') {
        handleConn(out, obj.conn).catch(e => err(`conn err: ${e.message}`));
        return;
      }
      if (id && pending.has(id)) {
        const { resolve } = pending.get(id);
        pending.delete(id);
        resolve(obj);
      }
    } catch {}
  });

  return { out };
}

function sendSysproxy(out, op, args = {}, timeoutMs = 1500) {
  const id = nextId++;
  const payload = { id, op, ...args };
  const line = `@sysproxy ${JSON.stringify(payload)}\n`;
  try { out.write(line); } catch (e) { err(`write failed: ${e.message}`); }
  return new Promise((resolve, reject) => {
    const to = setTimeout(() => {
      if (pending.has(id)) { pending.delete(id); reject(new Error(`timeout ${op} id=${id}`)); }
    }, timeoutMs);
    pending.set(id, { resolve: (val) => { clearTimeout(to); resolve(val); }, reject, ts: Date.now(), op });
  });
}

async function handleConn(out, conn) {
  try { await sendSysproxy(out, 'read', { fd: conn, max: 8192 }, 800); } catch {}
  const body = 'OK';
  const resp = [
    'HTTP/1.1 200 OK',
    'Content-Type: text/plain',
    `Content-Length: ${body.length}`,
    'Connection: close',
    '',
    body
  ].join('\r\n');
  try { await sendSysproxy(out, 'write', { fd: conn, data: resp }, 1000); } catch {}
  try { await sendSysproxy(out, 'close', { fd: conn }, 600); } catch {}
  log(`responded 200 and closed conn=${conn}`);
}

async function run() {
  log('Starting runtime');
  if (!fs.existsSync(ENGINE_OUT) || !fs.existsSync(ENGINE_IN)) {
    err('FIFOs not found');
    process.exit(2);
  }

  const { out } = openFifos();

  try { const r = await sendSysproxy(out, 'keepalive', {}); log(`keepalive ok pid=${r && r.pid}`); } catch (e) { err(`keepalive failed: ${e.message}`); }

  let listenFd = null;
  try {
    const lr = await sendSysproxy(out, 'listen', { host: '0.0.0.0', port: PORT, backlog: 128 }, 2000);
    if (lr && lr.ok) { listenFd = lr.fd || lr.socket || lr.listenfd; log(`listening on :${PORT} fd=${listenFd}`); }
  } catch (e) { err(`listen error: ${e.message}`); }
  if (!listenFd) { setTimeout(() => process.exit(3), 1500); return; }

  async function acceptLoop(loopId) {
    try {
      const acc = await sendSysproxy(out, 'accept', { socket: listenFd }, 1000);
      if (acc && acc.ok && typeof acc.conn === 'number') {
        handleConn(out, acc.conn).catch(e => err(`conn err: ${e.message}`));
      }
    } catch {}
    setTimeout(() => acceptLoop(loopId), 5);
  }

  for (let i = 0; i < 4; i++) acceptLoop(i + 1);
}

run().catch(e => { err(`fatal: ${e.message}`); process.exit(1); });

