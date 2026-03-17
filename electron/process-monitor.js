const { spawn, exec } = require('child_process');
const { ipcMain } = require('electron');
const fs = require('fs');
const path = require('path');

class ProcessMonitor {
  constructor() {
    this.processes = new Map();
    this.healthChecks = new Map();
    this.recoveryAttempts = new Map();
    this.maxRecoveryAttempts = 3;
    this.healthCheckInterval = 10000; // 10 seconds
    this.recoveryDelay = 5000; // 5 seconds
    
    this.setupIPC();
    this.startHealthMonitoring();
  }

  setupIPC() {
    ipcMain.handle('getProcessStatus', () => {
      const status = {};
      for (const [name, process] of this.processes) {
        status[name] = {
          pid: process.pid,
          alive: !process.killed,
          exitCode: process.exitCode,
          recoveryAttempts: this.recoveryAttempts.get(name) || 0
        };
      }
      return status;
    });

    ipcMain.handle('restartProcess', async (event, processName) => {
      return await this.restartProcess(processName);
    });

    ipcMain.handle('killProcess', async (event, processName) => {
      return await this.killProcess(processName);
    });

    ipcMain.handle('getHealthMetrics', () => {
      const metrics = {};
      for (const [name, health] of this.healthChecks) {
        metrics[name] = health;
      }
      return metrics;
    });
  }

  registerProcess(name, command, args = [], options = {}) {
    try {
      // Kill existing process if any
      if (this.processes.has(name)) {
        this.killProcess(name);
      }

      const process = spawn(command, args, {
        stdio: ['ignore', 'pipe', 'pipe'],
        ...options
      });

      this.processes.set(name, process);
      this.recoveryAttempts.set(name, 0);

      // Set up process event handlers
      process.on('exit', (code, signal) => {
        console.log(`Process ${name} exited with code ${code} and signal ${signal}`);
        this.handleProcessExit(name, code, signal);
      });

      process.on('error', (error) => {
        console.error(`Process ${name} error:`, error);
        this.handleProcessError(name, error);
      });

      // Set up health check for this process
      this.setupHealthCheck(name);

      console.log(`Process ${name} registered with PID ${process.pid}`);
      return { success: true, pid: process.pid };
    } catch (error) {
      console.error(`Failed to register process ${name}:`, error);
      return { success: false, error: error.message };
    }
  }

  setupHealthCheck(processName) {
    const healthCheck = setInterval(async () => {
      const process = this.processes.get(processName);
      if (!process || process.killed) {
        clearInterval(healthCheck);
        this.healthChecks.delete(processName);
        return;
      }

      try {
        const isHealthy = await this.checkProcessHealth(processName);
        this.healthChecks.set(processName, {
          timestamp: Date.now(),
          healthy: isHealthy,
          pid: process.pid,
          memory: await this.getProcessMemory(process.pid),
          cpu: await this.getProcessCPU(process.pid)
        });

        if (!isHealthy) {
          console.warn(`Process ${processName} health check failed`);
          await this.handleUnhealthyProcess(processName);
        }
      } catch (error) {
        console.error(`Health check failed for ${processName}:`, error);
        this.healthChecks.set(processName, {
          timestamp: Date.now(),
          healthy: false,
          error: error.message
        });
      }
    }, this.healthCheckInterval);

    this.healthChecks.set(processName, {
      timestamp: Date.now(),
      healthy: true,
      pid: null
    });
  }

  async checkProcessHealth(processName) {
    const process = this.processes.get(processName);
    if (!process || process.killed) return false;

    try {
      // Check if process is responding
      switch (processName) {
        case 'sysproxy':
          return await this.checkEndpointHealth('http://127.0.0.1:9099/health');
        case 'runtime':
          return await this.checkEndpointHealth('http://127.0.0.1:8080/healthz');
        case 'provider':
          return await this.checkEndpointHealth('http://127.0.0.1:5000/health');
        case 'proxy':
          return await this.checkEndpointHealth('http://127.0.0.1:5001/health');
        default:
          // For unknown processes, just check if they're alive
          return !process.killed && process.exitCode === null;
      }
    } catch (error) {
      console.error(`Health check error for ${processName}:`, error);
      return false;
    }
  }

  async checkEndpointHealth(url) {
    return new Promise((resolve) => {
      const { spawn } = require('child_process');
      const curl = spawn('curl', ['-sS', '-m', '2', '-o', '/dev/null', '-w', '%{http_code}', url]);
      
      let output = '';
      curl.stdout.on('data', (data) => output += data.toString());
      
      curl.on('close', (code) => {
        const httpCode = parseInt(output.trim());
        resolve(code === 0 && (httpCode === 200 || httpCode === 202));
      });
      
      curl.on('error', () => resolve(false));
    });
  }

  async getProcessMemory(pid) {
    try {
      const memInfo = fs.readFileSync(`/proc/${pid}/status`, 'utf8');
      const vmRssMatch = memInfo.match(/VmRSS:\s+(\d+)/);
      return vmRssMatch ? parseInt(vmRssMatch[1]) : null;
    } catch {
      return null;
    }
  }

  async getProcessCPU(pid) {
    try {
      const stat = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
      const parts = stat.split(' ');
      return parts.length > 13 ? parts[13] : null;
    } catch {
      return null;
    }
  }

  async handleUnhealthyProcess(processName) {
    const attempts = this.recoveryAttempts.get(processName) || 0;
    
    if (attempts >= this.maxRecoveryAttempts) {
      console.error(`Process ${processName} exceeded max recovery attempts`);
      return { success: false, error: 'Max recovery attempts exceeded' };
    }

    console.log(`Attempting to recover process ${processName} (attempt ${attempts + 1})`);
    
    // Increment recovery attempts
    this.recoveryAttempts.set(processName, attempts + 1);

    // Wait before attempting recovery
    await new Promise(resolve => setTimeout(resolve, this.recoveryDelay));

    // Attempt to restart the process
    return await this.restartProcess(processName);
  }

  async restartProcess(processName) {
    try {
      console.log(`Restarting process ${processName}`);
      
      // Kill existing process
      await this.killProcess(processName);
      
      // Wait a bit for cleanup
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      // Re-register the process (this will spawn a new one)
      const result = this.registerProcess(processName, this.getProcessCommand(processName));
      
      if (result.success) {
        console.log(`Process ${processName} restarted successfully`);
        this.recoveryAttempts.set(processName, 0); // Reset recovery attempts
      }
      
      return result;
    } catch (error) {
      console.error(`Failed to restart process ${processName}:`, error);
      return { success: false, error: error.message };
    }
  }

  getProcessCommand(processName) {
    const commands = {
      'sysproxy': '/usr/local/bin/azl-sysproxy',
      'runtime': process.execPath,
      'provider': process.execPath,
      'proxy': process.execPath
    };
    
    return commands[processName] || processName;
  }

  async killProcess(processName) {
    const process = this.processes.get(processName);
    if (!process) return { success: false, error: 'Process not found' };

    try {
      // Try graceful shutdown first
      process.kill('SIGTERM');
      
      // Wait for graceful shutdown
      await new Promise((resolve) => {
        const timeout = setTimeout(() => {
          resolve();
        }, 5000);
        
        process.once('exit', () => {
          clearTimeout(timeout);
          resolve();
        });
      });

      // Force kill if still alive
      if (!process.killed) {
        process.kill('SIGKILL');
      }

      this.processes.delete(processName);
      this.healthChecks.delete(processName);
      
      return { success: true };
    } catch (error) {
      console.error(`Failed to kill process ${processName}:`, error);
      return { success: false, error: error.message };
    }
  }

  handleProcessExit(processName, code, signal) {
    console.log(`Process ${processName} exited with code ${code} and signal ${signal}`);
    
    // Remove from active processes
    this.processes.delete(processName);
    this.healthChecks.delete(processName);
    
    // Attempt recovery if it wasn't a manual kill
    if (signal !== 'SIGTERM' && signal !== 'SIGKILL') {
      setTimeout(() => {
        this.handleUnhealthyProcess(processName);
      }, this.recoveryDelay);
    }
  }

  handleProcessError(processName, error) {
    console.error(`Process ${processName} error:`, error);
    
    // Attempt recovery
    setTimeout(() => {
      this.handleUnhealthyProcess(processName);
    }, this.recoveryDelay);
  }

  startHealthMonitoring() {
    console.log('Process health monitoring started');
  }

  stopHealthMonitoring() {
    // Clear all health check intervals
    for (const [name, health] of this.healthChecks) {
      if (health.interval) {
        clearInterval(health.interval);
      }
    }
    this.healthChecks.clear();
  }

  // Graceful shutdown of all processes
  async shutdown() {
    console.log('Initiating graceful shutdown...');
    
    const shutdownPromises = [];
    
    for (const [name, process] of this.processes) {
      shutdownPromises.push(this.killProcess(name));
    }
    
    try {
      await Promise.allSettled(shutdownPromises);
      console.log('All processes shut down successfully');
    } catch (error) {
      console.error('Error during shutdown:', error);
    }
    
    this.stopHealthMonitoring();
  }

  // Get summary of all processes
  getStatusSummary() {
    const summary = {
      total: this.processes.size,
      healthy: 0,
      unhealthy: 0,
      recovering: 0,
      processes: {}
    };

    for (const [name, process] of this.processes) {
      const health = this.healthChecks.get(name);
      const attempts = this.recoveryAttempts.get(name) || 0;
      
      const status = {
        pid: process.pid,
        alive: !process.killed,
        healthy: health ? health.healthy : false,
        recoveryAttempts: attempts,
        lastHealthCheck: health ? health.timestamp : null
      };

      summary.processes[name] = status;
      
      if (status.healthy) {
        summary.healthy++;
      } else if (attempts > 0) {
        summary.recovering++;
      } else {
        summary.unhealthy++;
      }
    }

    return summary;
  }
}

module.exports = ProcessMonitor;
