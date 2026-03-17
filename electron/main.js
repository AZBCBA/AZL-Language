const Ajv = require('ajv');
const { app, BrowserWindow, ipcMain, dialog, Tray, Menu, nativeImage, session, crashReporter } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');

// IPC channel allowlist registry
const ALLOWED_IPC_CHANNELS = new Set([
  'setMode','getSettings','updateSetting','resetSettings','exportSettings','importSettings',
  'getRuntimeConfig','tokenProxy',
  'listTrainingPlugins','enableTrainingPlugin','disableTrainingPlugin','getPluginStatus',
  'systemctl','serviceAction','status','healthz','healthAll',
  'startAdvancedTraining','stopTraining','getTrainingStatus','updateTrainingConfig',
  'pauseTraining','resumeTraining','startParallelTraining','getParallelTrainingStatus',
  'metrics.start','metrics.stop','getMetrics','attemptRecovery',
  'maintenance.set','maintenance.get',
  'start','stop','readLogs','readAllLogs','handleMenuAction'
]);

// Guard unknown channels (dev defense-in-depth): wrap ipcMain.handle to assert allowlist
function guardedHandle(channel, listener) {
  if (!ALLOWED_IPC_CHANNELS.has(channel)) {
    logWarn('Attempt to register non-allowlisted IPC channel', { channel });
    if (process.env.NODE_ENV === 'production') return; // refuse in production
  }
  return ipcMain.handle(channel, listener);
}

// Ajv validator setup
const ajv = new Ajv({ allErrors: true, useDefaults: true, coerceTypes: true, removeAdditional: 'failing' });
const schemas = {
  tokenProxy: ajv.compile({ type: 'object', properties: { path: { type: 'string' }, token: { type: 'string', nullable: true }, method: { type: 'string', enum: ['GET','POST','PUT','DELETE','PATCH','HEAD','OPTIONS'], nullable: true }, body: {}, timeoutSec: { type: 'integer', minimum: 1, maximum: 60, nullable: true } }, required: ['path'], additionalProperties: false }),
  updateTrainingConfig: ajv.compile({ type: 'object', properties: { token: { type: 'string', nullable: true }, device: { type: 'string', enum: ['cpu','cuda'], nullable: true }, gpu_limit: { type: 'integer', minimum: 0, maximum: 100, nullable: true }, epochs: { type: 'integer', minimum: 1, maximum: 100000, nullable: true }, batch_size: { type: 'integer', minimum: 1, maximum: 1000000, nullable: true }, mode: { type: 'string', nullable: true } }, additionalProperties: false }),
  startAdvancedTraining: ajv.compile({ type: 'object', properties: { dataset_path: { type: 'string' }, device: { type: 'string', enum: ['cpu','cuda'] }, epochs: { type: 'integer', minimum: 1, maximum: 100000 }, batch_size: { type: 'integer', minimum: 1, maximum: 1000000 }, gpu_limit: { type: 'integer', minimum: 0, maximum: 100, nullable: true }, mode: { type: 'string', nullable: true }, token: { type: 'string', nullable: true } }, required: ['dataset_path','device','epochs','batch_size'], additionalProperties: false }),
  serviceAction: ajv.compile({ type: 'object', properties: { target: { type: 'string', enum: ['runtime','sysproxy','provider','proxy','all'] }, action: { type: 'string', enum: ['start','stop','restart','enable','disable','status'] } }, required: ['target','action'], additionalProperties: false }),
  maintenanceSet: ajv.compile({ type: 'object', properties: { enabled: { type: 'boolean' } }, required: ['enabled'], additionalProperties: false }),
  metricsStart: ajv.compile({ type: 'object', properties: { intervalMs: { type: 'integer', minimum: 500, maximum: 60000, nullable: true }, detailed: { type: 'boolean', nullable: true }, token: { type: 'string', nullable: true } }, additionalProperties: false }),
  getMetrics: ajv.compile({ type: 'object', properties: { detailed: { type: 'boolean', nullable: true }, token: { type: 'string', nullable: true } }, additionalProperties: false }),
  readAllLogs: ajv.compile({ type: 'string', enum: ['runtimeOut','runtimeErr','providerOut','providerErr','proxyOut','proxyErr','sysproxyLog'] })
};
// (moved Electron/Node requires to top to ensure ipcMain is initialized before use)

// Import new services
const SettingsManager = require('./settings');
const AutoUpdateService = require('./auto-updater');
const ProcessMonitor = require('./process-monitor');
const ShortcutsManager = require('./shortcuts');

let mainWindow;
let tray;
let userMode = false; // false = system mode (systemd), true = app/user mode
let procs = { daemonRunner: null };

// Initialize services
let settingsManager;
let autoUpdateService;
let processMonitor;
let shortcutsManager;

// Runtime API target
const RUNTIME_HOST = process.env.AZL_HOST || '127.0.0.1';
const RUNTIME_PORT = parseInt(process.env.AZL_PORT || process.env.AZL_BUILD_API_PORT || '8080', 10);
const PROVIDER_PORT = parseInt(process.env.AZL_PROVIDER_PORT || '5000', 10);
const PROXY_PORT = parseInt(process.env.AZL_PROXY_PORT || '5001', 10);
const RUNTIME_BASE = `http://${RUNTIME_HOST}:${RUNTIME_PORT}`;
// Provider and proxy ports
// (deduped above)

// Live metrics state per window for real-time dashboard
const metricsIntervals = new Map(); // windowId -> interval handle
const metricsBaselines = new Map(); // windowId -> baseline snapshot for improvements
const autoMaintenanceByWindow = new Map(); // windowId -> { enabled: boolean, lastActionTs: number }

const DEFAULT_PEAK_MEM_GB_MAX = Number.isFinite(parseFloat(process.env.AZL_PEAK_MEM_MAX_GB))
  ? parseFloat(process.env.AZL_PEAK_MEM_MAX_GB)
  : 16.0;

// ================== Centralized Logging & Crash Reporting ==================
const LOG_DIR = () => path.join(app.getPath('userData'), 'logs');
const MAIN_LOG = () => path.join(LOG_DIR(), 'main.log');
const ERROR_LOG = () => path.join(LOG_DIR(), 'error.log');

function ensureLogDirExists() {
  try { fs.mkdirSync(LOG_DIR(), { recursive: true }); } catch {}
}

function rotateIfLarge(filePath, maxBytes = 10 * 1024 * 1024) {
  try {
    if (fs.existsSync(filePath)) {
      const st = fs.statSync(filePath);
      if (st.size > maxBytes) {
        const rotated = filePath + '.' + new Date().toISOString().replace(/[:.]/g, '-');
        fs.renameSync(filePath, rotated);
      }
    }
  } catch {}
}

function writeLog(level, message, details = undefined) {
  try {
    ensureLogDirExists();
    const entry = {
      timestamp: new Date().toISOString(),
      level,
      message,
      details: details === undefined ? undefined : details
    };
    const line = JSON.stringify(entry) + os.EOL;
    rotateIfLarge(MAIN_LOG());
    fs.appendFileSync(MAIN_LOG(), line);
    if (level === 'error' || level === 'fatal') {
      rotateIfLarge(ERROR_LOG());
      fs.appendFileSync(ERROR_LOG(), line);
    }
  } catch {}
}

function logInfo(msg, details) { writeLog('info', msg, details); }
function logWarn(msg, details) { writeLog('warn', msg, details); }
function logError(msg, details) { writeLog('error', msg, details); }

function startCrashReporter() {
  try {
    crashReporter.start({
      productName: 'AZL Desktop',
      companyName: 'AZL',
      submitURL: process.env.AZL_CRASH_URL || '',
      uploadToServer: Boolean(process.env.AZL_CRASH_URL),
      compress: true,
      extra: {
        version: app.getVersion(),
        userMode: String(userMode)
      }
    });
    logInfo('CrashReporter started', { uploadToServer: Boolean(process.env.AZL_CRASH_URL) });
  } catch (e) {
    logWarn('CrashReporter failed to start', { error: String(e && e.message || e) });
  }
}

// Uncaught error guards
process.on('uncaughtException', (err) => {
  const info = { message: String(err && err.message || err), stack: String(err && err.stack || '') };
  logError('uncaughtException', info);
});
process.on('unhandledRejection', (reason) => {
  const info = { reason: String(reason && reason.message || reason), stack: String(reason && reason.stack || '') };
  logError('unhandledRejection', info);
});

// ================== Security Hardening ==================
let autoRecoveryEnabled = true;
let rendererCrashWindowIdToHistory = new Map(); // windowId -> timestamps array

function attachWebContentsGuards(win) {
  try {
    const wc = win.webContents;
    wc.setWindowOpenHandler(() => ({ action: 'deny' }));
    wc.on('render-process-gone', (_e, details) => {
      logError('render-process-gone', { reason: details && details.reason, exitCode: details && details.exitCode });
      const id = wc.id;
      const nowTs = Date.now();
      const arr = rendererCrashWindowIdToHistory.get(id) || [];
      arr.push(nowTs);
      // keep only last minute
      const recent = arr.filter(ts => nowTs - ts < 60_000);
      rendererCrashWindowIdToHistory.set(id, recent);
      const tooManyCrashes = recent.length >= 3;
      if (autoRecoveryEnabled && !tooManyCrashes) {
        try { win.reload(); } catch {}
      } else {
        dialog.showMessageBox({
          type: 'error',
          title: 'Renderer Crash',
          message: 'The renderer process crashed. Auto-recovery is disabled or too many crashes occurred. Please restart the app.',
          noLink: true
        }).catch(() => {});
      }
    });
    wc.on('unresponsive', () => {
      logWarn('renderer-unresponsive', { id: wc.id });
    });
  } catch {}
}

function installPermissionHandlers() {
  try {
    const ses = session.defaultSession;
    if (!ses) return;
    // Proactively check permissions before request surfaces
    try {
      ses.setPermissionCheckHandler((_wb, permission, _origin, _details) => {
        const allowlist = (settingsManager && Array.isArray(settingsManager.get('security.permissionAllowlist'))) ? new Set(settingsManager.get('security.permissionAllowlist')) : new Set();
        return allowlist.has(permission);
      });
    } catch {}
    ses.setPermissionRequestHandler((webContents, permission, callback, details) => {
      // Deny all by default; use settings allowlist
      const allowlist = (settingsManager && Array.isArray(settingsManager.get('security.permissionAllowlist'))) ? new Set(settingsManager.get('security.permissionAllowlist')) : new Set();
      const decision = allowlist.has(permission);
      logInfo('permission-request', { url: details && details.requestingUrl, permission, decided: decision });
      try { callback(decision); } catch {}
    });
  } catch (e) {
    logWarn('Failed to install permission handler', { error: String(e && e.message || e) });
  }
}

function parsePinsFromEnv() {
  // Expect AZL_CERT_PINS as JSON: { "host": [ "sha256/base64 spki", ... ] }
  try {
    const raw = process.env.AZL_CERT_PINS || '';
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object') return parsed;
  } catch (e) {
    logWarn('Invalid AZL_CERT_PINS JSON', { error: String(e && e.message || e) });
  }
  return null;
}

function spkiSha256Base64FromCertData(pemOrDerBuffer) {
  try {
    const x509 = new crypto.X509Certificate(pemOrDerBuffer);
    const spkiDer = x509.publicKey.export({ type: 'spki', format: 'der' });
    const hash = crypto.createHash('sha256').update(spkiDer).digest('base64');
    return hash;
  } catch (e) {
    return null;
  }
}

function installCertificatePinning() {
  const pins = (settingsManager && settingsManager.get('tls.pins')) || parsePinsFromEnv();
  const enabled = (settingsManager && settingsManager.get('tls.pinningEnabled') === true) || process.env.AZL_CERT_PINNING === '1' || process.env.NODE_ENV === 'production';
  if (!enabled || !pins) {
    logInfo('Certificate pinning disabled or no pins configured', { enabled, hasPins: Boolean(pins) });
    return;
  }
  try {
    const ses = session.defaultSession;
    if (!ses) return;
    ses.setCertificateVerifyProc((request, callback) => {
      try {
        const { hostname, certificate, validatedCertificateChain } = request;
        const hostPins = pins[hostname] || pins['*'] || [];
        if (!Array.isArray(hostPins) || hostPins.length === 0) {
          // Reject connections to pinned-only hosts list if wildcard not provided
          logWarn('No pins for host; rejecting TLS', { hostname });
          return callback(-2); // net::ERR_FAILED
        }
        const chain = Array.isArray(validatedCertificateChain) && validatedCertificateChain.length > 0
          ? validatedCertificateChain
          : (certificate ? [certificate] : []);
        const spkiCandidates = [];
        for (const cert of chain) {
          const spki = spkiSha256Base64FromCertData(cert.data);
          if (spki) spkiCandidates.push(spki);
        }
        const match = spkiCandidates.some(h => hostPins.includes(h));
        if (!match) {
          logError('Certificate pinning mismatch', { hostname, spkiCandidates });
          return callback(-2);
        }
        return callback(0); // OK
      } catch (e) {
        logError('Certificate verify proc exception', { error: String(e && e.message || e) });
        return callback(-2);
      }
    });
    logInfo('Certificate pinning installed', { pinnedHosts: Object.keys(pins) });
  } catch (e) {
    logWarn('Failed to install certificate pinning', { error: String(e && e.message || e) });
  }
}

function installCspHeaders() {
  try {
    const ses = session.defaultSession;
    if (!ses) return;
    // Block unexpected external requests early
    try {
      ses.webRequest.onBeforeRequest((details, callback) => {
        try {
          const url = details.url || '';
          const allowConnect = (settingsManager && settingsManager.get('security.csp.policy')) || '';
          // Naive allowlist: always allow file:// and our localhost targets
          const allow = url.startsWith('file://') || url.startsWith('devtools://') || url.startsWith(`http://${RUNTIME_HOST}:${RUNTIME_PORT}`) || url.startsWith(`http://127.0.0.1:${PROVIDER_PORT}`) || url.startsWith(`http://127.0.0.1:${PROXY_PORT}`);
          if (!allow && url.startsWith('http')) {
            logWarn('Blocked external request', { url });
            return callback({ cancel: true });
          }
        } catch {}
        callback({ cancel: false });
      });
    } catch {}
    ses.webRequest.onHeadersReceived((details, callback) => {
      try {
        const headers = details.responseHeaders || {};
        const enforce = settingsManager ? settingsManager.get('security.csp.enforce') : true;
        if (enforce) {
          const policy = (settingsManager && settingsManager.get('security.csp.policy')) || "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'";
          headers['Content-Security-Policy'] = [policy];
        }
        callback({ responseHeaders: headers });
      } catch (e) {
        callback({ cancel: false });
      }
    });
    logInfo('CSP headers enforcement installed');
  } catch (e) {
    logWarn('Failed to install CSP headers', { error: String(e && e.message || e) });
  }
}

function createWindow() {
  // Get saved window bounds
  const bounds = settingsManager.getWindowBounds();
  
  mainWindow = new BrowserWindow({
    width: bounds.width || 900,
    height: bounds.height || 640,
    x: bounds.x,
    y: bounds.y,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      webSecurity: true,
      devTools: settingsManager.get('security.devToolsInProd') ? true : (process.env.NODE_ENV !== 'production')
    },
    show: false, // Don't show until ready
    titleBarStyle: 'default',
    autoHideMenuBar: false
  });

  // Apply theme
  settingsManager.applyTheme(mainWindow.webContents);

  mainWindow.loadFile(path.join(__dirname, 'ui.html'));

  // Show window when ready
  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  // Save window bounds on resize/move
  mainWindow.on('resize', () => {
    const bounds = mainWindow.getBounds();
    settingsManager.saveWindowBounds(bounds);
  });

  mainWindow.on('move', () => {
    const bounds = mainWindow.getBounds();
    settingsManager.saveWindowBounds(bounds);
  });

  // Minimize to tray on close
  mainWindow.on('close', (e) => {
    if (!app.isQuiting) {
      e.preventDefault();
      mainWindow.hide();
    }
  });

  // Poll health and show tray tooltip
  setInterval(async () => {
    try {
      const r1 = (await httpRequest({ url: `http://127.0.0.1:${RUNTIME_PORT}/healthz`, timeoutSec: 1, expectJson: false, retries: 0 })).httpCode;
      const r2 = (await httpRequest({ url: `http://127.0.0.1:${PROVIDER_PORT}/health`, timeoutSec: 1, expectJson: false, retries: 0 })).httpCode;
      const r3 = (await httpRequest({ url: `http://127.0.0.1:${PROXY_PORT}/health`, timeoutSec: 1, expectJson: false, retries: 0 })).httpCode;
      const msg = `AZL: ${String(r1)} | Provider: ${String(r2)} | Proxy: ${String(r3)}`;
      if (tray) tray.setToolTip(`AZL Desktop\n${msg}`);
    } catch {}
  }, 5000);

  // Attach security/error guards to this window
  attachWebContentsGuards(mainWindow);
}

function createTray() {
  try {
    const iconPath = path.join(__dirname, 'build', 'icons', '128x128.png');
    const icon = nativeImage.createFromPath(iconPath);
    tray = new Tray(icon);
    
  const ctx = Menu.buildFromTemplate([
      { label: 'Show', click: () => { if (mainWindow) { mainWindow.show(); mainWindow.focus(); } } },
      { label: 'Start Daemon', click: async () => { 
          // Prefer systemd unit; fallback to user mode
          if (fs.existsSync('/usr/bin/systemctl')) {
            await runCmd('/usr/bin/systemctl', ['--user', 'start', 'azl-daemon.service']);
          } else if (fs.existsSync('/usr/local/bin/azl-ctl')) {
            await runCmd('/usr/local/bin/azl-ctl', ['start', 'all']);
          } else {
            spawnUserMode();
          }
        }
      },
      { label: 'Stop Daemon', click: async () => { 
          if (fs.existsSync('/usr/bin/systemctl')) {
            await runCmd('/usr/bin/systemctl', ['--user', 'stop', 'azl-daemon.service']);
          } else if (fs.existsSync('/usr/local/bin/azl-ctl')) {
            await runCmd('/usr/local/bin/azl-ctl', ['stop', 'all']);
          } else {
            killUserMode();
          }
        }
      },
      { type: 'separator' },
      { label: 'Check for Updates', click: () => { if (mainWindow) mainWindow.webContents.send('menu-action', 'check-updates'); } },
      { label: 'Preferences', click: () => { if (mainWindow) mainWindow.webContents.send('menu-action', 'open-preferences'); } },
      { type: 'separator' },
      { label: 'Quit', click: () => { gracefulShutdown(); } },
    ]);
    
    tray.setToolTip('AZL Desktop');
    tray.setContextMenu(ctx);
    tray.on('click', () => { if (mainWindow) { mainWindow.show(); mainWindow.focus(); } });
  } catch {}
}

function runCmd(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    const p = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'], ...opts });
    let out = '', err = '';
    p.stdout.on('data', d => out += d.toString());
    p.stderr.on('data', d => err += d.toString());
    p.on('close', code => resolve({ code, out, err }));
  });
}

// ----- HTTP helpers (production, no placeholders) -----
function resolveAuthToken(passedToken) {
  if (typeof passedToken === 'string' && passedToken.trim() !== '') return passedToken.trim();
  if (typeof process.env.AZL_API_TOKEN === 'string' && process.env.AZL_API_TOKEN.trim() !== '') return process.env.AZL_API_TOKEN.trim();
  return '';
}

async function httpJson(method, path, bodyObj = null, timeoutSec = 5, token = '') {
  const url = `${RUNTIME_BASE}${path}`;
  return httpRequest({ url, method, bodyObj, timeoutSec, token, expectJson: true });
}

function jitterDelay(baseMs, attempt, maxMs = 10000) {
  const exp = Math.min(maxMs, baseMs * Math.pow(2, attempt));
  const jitter = Math.floor(Math.random() * Math.min(1000, exp));
  return exp + jitter;
}

async function httpRequest({ url, method = 'GET', bodyObj = null, timeoutSec = 5, token = '', expectJson = true, retries = 2, baseDelayMs = 300 }) {
  const headers = { 'Accept': 'application/json' };
  const auth = resolveAuthToken(token);
  if (auth) headers['Authorization'] = `Bearer ${auth}`;
  if (method !== 'GET' && bodyObj != null) headers['Content-Type'] = 'application/json';

  const attemptOnce = async () => {
    try {
      const ctrl = new AbortController();
      const to = setTimeout(() => ctrl.abort(), Math.max(100, timeoutSec * 1000));
      const resp = await fetch(url, { method: String(method || 'GET').toUpperCase(), headers, body: method !== 'GET' && bodyObj != null ? JSON.stringify(bodyObj) : undefined, signal: ctrl.signal });
      clearTimeout(to);
      const text = await resp.text();
      let json = null; if (expectJson) { try { json = text ? JSON.parse(text) : null; } catch { json = null; } }
      return { ok: true, httpCode: resp.status, json, body: text, err: '' };
    } catch (e) {
      return { ok: false, httpCode: 0, json: null, body: '', err: String(e && e.message || e) };
    }
  };

  let last = await attemptOnce();
  let attempt = 0;
  while ((!last.ok || (last.httpCode >= 500 || last.httpCode === 429)) && attempt < retries) {
    await new Promise(r => setTimeout(r, jitterDelay(baseDelayMs, attempt)));
    last = await attemptOnce();
    attempt += 1;
  }
  return last;
}

async function runtimeHealthy(timeoutSec = 2) {
  try {
    const res = await httpRequest({ url: `${RUNTIME_BASE}/healthz`, method: 'GET', timeoutSec, expectJson: false, retries: 1 });
    return res.httpCode === 200;
  } catch { return false; }
}

function makeError(type, message, details = {}) {
  return { ok: false, error: { type, message, details } };
}

function isPositiveInt(n) {
  return Number.isInteger(n) && n > 0;
}

// ------------------ Metrics helpers ------------------
function toNumber(value, fallback = 0) {
  const n = typeof value === 'number' ? value : parseFloat(value);
  return Number.isFinite(n) ? n : fallback;
}

function getNested(obj, pathArray, fallback = undefined) {
  try {
    return pathArray.reduce((acc, key) => (acc && acc[key] !== undefined ? acc[key] : undefined), obj) ?? fallback;
  } catch {
    return fallback;
  }
}

function buildImprovements(windowId, metrics) {
  if (!metricsBaselines.has(windowId)) {
    const baseline = {
      ts: Date.now(),
      avgLatencyMs: toNumber(getNested(metrics, ['core', 'avg_latency_ms'], getNested(metrics, ['avg_latency_ms'], null))),
      peakMemGb: toNumber(getNested(metrics, ['core', 'peak_memory_gb'], getNested(metrics, ['peak_memory_gb'], null))),
      quantumShare: toNumber(getNested(metrics, ['hybrid', 'quantum_share_percent'], null)),
      avgLoss: toNumber(getNested(metrics, ['core', 'avg_loss'], getNested(metrics, ['avg_loss'], null)))
    };
    metricsBaselines.set(windowId, baseline);
  }

  const baseline = metricsBaselines.get(windowId);
  const current = {
    avgLatencyMs: toNumber(getNested(metrics, ['core', 'avg_latency_ms'], getNested(metrics, ['avg_latency_ms'], null))),
    peakMemGb: toNumber(getNested(metrics, ['core', 'peak_memory_gb'], getNested(metrics, ['peak_memory_gb'], null))),
    quantumShare: toNumber(getNested(metrics, ['hybrid', 'quantum_share_percent'], null)),
    avgLoss: toNumber(getNested(metrics, ['core', 'avg_loss'], getNested(metrics, ['avg_loss'], null)))
  };

  const improvements = {
    latencyImprovementPct: baseline.avgLatencyMs > 0 && current.avgLatencyMs > 0
      ? ((baseline.avgLatencyMs - current.avgLatencyMs) / baseline.avgLatencyMs) * 100.0
      : 0,
    memoryImprovementGb: (Number.isFinite(baseline.peakMemGb) && Number.isFinite(current.peakMemGb))
      ? (baseline.peakMemGb - current.peakMemGb)
      : 0,
    quantumImprovementPct: (Number.isFinite(baseline.quantumShare) && Number.isFinite(current.quantumShare))
      ? (current.quantumShare - baseline.quantumShare)
      : 0,
    lossImprovementPct: baseline.avgLoss > 0 && current.avgLoss >= 0
      ? ((baseline.avgLoss - current.avgLoss) / baseline.avgLoss) * 100.0
      : 0
  };

  return { baseline, current, improvements };
}

function computePredictions(metrics) {
  const predictions = [];

  const health = getNested(metrics, ['health'], {}) || {};
  const riskScore = toNumber(health.risk_score, 0);
  const p95Ms = toNumber(health.p95_ms, null);
  const peakMemGb = toNumber(getNested(metrics, ['core', 'peak_memory_gb'], getNested(metrics, ['peak_memory_gb'], null)));
  const avgLatencyMs = toNumber(getNested(metrics, ['core', 'avg_latency_ms'], getNested(metrics, ['avg_latency_ms'], null)));
  const quantumShare = toNumber(getNested(metrics, ['hybrid', 'quantum_share_percent'], null));

  if (riskScore >= 0.7) {
    predictions.push({
      id: 'risk:high',
      severity: 'high',
      reason: `Model/system risk_score=${riskScore.toFixed(2)} exceeds threshold 0.70`,
      recommendations: [
        'Attempt recovery to clear transient issues',
        'Temporarily reduce batch size by ~25% to lower pressure',
        'Verify dataset quality and recent error spikes'
      ],
      actions: [{ kind: 'attempt_recovery' }]
    });
  }

  if (Number.isFinite(p95Ms) && p95Ms > 2000) {
    predictions.push({
      id: 'latency:p95',
      severity: 'medium',
      reason: `p95 latency ${Math.round(p95Ms)}ms is above target 2000ms`,
      recommendations: [
        'Reduce batch size 10-25% to improve latency',
        'Pause/resume training to reset hot paths if stalling persists'
      ],
      actions: []
    });
  } else if (avgLatencyMs > 2000) {
    predictions.push({
      id: 'latency:avg',
      severity: 'medium',
      reason: `Average latency ${Math.round(avgLatencyMs)}ms is above target 2000ms`,
      recommendations: [
        'Consider reducing batch size',
        'Check device imbalance and pipeline backpressure'
      ],
      actions: []
    });
  }

  if (Number.isFinite(peakMemGb) && peakMemGb >= 0.9 * DEFAULT_PEAK_MEM_GB_MAX) {
    predictions.push({
      id: 'memory:peak',
      severity: 'high',
      reason: `Peak memory ${peakMemGb.toFixed(2)}GB approaches/ exceeds ${DEFAULT_PEAK_MEM_GB_MAX}GB limit`,
      recommendations: [
        'Reduce batch size or GPU memory usage',
        'Attempt recovery to release leaked allocations',
        'Avoid parallel runs until memory headroom improves'
      ],
      actions: [{ kind: 'attempt_recovery' }]
    });
  }

  if (Number.isFinite(quantumShare) && quantumShare < 10) {
    predictions.push({
      id: 'quantum:opportunity',
      severity: 'low',
      reason: `Quantum share ${quantumShare.toFixed(2)}% is low; potential performance gains available`,
      recommendations: [
        'Enable or increase quantum offloading where safe',
        'Tune hybrid settings after stability improves'
      ],
      actions: []
    });
  }

  return predictions;
}

function emitMetricsUpdate(targetWebContents, payload) {
  try {
    if (targetWebContents && !targetWebContents.isDestroyed()) {
      targetWebContents.send('metrics.update', payload);
    }
  } catch {}
}

ipcMain.handle('setMode', async (_e, mode) => {
  if (!(mode === 'user' || mode === 'system')) return { ok: false, error: 'validation_error' };
  userMode = mode === 'user';
  return { ok: true, userMode };
});

// Settings IPC passthroughs
ipcMain.handle('getSettings', async () => {
  try { return settingsManager.store.store; } catch { return {}; }
});
ipcMain.handle('updateSetting', async (_e, key, value) => {
  try { settingsManager.set(key, value); return { ok: true }; } catch (e) { return { ok: false, error: String(e && e.message || e) }; }
});
// Dedicated API token getters/setters
ipcMain.handle('getApiToken', async () => {
  try { return { ok: true, token: settingsManager.get('api.token') || '' }; } catch { return { ok: true, token: '' }; }
});
ipcMain.handle('setApiToken', async (_e, token) => {
  try { settingsManager.set('api.token', String(token || '')); return { ok: true }; } catch (e) { return { ok: false, error: String(e && e.message || e) }; }
});

ipcMain.handle('resetSettings', async () => {
  try { settingsManager.resetToDefaults(); return { ok: true }; } catch (e) { return { ok: false, error: String(e && e.message || e) }; }
});
ipcMain.handle('exportSettings', async () => {
  try { return settingsManager.exportSettings(); } catch { return '{}'; }
});
ipcMain.handle('importSettings', async (_e, json) => {
  try { return settingsManager.importSettings(json); } catch { return false; }
});

// Expose runtime configuration to renderer
ipcMain.handle('getRuntimeConfig', async () => {
  try {
    return { ok: true, host: RUNTIME_HOST, port: RUNTIME_PORT, base: RUNTIME_BASE, providerPort: PROVIDER_PORT, proxyPort: PROXY_PORT };
  } catch (e) {
    return { ok: false, error: String(e && e.message || e) };
  }
});

// Token proxy to call runtime endpoints with bearer from renderer
ipcMain.handle('tokenProxy', async (_e, payload = {}) => {
  try {
    if (!schemas.tokenProxy(payload)) return { ok: false, error: 'validation_error', details: schemas.tokenProxy.errors };
    const { path: pth, token, method, body, timeoutSec } = payload;
    if (!pth || typeof pth !== 'string' || !pth.startsWith('/')) return { ok: false, error: 'invalid_path' };
    const res = await httpJson(method || 'GET', pth, body || null, timeoutSec || 5, token || '');
    return res;
  } catch (e) {
    return { ok: false, error: String(e && e.message || e) };
  }
});

// ----- Training Plugin Management IPC -----
ipcMain.handle('listTrainingPlugins', async () => {
  const res = await httpJson('GET', '/plugins/list', null, 6, resolveAuthToken(''));
  if (!res.ok || res.httpCode !== 200) return { ok: false, error: 'runtime_error', details: { status: res.httpCode, body: res.body } };
  return { ok: true, plugins: res.json };
});
ipcMain.handle('enableTrainingPlugin', async (_e, payload) => {
  if (!payload || typeof payload !== 'object' || !payload.pluginId || !payload.stage) return { ok: false, error: 'validation_error' };
  const res = await httpJson('POST', '/plugins/enable', { plugin_id: String(payload.pluginId), stage: String(payload.stage) }, 6, resolveAuthToken(''));
  if (!res.ok || (res.httpCode !== 200 && res.httpCode !== 202)) return { ok: false, error: 'runtime_error', details: { status: res.httpCode, body: res.body } };
  return { ok: true, response: res.json };
});
ipcMain.handle('disableTrainingPlugin', async (_e, payload) => {
  if (!payload || typeof payload !== 'object' || !payload.pluginId || !payload.stage) return { ok: false, error: 'validation_error' };
  const res = await httpJson('POST', '/plugins/disable', { plugin_id: String(payload.pluginId), stage: String(payload.stage) }, 6, resolveAuthToken(''));
  if (!res.ok || (res.httpCode !== 200 && res.httpCode !== 202)) return { ok: false, error: 'runtime_error', details: { status: res.httpCode, body: res.body } };
  return { ok: true, response: res.json };
});
ipcMain.handle('getPluginStatus', async () => {
  const res = await httpJson('GET', '/plugins/list', null, 6, resolveAuthToken(''));
  if (!res.ok || res.httpCode !== 200) return { ok: false, error: 'runtime_error', details: { status: res.httpCode, body: res.body } };
  return { ok: true, plugins: res.json };
});

ipcMain.handle('systemctl', async (_e, action) => {
  if (userMode) return { ok: false, error: 'Not in system mode' };
  // Use azl-ctl wrapper which self-escalates via pkexec and handles ordering
  if (!fs.existsSync('/usr/local/bin/azl-ctl')) return { ok: false, error: 'azl-ctl not found' };
  const res = await runCmd('/usr/local/bin/azl-ctl', [action, 'all']);
  return { ok: res.code === 0, result: res };
});

ipcMain.handle('serviceAction', async (_e, payload) => {
  if (userMode) return { ok: false, error: 'Not in system mode' };
  if (!schemas.serviceAction(payload)) return { ok: false, error: 'validation_error', details: schemas.serviceAction.errors };
  const { target, action } = payload;
  const res = await runCmd('/usr/local/bin/azl-ctl', [action, target]);
  return { ok: res.code === 0, result: res };
});

ipcMain.handle('status', async () => {
  if (!userMode) {
    try {
      if (!fs.existsSync('/usr/local/bin/azl-ctl')) return { ok: false, mode: 'system', status: 'azl-ctl not found' };
      const res = await runCmd('/usr/local/bin/azl-ctl', ['status', 'all']);
      return { ok: res.code === 0, mode: 'system', status: res.out || res.err };
    } catch (e) {
      return { ok: false, mode: 'system', status: String(e) };
    }
  }
  // user mode: read daemon pid
  try {
    const cwd = path.resolve(path.join(__dirname, '..'));
    const pidPath = path.join(cwd, '.azl', 'daemon.pid');
    const pid = fs.existsSync(pidPath) ? parseInt(fs.readFileSync(pidPath, 'utf8').trim(), 10) : null;
    let alive = false;
    if (pid && Number.isInteger(pid)) {
      try { process.kill(pid, 0); alive = true; } catch { alive = false; }
    }
    return { ok: true, mode: 'user', status: `daemon:${alive ? 'running' : 'stopped'} pid:${pid || 'n/a'}` };
  } catch (e) {
    return { ok: false, mode: 'user', status: String(e) };
  }
});

ipcMain.handle('healthz', async () => {
  try {
    const status = (await httpRequest({ url: `${RUNTIME_BASE}/healthz`, method: 'GET', expectJson: false, retries: 0 })).httpCode;
    return { ok: status === 200 };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
});

ipcMain.handle('healthAll', async () => {
  const h = {
    runtime: String((await httpRequest({ url: `${RUNTIME_BASE}/healthz`, method: 'GET', expectJson: false, retries: 0 })).httpCode || 0),
    provider: String((await httpRequest({ url: `http://127.0.0.1:${PROVIDER_PORT}/health`, method: 'GET', expectJson: false, retries: 0 })).httpCode || 0),
    proxy: String((await httpRequest({ url: `http://127.0.0.1:${PROXY_PORT}/health`, method: 'GET', expectJson: false, retries: 0 })).httpCode || 0),
  };
  return { ok: true, health: h };
});

// ----- Training Control IPC Handlers -----
ipcMain.handle('startAdvancedTraining', async (_e, payload) => {
  try {
    const p = payload || {};
    if (!schemas.startAdvancedTraining(p)) return makeError('validation_error', 'invalid payload', { errors: schemas.startAdvancedTraining.errors });
    const dataset = (p.dataset_path || p.dataset || p.data_path || '').toString();
    const mode = (p.mode || 'supervised').toString();
    const device = (p.device || 'cpu').toString();
    const epochs = Number.isFinite(p.epochs) ? Math.trunc(p.epochs) : Number.isFinite(parseInt(p.epochs)) ? parseInt(p.epochs) : 1;
    const batchSize = Number.isFinite(p.batch_size) ? Math.trunc(p.batch_size) : Number.isFinite(parseInt(p.batch_size)) ? parseInt(p.batch_size) : 1;
    const gpuLimit = Number.isFinite(p.gpu_limit) ? Math.trunc(p.gpu_limit) : Number.isFinite(parseInt(p.gpu_limit)) ? parseInt(p.gpu_limit) : 0;
    const token = (p.token || '').toString();

    if (!dataset || dataset.trim() === '') return makeError('validation_error', 'dataset_path is required');
    if (!(device === 'cpu' || device === 'cuda')) return makeError('validation_error', 'invalid device', { allowed: ['cpu', 'cuda'] });
    if (!isPositiveInt(epochs)) return makeError('validation_error', 'epochs must be a positive integer');
    if (!isPositiveInt(batchSize)) return makeError('validation_error', 'batch_size must be a positive integer');
    if (gpuLimit < 0 || gpuLimit > 100) return makeError('validation_error', 'gpu_limit must be between 0 and 100');

    // Health check first
    const healthy = await runtimeHealthy(3);
    if (!healthy) return makeError('runtime_unhealthy', 'AZL runtime not healthy on /healthz', { target: RUNTIME_BASE });

    const startRes = await httpJson('POST', '/training/start', {
      dataset_path: dataset,
      mode,
      device,
      gpu_limit: gpuLimit,
      epochs,
      batch_size: batchSize
    }, 10, token);

    if (!startRes.ok) return makeError('network_error', 'Failed to reach runtime', { err: startRes.err });
    if (!(startRes.httpCode === 200 || startRes.httpCode === 202)) {
      return makeError('runtime_error', 'Unexpected response from /training/start', { status: startRes.httpCode, body: startRes.body });
    }

    // Best-effort fetch run_id and status
    let runId = '';
    let statusSnap = null;
    for (let i = 0; i < 5; i += 1) {
      const st = await httpJson('GET', '/training/status', null, 4, token);
      if (st.ok && st.httpCode === 200) {
        const m = st.json && st.json.metrics;
        if (m && typeof m.run_id === 'string' && m.run_id) { runId = m.run_id; statusSnap = st.json; break; }
        statusSnap = st.json || statusSnap;
      }
      await new Promise(r => setTimeout(r, 200));
    }

    return { ok: true, accepted: true, jobId: runId || null, status: statusSnap || null };
  } catch (e) {
    return makeError('exception', 'Unhandled exception in startAdvancedTraining', { message: String(e && e.message || e) });
  }
});

ipcMain.handle('stopTraining', async (_e, payload) => {
  try {
    const token = (payload && payload.token) ? String(payload.token) : '';
    const healthy = await runtimeHealthy(3);
    if (!healthy) return makeError('runtime_unhealthy', 'AZL runtime not healthy on /healthz', { target: RUNTIME_BASE });

    const res = await httpJson('POST', '/training/control', { action: 'stop' }, 6, token);
    if (!res.ok) return makeError('network_error', 'Failed to reach runtime', { err: res.err });
    if (!(res.httpCode === 200 || res.httpCode === 202)) {
      return makeError('runtime_error', 'Unexpected response from /training/control', { status: res.httpCode, body: res.body });
    }
    // Optional status after stop
    const st = await httpJson('GET', '/training/status', null, 4, token);
    return { ok: true, stopped: true, status: (st.ok && st.httpCode === 200) ? st.json : null };
  } catch (e) {
    return makeError('exception', 'Unhandled exception in stopTraining', { message: String(e && e.message || e) });
  }
});

ipcMain.handle('getTrainingStatus', async (_e, payload) => {
  try {
    const token = (payload && payload.token) ? String(payload.token) : '';
    const healthy = await runtimeHealthy(3);
    if (!healthy) return makeError('runtime_unhealthy', 'AZL runtime not healthy on /healthz', { target: RUNTIME_BASE });

    const res = await httpJson('GET', '/training/status', null, 5, token);
    if (!res.ok) return makeError('network_error', 'Failed to reach runtime', { err: res.err });
    if (res.httpCode !== 200) return makeError('runtime_error', 'Unexpected status from /training/status', { status: res.httpCode, body: res.body });
    const runId = (res.json && res.json.metrics && res.json.metrics.run_id) ? res.json.metrics.run_id : null;
    return { ok: true, runId, status: res.json };
  } catch (e) {
    return makeError('exception', 'Unhandled exception in getTrainingStatus', { message: String(e && e.message || e) });
  }
});

ipcMain.handle('updateTrainingConfig', async (_e, payload) => {
  try {
    const p = payload || {};
    if (!schemas.updateTrainingConfig(p)) return makeError('validation_error', 'invalid payload', { errors: schemas.updateTrainingConfig.errors });
    const token = (p.token || '').toString();
    const cfg = {};
    if (p.device) {
      const d = String(p.device);
      if (!(d === 'cpu' || d === 'cuda')) return makeError('validation_error', 'invalid device', { allowed: ['cpu', 'cuda'] });
      cfg.device = d;
    }
    if (p.gpu_limit != null) {
      const g = Number.isFinite(p.gpu_limit) ? Math.trunc(p.gpu_limit) : parseInt(p.gpu_limit);
      if (!Number.isFinite(g) || g < 0 || g > 100) return makeError('validation_error', 'gpu_limit must be between 0 and 100');
      cfg.gpu_limit = g;
    }
    if (p.epochs != null) {
      const e = Number.isFinite(p.epochs) ? Math.trunc(p.epochs) : parseInt(p.epochs);
      if (!isPositiveInt(e)) return makeError('validation_error', 'epochs must be a positive integer');
      cfg.epochs = e;
    }
    if (p.batch_size != null) {
      const b = Number.isFinite(p.batch_size) ? Math.trunc(p.batch_size) : parseInt(p.batch_size);
      if (!isPositiveInt(b)) return makeError('validation_error', 'batch_size must be a positive integer');
      cfg.batch_size = b;
    }
    if (p.mode) { cfg.mode = String(p.mode); }
    if (Object.keys(cfg).length === 0) return makeError('validation_error', 'no valid config keys provided');

    const healthy = await runtimeHealthy(3);
    if (!healthy) return makeError('runtime_unhealthy', 'AZL runtime not healthy on /healthz', { target: RUNTIME_BASE });

    const res = await httpJson('POST', '/training/config', cfg, 6, token);
    if (!res.ok) return makeError('network_error', 'Failed to reach runtime', { err: res.err });
    if (!(res.httpCode === 200 || res.httpCode === 202)) {
      return makeError('runtime_error', 'Unexpected response from /training/config', { status: res.httpCode, body: res.body });
    }
    return { ok: true, updated: true, response: res.json };
  } catch (e) {
    return makeError('exception', 'Unhandled exception in updateTrainingConfig', { message: String(e && e.message || e) });
  }
});

ipcMain.handle('pauseTraining', async (_e, payload) => {
  try {
    const token = (payload && payload.token) ? String(payload.token) : '';
    const healthy = await runtimeHealthy(3);
    if (!healthy) return makeError('runtime_unhealthy', 'AZL runtime not healthy on /healthz', { target: RUNTIME_BASE });
    const res = await httpJson('POST', '/training/control', { action: 'pause' }, 6, token);
    if (!res.ok) return makeError('network_error', 'Failed to reach runtime', { err: res.err });
    if (!(res.httpCode === 200 || res.httpCode === 202)) {
      return makeError('runtime_error', 'Unexpected response from /training/control', { status: res.httpCode, body: res.body });
    }
    const st = await httpJson('GET', '/training/status', null, 4, token);
    return { ok: true, paused: true, status: (st.ok && st.httpCode === 200) ? st.json : null };
  } catch (e) {
    return makeError('exception', 'Unhandled exception in pauseTraining', { message: String(e && e.message || e) });
  }
});

ipcMain.handle('resumeTraining', async (_e, payload) => {
  try {
    const token = (payload && payload.token) ? String(payload.token) : '';
    const healthy = await runtimeHealthy(3);
    if (!healthy) return makeError('runtime_unhealthy', 'AZL runtime not healthy on /healthz', { target: RUNTIME_BASE });
    const res = await httpJson('POST', '/training/control', { action: 'resume' }, 6, token);
    if (!res.ok) return makeError('network_error', 'Failed to reach runtime', { err: res.err });
    if (!(res.httpCode === 200 || res.httpCode === 202)) {
      return makeError('runtime_error', 'Unexpected response from /training/control', { status: res.httpCode, body: res.body });
    }
    const st = await httpJson('GET', '/training/status', null, 4, token);
    return { ok: true, resumed: true, status: (st.ok && st.httpCode === 200) ? st.json : null };
  } catch (e) {
    return makeError('exception', 'Unhandled exception in resumeTraining', { message: String(e && e.message || e) });
  }
});

ipcMain.handle('startParallelTraining', async (_e, payload) => {
  try {
    const p = payload || {};
    // Allow flexible config; basic checks inline below
    const token = (p.token || '').toString();
    const dataset = (p.dataset_path || p.dataset || p.data_path || '').toString();
    const mode = (p.mode || 'supervised').toString();
    const config = p.config || {};
    const device = String(config.device || p.device || '');
    const numGpus = Number.isFinite(config.num_gpus) ? Math.trunc(config.num_gpus) : Number.isFinite(parseInt(config.num_gpus)) ? parseInt(config.num_gpus) : Number.isFinite(p.num_gpus) ? Math.trunc(p.num_gpus) : Number.isFinite(parseInt(p.num_gpus)) ? parseInt(p.num_gpus) : 0;
    const batchSize = Number.isFinite(config.batch_size) ? Math.trunc(config.batch_size) : Number.isFinite(parseInt(config.batch_size)) ? parseInt(config.batch_size) : (Number.isFinite(p.batch_size) ? Math.trunc(p.batch_size) : (Number.isFinite(parseInt(p.batch_size)) ? parseInt(p.batch_size) : undefined));

    if (!dataset || dataset.trim() === '') return makeError('validation_error', 'dataset_path is required');
    if (device !== 'cuda') return makeError('validation_error', 'parallel training requires device=cuda');
    if (!Number.isFinite(numGpus) || numGpus <= 1) return makeError('validation_error', 'parallel training requires num_gpus > 1');
    if (batchSize != null && (!isPositiveInt(batchSize))) return makeError('validation_error', 'batch_size must be a positive integer');

    const healthy = await runtimeHealthy(3);
    if (!healthy) return makeError('runtime_unhealthy', 'AZL runtime not healthy on /healthz', { target: RUNTIME_BASE });

    const cfgPayload = { device: 'cuda', num_gpus: numGpus };
    if (batchSize != null) cfgPayload.batch_size = batchSize;
    const res = await httpJson('POST', '/training/parallel/start', {
      dataset_path: dataset,
      mode,
      config: cfgPayload
    }, 15, token);

    if (!res.ok) return makeError('network_error', 'Failed to reach runtime', { err: res.err });
    if (!(res.httpCode === 200 || res.httpCode === 202)) {
      return makeError('runtime_error', 'Unexpected response from /training/parallel/start', { status: res.httpCode, body: res.body });
    }
    return { ok: true, accepted: true };
  } catch (e) {
    return makeError('exception', 'Unhandled exception in startParallelTraining', { message: String(e && e.message || e) });
  }
});

ipcMain.handle('getParallelTrainingStatus', async (_e, payload) => {
  try {
    const token = (payload && payload.token) ? String(payload.token) : '';
    const healthy = await runtimeHealthy(3);
    if (!healthy) return makeError('runtime_unhealthy', 'AZL runtime not healthy on /healthz', { target: RUNTIME_BASE });
    const res = await httpJson('GET', '/training/parallel/status', null, 6, token);
    if (!res.ok) return makeError('network_error', 'Failed to reach runtime', { err: res.err });
    if (res.httpCode !== 200) return makeError('runtime_error', 'Unexpected status from /training/parallel/status', { status: res.httpCode, body: res.body });
    return { ok: true, status: res.json };
  } catch (e) {
    return makeError('exception', 'Unhandled exception in getParallelTrainingStatus', { message: String(e && e.message || e) });
  }
});

// ----- Metrics live polling IPC -----
ipcMain.handle('metrics.start', async (e, opts) => {
  try {
    const sender = e && e.sender;
    if (!sender) return makeError('ipc_error', 'No sender');
    const windowId = sender.id;
    const options = opts || {};
    if (!schemas.metricsStart(options)) return makeError('validation_error', 'invalid payload', { errors: schemas.metricsStart.errors });
    const intervalMs = Number.isFinite(options.intervalMs) ? Math.max(500, Math.trunc(options.intervalMs)) : 1000;
    const detailed = options.detailed === true;
    const token = typeof options.token === 'string' ? options.token : '';

    if (metricsIntervals.has(windowId)) {
      clearInterval(metricsIntervals.get(windowId));
      metricsIntervals.delete(windowId);
    }

    const path = detailed ? '/metrics/detailed' : '/metrics';
    const handle = setInterval(async () => {
      try {
        const res = await httpJson('GET', path, null, 5, token);
        if (!res.ok || res.httpCode !== 200) {
          emitMetricsUpdate(sender, { ok: false, error: { type: 'http', status: res.httpCode, message: 'metrics fetch failed' } });
          return;
        }
        const metrics = res.json || {};
        const { baseline, current, improvements } = buildImprovements(windowId, metrics);
        const predictions = computePredictions(metrics);
        const payload = {
          ok: true,
          timestamp: Date.now(),
          metrics,
          improvements,
          baseline,
          current,
          predictions
        };

        // Optional proactive maintenance
        const auto = autoMaintenanceByWindow.get(windowId) || { enabled: false, lastActionTs: 0 };
        if (auto.enabled) {
          const now = Date.now();
          const cooldownMs = 60_000; // 60s cooldown between actions
          const actionable = predictions.find(p => Array.isArray(p.actions) && p.actions.some(a => a.kind === 'attempt_recovery'));
          if (actionable && (now - (auto.lastActionTs || 0) > cooldownMs)) {
            try {
              const rec = await httpJson('POST', '/training/recover', {}, 8, token);
              if (rec.ok && (rec.httpCode === 200 || rec.httpCode === 202)) {
                auto.lastActionTs = now;
                autoMaintenanceByWindow.set(windowId, auto);
                payload.maintenanceAction = { kind: 'attempt_recovery', at: now };
              }
            } catch {}
          }
        }

        emitMetricsUpdate(sender, payload);
      } catch (err) {
        emitMetricsUpdate(sender, { ok: false, error: { type: 'exception', message: String(err && err.message || err) } });
      }
    }, intervalMs);

    metricsIntervals.set(windowId, handle);
    return { ok: true };
  } catch (e2) {
    return makeError('exception', 'metrics.start failed', { message: String(e2 && e2.message || e2) });
  }
});

ipcMain.handle('metrics.stop', async (e) => {
  try {
    const sender = e && e.sender;
    if (!sender) return makeError('ipc_error', 'No sender');
    const windowId = sender.id;
    if (metricsIntervals.has(windowId)) {
      clearInterval(metricsIntervals.get(windowId));
      metricsIntervals.delete(windowId);
    }
    metricsBaselines.delete(windowId);
    return { ok: true };
  } catch (err) {
    return makeError('exception', 'metrics.stop failed', { message: String(err && err.message || err) });
  }
});

ipcMain.handle('getMetrics', async (_e, payload = {}) => {
  try {
    if (!schemas.getMetrics(payload)) return makeError('validation_error', 'invalid payload', { errors: schemas.getMetrics.errors });
    const path = payload.detailed ? '/metrics/detailed' : '/metrics';
    const res = await httpJson('GET', path, null, 5, typeof payload.token === 'string' ? payload.token : '');
    if (!res.ok || res.httpCode !== 200) return makeError('runtime_error', 'Unexpected response from metrics', { status: res.httpCode, body: res.body });
    return { ok: true, metrics: res.json };
  } catch (e) {
    return makeError('exception', 'Unhandled exception in getMetrics', { message: String(e && e.message || e) });
  }
});

// Renderer error events
ipcMain.on('renderer.error', (_e, payload) => {
  try { logError('renderer.error', payload); } catch {}
});
ipcMain.on('renderer.unhandledRejection', (_e, payload) => {
  try { logError('renderer.unhandledRejection', payload); } catch {}
});

ipcMain.handle('attemptRecovery', async (_e, { token } = {}) => {
  try {
    const res = await httpJson('POST', '/training/recover', {}, 8, typeof token === 'string' ? token : '');
    if (!res.ok) return makeError('network_error', 'Failed to reach runtime', { err: res.err });
    if (!(res.httpCode === 200 || res.httpCode === 202)) {
      return makeError('runtime_error', 'Unexpected response from /training/recover', { status: res.httpCode, body: res.body });
    }
    return { ok: true, accepted: true };
  } catch (e) {
    return makeError('exception', 'Unhandled exception in attemptRecovery', { message: String(e && e.message || e) });
  }
});

ipcMain.handle('maintenance.set', async (e, { enabled } = {}) => {
  try {
    const sender = e && e.sender; if (!sender) return makeError('ipc_error', 'No sender');
    const windowId = sender.id;
    const st = autoMaintenanceByWindow.get(windowId) || { enabled: false, lastActionTs: 0 };
    st.enabled = !!enabled;
    autoMaintenanceByWindow.set(windowId, st);
    return { ok: true, enabled: st.enabled };
  } catch (err) {
    return makeError('exception', 'maintenance.set failed', { message: String(err && err.message || err) });
  }
});

ipcMain.handle('maintenance.get', async (e) => {
  try {
    const sender = e && e.sender; if (!sender) return makeError('ipc_error', 'No sender');
    const windowId = sender.id;
    const st = autoMaintenanceByWindow.get(windowId) || { enabled: false, lastActionTs: 0 };
    return { ok: true, enabled: !!st.enabled, lastActionTs: st.lastActionTs || 0 };
  } catch (err) {
    return makeError('exception', 'maintenance.get failed', { message: String(err && err.message || err) });
  }
});

function spawnUserMode() {
  if (procs.daemonRunner) return;
  const cwd = path.resolve(path.join(__dirname, '..'));
  // Use enterprise daemon runner which starts sysproxy and wire when needed
  const runner = spawn('bash', ['scripts/run_enterprise_daemon.sh'], { cwd, env: { ...process.env } });
  try {
    const azlDir = path.join(cwd, '.azl');
    fs.mkdirSync(azlDir, { recursive: true });
    const out = fs.createWriteStream(path.join(azlDir, 'launcher.out'), { flags: 'a' });
    const err = fs.createWriteStream(path.join(azlDir, 'launcher.err'), { flags: 'a' });
    runner.stdout.pipe(out);
    runner.stderr.pipe(err);
  } catch {}
  procs.daemonRunner = runner;
}

function killUserMode() {
  const cwd = path.resolve(path.join(__dirname, '..'));
  try {
    const pidPath = path.join(cwd, '.azl', 'daemon.pid');
    if (fs.existsSync(pidPath)) {
      const pid = parseInt(fs.readFileSync(pidPath, 'utf8').trim(), 10);
      if (pid && Number.isInteger(pid)) {
        try { process.kill(pid, 'SIGTERM'); } catch {}
      }
    }
    for (const aux of ['sysproxy.pid', 'syswire.pid']) {
      const p = path.join(cwd, '.azl', aux);
      if (fs.existsSync(p)) {
        const apid = parseInt(fs.readFileSync(p, 'utf8').trim(), 10);
        if (apid && Number.isInteger(apid)) { try { process.kill(apid, 'SIGTERM'); } catch {} }
      }
    }
  } catch {}
  if (procs.daemonRunner && !procs.daemonRunner.killed) {
    try { procs.daemonRunner.kill('TERM'); } catch {}
  }
  procs.daemonRunner = null;
}

ipcMain.handle('start', async () => {
  if (!userMode) {
    if (!fs.existsSync('/usr/local/bin/azl-ctl')) return { ok: false, error: 'azl-ctl not found' };
    const res = await runCmd('/usr/local/bin/azl-ctl', ['start', 'all']);
    return { ok: res.code === 0 };
  }
  // User mode: one-click start using the pure AZL combined bundle + runner
  try {
    const cwd = path.resolve(path.join(__dirname, '..'));
    const env = { ...process.env, AZL_STRICT: '1', AZL_LOG_LEVEL: 'debug', AZL_DAEMON: '1' };
    // Step 1: build combined bundle and capture Prepared path
    const build = spawn('bash', ['-lc', './scripts/run_full.sh'], { cwd, env });
    let prepared = '';
    await new Promise((resolve) => {
      build.stdout.on('data', (d) => {
        const s = d.toString();
        logInfo('run_full.sh', { out: s.trim() });
        const m = s.match(/Prepared:\s*(\S+)/);
        if (m && m[1]) prepared = m[1];
      });
      build.stderr.on('data', (d) => logWarn('run_full.sh.stderr', { err: d.toString().trim() }));
      build.on('close', () => resolve());
    });
    if (!prepared) return { ok: false, error: 'Failed to build combined AZL bundle' };
    // Step 2: launch runner in background and persist PID
    try { fs.mkdirSync(path.join(cwd, '.azl'), { recursive: true }); } catch {}
    const runner = spawn('bash', ['-lc', `python3 azl_runner.py ${prepared} >> .azl/daemon.out 2>> .azl/daemon.err & echo $!`], { cwd, env });
    let pidOut = '';
    await new Promise((resolve) => {
      runner.stdout.on('data', (d) => { pidOut += d.toString(); });
      runner.stderr.on('data', (d) => logWarn('runner.stderr', { err: d.toString().trim() }));
      runner.on('close', () => resolve());
    });
    const pid = parseInt((pidOut || '').trim(), 10);
    if (!pid || Number.isNaN(pid)) return { ok: false, error: 'Failed to acquire runner PID' };
    procs.daemonRunner = { pid };
    fs.writeFileSync(path.join(cwd, '.azl', 'daemon.pid'), String(pid));
    return { ok: true, pid };
  } catch (e) {
    logError('start_user_mode_failed', { error: String(e && e.message || e) });
    return { ok: false, error: String(e && e.message || e) };
  }
});

ipcMain.handle('stop', async () => {
  if (!userMode) {
    if (!fs.existsSync('/usr/local/bin/azl-ctl')) return { ok: false, error: 'azl-ctl not found' };
    const res = await runCmd('/usr/local/bin/azl-ctl', ['stop', 'all']);
    return { ok: res.code === 0 };
  }
  killUserMode();
  return { ok: true };
});

ipcMain.handle('readLogs', async () => {
  try {
    ensureLogDirExists();
    const out = fs.existsSync(MAIN_LOG()) ? fs.readFileSync(MAIN_LOG(), 'utf8') : '';
    const err = fs.existsSync(ERROR_LOG()) ? fs.readFileSync(ERROR_LOG(), 'utf8') : '';
    return { ok: true, outTail: out.split('\n').slice(-200).join('\n'), errTail: err.split('\n').slice(-200).join('\n') };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
});

ipcMain.handle('readAllLogs', async (_e, which) => {
  try {
    if (!schemas.readAllLogs(which)) return { ok: false, error: 'validation_error' };
    const cwd = path.resolve(path.join(__dirname, '..'));
    const map = {
      runtimeOut: path.join(cwd, '.azl', 'daemon.out'),
      runtimeErr: path.join(cwd, '.azl', 'daemon.err'),
      providerOut: path.join(cwd, '.azl', 'azme-provider.out'),
      providerErr: path.join(cwd, '.azl', 'azme-provider.err'),
      proxyOut: path.join(cwd, '.azl', 'azme-proxy.out'),
      proxyErr: path.join(cwd, '.azl', 'azme-proxy.err'),
      sysproxyLog: path.join(cwd, '.azl', 'sysproxy.log'),
    };
    const file = map[which];
    if (!file) return { ok: false, error: 'invalid log key' };
    const data = fs.readFileSync(file, 'utf8');
    return { ok: true, tail: data.split('\n').slice(-400).join('\n') };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
});

// Settings management IPC handlers
ipcMain.handle('getSettings', () => {
  return {
    theme: settingsManager.get('theme'),
    autoStart: settingsManager.get('autoStart'),
    minimizeToTray: settingsManager.get('minimizeToTray'),
    autoUpdate: settingsManager.get('autoUpdate'),
    accessibility: settingsManager.getAccessibilitySettings(),
    shortcuts: settingsManager.getShortcuts()
  };
});

ipcMain.handle('updateSetting', async (event, key, value) => {
  try {
    settingsManager.set(key, value);
    
    // Apply theme changes immediately
    if (key === 'theme' || key.startsWith('accessibility.')) {
      settingsManager.applyTheme(mainWindow.webContents);
    }
    
    return { success: true };
  } catch (error) {
    return { success: false, error: error.message };
  }
});

ipcMain.handle('resetSettings', () => {
  try {
    settingsManager.resetToDefaults();
    settingsManager.applyTheme(mainWindow.webContents);
    return { success: true };
  } catch (error) {
    return { success: false, error: error.message };
  }
});

ipcMain.handle('exportSettings', () => {
  try {
    return { success: true, data: settingsManager.exportSettings() };
  } catch (error) {
    return { success: false, error: error.message };
  }
});

ipcMain.handle('importSettings', async (event, jsonString) => {
  try {
    const success = settingsManager.importSettings(jsonString);
    if (success) {
      settingsManager.applyTheme(mainWindow.webContents);
    }
    return { success };
  } catch (error) {
    return { success: false, error: error.message };
  }
});

// Menu action handlers
ipcMain.handle('handleMenuAction', async (event, action) => {
  try {
    switch (action) {
      case 'new-session':
        // Handle new session
        return { success: true };
      case 'open-logs':
        // Handle open logs
        return { success: true };
      case 'open-preferences':
        // Handle open preferences
        return { success: true };
      case 'open-chat':
        try {
          const { BrowserWindow } = require('electron');
          const chatWin = new BrowserWindow({
            width: 1200,
            height: 800,
            webPreferences: {
              preload: path.join(__dirname, 'preload.js'),
              contextIsolation: true,
              nodeIntegration: false,
              sandbox: true,
              webSecurity: true
            }
          });
          chatWin.loadFile(path.join(__dirname, 'chat-interface.html'));
          chatWin.once('ready-to-show', () => chatWin.show());
          return { success: true };
        } catch (e) {
          return { success: false, error: String(e && e.message || e) };
        }
      case 'quit':
        await gracefulShutdown();
        return { success: true };
      case 'start-all':
        return await ipcMain.handlers.start();
      case 'stop-all':
        return await ipcMain.handlers.stop();
      case 'check-health':
        // Handle health check
        return { success: true };
      case 'show-logs':
        // Handle show logs
        return { success: true };
      case 'restart-sysproxy':
        return await processMonitor.restartProcess('sysproxy');
      case 'restart-runtime':
        return await processMonitor.restartProcess('runtime');
      case 'restart-provider':
        return await processMonitor.restartProcess('provider');
      case 'restart-proxy':
        return await processMonitor.restartProcess('proxy');
      case 'about':
        // Handle about dialog
        return { success: true };
      case 'check-updates':
        return await autoUpdateService.checkForUpdates();
      case 'documentation':
        // Handle documentation
        return { success: true };
      case 'report-issue':
        // Handle report issue
        return { success: true };
      default:
        return { success: false, error: 'Unknown action' };
    }
  } catch (error) {
    return { success: false, error: error.message };
  }
});

app.whenReady().then(async () => {
  try {
    // Enforce single instance
    const gotTheLock = app.requestSingleInstanceLock();
    if (!gotTheLock) {
      app.quit();
      return;
    }
    app.on('second-instance', () => {
      if (mainWindow) {
        if (mainWindow.isMinimized()) mainWindow.restore();
        mainWindow.show();
        mainWindow.focus();
      }
    });

    ensureLogDirExists();
    startCrashReporter();
    installPermissionHandlers();
    installCertificatePinning();
    installCspHeaders();
    // Initialize services in order
    settingsManager = new SettingsManager();
    
    // Create window first to pass to services
    createWindow();
    
    // Initialize services that need mainWindow
    autoUpdateService = new AutoUpdateService(mainWindow);
    processMonitor = new ProcessMonitor();
    shortcutsManager = new ShortcutsManager(mainWindow, settingsManager);
    
    // Create tray after services are initialized
    createTray();
    
    // Schedule update checks
    if (settingsManager.get('autoUpdate')) {
      const interval = settingsManager.get('checkUpdatesInterval');
      autoUpdateService.scheduleUpdateChecks(interval);
    }
    
    console.log('AZL Desktop initialized successfully');
  } catch (error) {
    console.error('Failed to initialize AZL Desktop:', error);
    app.quit();
  }
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    gracefulShutdown();
  }
});

// Cleanup metrics intervals when a window closes
app.on('browser-window-created', (_e, win) => {
  win.on('closed', () => {
    try {
      const id = win.webContents.id;
      if (metricsIntervals.has(id)) { clearInterval(metricsIntervals.get(id)); metricsIntervals.delete(id); }
      metricsBaselines.delete(id);
    } catch {}
  });
});

async function gracefulShutdown() {
  console.log('Initiating graceful shutdown...');
  
  try {
    // Stop process monitoring
    if (processMonitor) {
      await processMonitor.shutdown();
    }
    
    // Cleanup shortcuts
    if (shortcutsManager) {
      shortcutsManager.cleanup();
    }
    
    // Kill user mode processes
    if (procs.sysproxy) {
      console.log('Killing sysproxy process...');
      try { 
        procs.sysproxy.kill('SIGTERM'); 
        procs.sysproxy = null;
      } catch (e) { 
        console.error('Failed to kill sysproxy:', e); 
      }
    }
    
    if (procs.runtime) {
      console.log('Killing runtime process...');
      try { 
        procs.runtime.kill('SIGTERM'); 
        procs.runtime = null;
      } catch (e) { 
        console.error('Failed to kill runtime:', e); 
      }
    }
    
    // Stop systemd services if in system mode
    if (!userMode) {
      console.log('Stopping systemd services...');
      try {
        await runCmd('/usr/local/bin/azl-ctl', ['stop', 'all']);
      } catch (e) {
        console.error('Failed to stop systemd services:', e);
      }
    }
    
    console.log('Graceful shutdown completed');
    app.isQuiting = true;
    app.quit();
    
  } catch (error) {
    console.error('Error during graceful shutdown:', error);
    process.exit(1);
  }
}

// Handle app quit events
app.on('before-quit', async (event) => {
  if (!app.isQuiting) {
    event.preventDefault();
    await gracefulShutdown();
  }
});

app.on('will-quit', () => {
  console.log('App will quit');
});

// Handle process signals
process.on('SIGTERM', async () => {
  console.log('Received SIGTERM, initiating graceful shutdown...');
  await gracefulShutdown();
});

process.on('SIGINT', async () => {
  console.log('Received SIGTERM, initiating graceful shutdown...');
  process.exit(1);
});
