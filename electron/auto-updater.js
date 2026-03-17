const { autoUpdater } = require('electron-updater');
const { app, dialog, BrowserWindow, ipcMain } = require('electron');
const path = require('path');

class AutoUpdateService {
  constructor(mainWindow) {
    this.mainWindow = mainWindow;
    this.updateAvailable = false;
    this.updateDownloaded = false;
    this.updateError = null;
    
    this.setupAutoUpdater();
    this.setupIPC();
  }

  setupAutoUpdater() {
    // Configure auto updater
    autoUpdater.autoDownload = false;
    autoUpdater.autoInstallOnAppQuit = true;
    
    // Set update server URL (GitHub releases)
    autoUpdater.setFeedURL({
      provider: 'github',
      owner: 'abdulrahman-alzalameh',
      repo: 'azl-language',
      private: false
    });

    // Event handlers
    autoUpdater.on('checking-for-update', () => {
      this.sendUpdateStatus('checking');
    });

    autoUpdater.on('update-available', (info) => {
      this.updateAvailable = true;
      this.sendUpdateStatus('available', info);
      this.showUpdateAvailableDialog(info);
    });

    autoUpdater.on('update-not-available', (info) => {
      this.updateAvailable = false;
      this.sendUpdateStatus('not-available', info);
    });

    autoUpdater.on('error', (err) => {
      this.updateError = err;
      this.sendUpdateStatus('error', { error: err.message });
      console.error('Auto updater error:', err);
    });

    autoUpdater.on('download-progress', (progressObj) => {
      this.sendUpdateStatus('downloading', progressObj);
    });

    autoUpdater.on('update-downloaded', (info) => {
      this.updateDownloaded = true;
      this.sendUpdateStatus('downloaded', info);
      this.showUpdateReadyDialog(info);
    });

    // Check for updates on startup
    this.checkForUpdates();
  }

  setupIPC() {
    ipcMain.handle('checkForUpdates', async () => {
      try {
        const result = await autoUpdater.checkForUpdates();
        return { success: true, result };
      } catch (error) {
        return { success: false, error: error.message };
      }
    });

    ipcMain.handle('downloadUpdate', async () => {
      try {
        if (this.updateAvailable && !this.updateDownloaded) {
          await autoUpdater.downloadUpdate();
          return { success: true };
        }
        return { success: false, error: 'No update available to download' };
      } catch (error) {
        return { success: false, error: error.message };
      }
    });

    ipcMain.handle('installUpdate', async () => {
      try {
        if (this.updateDownloaded) {
          autoUpdater.quitAndInstall();
          return { success: true };
        }
        return { success: false, error: 'No update downloaded to install' };
      } catch (error) {
        return { success: false, error: error.message };
      }
    });

    ipcMain.handle('getUpdateStatus', () => {
      return {
        updateAvailable: this.updateAvailable,
        updateDownloaded: this.updateDownloaded,
        updateError: this.updateError
      };
    });
  }

  sendUpdateStatus(status, data = {}) {
    if (this.mainWindow && !this.mainWindow.isDestroyed()) {
      this.mainWindow.webContents.send('update-status', { status, data });
    }
  }

  async checkForUpdates() {
    try {
      await autoUpdater.checkForUpdates();
    } catch (error) {
      console.error('Failed to check for updates:', error);
    }
  }

  showUpdateAvailableDialog(info) {
    if (!this.mainWindow || this.mainWindow.isDestroyed()) return;

    dialog.showMessageBox(this.mainWindow, {
      type: 'info',
      title: 'Update Available',
      message: `Version ${info.version} is available`,
      detail: `A new version of AZL Desktop is available.\n\nCurrent version: ${app.getVersion()}\nNew version: ${info.version}\n\nWould you like to download it now?`,
      buttons: ['Download Now', 'Later', 'Release Notes'],
      defaultId: 0,
      cancelId: 1
    }).then((result) => {
      switch (result.response) {
        case 0: // Download Now
          this.downloadUpdate();
          break;
        case 2: // Release Notes
          this.openReleaseNotes(info);
          break;
      }
    });
  }

  showUpdateReadyDialog(info) {
    if (!this.mainWindow || this.mainWindow.isDestroyed()) return;

    dialog.showMessageBox(this.mainWindow, {
      type: 'info',
      title: 'Update Ready',
      message: 'Update downloaded successfully',
      detail: `Version ${info.version} has been downloaded and is ready to install.\n\nThe application will restart to complete the update.`,
      buttons: ['Restart Now', 'Later'],
      defaultId: 0,
      cancelId: 1
    }).then((result) => {
      if (result.response === 0) {
        autoUpdater.quitAndInstall();
      }
    });
  }

  async downloadUpdate() {
    try {
      await autoUpdater.downloadUpdate();
    } catch (error) {
      console.error('Failed to download update:', error);
      this.showErrorDialog('Download Failed', 'Failed to download the update. Please try again later.');
    }
  }

  showErrorDialog(title, message) {
    if (!this.mainWindow || this.mainWindow.isDestroyed()) return;

    dialog.showErrorBox(title, message);
  }

  openReleaseNotes(info) {
    const releaseUrl = `https://github.com/abdulrahman-alzalameh/azl-language/releases/tag/v${info.version}`;
    require('electron').shell.openExternal(releaseUrl);
  }

  // Schedule periodic update checks
  scheduleUpdateChecks(interval = 3600000) { // Default: 1 hour
    setInterval(() => {
      this.checkForUpdates();
    }, interval);
  }
}

module.exports = AutoUpdateService;
