#!/usr/bin/env python3
"""
Master Training Launcher
Integrates dataset loading, model architectures, and continuous training
"""

import os
import sys
import json
import argparse
from pathlib import Path

# Import our systems
from real_dataset_loader import RealDatasetLoader
from advanced_model_architectures import AdvancedModelArchitectures
from continuous_training_system import ContinuousTrainingSystem

class MasterTrainingLauncher:
    def __init__(self):
        self.dataset_loader = RealDatasetLoader()
        self.model_architectures = AdvancedModelArchitectures()
        self.continuous_system = None
        
        # Configuration
        self.config_file = "master_training_config.json"
        self.config = self.load_master_config()
    
    def load_master_config(self):
        """Load master configuration"""
        default_config = {
            "project_name": "AZL Advanced Training System",
            "dataset": {
                "name": "custom",
                "path": "datasets/my_dataset.txt",
                "type": "text",
                "preprocessing": {
                    "min_length": 10,
                    "max_length": 1000,
                    "val_split": 0.1
                }
            },
            "model": {
                "architecture": "gpt_mini",
                "custom_params": {},
                "save_name": "my_trained_model"
            },
            "training": {
                "continuous": True,
                "max_epochs": 0,  # 0 = unlimited
                "steps_per_epoch": 1000,
                "learning_rate": 0.0001,
                "batch_size": 4,
                "checkpoint_every": 100
            },
            "paths": {
                "weights_dir": "weights/master_training",
                "logs_dir": "logs/master_training",
                "checkpoints_dir": "checkpoints/master_training"
            }
        }
        
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r') as f:
                    user_config = json.load(f)
                # Deep merge
                self.deep_merge(default_config, user_config)
                print(f"✅ Loaded master config from {self.config_file}")
            except Exception as e:
                print(f"⚠️  Error loading master config: {e}, using defaults")
        else:
            print(f"📝 No master config found, creating default: {self.config_file}")
            self.save_master_config(default_config)
        
        return default_config
    
    def deep_merge(self, base, update):
        """Deep merge configuration dictionaries"""
        for key, value in update.items():
            if key in base and isinstance(base[key], dict) and isinstance(value, dict):
                self.deep_merge(base[key], value)
            else:
                base[key] = value
    
    def save_master_config(self, config):
        """Save master configuration"""
        with open(self.config_file, 'w') as f:
            json.dump(config, f, indent=2)
    
    def setup_dataset(self):
        """Setup and load dataset"""
        print("📚 SETTING UP DATASET")
        print("=" * 40)
        
        dataset_config = self.config["dataset"]
        
        if dataset_config["name"] == "azl_azme":
            # Use pre-created AZL/AZME dataset
            dataset_path = dataset_config["path"]
            
            if not os.path.exists(dataset_path):
                print(f"❌ AZL/AZME dataset not found: {dataset_path}")
                print("💡 Please run azl_azme_dataset_creator.py first")
                return False
            
            print(f"✅ Using AZL/AZME dataset: {dataset_path}")
            
            # Read the dataset
            try:
                with open(dataset_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                # Split into training samples (simple approach)
                samples = content.split("=" * 80)
                samples = [s.strip() for s in samples if s.strip()]
                
                print(f"📊 Loaded {len(samples)} AZL/AZME code samples")
                
                # Update config with processed info
                self.config["dataset"]["processed"] = {
                    "train": dataset_path,
                    "validation": dataset_path,  # Use same file for now
                    "total_samples": len(samples)
                }
                
                return True
                
            except Exception as e:
                print(f"❌ Error loading AZL/AZME dataset: {e}")
                return False
        
        elif dataset_config["name"] == "custom":
            # Load custom dataset
            dataset_path = dataset_config["path"]
            
            if not os.path.exists(dataset_path):
                print(f"❌ Dataset not found: {dataset_path}")
                print("💡 Available options:")
                
                # Show sample datasets
                sample_datasets = self.dataset_loader.get_sample_datasets()
                for name, url in sample_datasets.items():
                    print(f"  • {name}: {url}")
                
                # Ask user to download sample dataset
                choice = input("\n🎯 Download sample dataset? (y/n): ").lower()
                if choice == 'y':
                    dataset_name = input("📥 Enter dataset name: ").strip()
                    if dataset_name in sample_datasets:
                        dataset_path = self.dataset_loader.download_sample_dataset(dataset_name)
                        if dataset_path:
                            dataset_config["path"] = dataset_path
                            print(f"✅ Downloaded dataset: {dataset_path}")
                        else:
                            print("❌ Failed to download dataset")
                            return False
                    else:
                        print(f"❌ Unknown dataset: {dataset_name}")
                        return False
                else:
                    print("❌ No dataset available, cannot continue")
                    return False
            
            # Load dataset
            print(f"📂 Loading dataset: {dataset_path}")
            
            if dataset_config["type"] == "text":
                texts = self.dataset_loader.load_text_file(dataset_path)
            elif dataset_config["type"] == "csv":
                texts = self.dataset_loader.load_csv_file(dataset_path)
            elif dataset_config["type"] == "json":
                texts = self.dataset_loader.load_json_file(dataset_path)
            else:
                # Auto-detect
                texts = self.dataset_loader.load_dataset(dataset_path)
            
            if not texts:
                print("❌ Failed to load dataset")
                return False
            
            # Preprocess
            preprocessing = dataset_config["preprocessing"]
            texts = self.dataset_loader.preprocess_text(
                texts, 
                preprocessing["min_length"], 
                preprocessing["max_length"]
            )
            
            # Split train/val
            train_texts, val_texts = self.dataset_loader.split_train_val(
                texts, 
                preprocessing["val_split"]
            )
            
            # Save processed dataset
            processed_dir = "datasets/processed"
            os.makedirs(processed_dir, exist_ok=True)
            
            train_file = os.path.join(processed_dir, "train_data.txt")
            val_file = os.path.join(processed_dir, "val_data.txt")
            
            with open(train_file, 'w') as f:
                for text in train_texts:
                    f.write(text + '\n')
            
            with open(val_file, 'w') as f:
                for text in val_texts:
                    f.write(text + '\n')
            
            print(f"✅ Dataset processed: {len(train_texts)} train, {len(val_texts)} validation")
            print(f"💾 Saved to: {processed_dir}")
            
            # Update config
            self.config["dataset"]["processed"] = {
                "train": train_file,
                "validation": val_file,
                "total_samples": len(texts)
            }
            
        return True
    
    def setup_model(self):
        """Setup model architecture"""
        print("\n🔧 SETTING UP MODEL ARCHITECTURE")
        print("=" * 40)
        
        model_config = self.config["model"]
        architecture_name = model_config["architecture"]
        
        try:
            # Get architecture
            if architecture_name in self.model_architectures.architectures:
                config = self.model_architectures.get_architecture(architecture_name)
                print(f"✅ Using predefined architecture: {architecture_name}")
            else:
                # Create custom architecture
                custom_params = model_config["custom_params"]
                config = self.model_architectures.create_custom_architecture(**custom_params)
                print(f"✅ Created custom architecture: {architecture_name}")
            
            # Get model info
            info = self.model_architectures.get_model_info(config)
            print(f"📊 Model: {info['total_parameters']:,} parameters, {info['memory_mb']:.1f} MB")
            
            # Initialize weights
            weights = self.model_architectures.initialize_weights(config)
            
            # Save architecture and weights
            save_name = model_config["save_name"]
            self.model_architectures.save_architecture(config, save_name)
            
            # Update config
            self.config["model"]["config"] = {
                "model_type": config.model_type,
                "vocab_size": config.vocab_size,
                "hidden_size": config.hidden_size,
                "num_layers": config.num_layers,
                "num_heads": config.num_heads,
                "max_seq_length": config.max_seq_length,
                "dropout": config.dropout,
                "activation": config.activation,
                "normalization": config.normalization
            }
            
            print(f"💾 Model saved: {save_name}")
            return True
            
        except Exception as e:
            print(f"❌ Error setting up model: {e}")
            return False
    
    def setup_training(self):
        """Setup training system"""
        print("\n🚀 SETTING UP TRAINING SYSTEM")
        print("=" * 40)
        
        # Create training config
        training_config = {
            "model_architecture": self.config["model"]["save_name"],
            "dataset_path": self.config["dataset"]["processed"]["train"],
            "training_params": {
                "learning_rate": self.config["training"]["learning_rate"],
                "batch_size": self.config["training"]["batch_size"],
                "max_steps_per_run": self.config["training"]["steps_per_epoch"],
                "checkpoint_every": self.config["training"]["checkpoint_every"],
                "save_every": 50
            },
            "continuous_params": {
                "max_runs": self.config["training"]["max_epochs"],
                "restart_delay": 60,
                "monitor_interval": 30,
                "auto_restart": True,
                "max_memory_gb": 18.0,
                "max_cpu_percent": 80.0
            },
            "paths": self.config["paths"]
        }

        # Propagate GPU policy to real trainer via config
        training_config["training"] = {
            "gpu_acceleration": self.config["training"].get("gpu_acceleration", True),
            "multi_gpu": self.config["training"].get("multi_gpu", True),
            "gpu_memory_fraction": self.config["training"].get("gpu_memory_fraction", 0.8)
        }
        
        # Save training config
        training_config_file = "training_config.json"
        with open(training_config_file, 'w') as f:
            json.dump(training_config, f, indent=2)
        
        print(f"✅ Training config saved: {training_config_file}")
        
        # Create continuous training system
        self.continuous_system = ContinuousTrainingSystem(training_config_file)
        
        return True
    
    def start_training(self):
        """Start the training process"""
        print("\n🎯 STARTING TRAINING")
        print("=" * 40)
        
        if not self.continuous_system:
            print("❌ Training system not initialized")
            return False
        
        try:
            # Start continuous training
            self.continuous_system.start_continuous_training()
            return True
        except KeyboardInterrupt:
            print("\n🛑 Training interrupted by user")
            self.continuous_system.stop_continuous_training()
            return False
        except Exception as e:
            print(f"❌ Error during training: {e}")
            return False
    
    def show_status(self):
        """Show current status"""
        if self.continuous_system:
            self.continuous_system.print_status()
        else:
            print("📊 No training system running")
    
    def run_full_setup(self):
        """Run complete setup (prepare corpus + configs) without starting training."""
        print("🚀 AZL MASTER TRAINING LAUNCHER")
        print("=" * 50)
        print("This will:")
        print("  ✅ Prepare unified corpus from all datasets (no training)")
        print("  ✅ Setup advanced model architecture")
        print("  ✅ Configure continuous training (no run)")
        print()

        # Prepare unified corpus (strict, non-interactive)
        try:
            import subprocess
            subprocess.run([
                "python3",
                str(Path("scripts/prepare_azme_full_corpus.py")),
            ], check=True)
            # Point dataset path to unified corpus
            self.config["dataset"]["name"] = "azme_full_corpus"
            self.config["dataset"]["path"] = "datasets/real_world_training/azme_full_corpus.txt"
            self.config["dataset"]["processed"] = {
                "train": "datasets/real_world_training/azme_full_corpus.txt",
                "validation": "datasets/real_world_training/azme_full_corpus.txt",
                "total_samples": 0
            }
        except Exception as e:
            print(f"❌ Failed to prepare unified corpus: {e}")
            return False

        # Setup dataset metadata
        if not self.setup_dataset():
            return False
        
        # Setup model
        if not self.setup_model():
            return False
        
        # Setup training
        if not self.setup_training():
            return False
        
        # Save master config
        self.save_master_config(self.config)
        
        # Do not auto-start training here; caller can start later
        return True

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Master Training Launcher")
    parser.add_argument("--action", choices=["prepare", "setup", "train", "status", "full"], default="prepare",
                       help="Action to perform")
    parser.add_argument("--config", default="master_training_config.json", help="Master config file")
    
    args = parser.parse_args()
    
    # Create launcher
    launcher = MasterTrainingLauncher()
    
    if args.action == "prepare":
        print("🧰 PREPARE MODE (no training)")
        launcher.run_full_setup()
        launcher.save_master_config(launcher.config)
        print("\n✅ Preparation complete! You can now run with --action train")
    elif args.action == "setup":
        # Just setup
        print("🔧 SETUP MODE")
        launcher.setup_dataset()
        launcher.setup_model()
        launcher.setup_training()
        launcher.save_master_config(launcher.config)
        print("\n✅ Setup complete! Run with --action train to start training")
        
    elif args.action == "train":
        # Just train (assumes setup is done)
        print("🚀 TRAIN MODE")
        launcher.setup_training()
        launcher.start_training()
        
    elif args.action == "status":
        # Show status
        launcher.show_status()
        
    elif args.action == "full":
        # Full setup and training
        launcher.run_full_setup()

if __name__ == "__main__":
    main()
