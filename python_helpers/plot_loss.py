#!/usr/bin/env python3
"""
Loss curve plotting utility for AZL training pipeline.
Reads loss data from TSV file and generates visualization.
"""

import pandas as pd
import matplotlib.pyplot as plt
import os
import sys
from pathlib import Path

def plot_loss_curve():
    """Plot loss curve from TSV data and save to file."""
    
    # Paths
    log_file = "logs/loss.tsv"
    output_dir = "mnt/data"
    output_file = os.path.join(output_dir, "loss_curve.png")
    
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    try:
        # Read the TSV file
        if os.path.exists(log_file):
            df = pd.read_csv(log_file, sep='\t', names=['step', 'loss'])
            
            # Display recent data
            print("📊 Recent loss data:")
            print(df.tail(10).to_string(index=False))
            
            # Create the plot
            plt.figure(figsize=(12, 8))
            plt.plot(df['step'], df['loss'], 'b-', linewidth=2, alpha=0.8)
            plt.yscale('log')
            plt.xlabel('Global Step', fontsize=12)
            plt.ylabel('Cross-entropy Loss', fontsize=12)
            plt.title('Training Loss Curve', fontsize=14, fontweight='bold')
            plt.grid(True, alpha=0.3)
            
            # Add some styling
            plt.tight_layout()
            
            # Save the plot
            plt.savefig(output_file, dpi=300, bbox_inches='tight')
            plt.close()
            
            print(f"🖼️ Loss curve saved to: {output_file}")
            
            # Also save a summary
            summary_file = os.path.join(output_dir, "loss_summary.txt")
            with open(summary_file, 'w') as f:
                f.write(f"Loss Summary\n")
                f.write(f"============\n")
                f.write(f"Total steps: {len(df)}\n")
                f.write(f"Final loss: {df['loss'].iloc[-1]:.4f}\n")
                f.write(f"Min loss: {df['loss'].min():.4f}\n")
                f.write(f"Max loss: {df['loss'].max():.4f}\n")
                f.write(f"Average loss: {df['loss'].mean():.4f}\n")
            
            print(f"📄 Summary saved to: {summary_file}")
            
        else:
            print(f"⚠️ Log file not found: {log_file}")
            print("Creating sample plot...")
            
            # Create a sample plot if no data exists
            steps = list(range(1, 101))
            losses = [2.73 - (i * 0.01) for i in steps]
            
            plt.figure(figsize=(12, 8))
            plt.plot(steps, losses, 'b-', linewidth=2, alpha=0.8)
            plt.yscale('log')
            plt.xlabel('Global Step', fontsize=12)
            plt.ylabel('Cross-entropy Loss', fontsize=12)
            plt.title('Sample Training Loss Curve', fontsize=14, fontweight='bold')
            plt.grid(True, alpha=0.3)
            plt.tight_layout()
            plt.savefig(output_file, dpi=300, bbox_inches='tight')
            plt.close()
            
            print(f"🖼️ Sample loss curve saved to: {output_file}")
            
    except Exception as e:
        print(f"❌ Error plotting loss curve: {e}")
        return False
    
    return True

if __name__ == "__main__":
    success = plot_loss_curve()
    if success:
        print("✅ Loss curve plotting completed successfully!")
    else:
        print("❌ Loss curve plotting failed!")
        sys.exit(1)
