let currentSettings = {};

document.addEventListener('DOMContentLoaded', async () => {
  await loadSettings();
  setupEventListeners();
  updateUI();
});

async function loadSettings() {
  try {
    currentSettings = await window.electronAPI.getSettings();
  } catch (error) {
    console.error('Failed to load settings:', error);
  }
}

function setupEventListeners() {
  document.getElementById('themeSelect').addEventListener('change', (e) => {
    updateSetting('theme', e.target.value);
    updateThemePreview();
  });

  document.querySelectorAll('.theme-option').forEach(option => {
    option.addEventListener('click', () => {
      const theme = option.dataset.theme;
      document.getElementById('themeSelect').value = theme;
      updateSetting('theme', theme);
      updateThemePreview();
    });
  });

  ['highContrastToggle', 'reduceMotionToggle', 'screenReaderToggle', 
   'autoUpdateToggle', 'autoStartToggle', 'minimizeToTrayToggle',
   'cspEnforceToggle', 'pinningToggle', 'autoRecoveryToggle'].forEach(id => {
    document.getElementById(id).addEventListener('click', () => {
      const toggle = document.getElementById(id);
      const isActive = toggle.classList.contains('active');
      toggle.classList.toggle('active');
      
      const settingMap = {
        'highContrastToggle': 'accessibility.highContrast',
        'reduceMotionToggle': 'accessibility.reduceMotion',
        'screenReaderToggle': 'accessibility.screenReader',
        'autoUpdateToggle': 'autoUpdate',
        'autoStartToggle': 'autoStart',
        'minimizeToTrayToggle': 'minimizeToTray',
        'cspEnforceToggle': 'security.csp.enforce',
        'pinningToggle': 'tls.pinningEnabled',
        'autoRecoveryToggle': 'behavior.autoRecoveryRenderer'
      };
      
      updateSetting(settingMap[id], !isActive);
    });
  });

  document.getElementById('cspPolicy').addEventListener('change', (e) => {
    updateSetting('security.csp.policy', e.target.value);
  });
  document.getElementById('pinsJson').addEventListener('change', (e) => {
    try { const obj = JSON.parse(e.target.value || '{}'); updateSetting('tls.pins', obj); } catch {}
  });
  document.getElementById('permAllowlist').addEventListener('change', (e) => {
    const list = (e.target.value || '').split(',').map(s => s.trim()).filter(Boolean);
    updateSetting('security.permissionAllowlist', list);
  });
}

function updateUI() {
  document.getElementById('themeSelect').value = currentSettings.theme || 'dark';
  updateThemePreview();

  updateToggleUI('highContrastToggle', currentSettings.accessibility?.highContrast || false);
  updateToggleUI('reduceMotionToggle', currentSettings.accessibility?.reduceMotion || false);
  updateToggleUI('screenReaderToggle', currentSettings.accessibility?.screenReader || false);
  updateToggleUI('autoUpdateToggle', currentSettings.autoUpdate || false);
  updateToggleUI('autoStartToggle', currentSettings.autoStart || false);
  updateToggleUI('minimizeToTrayToggle', currentSettings.minimizeToTray || false);
  updateToggleUI('cspEnforceToggle', currentSettings.security?.csp?.enforce ?? true);
  document.getElementById('cspPolicy').value = currentSettings.security?.csp?.policy || '';
  updateToggleUI('pinningToggle', currentSettings.tls?.pinningEnabled || false);
  document.getElementById('pinsJson').value = JSON.stringify(currentSettings.tls?.pins || {});
  document.getElementById('permAllowlist').value = (currentSettings.security?.permissionAllowlist || []).join(',');
  updateToggleUI('autoRecoveryToggle', currentSettings.behavior?.autoRecoveryRenderer ?? true);

  updateShortcutDisplay();
}

function updateThemePreview() {
  const theme = currentSettings.theme || 'dark';
  document.querySelectorAll('.theme-option').forEach(option => {
    option.classList.remove('active');
    if (option.dataset.theme === theme) {
      option.classList.add('active');
    }
  });
}

function updateToggleUI(toggleId, isActive) {
  const toggle = document.getElementById(toggleId);
  if (isActive) {
    toggle.classList.add('active');
  } else {
    toggle.classList.remove('active');
  }
}

function updateShortcutDisplay() {
  const shortcuts = currentSettings.shortcuts || {};
  document.getElementById('showHideShortcut').value = shortcuts.showHide || 'CmdOrCtrl+Shift+A';
  document.getElementById('startAllShortcut').value = shortcuts.startAll || 'CmdOrCtrl+Shift+S';
  document.getElementById('stopAllShortcut').value = shortcuts.stopAll || 'CmdOrCtrl+Shift+X';
}

async function updateSetting(key, value) {
  try {
    await window.electronAPI.updateSetting(key, value);
    if (key.includes('.')) {
      const [parent, child] = key.split('.');
      if (!currentSettings[parent]) currentSettings[parent] = {};
      currentSettings[parent][child] = value;
    } else {
      currentSettings[key] = value;
    }
  } catch (error) {
    console.error('Failed to update setting:', error);
  }
}

async function checkForUpdates() {
  try {
    await window.electronAPI.checkForUpdates();
  } catch (error) {
    console.error('Failed to check for updates:', error);
  }
}

async function saveSettings() {
  alert('Settings saved successfully!');
}

async function exportSettings() {
  try {
    const result = await window.electronAPI.exportSettings();
    if (result.success) {
      const blob = new Blob([result.data], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'azl-desktop-settings.json';
      a.click();
      URL.revokeObjectURL(url);
    }
  } catch (error) {
    console.error('Failed to export settings:', error);
  }
}

async function importSettings() {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = '.json';
  input.onchange = async (e) => {
    const file = e.target.files[0];
    if (file) {
      try {
        const text = await file.text();
        const result = await window.electronAPI.importSettings(text);
        if (result.success) {
          await loadSettings();
          updateUI();
          alert('Settings imported successfully!');
        }
      } catch (error) {
        console.error('Failed to import settings:', error);
      }
    }
  };
  input.click();
}

async function resetSettings() {
  if (confirm('Reset all settings to defaults?')) {
    try {
      await window.electronAPI.resetSettings();
      await loadSettings();
      updateUI();
      alert('Settings reset to defaults!');
    } catch (error) {
      console.error('Failed to reset settings:', error);
    }
  }
}

async function resetShortcuts() {
  if (confirm('Reset keyboard shortcuts to defaults?')) {
    try {
      await window.electronAPI.resetShortcuts();
      await loadSettings();
      updateUI();
      alert('Shortcuts reset to defaults!');
    } catch (error) {
      console.error('Failed to reset shortcuts:', error);
    }
  }
}


