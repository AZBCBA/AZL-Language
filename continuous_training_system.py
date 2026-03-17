#!/usr/bin/env python3
"""
Continuous Training System
Runs training indefinitely with monitoring and automatic restarts
"""

import os
import time
import json
import signal
import threading
import subprocess
import psutil
from datetime import datetime, timedelta
from pathlib import Path
import logging
from typing import Dict, List, Any, Optional

class ContinuousTrainingSystem:
    def __init__(self, config_path: str = "training_config.json"):
        self.config_path = config_path
        self.config = self.load_config()
        
        # Setup directories
        self.setup_directories()
        
        # Setup logging
        self.setup_logging()
        
        # Training state
        self.is_running = False
        self.current_epoch = 0
        self.total_steps = 0
        self.start_time = None
        self.last_checkpoint = None
        
        # Process management
        self.training_process = None
        self.process_id = None
        
        # Monitoring
        self.monitor_thread = None
        self.stop_monitoring = False
        self.output_thread = None
        
        # Statistics
        self.stats = {
            "total_runs": 0,
            "successful_runs": 0,
            "failed_runs": 0,
            "total_training_time": 0,
            "best_loss": float('inf'),
            "current_loss": float('inf')
        }
    
    def load_config(self) -> Dict[str, Any]:
        """Load training configuration"""
        default_config = {
            "model_architecture": "gpt_mini",
            "dataset_path": "datasets/sample_data.txt",
            "training_params": {
                "learning_rate": 0.0001,
                "batch_size": 4,
                "max_steps_per_run": 1000,
                "checkpoint_every": 100,
                "save_every": 50
            },
            "continuous_params": {
                "max_runs": 0,  # 0 = unlimited
                "restart_delay": 60,  # seconds
                "monitor_interval": 30,  # seconds
                "auto_restart": True,
                "max_memory_gb": 8.0,
                "max_cpu_percent": 80.0
            },
            "paths": {
                "weights_dir": "weights/continuous_training",
                "logs_dir": "logs/continuous_training",
                "checkpoints_dir": "checkpoints/continuous_training"
            }
        }
        
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, 'r') as f:
                    user_config = json.load(f)
                # Merge with defaults
                default_config.update(user_config)
                print(f"✅ Loaded config from {self.config_path}")
            except Exception as e:
                print(f"⚠️  Error loading config: {e}, using defaults")
        else:
            print(f"📝 No config found, creating default: {self.config_path}")
            self.save_config(default_config)
        
        return default_config
    
    def save_config(self, config: Dict[str, Any]):
        """Save training configuration"""
        with open(self.config_path, 'w') as f:
            json.dump(config, f, indent=2)
    
    def setup_directories(self):
        """Create necessary directories"""
        paths = self.config["paths"]
        for path in paths.values():
            os.makedirs(path, exist_ok=True)
    
    def setup_logging(self):
        """Setup logging system"""
        log_dir = self.config["paths"]["logs_dir"]
        log_file = os.path.join(log_dir, f"continuous_training_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler()
            ]
        )
        
        self.logger = logging.getLogger(__name__)
        self.logger.info("🚀 Continuous Training System Started")
    
    def start_training_run(self) -> bool:
        """Start a single training run"""
        try:
            self.logger.info(f"🎯 Starting training run {self.stats['total_runs'] + 1}")
            
            # Prepare training command
            # Use real GPU autoscaling trainer instead of simulated runner
            # Map key params from continuous config to real_training flags
            steps = str(self.config.get("training_params", {}).get("max_steps_per_run", 1000))
            batch = str(self.config.get("training_params", {}).get("batch_size", 4))
            ckpt_every = str(self.config.get("training_params", {}).get("checkpoint_every", 100))
            outdir = self.config.get("paths", {}).get("checkpoints_dir", "checkpoints/real_training_continuous")
            cmd = [
                "python3", "real_training.py",
                "--config", self.config_path,
                "--steps", steps,
                "--batch-size", batch,
                "--ckpt-every", ckpt_every,
                "--outdir", outdir
            ]
            
            # Start training process
            self.training_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True
            )
            
            self.process_id = self.training_process.pid
            self.is_running = True
            self.start_time = datetime.now()
            
            self.logger.info(f"✅ Training started with PID: {self.process_id}")

            # Stream child's stdout into our logs in a separate thread
            def _stream_child_output():
                try:
                    assert self.training_process and self.training_process.stdout
                    for line in self.training_process.stdout:
                        if not line:
                            break
                        self.logger.info(f"[trainer] {line.rstrip()}")
                except Exception as e:
                    self.logger.warning(f"⚠️  Output streaming ended: {e}")

            self.output_thread = threading.Thread(target=_stream_child_output)
            self.output_thread.daemon = True
            self.output_thread.start()
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Failed to start training: {e}")
            return False
    
    def stop_training_run(self):
        """Stop current training run"""
        if self.training_process and self.is_running:
            try:
                self.logger.info("🛑 Stopping training run...")
                self.training_process.terminate()
                self.training_process.wait(timeout=30)
                self.is_running = False
                self.logger.info("✅ Training stopped")
                # Join output thread if running
                if self.output_thread and self.output_thread.is_alive():
                    self.output_thread.join(timeout=2)
            except subprocess.TimeoutExpired:
                self.logger.warning("⚠️  Training didn't stop gracefully, killing...")
                self.training_process.kill()
                self.is_running = False
            except Exception as e:
                self.logger.error(f"❌ Error stopping training: {e}")
    
    def monitor_training(self):
        """Monitor training process and system resources"""
        while not self.stop_monitoring:
            try:
                if self.is_running and self.training_process:
                    # Check if process is still alive
                    if self.training_process.poll() is not None:
                        self.logger.info("📊 Training process completed")
                        self.handle_training_completion()
                        continue
                    
                    # Check system resources
                    self.check_system_resources()
                    
                    # Update statistics
                    self.update_training_stats()
                
                time.sleep(self.config["continuous_params"]["monitor_interval"])
                
            except Exception as e:
                self.logger.error(f"❌ Error in monitoring: {e}")
                time.sleep(5)
    
    def check_system_resources(self):
        """Check system resources and restart if needed"""
        try:
            # Check memory usage
            memory = psutil.virtual_memory()
            memory_gb = memory.used / (1024**3)
            
            if memory_gb > self.config["continuous_params"]["max_memory_gb"]:
                self.logger.warning(f"⚠️  High memory usage: {memory_gb:.1f} GB")
                if self.config["continuous_params"]["auto_restart"]:
                    self.logger.info("🔄 Auto-restarting due to high memory usage")
                    self.restart_training()
                    return
            
            # Check CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            if cpu_percent > self.config["continuous_params"]["max_cpu_percent"]:
                self.logger.warning(f"⚠️  High CPU usage: {cpu_percent:.1f}%")
            
        except Exception as e:
            self.logger.error(f"❌ Error checking system resources: {e}")
    
    def update_training_stats(self):
        """Update training statistics"""
        if self.start_time:
            elapsed = datetime.now() - self.start_time
            self.stats["total_training_time"] += elapsed.total_seconds()
    
    def handle_training_completion(self):
        """Handle training run completion"""
        self.is_running = False
        self.stats["total_runs"] += 1
        
        # Check exit code
        exit_code = self.training_process.returncode if self.training_process else None
        
        if exit_code == 0:
            self.stats["successful_runs"] += 1
            self.logger.info("✅ Training run completed successfully")
        else:
            self.stats["failed_runs"] += 1
            self.logger.warning(f"⚠️  Training run failed with exit code: {exit_code}")
        
        # Update checkpoint info
        self.update_checkpoint_info()
        
        # Check if we should continue
        if self.should_continue_training():
            self.schedule_next_run()
        else:
            self.logger.info("🎯 Training target reached, stopping continuous training")
            self.stop_continuous_training()
    
    def update_checkpoint_info(self):
        """Update checkpoint information"""
        checkpoints_dir = self.config["paths"]["checkpoints_dir"]
        checkpoint_files = list(Path(checkpoints_dir).glob("checkpoint_step_*.json"))
        
        if checkpoint_files:
            # Get latest checkpoint
            latest_checkpoint = max(checkpoint_files, key=lambda x: x.stat().st_mtime)
            self.last_checkpoint = latest_checkpoint.stem
            
            # Load checkpoint info
            try:
                with open(latest_checkpoint, 'r') as f:
                    checkpoint_data = json.load(f)
                
                current_loss = checkpoint_data.get("loss", float('inf'))
                self.stats["current_loss"] = current_loss
                
                if current_loss < self.stats["best_loss"]:
                    self.stats["best_loss"] = current_loss
                    self.logger.info(f"🏆 New best loss: {current_loss:.4f}")
                
            except Exception as e:
                self.logger.error(f"❌ Error reading checkpoint: {e}")
    
    def should_continue_training(self) -> bool:
        """Check if training should continue"""
        max_runs = self.config["continuous_params"]["max_runs"]
        
        if max_runs == 0:  # Unlimited
            return True
        
        return self.stats["total_runs"] < max_runs
    
    def schedule_next_run(self):
        """Schedule next training run"""
        delay = self.config["continuous_params"]["restart_delay"]
        self.logger.info(f"⏰ Scheduling next run in {delay} seconds...")
        
        # Start monitoring thread if not already running
        if not self.monitor_thread or not self.monitor_thread.is_alive():
            self.monitor_thread = threading.Thread(target=self.monitor_training)
            self.monitor_thread.daemon = True
            self.monitor_thread.start()
        
        # Schedule restart
        threading.Timer(delay, self.restart_training).start()
    
    def restart_training(self):
        """Restart training"""
        if self.is_running:
            self.stop_training_run()
        
        self.current_epoch += 1
        self.start_training_run()
    
    def start_continuous_training(self):
        """Start continuous training system"""
        self.logger.info("🚀 Starting continuous training system")
        
        # Start first training run
        if self.start_training_run():
            # Start monitoring
            self.monitor_thread = threading.Thread(target=self.monitor_training)
            self.monitor_thread.daemon = True
            self.monitor_thread.start()
            
            # Wait for completion
            try:
                while self.is_running:
                    time.sleep(1)
            except KeyboardInterrupt:
                self.logger.info("🛑 Received interrupt signal")
                self.stop_continuous_training()
        else:
            self.logger.error("❌ Failed to start training")
    
    def stop_continuous_training(self):
        """Stop continuous training system"""
        self.logger.info("🛑 Stopping continuous training system")
        
        self.stop_monitoring = True
        self.stop_training_run()
        
        # Wait for monitoring thread
        if self.monitor_thread and self.monitor_thread.is_alive():
            self.monitor_thread.join(timeout=5)
        
        # Save final statistics
        self.save_statistics()
        
        self.logger.info("✅ Continuous training system stopped")
    
    def save_statistics(self):
        """Save training statistics"""
        stats_file = os.path.join(self.config["paths"]["logs_dir"], "training_statistics.json")
        
        stats_data = {
            "timestamp": datetime.now().isoformat(),
            "statistics": self.stats,
            "config": self.config
        }
        
        with open(stats_file, 'w') as f:
            json.dump(stats_data, f, indent=2)
        
        self.logger.info(f"💾 Statistics saved to {stats_file}")
    
    def get_status(self) -> Dict[str, Any]:
        """Get current training status"""
        status = {
            "is_running": self.is_running,
            "current_epoch": self.current_epoch,
            "total_steps": self.total_steps,
            "process_id": self.process_id,
            "start_time": self.start_time.isoformat() if self.start_time else None,
            "last_checkpoint": self.last_checkpoint,
            "statistics": self.stats.copy()
        }
        
        if self.is_running and self.start_time:
            elapsed = datetime.now() - self.start_time
            status["elapsed_time"] = str(elapsed)
        
        return status
    
    def print_status(self):
        """Print current training status"""
        status = self.get_status()
        
        print("📊 CONTINUOUS TRAINING STATUS")
        print("=" * 50)
        print(f"🔄 Running: {'Yes' if status['is_running'] else 'No'}")
        print(f"📈 Current Epoch: {status['current_epoch']}")
        print(f"🎯 Total Steps: {status['total_steps']}")
        print(f"🆔 Process ID: {status['process_id']}")
        
        if status['start_time']:
            print(f"⏰ Start Time: {status['start_time']}")
            if status['elapsed_time']:
                print(f"⏱️  Elapsed: {status['elapsed_time']}")
        
        print(f"💾 Last Checkpoint: {status['last_checkpoint']}")
        
        print("\n📊 STATISTICS:")
        stats = status['statistics']
        print(f"  • Total Runs: {stats['total_runs']}")
        print(f"  • Successful: {stats['successful_runs']}")
        print(f"  • Failed: {stats['failed_runs']}")
        print(f"  • Best Loss: {stats['best_loss']:.4f}")
        print(f"  • Current Loss: {stats['current_loss']:.4f}")
        print(f"  • Total Time: {stats['total_training_time']/3600:.1f} hours")

def main():
    """Main function"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Continuous Training System")
    parser.add_argument("--config", default="training_config.json", help="Configuration file path")
    parser.add_argument("--action", choices=["start", "stop", "status", "restart"], default="start", help="Action to perform")
    
    args = parser.parse_args()
    
    # Create training system
    training_system = ContinuousTrainingSystem(args.config)
    
    if args.action == "start":
        # Setup signal handlers
        def signal_handler(signum, frame):
            training_system.stop_continuous_training()
            exit(0)
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
        
        # Start continuous training
        training_system.start_continuous_training()
        
    elif args.action == "stop":
        training_system.stop_continuous_training()
        
    elif args.action == "status":
        training_system.print_status()
        
    elif args.action == "restart":
        training_system.restart_training()

if __name__ == "__main__":
    main()
