#!/usr/bin/env python3
"""
AZL/AZME Weight Manager
Handles loading, saving, and using trained model weights
"""

import os
import json
import pickle
import numpy as np
from pathlib import Path
from datetime import datetime

class AZLAZMEWeightManager:
    def __init__(self):
        self.weights_dir = "weights/azl_azme_training"
        self.checkpoints_dir = "checkpoints"
        self.models_dir = "trained_models"
        
        # Create directories
        os.makedirs(self.weights_dir, exist_ok=True)
        os.makedirs(self.checkpoints_dir, exist_ok=True)
        os.makedirs(self.models_dir, exist_ok=True)
        
        # Model architecture
        self.model_architecture = {
            "quantum_layers": 4,
            "neural_layers": 8,
            "attention_heads": 12,
            "embedding_dim": 768,
            "vocab_size": 32000,
            "max_sequence_length": 1024
        }
        
        # Current weights
        self.current_weights = {}
        self.weight_history = []
        
    def initialize_weights(self):
        """Initialize model weights for training"""
        print("🔧 Initializing AZL/AZME Model Weights...")
        
        weights = {}
        
        # Quantum neural weights
        for i in range(self.model_architecture["quantum_layers"]):
            layer_name = f"quantum_layer_{i}"
            weights[f"{layer_name}_qubits"] = {
                "shape": [self.model_architecture["embedding_dim"], self.model_architecture["embedding_dim"]],
                "data": np.random.randn(self.model_architecture["embedding_dim"], self.model_architecture["embedding_dim"]) * 0.1,
                "type": "quantum_enhanced"
            }
            weights[f"{layer_name}_entanglement"] = {
                "shape": [self.model_architecture["embedding_dim"]],
                "data": np.random.randn(self.model_architecture["embedding_dim"]) * 0.05,
                "type": "quantum_correlation"
            }
        
        # Neural network weights
        for i in range(self.model_architecture["neural_layers"]):
            layer_name = f"neural_layer_{i}"
            weights[f"{layer_name}_weights"] = {
                "shape": [self.model_architecture["embedding_dim"], self.model_architecture["embedding_dim"]],
                "data": np.random.randn(self.model_architecture["embedding_dim"], self.model_architecture["embedding_dim"]) * 0.1,
                "type": "neural"
            }
            weights[f"{layer_name}_bias"] = {
                "shape": [self.model_architecture["embedding_dim"]],
                "data": np.zeros(self.model_architecture["embedding_dim"]),
                "type": "bias"
            }
        
        # Attention mechanism weights
        weights["attention_query"] = {
            "shape": [self.model_architecture["embedding_dim"], self.model_architecture["embedding_dim"]],
            "data": np.random.randn(self.model_architecture["embedding_dim"], self.model_architecture["embedding_dim"]) * 0.1,
            "type": "attention"
        }
        weights["attention_key"] = {
            "shape": [self.model_architecture["embedding_dim"], self.model_architecture["embedding_dim"]],
            "data": np.random.randn(self.model_architecture["embedding_dim"], self.model_architecture["embedding_dim"]) * 0.1,
            "type": "attention"
        }
        weights["attention_value"] = {
            "shape": [self.model_architecture["embedding_dim"], self.model_architecture["embedding_dim"]],
            "data": np.random.randn(self.model_architecture["embedding_dim"], self.model_architecture["embedding_dim"]) * 0.1,
            "type": "attention"
        }
        
        # Output projection
        weights["output_projection"] = {
            "shape": [self.model_architecture["embedding_dim"], self.model_architecture["vocab_size"]],
            "data": np.random.randn(self.model_architecture["embedding_dim"], self.model_architecture["vocab_size"]) * 0.1,
            "type": "output"
        }
        
        self.current_weights = weights
        print(f"✅ Initialized {len(weights)} weight matrices")
        print(f"📊 Total parameters: {self.count_parameters(weights):,}")
        
        return weights
    
    def count_parameters(self, weights):
        """Count total parameters in weights"""
        total = 0
        for name, weight_data in weights.items():
            if "data" in weight_data and hasattr(weight_data["data"], "size"):
                total += weight_data["data"].size
        return total
    
    def save_weights(self, filename=None, include_metadata=True):
        """Save current weights to file"""
        if filename is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"azl_azme_weights_{timestamp}.pkl"
        
        filepath = os.path.join(self.weights_dir, filename)
        
        save_data = {
            "weights": self.current_weights,
            "architecture": self.model_architecture,
            "timestamp": datetime.now().isoformat(),
            "total_parameters": self.count_parameters(self.current_weights)
        }
        
        if include_metadata:
            save_data["metadata"] = {
                "training_steps": len(self.weight_history),
                "weight_history": self.weight_history[-100:] if self.weight_history else [],  # Last 100 entries
                "system_info": {
                    "quantum_layers": self.model_architecture["quantum_layers"],
                    "neural_layers": self.model_architecture["neural_layers"],
                    "embedding_dim": self.model_architecture["embedding_dim"]
                }
            }
        
        with open(filepath, 'wb') as f:
            pickle.dump(save_data, f)
        
        print(f"💾 Weights saved: {filepath}")
        print(f"📊 File size: {os.path.getsize(filepath) / (1024*1024):.2f} MB")
        
        return filepath
    
    def load_weights(self, filepath):
        """Load weights from file"""
        print(f"📂 Loading weights from: {filepath}")
        
        if not os.path.exists(filepath):
            print(f"❌ Weight file not found: {filepath}")
            return False
        
        try:
            with open(filepath, 'rb') as f:
                load_data = pickle.load(f)
            
            self.current_weights = load_data["weights"]
            if "architecture" in load_data:
                self.model_architecture.update(load_data["architecture"])
            
            print(f"✅ Weights loaded successfully")
            print(f"📊 Total parameters: {self.count_parameters(self.current_weights):,}")
            print(f"🔧 Architecture: {self.model_architecture['quantum_layers']} quantum + {self.model_architecture['neural_layers']} neural layers")
            
            if "metadata" in load_data:
                print(f"📅 Saved: {load_data.get('timestamp', 'Unknown')}")
                print(f"🔄 Training steps: {load_data['metadata'].get('training_steps', 0)}")
            
            return True
            
        except Exception as e:
            print(f"❌ Error loading weights: {e}")
            return False
    
    def update_weights(self, gradients, learning_rate=0.001):
        """Update weights using gradients (training step)"""
        print(f"🔄 Updating weights with learning rate: {learning_rate}")
        
        updated_weights = {}
        total_updates = 0
        
        for name, weight_data in self.current_weights.items():
            if "data" in weight_data and name in gradients:
                # Apply gradient update
                gradient = gradients[name]
                current_data = weight_data["data"]
                
                # Update weight
                updated_data = current_data - learning_rate * gradient
                updated_weights[name] = {
                    **weight_data,
                    "data": updated_data
                }
                total_updates += 1
            else:
                # Keep unchanged
                updated_weights[name] = weight_data
        
        self.current_weights = updated_weights
        
        # Record weight update
        self.weight_history.append({
            "step": len(self.weight_history) + 1,
            "timestamp": datetime.now().isoformat(),
            "learning_rate": learning_rate,
            "updates_applied": total_updates
        })
        
        print(f"✅ Updated {total_updates} weight matrices")
        return updated_weights
    
    def get_weight_info(self):
        """Get information about current weights"""
        info = {
            "total_weights": len(self.current_weights),
            "total_parameters": self.count_parameters(self.current_weights),
            "architecture": self.model_architecture,
            "weight_types": {},
            "memory_usage_mb": 0
        }
        
        # Analyze weight types
        for name, weight_data in self.current_weights.items():
            weight_type = weight_data.get("type", "unknown")
            if weight_type not in info["weight_types"]:
                info["weight_types"][weight_type] = 0
            info["weight_types"][weight_type] += 1
        
        # Estimate memory usage
        info["memory_usage_mb"] = info["total_parameters"] * 4 / (1024 * 1024)  # Assuming float32
        
        return info
    
    def list_saved_weights(self):
        """List all saved weight files"""
        print("📁 Available Weight Files:")
        print("=" * 50)
        
        weight_files = []
        for file in os.listdir(self.weights_dir):
            if file.endswith('.pkl'):
                filepath = os.path.join(self.weights_dir, file)
                file_size = os.path.getsize(filepath) / (1024 * 1024)
                mod_time = datetime.fromtimestamp(os.path.getmtime(filepath))
                
                weight_files.append({
                    "filename": file,
                    "size_mb": file_size,
                    "modified": mod_time,
                    "filepath": filepath
                })
        
        if not weight_files:
            print("❌ No weight files found")
            return []
        
        # Sort by modification time (newest first)
        weight_files.sort(key=lambda x: x["modified"], reverse=True)
        
        for i, file_info in enumerate(weight_files):
            print(f"{i+1:2d}. {file_info['filename']}")
            print(f"    📊 Size: {file_info['size_mb']:.2f} MB")
            print(f"    📅 Modified: {file_info['modified'].strftime('%Y-%m-%d %H:%M:%S')}")
            print()
        
        return weight_files
    
    def load_latest_weights(self):
        """Load the most recent weight file"""
        weight_files = self.list_saved_weights()
        
        if not weight_files:
            print("❌ No weight files available")
            return False
        
        latest_file = weight_files[0]["filepath"]
        return self.load_weights(latest_file)
    
    def export_weights_for_azl(self, filename=None):
        """Export weights in AZL-compatible format"""
        if filename is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"azl_azme_weights_azl_{timestamp}.json"
        
        filepath = os.path.join(self.weights_dir, filename)
        
        # Convert weights to AZL-compatible format
        azl_weights = {}
        for name, weight_data in self.current_weights.items():
            if "data" in weight_data:
                # Convert numpy arrays to lists for JSON serialization
                if hasattr(weight_data["data"], "tolist"):
                    azl_weights[name] = {
                        "shape": weight_data["shape"],
                        "data": weight_data["data"].tolist(),
                        "type": weight_data["type"]
                    }
                else:
                    azl_weights[name] = weight_data
        
        export_data = {
            "weights": azl_weights,
            "architecture": self.model_architecture,
            "export_timestamp": datetime.now().isoformat(),
            "format": "azl_compatible",
            "total_parameters": self.count_parameters(self.current_weights)
        }
        
        with open(filepath, 'w') as f:
            json.dump(export_data, f, indent=2)
        
        print(f"📤 Weights exported for AZL: {filepath}")
        return filepath
    
    def create_training_checkpoint(self, step, loss, best_loss):
        """Create a training checkpoint with current weights"""
        checkpoint_dir = os.path.join(self.checkpoints_dir, "azl_azme_training")
        os.makedirs(checkpoint_dir, exist_ok=True)
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        checkpoint_file = f"checkpoint_step_{step:06d}_{timestamp}.pkl"
        checkpoint_path = os.path.join(checkpoint_dir, checkpoint_file)
        
        checkpoint_data = {
            "step": step,
            "loss": loss,
            "best_loss": best_loss,
            "timestamp": datetime.now().isoformat(),
            "weights": self.current_weights,
            "architecture": self.model_architecture,
            "weight_history": self.weight_history[-50:] if self.weight_history else [],  # Last 50 entries
            "training_stats": {
                "total_parameters": self.count_parameters(self.current_weights),
                "weight_types": self.get_weight_info()["weight_types"]
            }
        }
        
        with open(checkpoint_path, 'wb') as f:
            pickle.dump(checkpoint_data, f)
        
        print(f"💾 Training checkpoint saved: {checkpoint_path}")
        return checkpoint_path

def main():
    """Demo the weight manager"""
    print("🔧 AZL/AZME Weight Manager Demo")
    print("=" * 50)
    
    # Create weight manager
    manager = AZLAZMEWeightManager()
    
    # Initialize weights
    manager.initialize_weights()
    
    # Show weight info
    info = manager.get_weight_info()
    print(f"\n📊 Weight Information:")
    print(f"  Total weights: {info['total_weights']}")
    print(f"  Total parameters: {info['total_parameters']:,}")
    print(f"  Memory usage: {info['memory_usage_mb']:.2f} MB")
    print(f"  Weight types: {info['weight_types']}")
    
    # Save weights
    weight_file = manager.save_weights()
    
    # List saved weights
    print(f"\n📁 Saved Weights:")
    manager.list_saved_weights()
    
    # Export for AZL
    azl_file = manager.export_weights_for_azl()
    
    print(f"\n✅ Weight Manager Demo Complete!")
    print(f"💾 Weights saved: {weight_file}")
    print(f"📤 AZL export: {azl_file}")

if __name__ == "__main__":
    main()
