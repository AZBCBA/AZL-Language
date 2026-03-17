const Store = require('electron-store');
const path = require('path');

class SettingsManager {
  constructor() {
    this.store = new Store({
      name: 'azl-desktop-settings',
      defaults: {
        theme: 'dark',
        autoStart: false,
        minimizeToTray: true,
        autoUpdate: true,
        checkUpdatesInterval: 3600000, // 1 hour
        windowBounds: {
          width: 900,
          height: 640,
          x: undefined,
          y: undefined
        },
        behavior: {
          autoRecoveryRenderer: true
        },
        security: {
          csp: {
            enforce: true,
            policy: "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self' http://127.0.0.1:8080 http://127.0.0.1:5000 http://127.0.0.1:5001; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
          },
          permissionAllowlist: [],
          devToolsInProd: false
        },
        api: {
          token: ""
        },
        tls: {
          pinningEnabled: false,
          pins: {}
        },
        accessibility: {
          highContrast: false,
          reduceMotion: false,
          screenReader: false
        },
        shortcuts: {
          showHide: 'CmdOrCtrl+Shift+A',
          startAll: 'CmdOrCtrl+Shift+S',
          stopAll: 'CmdOrCtrl+Shift+X',
          health: 'CmdOrCtrl+Shift+H',
          logs: 'CmdOrCtrl+Shift+L'
        }
      }
    });

    this.themes = {
      dark: {
        '--bg': '#0f172a',
        '--card': '#111827',
        '--fg': '#e5e7eb',
        '--muted': '#9ca3af',
        '--accent': '#22d3ee',
        '--ok': '#22c55e',
        '--bad': '#ef4444',
        '--btn': '#1f2937',
        '--border': '#1f2937',
        '--input-bg': '#0a0f1a',
        '--input-fg': '#cbd5e1'
      },
      light: {
        '--bg': '#ffffff',
        '--card': '#f8fafc',
        '--fg': '#0f172a',
        '--muted': '#64748b',
        '--accent': '#0891b2',
        '--ok': '#16a34a',
        '--bad': '#dc2626',
        '--btn': '#e2e8f0',
        '--border': '#cbd5e1',
        '--input-bg': '#ffffff',
        '--input-fg': '#0f172a'
      },
      highContrast: {
        '--bg': '#000000',
        '--card': '#000000',
        '--fg': '#ffffff',
        '--muted': '#ffffff',
        '--accent': '#ffff00',
        '--ok': '#00ff00',
        '--bad': '#ff0000',
        '--btn': '#ffffff',
        '--border': '#ffffff',
        '--input-bg': '#000000',
        '--input-fg': '#ffffff'
      }
    };
  }

  get(key) {
    return this.store.get(key);
  }

  set(key, value) {
    this.store.set(key, value);
    return this;
  }

  getTheme() {
    const themeName = this.get('theme');
    const highContrast = this.get('accessibility.highContrast');
    
    if (highContrast) {
      return this.themes.highContrast;
    }
    
    return this.themes[themeName] || this.themes.dark;
  }

  applyTheme(webContents) {
    const theme = this.getTheme();
    const css = Object.entries(theme)
      .map(([property, value]) => `${property}: ${value};`)
      .join('\n');
    
    webContents.insertCSS(`
      :root {
        ${css}
      }
    `);
  }

  getWindowBounds() {
    return this.get('windowBounds');
  }

  saveWindowBounds(bounds) {
    this.set('windowBounds', bounds);
  }

  getShortcuts() {
    return this.get('shortcuts');
  }

  updateShortcut(action, key) {
    this.set(`shortcuts.${action}`, key);
  }

  getAccessibilitySettings() {
    return this.get('accessibility');
  }

  updateAccessibilitySetting(setting, value) {
    this.set(`accessibility.${setting}`, value);
  }

  resetToDefaults() {
    this.store.clear();
    this.store.store = { ...this.store.store, ...this.store.defaults };
  }

  exportSettings() {
    return JSON.stringify(this.store.store, null, 2);
  }

  importSettings(jsonString) {
    try {
      const settings = JSON.parse(jsonString);
      this.store.store = { ...this.store.store, ...settings };
      return true;
    } catch (error) {
      return false;
    }
  }
}

module.exports = SettingsManager;
