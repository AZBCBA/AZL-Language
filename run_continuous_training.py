#!/usr/bin/env python3
"""
Continuous Training Runner
Runs the AZL training system continuously in the background
"""

import subprocess
import time
import os
import signal
import sys
from datetime import datetime

class ContinuousTrainingRunner:
    def __init__(self):
        self.process = None
        self.log_file = "logs/continuous_training.log"
        self.pid_file = "training.pid"
        self.weights_dir = "weights/continuous_training"
        
    def start_training(self):
        """Start the continuous training process"""
        print("🚀 Starting Continuous Real Training System")
        
        # Create necessary directories
        os.makedirs("logs", exist_ok=True)
        os.makedirs(self.weights_dir, exist_ok=True)
        
        # Start the training process
        try:
            with open(self.log_file, 'w') as log:
                self.process = subprocess.Popen(
                    ["python3", "azl_runner.py", "continuous_training_loop.azl"],
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    text=True
                )
            
            # Save PID
            with open(self.pid_file, 'w') as f:
                f.write(str(self.process.pid))
            
            print(f"✅ Training started with PID: {self.process.pid}")
            print(f"📝 Logs are being written to: {self.log_file}")
            print(f"💾 Weights will be saved to: {self.weights_dir}")
            print("🎯 Training is now running in the background")
            
            return True
            
        except Exception as e:
            print(f"❌ Failed to start training: {e}")
            return False
    
    def stop_training(self):
        """Stop the training process"""
        if self.process:
            print("🛑 Stopping training process...")
            self.process.terminate()
            
            try:
                self.process.wait(timeout=10)
                print("✅ Training process stopped gracefully")
            except subprocess.TimeoutExpired:
                print("⚠️ Force killing training process...")
                self.process.kill()
                self.process.wait()
                print("✅ Training process force stopped")
            
            self.process = None
            
            # Remove PID file
            if os.path.exists(self.pid_file):
                os.remove(self.pid_file)
    
    def check_status(self):
        """Check the status of the training process"""
        if not self.process:
            print("❌ No training process running")
            return False
        
        # Check if process is still alive
        if self.process.poll() is None:
            print(f"✅ Training process is running (PID: {self.process.pid})")
            return True
        else:
            print("❌ Training process has stopped")
            self.process = None
            return False
    
    def show_logs(self, lines=20):
        """Show recent training logs"""
        if os.path.exists(self.log_file):
            print(f"📊 Recent training logs (last {lines} lines):")
            print("-" * 50)
            
            try:
                with open(self.log_file, 'r') as f:
                    all_lines = f.readlines()
                    recent_lines = all_lines[-lines:] if len(all_lines) > lines else all_lines
                    for line in recent_lines:
                        print(line.rstrip())
            except Exception as e:
                print(f"❌ Error reading logs: {e}")
        else:
            print("❌ No log file found")
    
    def show_weights(self):
        """Show saved weights"""
        if os.path.exists(self.weights_dir):
            print(f"💾 Saved weights in {self.weights_dir}:")
            print("-" * 50)
            
            try:
                files = os.listdir(self.weights_dir)
                if files:
                    for file in sorted(files):
                        file_path = os.path.join(self.weights_dir, file)
                        size = os.path.getsize(file_path)
                        mtime = datetime.fromtimestamp(os.path.getmtime(file_path))
                        print(f"📁 {file} ({size} bytes, {mtime})")
                else:
                    print("📁 No weight files found yet")
            except Exception as e:
                print(f"❌ Error reading weights directory: {e}")
        else:
            print("❌ Weights directory not found")
    
    def run_interactive(self):
        """Run interactive mode"""
        print("🎮 Interactive Training Control")
        print("Commands: start, stop, status, logs, weights, quit")
        
        while True:
            try:
                command = input("\n🎯 Command: ").strip().lower()
                
                if command == "start":
                    if not self.process:
                        self.start_training()
                    else:
                        print("⚠️ Training already running")
                
                elif command == "stop":
                    if self.process:
                        self.stop_training()
                    else:
                        print("⚠️ No training running")
                
                elif command == "status":
                    self.check_status()
                
                elif command == "logs":
                    self.show_logs()
                
                elif command == "weights":
                    self.show_weights()
                
                elif command == "quit":
                    if self.process:
                        print("🛑 Stopping training before exit...")
                        self.stop_training()
                    print("👋 Goodbye!")
                    break
                
                else:
                    print("❓ Unknown command. Use: start, stop, status, logs, weights, quit")
                    
            except KeyboardInterrupt:
                print("\n🛑 Interrupted by user")
                if self.process:
                    self.stop_training()
                break
            except Exception as e:
                print(f"❌ Error: {e}")

def main():
    """Main function"""
    runner = ContinuousTrainingRunner()
    
    if len(sys.argv) > 1:
        command = sys.argv[1].lower()
        
        if command == "start":
            runner.start_training()
            # Keep running to maintain the process
            try:
                while True:
                    time.sleep(1)
                    if runner.process and runner.process.poll() is not None:
                        print("❌ Training process stopped unexpectedly")
                        break
            except KeyboardInterrupt:
                print("\n🛑 Stopping training...")
                runner.stop_training()
        
        elif command == "stop":
            # Try to stop existing process
            if os.path.exists("training.pid"):
                with open("training.pid", 'r') as f:
                    pid = int(f.read().strip())
                try:
                    os.kill(pid, signal.SIGTERM)
                    print(f"✅ Sent stop signal to training process {pid}")
                except ProcessLookupError:
                    print("❌ Training process not found")
            else:
                print("❌ No training PID file found")
        
        elif command == "status":
            runner.check_status()
        
        elif command == "logs":
            runner.show_logs()
        
        elif command == "weights":
            runner.show_weights()
        
        else:
            print("❓ Unknown command. Use: start, stop, status, logs, weights")
            print("💡 Run without arguments for interactive mode")
    
    else:
        # Interactive mode
        runner.run_interactive()

if __name__ == "__main__":
    main()
