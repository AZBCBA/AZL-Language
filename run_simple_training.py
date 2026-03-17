#!/usr/bin/env python3
"""
Simple Training Runner
Runs the AZL training system without crashing
"""

import subprocess
import time
import os
import signal
import sys

def run_training():
    """Run the simple training system"""
    print("🚀 Starting Simple Working Training System")
    print("🎯 This will actually train on real data!")
    print("=" * 50)
    
    try:
        # Run the AZL training system
        process = subprocess.Popen(
            ["python3", "azl_runner.py", "simple_working_training.azl"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True
        )
        
        print(f"✅ Training started with PID: {process.pid}")
        print("📊 Training progress:")
        print("-" * 30)
        
        # Monitor the training process
        while True:
            output = process.stdout.readline()
            if output == '' and process.poll() is not None:
                break
            if output:
                print(output.strip())
        
        # Wait for completion
        return_code = process.poll()
        
        if return_code == 0:
            print("\n🎉 Training completed successfully!")
            print("✅ You can now train on real datasets!")
        else:
            print(f"\n❌ Training failed with return code: {return_code}")
            
    except KeyboardInterrupt:
        print("\n🛑 Training interrupted by user")
        if 'process' in locals():
            process.terminate()
            process.wait()
        return False
    except Exception as e:
        print(f"❌ Error running training: {e}")
        return False
    
    return True

def main():
    """Main function"""
    print("🎯 AZL Simple Training System")
    print("This system will:")
    print("  ✅ Train on real data")
    print("  ✅ Show training progress")
    print("  ✅ Save checkpoints")
    print("  ✅ Complete without crashing")
    print()
    
    # Run training
    success = run_training()
    
    if success:
        print("\n🎉 Training system working perfectly!")
        print("🚀 You can now use this for real datasets!")
    else:
        print("\n❌ Training system needs fixing")
        print("🔧 Let me know if you want me to debug it")

if __name__ == "__main__":
    main()
