const { contextBridge, ipcRenderer } = require('electron');

// Renderer crash reporting and error capture
window.addEventListener('error', (e) => {
  try {
    ipcRenderer.send('renderer.error', { message: String(e && e.message || e), filename: e && e.filename, lineno: e && e.lineno, colno: e && e.colno, stack: String(e && e.error && e.error.stack || '') });
  } catch {}
});
window.addEventListener('unhandledrejection', (e) => {
  try {
    const reason = e && e.reason;
    ipcRenderer.send('renderer.unhandledRejection', { reason: String(reason && reason.message || reason), stack: String(reason && reason.stack || '') });
  } catch {}
});

// Consistent error system wrapper for all IPC calls
const invokeSafely = async (channel, ...args) => {
  try {
    return await ipcRenderer.invoke(channel, ...args);
  } catch (err) {
    return {
      ok: false,
      error: {
        type: 'ipc_error',
        message: `IPC invoke failed for ${channel}`,
        details: { message: String((err && err.message) || err) }
      }
    };
  }
};

contextBridge.exposeInMainWorld('azl', {
  // Runtime info
  getRuntimeConfig: () => invokeSafely('getRuntimeConfig'),
  tokenProxy: (path, token, method = 'GET', body = null, timeoutSec = 5) => invokeSafely('tokenProxy', { path, token, method, body, timeoutSec }),
  // Core controls
  setMode: (mode) => invokeSafely('setMode', mode),
  start: () => invokeSafely('start'),
  stop: () => invokeSafely('stop'),
  status: () => invokeSafely('status'),
  healthz: () => invokeSafely('healthz'),
  healthAll: () => invokeSafely('healthAll'),
  readLogs: () => invokeSafely('readLogs'),
  readAllLogs: (which) => invokeSafely('readAllLogs', which),
  systemctl: (action) => invokeSafely('systemctl', action),
  serviceAction: (target, action) => invokeSafely('serviceAction', { target, action }),

  // Training control
  startAdvancedTraining: (config) => invokeSafely('startAdvancedTraining', config),
  stopTraining: () => invokeSafely('stopTraining'),
  getTrainingStatus: () => invokeSafely('getTrainingStatus'),
  updateTrainingConfig: (config) => invokeSafely('updateTrainingConfig', config),
  getTrainingMetrics: async () => {
    const res = await invokeSafely('getTrainingStatus');
    if (res && res.ok) {
      const metrics = res.status && res.status.metrics ? res.status.metrics : null;
      const runId = res.runId || (metrics && metrics.run_id) || null;
      return { ok: true, metrics, runId, status: res.status || null };
    }
    return res;
  },

  // Real-time metrics
  startMetrics: (options) => invokeSafely('metrics.start', options),
  stopMetrics: () => invokeSafely('metrics.stop'),
  getMetrics: (opts) => invokeSafely('getMetrics', opts),
  attemptRecovery: (opts) => invokeSafely('attemptRecovery', opts),
  onMetricsUpdate: (callback) => {
    if (typeof callback !== 'function') return () => {};
    const handler = (_event, payload) => {
      try { callback(payload); } catch {}
    };
    ipcRenderer.on('metrics.update', handler);
    return () => ipcRenderer.removeListener('metrics.update', handler);
  },
  setAutoMaintenance: (enabled) => invokeSafely('maintenance.set', { enabled }),
  getAutoMaintenance: () => invokeSafely('maintenance.get'),

  // Training plugin management
  listTrainingPlugins: () => invokeSafely('listTrainingPlugins'),
  enableTrainingPlugin: (pluginId, stage) => invokeSafely('enableTrainingPlugin', { pluginId, stage }),
  disableTrainingPlugin: (pluginId, stage) => invokeSafely('disableTrainingPlugin', { pluginId, stage }),
  getPluginStatus: () => invokeSafely('getPluginStatus'),

  // Existing extras (kept for compatibility)
  pauseTraining: (options) => invokeSafely('pauseTraining', options),
  resumeTraining: (options) => invokeSafely('resumeTraining', options),
  startParallelTraining: (config) => invokeSafely('startParallelTraining', config),
  getParallelTrainingStatus: (options) => invokeSafely('getParallelTrainingStatus', options)
});

// Harden renderer globals
try {
  Object.defineProperty(window, 'chrome', { value: undefined });
} catch {}
try {
  Object.freeze(navigator);
} catch {}

// New electronAPI for preferences and settings
contextBridge.exposeInMainWorld('electronAPI', {
  // Settings management
  getSettings: () => invokeSafely('getSettings'),
  updateSetting: (key, value) => invokeSafely('updateSetting', key, value),
  resetSettings: () => invokeSafely('resetSettings'),
  exportSettings: async () => {
    const data = await invokeSafely('exportSettings');
    return { success: true, data };
  },
  importSettings: async (jsonString) => {
    const ok = await invokeSafely('importSettings', jsonString);
    return { success: !!ok };
  },
  getApiToken: () => invokeSafely('getApiToken'),
  setApiToken: (token) => invokeSafely('setApiToken', token),

  // Auto-updater
  checkForUpdates: () => invokeSafely('checkForUpdates'),
  downloadUpdate: () => invokeSafely('downloadUpdate'),
  installUpdate: () => invokeSafely('installUpdate'),
  getUpdateStatus: () => invokeSafely('getUpdateStatus'),

  // Keyboard shortcuts
  getShortcuts: () => invokeSafely('getShortcuts'),
  updateShortcut: (action, accelerator) => invokeSafely('updateShortcut', action, accelerator),
  resetShortcuts: () => invokeSafely('resetShortcuts'),

  // Process monitoring
  getProcessStatus: () => invokeSafely('getProcessStatus'),
  restartProcess: (processName) => invokeSafely('restartProcess', processName),
  killProcess: (processName) => invokeSafely('killProcess', processName),
  getHealthMetrics: () => invokeSafely('getHealthMetrics'),

  // Menu actions
  handleMenuAction: (action) => invokeSafely('handleMenuAction', action),

  // Update status listener
  onUpdateStatus: (callback) => {
    if (typeof callback !== 'function') return () => {};
    const handler = (_event, { status, data }) => {
      try { callback(status, data); } catch {}
    };
    ipcRenderer.on('update-status', handler);
    return () => ipcRenderer.removeListener('update-status', handler);
  },

  // Menu action listener
  onMenuAction: (callback) => {
    if (typeof callback !== 'function') return () => {};
    const handler = (_event, action) => {
      try { callback(action); } catch {}
    };
    ipcRenderer.on('menu-action', handler);
    return () => ipcRenderer.removeListener('menu-action', handler);
  }
});
