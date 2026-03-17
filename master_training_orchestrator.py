#!/usr/bin/env python3
"""
Master Training Orchestrator for AZL/AZME
Trains ALL available models and datasets systematically
"""

import os
import sys
import json
import subprocess
import time
import logging
from pathlib import Path
from typing import Dict, List, Optional
import argparse

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class MasterTrainingOrchestrator:
    """Orchestrates training of all AZL/AZME models and datasets"""
    
    def __init__(self, base_dir: str = "/home/abdulrahman-alzalameh/azl-language"):
        self.base_dir = Path(base_dir)
        self.training_dir = Path("/mnt/ssd4t/azl-training")
        self.datasets_dir = self.base_dir / "datasets"
        self.scripts_dir = self.base_dir / "python_helpers"
        self.checkpoints_dir = self.training_dir / "checkpoints"
        
        # Ensure training directories exist
        self.training_dir.mkdir(exist_ok=True)
        (self.training_dir / "weights").mkdir(exist_ok=True)
        (self.training_dir / "logs").mkdir(exist_ok=True)
        
        # Training configurations
        self.training_configs = self._discover_training_configs()
        self.datasets = self._discover_datasets()
        
    def _discover_training_configs(self) -> Dict[str, Dict]:
        """Discover all available training configurations"""
        configs = {}
        
        # Master training configs
        master_configs = [
            "master_training_config.json",
            "master_training_config_A.json", 
            "master_training_config_B.json",
            "master_training_config_C.json",
            "master_training_config_D.json"
        ]
        
        for config in master_configs:
            config_path = self.base_dir / config
            if config_path.exists():
                try:
                    with open(config_path, 'r') as f:
                        config_data = json.load(f)
                    configs[config] = {
                        'path': str(config_path),
                        'type': 'master',
                        'data': config_data
                    }
                except Exception as e:
                    logger.warning(f"Could not load {config}: {e}")
        
        # Dataset-specific configs
        dataset_configs = [
            "datasets/real_world_training/dataset_config.json",
            "datasets/azl_azme_training_enhanced/enhanced_dataset_statistics.json"
        ]
        
        for config in dataset_configs:
            config_path = self.base_dir / config
            if config_path.exists():
                try:
                    with open(config_path, 'r') as f:
                        config_data = json.load(f)
                    configs[config] = {
                        'path': str(config_path),
                        'type': 'dataset',
                        'data': config_data
                    }
                except Exception as e:
                    logger.warning(f"Could not load {config}: {e}")
        
        return configs
    
    def _discover_datasets(self) -> Dict[str, Dict]:
        """Discover all available datasets"""
        datasets = {}
        
        dataset_dirs = [
            "real_world_training",
            "azl_azme_training_enhanced", 
            "azl_azme_training",
            "cache"
        ]
        
        for dataset_dir in dataset_dirs:
            dataset_path = self.datasets_dir / dataset_dir
            if dataset_path.exists():
                datasets[dataset_dir] = {
                    'path': str(dataset_path),
                    'files': list(dataset_path.glob('*')),
                    'size': sum(f.stat().st_size for f in dataset_path.glob('*') if f.is_file())
                }
        
        return datasets
    
    def _discover_training_scripts(self) -> List[str]:
        """Discover all available training scripts"""
        scripts = []
        
        script_patterns = [
            "train_*.py",
            "*_train.py", 
            "*_training.py"
        ]
        
        for pattern in script_patterns:
            scripts.extend(self.scripts_dir.glob(pattern))
        
        return [str(s) for s in scripts]
    
    def show_training_inventory(self):
        """Display complete training inventory"""
        print("🚀 MASTER TRAINING INVENTORY")
        print("=" * 60)
        
        print(f"\n📋 Training Configurations ({len(self.training_configs)}):")
        for name, config in self.training_configs.items():
            config_type = config['type']
            print(f"   • {name} ({config_type})")
        
        print(f"\n📊 Available Datasets ({len(self.datasets)}):")
        for name, dataset in self.datasets.items():
            size_gb = dataset['size'] / (1024**3)
            file_count = len(dataset['files'])
            print(f"   • {name}: {file_count} files, {size_gb:.1f} GB")
        
        print(f"\n🔧 Training Scripts:")
        scripts = self._discover_training_scripts()
        for script in scripts:
            print(f"   • {os.path.basename(script)}")
        
        print(f"\n💾 Training Storage:")
        print(f"   • Base Directory: {self.base_dir}")
        print(f"   • Training Directory: {self.training_dir}")
        print(f"   • Checkpoints: {self.checkpoints_dir}")
        
        # Show current training status
        self._show_current_training_status()
    
    def _show_current_training_status(self):
        """Show current training progress"""
        print(f"\n📈 Current Training Status:")
        
        if self.checkpoints_dir.exists():
            checkpoints = list(self.checkpoints_dir.glob("step_*.pt"))
            if checkpoints:
                latest = max(checkpoints, key=lambda x: x.stat().st_mtime)
                latest_step = latest.stem.replace("step_", "")
                print(f"   • Latest Checkpoint: step_{latest_step}")
                print(f"   • Total Checkpoints: {len(checkpoints)}")
                print(f"   • Total Training Steps: {len(checkpoints) * 200}")
            else:
                print("   • No checkpoints found")
        else:
            print("   • Training directory not initialized")
    
    def create_training_plan(self, target_steps: int = 10000):
        """Create comprehensive training plan for all models"""
        print(f"\n🎯 CREATING TRAINING PLAN ({target_steps:,} steps)")
        print("=" * 60)
        
        training_plan = []
        
        # Phase 1: Core AZL/AZME Models
        print(f"\n📋 Phase 1: Core AZL/AZME Models")
        print("   • AZL/AZME Enhanced Model: {target_steps:,} steps")
        print("   • AZL-Only Model: {target_steps:,} steps") 
        print("   • AZME-Only Model: {target_steps:,} steps")
        
        training_plan.extend([
            {
                'name': 'azl_azme_enhanced',
                'script': 'train_enhanced_model.py',
                'config': 'master_training_config_A.json',
                'steps': target_steps,
                'priority': 'high'
            },
            {
                'name': 'azl_only',
                'script': 'train_enhanced_model.py', 
                'config': 'master_training_config_B.json',
                'steps': target_steps,
                'priority': 'high'
            },
            {
                'name': 'azme_only',
                'script': 'train_enhanced_model.py',
                'config': 'master_training_config_C.json', 
                'steps': target_steps,
                'priority': 'high'
            }
        ])
        
        # Phase 2: Advanced Models
        print(f"\n📋 Phase 2: Advanced Models")
        print("   • Real AGI Model: {target_steps:,} steps")
        print("   • Event Sequence Model: {target_steps:,} steps")
        print("   • Quantum Enhanced Model: {target_steps:,} steps")
        
        training_plan.extend([
            {
                'name': 'real_agi',
                'script': 'train_real_agi_model.py',
                'config': 'datasets/real_world_training/dataset_config.json',
                'steps': target_steps,
                'priority': 'medium'
            },
            {
                'name': 'event_sequence',
                'script': 'bpe_llm_train.py',
                'config': 'master_training_config_D.json',
                'steps': target_steps,
                'priority': 'medium'
            }
        ])
        
        # Phase 3: Specialized Models
        print(f"\n📋 Phase 3: Specialized Models")
        print("   • Benchmark Models: A, B, C, D")
        print("   • Consciousness Model")
        print("   • Neural Network Models")
        
        training_plan.extend([
            {
                'name': 'benchmark_a',
                'script': 'train_available_data.py',
                'config': 'master_training_config_A.json',
                'steps': 5000,
                'priority': 'low'
            },
            {
                'name': 'benchmark_b', 
                'script': 'train_available_data.py',
                'config': 'master_training_config_B.json',
                'steps': 5000,
                'priority': 'low'
            }
        ])
        
        print(f"\n📊 Training Plan Summary:")
        print(f"   • Total Models: {len(training_plan)}")
        print(f"   • Total Steps: {sum(m['steps'] for m in training_plan):,}")
        print(f"   • Estimated Time: {sum(m['steps'] for m in training_plan) / 1000:.1f} hours")
        
        return training_plan
    
    def execute_training_plan(self, training_plan: List[Dict], parallel: bool = False):
        """Execute the training plan"""
        print(f"\n🚀 EXECUTING TRAINING PLAN")
        print("=" * 60)
        
        if parallel:
            print("⚠️  Parallel training not yet implemented - running sequentially")
        
        for i, model in enumerate(training_plan, 1):
            print(f"\n🎯 Training Model {i}/{len(training_plan)}: {model['name']}")
            print(f"   • Script: {model['script']}")
            print(f"   • Config: {model['config']}")
            print(f"   • Steps: {model['steps']:,}")
            print(f"   • Priority: {model['priority']}")
            
            try:
                self._train_model(model)
                print(f"✅ {model['name']} training completed successfully")
            except Exception as e:
                print(f"❌ {model['name']} training failed: {e}")
                logger.error(f"Training failed for {model['name']}: {e}")
            
            # Wait between models
            if i < len(training_plan):
                print("   ⏳ Waiting 30 seconds before next model...")
                time.sleep(30)
    
    def _train_model(self, model: Dict):
        """Train a single model"""
        script_path = self.scripts_dir / model['script']
        config_path = self.base_dir / model['config']
        
        if not script_path.exists():
            raise FileNotFoundError(f"Training script not found: {script_path}")
        
        if not config_path.exists():
            raise FileNotFoundError(f"Config file not found: {config_path}")
        
        # Build training command based on script type
        if 'enhanced' in model['script']:
            cmd = [
                sys.executable, str(script_path),
                '--data_path', 'datasets/azl_azme_training_enhanced',
                '--model_path', str(self.training_dir / model['name'] / 'model.pt'),
                '--epochs', str(model['steps'] // 100),  # Convert steps to epochs
                '--batch_size', '32',
                '--learning_rate', '0.001'
            ]
        elif 'real_agi' in model['script']:
            cmd = [
                sys.executable, str(script_path),
                '--config', str(config_path),
                '--steps', str(model['steps'])
            ]
        else:
            cmd = [
                sys.executable, str(script_path),
                '--config', str(config_path),
                '--steps', str(model['steps'])
            ]
        
        print(f"   🚀 Running: {' '.join(cmd)}")
        
        # Execute training
        result = subprocess.run(
            cmd,
            cwd=self.base_dir,
            capture_output=True,
            text=True,
            timeout=3600  # 1 hour timeout per model
        )
        
        if result.returncode != 0:
            raise RuntimeError(f"Training failed with return code {result.returncode}")
        
        print(f"   📊 Training output: {result.stdout[-500:]}")  # Last 500 chars
    
    def run_quick_training(self, model_name: str = "azl_azme_enhanced", steps: int = 5000):
        """Run a quick training session for testing"""
        print(f"\n🚀 QUICK TRAINING: {model_name}")
        print("=" * 50)
        
        quick_plan = [{
            'name': model_name,
            'script': 'train_enhanced_model.py',
            'config': 'datasets/azl_azme_training_enhanced/enhanced_dataset_statistics.json',
            'steps': steps,
            'priority': 'high'
        }]
        
        self.execute_training_plan(quick_plan)
    
    def monitor_training(self):
        """Monitor ongoing training progress"""
        print(f"\n📊 TRAINING MONITOR")
        print("=" * 50)
        
        while True:
            try:
                self._show_current_training_status()
                print("\n⏳ Monitoring... Press Ctrl+C to stop")
                time.sleep(60)  # Update every minute
            except KeyboardInterrupt:
                print("\n🛑 Monitoring stopped")
                break

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Master Training Orchestrator")
    parser.add_argument('--action', choices=['inventory', 'plan', 'train', 'quick', 'monitor'], 
                       default='inventory', help='Action to perform')
    parser.add_argument('--steps', type=int, default=10000, help='Target training steps')
    parser.add_argument('--model', type=str, default='azl_azme_enhanced', help='Model name for quick training')
    parser.add_argument('--parallel', action='store_true', help='Enable parallel training')
    
    args = parser.parse_args()
    
    # Initialize orchestrator
    orchestrator = MasterTrainingOrchestrator()
    
    if args.action == 'inventory':
        orchestrator.show_training_inventory()
    
    elif args.action == 'plan':
        plan = orchestrator.create_training_plan(args.steps)
        print(f"\n💾 Training plan created with {len(plan)} models")
    
    elif args.action == 'train':
        plan = orchestrator.create_training_plan(args.steps)
        orchestrator.execute_training_plan(plan, args.parallel)
    
    elif args.action == 'quick':
        orchestrator.run_quick_training(args.model, args.steps)
    
    elif args.action == 'monitor':
        orchestrator.monitor_training()

if __name__ == "__main__":
    main()
