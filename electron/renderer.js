document.addEventListener('DOMContentLoaded', () => {
  const btnChat = document.getElementById('btnChat');
  if (btnChat) btnChat.onclick = () => {
    if (window.electronAPI && window.electronAPI.handleMenuAction) {
      window.electronAPI.handleMenuAction('open-chat');
    } else {
      window.open('chat-interface.html', 'azme-chat', 'width=1200,height=800,resizable=yes,scrollbars=yes');
    }
  };

  const btnPreferences = document.getElementById('btnPreferences');
  if (btnPreferences) btnPreferences.onclick = () => {
    if (window.electronAPI && window.electronAPI.handleMenuAction) {
      window.electronAPI.handleMenuAction('open-preferences');
    }
  };

  const btnUpdates = document.getElementById('btnUpdates');
  if (btnUpdates) btnUpdates.onclick = () => {
    if (window.electronAPI && window.electronAPI.handleMenuAction) {
      window.electronAPI.handleMenuAction('check-updates');
    }
  };

  const btnProcessStatus = document.getElementById('btnProcessStatus');
  if (btnProcessStatus) btnProcessStatus.onclick = () => {
    if (window.electronAPI && window.electronAPI.handleMenuAction) {
      window.electronAPI.handleMenuAction('show-logs');
    }
  };

  // Persist token changes
  const tokenInput = document.getElementById('token');
  if (tokenInput) {
    try {
      // Load token from settings, then fallback to localStorage
      if (window.electronAPI && window.electronAPI.getApiToken) {
        window.electronAPI.getApiToken().then(res => {
          if (res && res.ok && res.token && !tokenInput.value) tokenInput.value = res.token;
        });
      }
      const stored = localStorage.getItem('azl_api_token');
      if (stored && !tokenInput.value) tokenInput.value = stored;
    } catch {}
    tokenInput.addEventListener('input', () => {
      const v = tokenInput.value || '';
      try { localStorage.setItem('azl_api_token', v); } catch {}
      if (window.electronAPI && window.electronAPI.setApiToken) {
        window.electronAPI.setApiToken(v);
      }
    });
  }
});

// Strictly avoid eval-like usage in renderer
window.eval = () => { throw new Error('eval is disabled by CSP'); };

const $ = (id) => document.getElementById(id);

// Remove legacy duplicate DOMContentLoaded path in favor of single init()
/* document.addEventListener('DOMContentLoaded', async () => {
  const radios = document.querySelectorAll('input[name="mode"]');
  radios.forEach(r => r.addEventListener('change', async () => {
    await window.azl.setMode(r.value);
  }));

  function setBadge(ok) {
    const b = $('healthBadge');
    b.textContent = ok ? 'OK' : 'FAIL';
    b.className = 'badge ' + (ok ? 'ok' : 'bad');
  }

  $('start').onclick = async () => { await window.azl.start(); };
  $('stop').onclick = async () => { await window.azl.stop(); };
  $('status').onclick = async () => {
    const res = await window.azl.status();
    $('statusText').textContent = (res && res.status) || '';
  };
  $('health').onclick = async () => {
    const res = await window.azl.healthz();
    setBadge(res.ok);
  };
  $('refreshLogs').onclick = async () => {
    const r = await window.azl.readLogs();
    if (r.ok) { $('out').value = r.outTail; $('err').value = r.errTail; }
  };

  document.querySelectorAll('button[data-svc]').forEach(btn => {
    btn.onclick = async () => {
      const svc = btn.getAttribute('data-svc');
      const act = btn.getAttribute('data-act') || 'restart';
      await window.azl.serviceAction(svc, act);
      $('status').click();
    };
  });

  $('healthAll').onclick = async () => {
    const h = await window.azl.healthAll();
    if (h && h.ok) {
      const ok8080 = h.health.runtime === '200';
      const ok5000 = h.health.provider === '200';
      const ok5001 = h.health.proxy === '200';
      const b = (id, ok) => { const el = $(id); el.textContent = id === 'hRuntime' ? '8080 ' + (ok?'OK':'FAIL') : (id === 'hProvider' ? '5000 ' + (ok?'OK':'FAIL') : '5001 ' + (ok?'OK':'FAIL')); el.className = 'badge ' + (ok?'ok':'bad'); };
      b('hRuntime', ok8080); b('hProvider', ok5000); b('hProxy', ok5001);
    }
  };

  $('readLog').onclick = async () => {
    const which = $('logSelect').value;
    const r = await window.azl.readAllLogs(which);
    if (r && r.ok) $('logTail').value = r.tail; else $('logTail').value = (r && r.error) || 'error';
  };

  // Kick initial status/health
  $('status').click();
  $('healthAll').click();

  async function tokenFetch(path) {
    const token = $('token').value.trim();
    const res = await window.azl.tokenProxy(path, token, 'GET', null, 5);
    return res && res.ok ? (res.body || '') : (res && res.err) || '';
  }

  let runtimeCfg = null;
  try { const cfg = await window.azl.getRuntimeConfig(); if (cfg && cfg.ok) runtimeCfg = cfg; } catch {}
  function baseUrl() { return (runtimeCfg && runtimeCfg.base) ? runtimeCfg.base : 'http://127.0.0.1:8080'; }
  $('readyz').onclick = async () => {
    const t = $('token').value.trim();
    const r = await fetch(baseUrl() + '/readyz', { headers: t ? { 'Authorization': 'Bearer ' + t } : {} }).then(r => r.status);
    $('statusText').textContent = '/readyz ' + r;
  };
  $('statusApi').onclick = async () => {
    const t = $('token').value.trim();
    const r = await fetch(baseUrl() + '/status', { headers: t ? { 'Authorization': 'Bearer ' + t } : {} }).then(r => r.status);
    $('statusText').textContent = '/status ' + r;
  };
  $('metrics').onclick = async () => {
    const t = $('token').value.trim();
    const r = await fetch(baseUrl() + '/metrics', { headers: t ? { 'Authorization': 'Bearer ' + t } : {} }).then(r => r.status);
    $('statusText').textContent = '/metrics ' + r;
  };

  $('startTrain').onclick = async () => {
    const dataset = $('dataset').value.trim();
    const device = $('device').value || 'cpu';
    const epochs = parseInt(($('epochs').value || '1'), 10) || 1;
    const batch_size = parseInt(($('batch').value || '1'), 10) || 1;
    const token = $('token').value.trim();
    const r = await window.azl.startAdvancedTraining({ dataset_path: dataset, device, epochs, batch_size, token });
    $('statusText').textContent = r && r.ok ? 'training accepted' : ('error: ' + ((r && r.error && r.error.message) || JSON.stringify(r)));
  };
  $('pauseTrain').onclick = async () => { const token = $('token').value.trim(); const r = await window.azl.pauseTraining({ token }); $('statusText').textContent = r && r.ok ? 'paused' : 'pause error'; };
  $('resumeTrain').onclick = async () => { const token = $('token').value.trim(); const r = await window.azl.resumeTraining({ token }); $('statusText').textContent = r && r.ok ? 'resumed' : 'resume error'; };
  $('stopTrain').onclick = async () => { const token = $('token').value.trim(); const r = await window.azl.stopTraining({ token }); $('statusText').textContent = r && r.ok ? 'stopped' : 'stop error'; };

  // Auto-refresh logs
  setInterval(() => $('refreshLogs').click(), 3000);

  function setVal(id, v) { const el = $(id); if (el) el.textContent = v; }
  function fmt(n, digits=2) { return (Number.isFinite(n) ? Number(n).toFixed(digits) : '-'); }
  function signFmt(n, digits=2) { if (!Number.isFinite(n)) return '-'; const s = Number(n).toFixed(digits); return (n>=0?'+':'') + s; }

  if (window.azl && window.azl.onMetricsUpdate) {
    window.azl.onMetricsUpdate((payload) => {
      if (!payload || !payload.ok) return;
      const m = payload.metrics || {};
      const core = m.core || m || {};
      const health = m.health || {};
      const hybrid = m.hybrid || {};
      setVal('kLatency', fmt(core.avg_latency_ms ?? m.avg_latency_ms));
      setVal('kP95', fmt(health.p95_ms));
      setVal('kMem', fmt(core.peak_memory_gb ?? m.peak_memory_gb));
      setVal('kThpt', fmt(core.avg_throughput ?? m.avg_throughput));
      setVal('kLoss', fmt(core.avg_loss ?? m.avg_loss));
      setVal('kQuantum', fmt(hybrid.quantum_share_percent));

      const imp = (payload.improvements || {});
      setVal('iLatency', signFmt(imp.latencyImprovementPct));
      setVal('iMem', signFmt(imp.memoryImprovementGb));
      setVal('iLoss', signFmt(imp.lossImprovementPct));
      setVal('iQuantum', signFmt(imp.quantumImprovementPct));

      const preds = payload.predictions || [];
      const ul = $('predictions');
      if (ul) {
        ul.innerHTML = '';
        preds.forEach(p => {
          const li = document.createElement('li');
          li.textContent = `[${p.severity}] ${p.reason}`;
          ul.appendChild(li);
        });
        if (preds.length === 0) {
          const li = document.createElement('li');
          li.textContent = 'No issues predicted';
          ul.appendChild(li);
        }
      }
    });
  }

  $('metricsStart').onclick = async () => {
    const t = $('token').value.trim();
    await window.azl.startMetrics({ detailed: true, intervalMs: 1000, token: t });
  };
  $('metricsStop').onclick = async () => { await window.azl.stopMetrics(); };
  $('attemptRecovery').onclick = async () => {
    const t = $('token').value.trim();
    await window.azl.attemptRecovery({ token: t });
  };

  // Auto maintenance toggle
  (async () => {
    const st = await window.azl.getAutoMaintenance();
    if (st && st.ok) { $('autoMaintenance').checked = !!st.enabled; }
  })();
  $('autoMaintenance').onchange = async (e) => {
    await window.azl.setAutoMaintenance(e.target.checked);
  };

  // New functions for enhanced features
  window.openPreferences = function openPreferences() {
    window.open('preferences.html', 'preferences', 'width=900,height=700,resizable=yes,scrollbars=yes');
  };

  window.checkForUpdates = async function checkForUpdates() {
    try {
      const result = await window.electronAPI.checkForUpdates();
      if (result.success) {
        alert('Update check completed successfully');
      } else {
        alert(`Update check failed: ${result.error}`);
      }
    } catch (error) {
      alert(`Error checking for updates: ${error.message}`);
    }
  };

  window.showProcessStatus = async function showProcessStatus() {
    try {
      const status = await window.electronAPI.getProcessStatus();
      const health = await window.electronAPI.getHealthMetrics();
      
      let statusText = 'Process Status:\n';
      for (const [name, info] of Object.entries(status)) {
        statusText += `${name}: PID ${info.pid}, Alive: ${info.alive}, Recovery Attempts: ${info.recoveryAttempts}\n`;
      }
      
      statusText += '\nHealth Metrics:\n';
      for (const [name, metrics] of Object.entries(health)) {
        statusText += `${name}: ${metrics.healthy ? 'Healthy' : 'Unhealthy'}, Last Check: ${new Date(metrics.timestamp).toLocaleString()}\n`;
      }
      
      alert(statusText);
    } catch (error) {
      alert(`Error getting process status: ${error.message}`);
    }
  };

  // Listen for menu actions
  if (window.electronAPI && window.electronAPI.onMenuAction) {
    window.electronAPI.onMenuAction((action) => {
      switch (action) {
        case 'start-all':
          document.getElementById('start').click();
          break;
        case 'stop-all':
          document.getElementById('stop').click();
          break;
        case 'check-health':
          document.getElementById('health').click();
          break;
        case 'show-logs':
          document.getElementById('out').focus();
          break;
        case 'open-preferences':
          window.openPreferences();
          break;
        case 'check-updates':
          window.checkForUpdates();
          break;
      }
    });
  }

  // Listen for update status
  if (window.electronAPI && window.electronAPI.onUpdateStatus) {
    window.electronAPI.onUpdateStatus((status, data) => {
      console.log('Update status:', status, data);
    });
  }
}); */

(() => {
  'use strict';

  const $ = (id) => document.getElementById(id);

  // Disable eval in renderer context
  window.eval = () => { throw new Error('eval is disabled by CSP'); };

  function setBadge(ok) {
    const b = $('healthBadge');
    if (!b) return;
    b.textContent = ok ? 'OK' : 'FAIL';
    b.className = 'badge ' + (ok ? 'ok' : 'bad');
  }

  function setVal(id, v) { const el = $(id); if (el) el.textContent = v; }
  function fmt(n, digits = 2) { return (Number.isFinite(n) ? Number(n).toFixed(digits) : '-'); }
  function signFmt(n, digits = 2) { if (!Number.isFinite(n)) return '-'; const s = Number(n).toFixed(digits); return (n >= 0 ? '+' : '') + s; }

  async function init() {
    // Mode radio selection
    const radios = document.querySelectorAll('input[name="mode"]');
    radios.forEach(r => r.addEventListener('change', async () => {
      try { await window.azl.setMode(r.value); } catch {}
    }));

    // Core controls
    $('start')?.addEventListener('click', async () => { await window.azl.start(); });
    $('stop')?.addEventListener('click', async () => { await window.azl.stop(); });
    $('status')?.addEventListener('click', async () => {
      const res = await window.azl.status();
      setVal('statusText', (res && res.status) || '');
    });
    $('health')?.addEventListener('click', async () => {
      const res = await window.azl.healthz();
      setBadge(res.ok);
    });
    $('refreshLogs')?.addEventListener('click', async () => {
      const r = await window.azl.readLogs();
      if (r && r.ok) { setVal('out', r.outTail || ''); setVal('err', r.errTail || ''); }
    });

    document.querySelectorAll('button[data-svc]').forEach(btn => {
      btn.addEventListener('click', async () => {
        const svc = btn.getAttribute('data-svc');
        const act = btn.getAttribute('data-act') || 'restart';
        await window.azl.serviceAction(svc, act);
        $('status')?.click();
      });
    });

    $('healthAll')?.addEventListener('click', async () => {
      const h = await window.azl.healthAll();
      if (h && h.ok) {
        const ok8080 = h.health.runtime === '200';
        const ok5000 = h.health.provider === '200';
        const ok5001 = h.health.proxy === '200';
        const b = (id, ok) => { const el = $(id); if (!el) return; el.textContent = id === 'hRuntime' ? ('8080 ' + (ok ? 'OK' : 'FAIL')) : (id === 'hProvider' ? ('5000 ' + (ok ? 'OK' : 'FAIL')) : ('5001 ' + (ok ? 'OK' : 'FAIL'))); el.className = 'badge ' + (ok ? 'ok' : 'bad'); };
        b('hRuntime', ok8080); b('hProvider', ok5000); b('hProxy', ok5001);
      }
    });

    $('readLog')?.addEventListener('click', async () => {
      const which = $('logSelect').value;
      const r = await window.azl.readAllLogs(which);
      setVal('logTail', (r && r.ok) ? (r.tail || '') : ((r && r.error) || 'error'));
    });

    // Initial status/health
    $('status')?.click();
    $('healthAll')?.click();

    // Runtime base URL helper
    let runtimeCfg = null;
    try { const cfg = await window.azl.getRuntimeConfig(); if (cfg && cfg.ok) runtimeCfg = cfg; } catch {}
    const baseUrl = () => (runtimeCfg && runtimeCfg.base) ? runtimeCfg.base : 'http://127.0.0.1:8080';

    $('readyz')?.addEventListener('click', async () => {
      const t = $('token').value.trim();
      const r = await fetch(baseUrl() + '/readyz', { headers: t ? { 'Authorization': 'Bearer ' + t } : {} }).then(r => r.status).catch(() => 0);
      setVal('statusText', '/readyz ' + r);
    });
    $('statusApi')?.addEventListener('click', async () => {
      const t = $('token').value.trim();
      const r = await fetch(baseUrl() + '/status', { headers: t ? { 'Authorization': 'Bearer ' + t } : {} }).then(r => r.status).catch(() => 0);
      setVal('statusText', '/status ' + r);
    });
    $('metrics')?.addEventListener('click', async () => {
      const t = $('token').value.trim();
      const r = await fetch(baseUrl() + '/metrics', { headers: t ? { 'Authorization': 'Bearer ' + t } : {} }).then(r => r.status).catch(() => 0);
      setVal('statusText', '/metrics ' + r);
    });

    // Training controls
    $('startTrain')?.addEventListener('click', async () => {
      const dataset = $('dataset').value.trim();
      const device = $('device').value || 'cpu';
      const epochs = parseInt(($('epochs').value || '1'), 10) || 1;
      const batch_size = parseInt(($('batch').value || '1'), 10) || 1;
      const token = $('token').value.trim();
      const r = await window.azl.startAdvancedTraining({ dataset_path: dataset, device, epochs, batch_size, token });
      setVal('statusText', r && r.ok ? 'training accepted' : ('error: ' + ((r && r.error && r.error.message) || JSON.stringify(r))));
    });
    $('pauseTrain')?.addEventListener('click', async () => { const token = $('token').value.trim(); const r = await window.azl.pauseTraining({ token }); setVal('statusText', r && r.ok ? 'paused' : 'pause error'); });
    $('resumeTrain')?.addEventListener('click', async () => { const token = $('token').value.trim(); const r = await window.azl.resumeTraining({ token }); setVal('statusText', r && r.ok ? 'resumed' : 'resume error'); });
    $('stopTrain')?.addEventListener('click', async () => { const token = $('token').value.trim(); const r = await window.azl.stopTraining({ token }); setVal('statusText', r && r.ok ? 'stopped' : 'stop error'); });

    // Auto-refresh logs
    setInterval(() => $('refreshLogs')?.click(), 3000);

    // Metrics streaming
    if (window.azl && window.azl.onMetricsUpdate) {
      window.azl.onMetricsUpdate((payload) => {
        if (!payload || !payload.ok) return;
        const m = payload.metrics || {};
        const core = m.core || m || {};
        const health = m.health || {};
        const hybrid = m.hybrid || {};
        setVal('kLatency', fmt(core.avg_latency_ms ?? m.avg_latency_ms));
        setVal('kP95', fmt(health.p95_ms));
        setVal('kMem', fmt(core.peak_memory_gb ?? m.peak_memory_gb));
        setVal('kThpt', fmt(core.avg_throughput ?? m.avg_throughput));
        setVal('kLoss', fmt(core.avg_loss ?? m.avg_loss));
        setVal('kQuantum', fmt(hybrid.quantum_share_percent));

        const imp = (payload.improvements || {});
        setVal('iLatency', signFmt(imp.latencyImprovementPct));
        setVal('iMem', signFmt(imp.memoryImprovementGb));
        setVal('iLoss', signFmt(imp.lossImprovementPct));
        setVal('iQuantum', signFmt(imp.quantumImprovementPct));

        const preds = payload.predictions || [];
        const ul = $('predictions');
        if (ul) {
          ul.innerHTML = '';
          preds.forEach(p => {
            const li = document.createElement('li');
            li.textContent = `[${p.severity}] ${p.reason}`;
            ul.appendChild(li);
          });
          if (preds.length === 0) {
            const li = document.createElement('li');
            li.textContent = 'No issues predicted';
            ul.appendChild(li);
          }
        }
      });
    }

    $('metricsStart')?.addEventListener('click', async () => {
      const t = $('token').value.trim();
      await window.azl.startMetrics({ detailed: true, intervalMs: 1000, token: t });
    });
    $('metricsStop')?.addEventListener('click', async () => { await window.azl.stopMetrics(); });
    $('attemptRecovery')?.addEventListener('click', async () => {
      const t = $('token').value.trim();
      await window.azl.attemptRecovery({ token: t });
    });

    // Auto maintenance toggle
    try {
      const st = await window.azl.getAutoMaintenance();
      if (st && st.ok) { const el = $('autoMaintenance'); if (el) el.checked = !!st.enabled; }
    } catch {}
    $('autoMaintenance')?.addEventListener('change', async (e) => {
      await window.azl.setAutoMaintenance(e.target.checked);
    });

    // Header buttons
    $('btnPreferences')?.addEventListener('click', () => {
      window.open('preferences.html', 'preferences', 'width=900,height=700,resizable=yes,scrollbars=yes');
    });
    $('btnUpdates')?.addEventListener('click', async () => {
      try {
        const result = await window.electronAPI.checkForUpdates();
        alert(result && result.success ? 'Update check completed successfully' : `Update check failed: ${(result && result.error) || 'unknown'}`);
      } catch (error) {
        alert(`Error checking for updates: ${error && error.message}`);
      }
    });
    $('btnProcessStatus')?.addEventListener('click', async () => {
      try {
        const status = await window.electronAPI.getProcessStatus();
        const health = await window.electronAPI.getHealthMetrics();
        let statusText = 'Process Status:\n';
        for (const [name, info] of Object.entries(status || {})) {
          statusText += `${name}: PID ${info.pid}, Alive: ${info.alive}, Recovery Attempts: ${info.recoveryAttempts}\n`;
        }
        statusText += '\nHealth Metrics:\n';
        for (const [name, metrics] of Object.entries(health || {})) {
          statusText += `${name}: ${metrics.healthy ? 'Healthy' : 'Unhealthy'}, Last Check: ${new Date(metrics.timestamp).toLocaleString()}\n`;
        }
        alert(statusText);
      } catch (error) {
        alert(`Error getting process status: ${error && error.message}`);
      }
    });

    // Menu and update listeners
    if (window.electronAPI && window.electronAPI.onMenuAction) {
      window.electronAPI.onMenuAction((action) => {
        switch (action) {
          case 'start-all': $('start')?.click(); break;
          case 'stop-all': $('stop')?.click(); break;
          case 'check-health': $('health')?.click(); break;
          case 'show-logs': $('out')?.focus(); break;
          case 'open-preferences': $('btnPreferences')?.click(); break;
          case 'check-updates': $('btnUpdates')?.click(); break;
        }
      });
    }
    if (window.electronAPI && window.electronAPI.onUpdateStatus) {
      window.electronAPI.onUpdateStatus((status, data) => {
        console.log('Update status:', status, data);
      });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();


