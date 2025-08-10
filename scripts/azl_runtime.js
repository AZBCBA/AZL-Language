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
  // Open write FIFO (engine.out) in append mode
  const out = fs.createWriteStream(ENGINE_OUT, { flags: 'a' });
  out.on('error', e => err(`engine.out error: ${e.message}`));

  // Open read FIFO (engine.in)
  const inStream = fs.createReadStream(ENGINE_IN, { encoding: 'utf8' });
  inStream.on('error', e => err(`engine.in error: ${e.message}`));

  // Line reader for responses
  const rl = readline.createInterface({ input: inStream });
  rl.on('line', line => {
    if (!line) return;
    // Expect: @sysproxy.response {json}
    const idx = line.indexOf('@sysproxy.response');
    let jsonPart = null;
    if (idx >= 0) {
      jsonPart = line.substring(idx + '@sysproxy.response'.length).trim();
    } else {
      // Engine might deliver raw JSON; try parse anyway
      jsonPart = line.trim();
    }
    try {
      const obj = JSON.parse(jsonPart);
      const id = obj && obj.id;
      if (id && pending.has(id)) {
        const { resolve } = pending.get(id);
        pending.delete(id);
        resolve(obj);
      }
    } catch (e) {
      // Not a JSON response we care about
    }
  });

  return { out };
}

function sendSysproxy(out, op, args = {}) {
  const id = nextId++;
  const payload = { id, op, ...args };
  const line = `@sysproxy ${JSON.stringify(payload)}\n`;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject, ts: Date.now(), op });
    try {
      out.write(line);
    } catch (e) {
      pending.delete(id);
      reject(e);
    }
    // Timeout safeguard
    setTimeout(() => {
      if (pending.has(id)) {
        pending.delete(id);
        reject(new Error(`sysproxy timeout for op=${op} id=${id}`));
      }
    }, 3000);
  });
}

async function run() {
  log(`Starting runtime at ${now()}`);
  // Ensure FIFOs exist
  if (!fs.existsSync(ENGINE_OUT) || !fs.existsSync(ENGINE_IN)) {
    err(`FIFOs not found: ${ENGINE_OUT} / ${ENGINE_IN}`);
    process.exit(2);
  }

  const { out } = openFifos();

  // Boot keepalive
  try {
    const r = await sendSysproxy(out, 'keepalive', {});
    log(`keepalive ok pid=${r && r.pid}`);
  } catch (e) {
    err(`keepalive failed: ${e.message}`);
  }

  // Listen on 0.0.0.0:8080
  let listenFd = null;
  try {
    const listenResp = await sendSysproxy(out, 'listen', { host: '0.0.0.0', port: PORT, backlog: 128 });
    if (listenResp && listenResp.ok) {
      listenFd = listenResp.fd || listenResp.socket || listenResp.listenfd;
      log(`listening on :${PORT} fd=${listenFd}`);
    } else {
      throw new Error(`listen failed ${JSON.stringify(listenResp)}`);
    }
  } catch (e) {
    err(`listen error: ${e.message}`);
    process.exit(3);
  }

  // Accept loop
  async function handleConn() {
    try {
      const acc = await sendSysproxy(out, 'accept', { fd: listenFd });
      if (!acc || !acc.ok) {
        setTimeout(handleConn, 100); // retry
        return;
      }
      const conn = acc.conn;
      log(`accepted conn=${conn}`);

      // For healthz, reply 200 OK regardless of request (simplified HTTP)
      const body = 'OK';
      const resp = [
        'HTTP/1.1 200 OK',
        'Content-Type: text/plain',
        `Content-Length: ${body.length}`,
        'Connection: close',
        '',
        body
      ].join('\r\n');

      await sendSysproxy(out, 'write', { fd: conn, data: resp });
      await sendSysproxy(out, 'close', { fd: conn });
      log(`responded 200 and closed conn=${conn}`);
    } catch (e) {
      err(`accept/write error: ${e.message}`);
    } finally {
      // continue accepting
      setImmediate(handleConn);
    }
  }

  handleConn();
}

run().catch(e => {
  err(`fatal: ${e.message}`);
  process.exit(1);
});

