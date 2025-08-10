#!/usr/bin/env node
/*
  AZL Runtime Executor - Production sysproxy bridge
*/
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const ENGINE_OUT = path.resolve('.azl/engine.out');
const ENGINE_IN = path.resolve('.azl/engine.in');
const PORT = parseInt(process.env.AZL_BUILD_API_PORT || '8080', 10);

let nextId = 1;
const pending = new Map();
let requestCount = 0;
let controlOut = null;
let listenFd = null;

function now() { return new Date().toISOString(); }
function log(msg) { console.log(`[runtime] ${msg}`); }
function err(msg) { console.error(`[runtime:err] ${msg}`); }

function openFifos() {
  controlOut = fs.createWriteStream(ENGINE_OUT, { flags: 'a' });
  controlOut.on('error', e => err(`engine.out error: ${e.message}`));

  const inStream = fs.createReadStream(ENGINE_IN, { encoding: 'utf8' });
  inStream.on('error', e => err(`engine.in error: ${e.message}`));

  const rl = readline.createInterface({ input: inStream });
  rl.on('line', line => onResponseLine(line));
}

function writeLine(op, args = {}) {
  const id = nextId++;
  const payload = { id, op, ...args };
  const line = `@sysproxy ${JSON.stringify(payload)}\n`;
  try { controlOut.write(line); } catch (e) { err(`writeLine failed: ${e.message}`); }
  return id;
}

function sendAndWait(op, args = {}, timeoutMs = 1500) {
  const id = writeLine(op, args);
  return new Promise((resolve, reject) => {
    const to = setTimeout(() => {
      if (pending.has(id)) { pending.delete(id); reject(new Error(`timeout ${op} id=${id}`)); }
    }, timeoutMs);
    pending.set(id, { resolve: (val) => { clearTimeout(to); resolve(val); }, reject, ts: Date.now(), op });
  });
}

async function handleConn(conn) {
  let firstLine = '';
  try {
    const req = await sendAndWait('read', { fd: conn, max: 8192 }, 1000);
    const raw = req && typeof req.data === 'string' ? req.data : '';
    firstLine = raw.split('\r\n', 1)[0] || '';
  } catch {}

  // Parse path
  let path = '/';
  const m = /^([A-Z]+)\s+([^\s]+)\s+HTTP\//.exec(firstLine);
  if (m) path = m[2];
  requestCount++;

  // Route
  let status = 200;
  let bodyObj;
  if (path === '/healthz') {
    bodyObj = { status: 'healthy', ts: now() };
  } else if (path === '/readyz') {
    bodyObj = { status: 'ready', ts: now() };
  } else if (path === '/status') {
    bodyObj = { status: 'ok', requests: requestCount, port: PORT, ts: now() };
  } else {
    status = 404;
    bodyObj = { error: 'Not Found', path };
  }
  const body = JSON.stringify(bodyObj);
  const resp = [
    `HTTP/1.1 ${status} ${status === 200 ? 'OK' : 'Not Found'}`,
    'Content-Type: application/json',
    `Content-Length: ${Buffer.byteLength(body)}`,
    'Connection: close',
    '',
    body
  ].join('\r\n');

  try { await sendAndWait('write', { fd: conn, data: resp }, 1500); } catch (e) { err(`write error: ${e.message}`); }
  try { await sendAndWait('close', { fd: conn }, 800); } catch (e) { err(`close error: ${e.message}`); }
  log(`served ${path} status=${status} conn=${conn}`);
}

function onResponseLine(line) {
  if (!line) return;
  const idx = line.indexOf('@sysproxy.response');
  const jsonPart = idx >= 0 ? line.substring(idx + '@sysproxy.response'.length).trim() : line.trim();
  let obj;
  try { obj = JSON.parse(jsonPart); } catch { return; }
  const id = obj && obj.id;
  if (obj && typeof obj.conn === 'number') {
    handleConn(obj.conn);
    return;
  }
  if (id && pending.has(id)) {
    const { resolve } = pending.get(id);
    pending.delete(id);
    resolve(obj);
  }
}

async function run() {
  log(`Starting runtime at ${now()}`);
  if (!fs.existsSync(ENGINE_OUT) || !fs.existsSync(ENGINE_IN)) {
    err(`FIFOs not found`);
    process.exit(2);
  }
  openFifos();

  try { const r = await sendAndWait('keepalive', {}); log(`keepalive ok pid=${r && r.pid}`); } catch {}

  try {
    const lr = await sendAndWait('listen', { host: '0.0.0.0', port: PORT, backlog: 128 });
    if (lr && lr.ok) { listenFd = lr.fd || lr.socket || lr.listenfd; log(`listening on :${PORT} fd=${listenFd}`); }
  } catch {}
  if (!listenFd) { setTimeout(() => process.exit(3), 2000); return; }

  // Fire-and-forget accept pollers
  setInterval(() => writeLine('accept', { socket: listenFd }), 5);
}

run().catch(e => { err(`fatal: ${e.message}`); process.exit(1); });

