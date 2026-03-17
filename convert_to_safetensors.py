#!/usr/bin/env python3
"""
One-time conversion script to convert state_dict checkpoints to safetensors format.
This eliminates pickle loading and provides faster, safer model loading.
"""

import os
import torch
from pathlib import Path
from safetensors.torch import save_file

# Directories to process
ROOTS = [
    "/mnt/ssd4t/azl-training",
    "/mnt/ssd4t/models", 
    "/mnt/ssd4t/azme-venv-image-models",
    "weights",
    "checkpoints"
]

def is_zip_torchscript(p: Path) -> bool:
    """Check if file is a TorchScript zip archive"""
    try:
        with open(p, "rb") as f:
            sig = f.read(4)
        return sig == b"PK\x03\x04"  # TorchScript .pt is a zip
    except Exception:
        return False

def convert_checkpoints():
    """Convert state_dict checkpoints to safetensors format"""
    total_files = 0
    converted = 0
    errors = 0
    
    print("🔄 Starting safetensors conversion...")
    print(f"📁 Processing directories: {', '.join(ROOTS)}")
    print()
    
    for root in ROOTS:
        root_path = Path(root)
        if not root_path.exists():
            print(f"⚠️  Directory not found: {root}")
            continue
            
        print(f"🔍 Scanning: {root}")
        
        for dp, _, fns in os.walk(root):
            for fn in fns:
                if not fn.endswith(".pt"):
                    continue
                    
                p = Path(dp) / fn
                total_files += 1
                
                # Skip TorchScript files (they're already optimized)
                if is_zip_torchscript(p):
                    continue
                    
                # Check if safetensors already exists
                st = p.with_suffix(".safetensors")
                if st.exists():
                    continue
                    
                try:
                    # Load the checkpoint
                    obj = torch.load(str(p), map_location="cpu", weights_only=False)
                    
                    if isinstance(obj, dict):
                        # Extract state_dict
                        state_dict = obj.get("state_dict", obj)
                        
                        # Save as safetensors
                        save_file(state_dict, str(st))
                        converted += 1
                        print(f"✅ [OK] {p.name} -> {st.name}")
                    else:
                        print(f"⚠️  [SKIP] {p.name} (not a state_dict)")
                        
                except Exception as e:
                    errors += 1
                    print(f"❌ [ERR] {p.name}: {e}")
    
    print()
    print("="*60)
    print("📊 CONVERSION SUMMARY")
    print("="*60)
    print(f"🔍 Total .pt files scanned: {total_files}")
    print(f"✅ Successfully converted: {converted}")
    print(f"❌ Errors encountered: {errors}")
    print(f"📁 Safetensors files created: {converted}")
    print()
    
    if converted > 0:
        print("🎉 Conversion complete! Your loader will now auto-prefer .safetensors files.")
        print("💡 Benefits: Faster loading, no pickle security risks, smaller file sizes")
    else:
        print("ℹ️  No new conversions needed. All eligible files already have safetensors versions.")

if __name__ == "__main__":
    try:
        convert_checkpoints()
    except KeyboardInterrupt:
        print("\n⚠️  Conversion interrupted by user")
    except Exception as e:
        print(f"\n❌ Conversion failed: {e}")
