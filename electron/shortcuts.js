const { globalShortcut, Menu, MenuItem, ipcMain } = require('electron');
const path = require('path');

class ShortcutsManager {
  constructor(mainWindow, settingsManager) {
    this.mainWindow = mainWindow;
    this.settingsManager = settingsManager;
    this.registeredShortcuts = new Map();
    this.menu = null;
    
    this.setupMenu();
    this.setupGlobalShortcuts();
    this.setupIPC();
  }

  setupMenu() {
    this.menu = Menu.buildFromTemplate([
      {
        label: 'File',
        submenu: [
          {
            label: 'New Chat',
            accelerator: 'CmdOrCtrl+Shift+C',
            click: () => this.mainWindow.webContents.send('menu-action', 'open-chat')
          },
          {
            label: 'New Session',
            accelerator: 'CmdOrCtrl+N',
            click: () => this.mainWindow.webContents.send('menu-action', 'new-session')
          },
          {
            label: 'Open Logs',
            accelerator: 'CmdOrCtrl+O',
            click: () => this.mainWindow.webContents.send('menu-action', 'open-logs')
          },
          { type: 'separator' },
          {
            label: 'Preferences...',
            accelerator: 'CmdOrCtrl+,',
            click: () => this.mainWindow.webContents.send('menu-action', 'open-preferences')
          },
          { type: 'separator' },
          {
            label: 'Quit',
            accelerator: process.platform === 'darwin' ? 'Cmd+Q' : 'Ctrl+Q',
            click: () => this.mainWindow.webContents.send('menu-action', 'quit')
          }
        ]
      },
      {
        label: 'Edit',
        submenu: [
          { role: 'undo', accelerator: 'CmdOrCtrl+Z' },
          { role: 'redo', accelerator: 'CmdOrCtrl+Shift+Z' },
          { type: 'separator' },
          { role: 'cut', accelerator: 'CmdOrCtrl+X' },
          { role: 'copy', accelerator: 'CmdOrCtrl+C' },
          { role: 'paste', accelerator: 'CmdOrCtrl+V' },
          { role: 'selectall', accelerator: 'CmdOrCtrl+A' }
        ]
      },
      {
        label: 'View',
        submenu: [
          { role: 'reload', accelerator: 'CmdOrCtrl+R' },
          { role: 'forceReload', accelerator: 'CmdOrCtrl+Shift+R' },
          { role: 'toggleDevTools', accelerator: 'F12' },
          { type: 'separator' },
          { role: 'resetZoom', accelerator: 'CmdOrCtrl+0' },
          { role: 'zoomIn', accelerator: 'CmdOrCtrl+Plus' },
          { role: 'zoomOut', accelerator: 'CmdOrCtrl+-' },
          { type: 'separator' },
          { role: 'togglefullscreen', accelerator: 'F11' }
        ]
      },
      {
        label: 'AZL',
        submenu: [
          {
            label: 'Start All Services',
            accelerator: 'CmdOrCtrl+Shift+S',
            click: () => this.mainWindow.webContents.send('menu-action', 'start-all')
          },
          {
            label: 'Stop All Services',
            accelerator: 'CmdOrCtrl+Shift+X',
            click: () => this.mainWindow.webContents.send('menu-action', 'stop-all')
          },
          {
            label: 'Check Health',
            accelerator: 'CmdOrCtrl+Shift+H',
            click: () => this.mainWindow.webContents.send('menu-action', 'check-health')
          },
          {
            label: 'Show Logs',
            accelerator: 'CmdOrCtrl+Shift+L',
            click: () => this.mainWindow.webContents.send('menu-action', 'show-logs')
          },
          { type: 'separator' },
          {
            label: 'Restart Sysproxy',
            accelerator: 'CmdOrCtrl+Shift+1',
            click: () => this.mainWindow.webContents.send('menu-action', 'restart-sysproxy')
          },
          {
            label: 'Restart Runtime',
            accelerator: 'CmdOrCtrl+Shift+2',
            click: () => this.mainWindow.webContents.send('menu-action', 'restart-runtime')
          },
          {
            label: 'Restart Provider',
            accelerator: 'CmdOrCtrl+Shift+3',
            click: () => this.mainWindow.webContents.send('menu-action', 'restart-provider')
          },
          {
            label: 'Restart Proxy',
            accelerator: 'CmdOrCtrl+Shift+4',
            click: () => this.mainWindow.webContents.send('menu-action', 'restart-proxy')
          }
        ]
      },
      {
        label: 'Window',
        submenu: [
          {
            label: 'Minimize',
            accelerator: 'CmdOrCtrl+M',
            click: () => this.mainWindow.minimize()
          },
          {
            label: 'Hide',
            accelerator: 'CmdOrCtrl+H',
            click: () => this.mainWindow.hide()
          },
          {
            label: 'Show/Hide',
            accelerator: 'CmdOrCtrl+Shift+A',
            click: () => this.toggleWindowVisibility()
          },
          { type: 'separator' },
          { role: 'close' }
        ]
      },
      {
        label: 'Help',
        submenu: [
          {
            label: 'About AZL Desktop',
            click: () => this.mainWindow.webContents.send('menu-action', 'about')
          },
          {
            label: 'Check for Updates',
            click: () => this.mainWindow.webContents.send('menu-action', 'check-updates')
          },
          {
            label: 'Documentation',
            click: () => this.mainWindow.webContents.send('menu-action', 'documentation')
          },
          {
            label: 'Report Issue',
            click: () => this.mainWindow.webContents.send('menu-action', 'report-issue')
          }
        ]
      }
    ]);

    // Set the menu
    Menu.setApplicationMenu(this.menu);
  }

  setupGlobalShortcuts() {
    const shortcuts = this.settingsManager.getShortcuts();
    
    // Register global shortcuts
    this.registerGlobalShortcut('showHide', shortcuts.showHide, () => {
      this.toggleWindowVisibility();
    });

    this.registerGlobalShortcut('startAll', shortcuts.startAll, () => {
      this.mainWindow.webContents.send('menu-action', 'start-all');
    });

    this.registerGlobalShortcut('stopAll', shortcuts.stopAll, () => {
      this.mainWindow.webContents.send('menu-action', 'stop-all');
    });

    this.registerGlobalShortcut('health', shortcuts.health, () => {
      this.mainWindow.webContents.send('menu-action', 'check-health');
    });

    this.registerGlobalShortcut('logs', shortcuts.logs, () => {
      this.mainWindow.webContents.send('menu-action', 'show-logs');
    });

    // Chat shortcut (fixed mapping, also in menu)
    this.registerGlobalShortcut('openChat', 'CmdOrCtrl+Shift+C', () => {
      this.mainWindow.webContents.send('menu-action', 'open-chat');
    });
  }

  registerGlobalShortcut(name, accelerator, callback) {
    try {
      if (this.registeredShortcuts.has(name)) {
        globalShortcut.unregister(this.registeredShortcuts.get(name));
      }
      
      if (globalShortcut.register(accelerator, callback)) {
        this.registeredShortcuts.set(name, accelerator);
        console.log(`Global shortcut registered: ${name} -> ${accelerator}`);
      } else {
        console.warn(`Failed to register global shortcut: ${name} -> ${accelerator}`);
      }
    } catch (error) {
      console.error(`Error registering shortcut ${name}:`, error);
    }
  }

  setupIPC() {
    ipcMain.handle('updateShortcut', async (event, action, newAccelerator) => {
      try {
        // Unregister old shortcut
        const oldAccelerator = this.registeredShortcuts.get(action);
        if (oldAccelerator) {
          globalShortcut.unregister(oldAccelerator);
        }

        // Register new shortcut
        const shortcuts = this.settingsManager.getShortcuts();
        const callback = this.getShortcutCallback(action);
        
        if (callback && globalShortcut.register(newAccelerator, callback)) {
          this.registeredShortcuts.set(action, newAccelerator);
          this.settingsManager.updateShortcut(action, newAccelerator);
          
          // Update menu if it's a menu shortcut
          this.updateMenuShortcut(action, newAccelerator);
          
          return { success: true };
        } else {
          return { success: false, error: 'Invalid accelerator' };
        }
      } catch (error) {
        return { success: false, error: error.message };
      }
    });

    ipcMain.handle('getShortcuts', () => {
      return this.settingsManager.getShortcuts();
    });

    ipcMain.handle('resetShortcuts', () => {
      this.resetShortcutsToDefaults();
      return { success: true };
    });
  }

  getShortcutCallback(action) {
    const callbacks = {
      'showHide': () => this.toggleWindowVisibility(),
      'startAll': () => this.mainWindow.webContents.send('menu-action', 'start-all'),
      'stopAll': () => this.mainWindow.webContents.send('menu-action', 'stop-all'),
      'health': () => this.mainWindow.webContents.send('menu-action', 'check-health'),
      'logs': () => this.mainWindow.webContents.send('menu-action', 'show-logs')
    };
    
    return callbacks[action];
  }

  updateMenuShortcut(action, accelerator) {
    // Update menu items with new accelerators
    const menuItems = this.menu.items;
    
    for (const menu of menuItems) {
      if (menu.submenu) {
        this.updateSubmenuShortcuts(menu.submenu, action, accelerator);
      }
    }
  }

  updateSubmenuShortcuts(submenu, action, accelerator) {
    for (const item of submenu.items) {
      if (item.submenu) {
        this.updateSubmenuShortcuts(item.submenu, action, accelerator);
      } else if (item.click && item.accelerator) {
        // Update specific menu items based on action
        if (action === 'showHide' && item.label === 'Show/Hide') {
          item.accelerator = accelerator;
        } else if (action === 'startAll' && item.label === 'Start All Services') {
          item.accelerator = accelerator;
        } else if (action === 'stopAll' && item.label === 'Stop All Services') {
          item.accelerator = accelerator;
        } else if (action === 'health' && item.label === 'Check Health') {
          item.accelerator = accelerator;
        } else if (action === 'logs' && item.label === 'Show Logs') {
          item.accelerator = accelerator;
        }
      }
    }
  }

  toggleWindowVisibility() {
    if (this.mainWindow.isVisible()) {
      this.mainWindow.hide();
    } else {
      this.mainWindow.show();
      this.mainWindow.focus();
    }
  }

  resetShortcutsToDefaults() {
    const defaultShortcuts = {
      showHide: 'CmdOrCtrl+Shift+A',
      startAll: 'CmdOrCtrl+Shift+S',
      stopAll: 'CmdOrCtrl+Shift+X',
      health: 'CmdOrCtrl+Shift+H',
      logs: 'CmdOrCtrl+Shift+L'
    };

    // Unregister all current shortcuts
    for (const [name, accelerator] of this.registeredShortcuts) {
      globalShortcut.unregister(accelerator);
    }
    this.registeredShortcuts.clear();

    // Reset settings
    this.settingsManager.set('shortcuts', defaultShortcuts);

    // Re-register with defaults
    this.setupGlobalShortcuts();
    
    // Rebuild menu
    this.setupMenu();
  }

  // Validate accelerator format
  validateAccelerator(accelerator) {
    try {
      // Test if the accelerator is valid by trying to register it temporarily
      const testRegistration = globalShortcut.register(accelerator, () => {});
      if (testRegistration) {
        globalShortcut.unregister(accelerator);
        return true;
      }
      return false;
    } catch {
      return false;
    }
  }

  // Get all registered shortcuts
  getRegisteredShortcuts() {
    return Object.fromEntries(this.registeredShortcuts);
  }

  // Cleanup
  cleanup() {
    globalShortcut.unregisterAll();
    this.registeredShortcuts.clear();
  }
}

module.exports = ShortcutsManager;
