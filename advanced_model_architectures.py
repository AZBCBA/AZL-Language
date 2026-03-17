#!/usr/bin/env python3
"""
Advanced Model Architectures
Different neural network architectures for training
"""

import numpy as np
import json
import os
from typing import Dict, List, Any, Tuple
from dataclasses import dataclass

@dataclass
class ModelConfig:
    """Model configuration dataclass"""
    model_type: str
    vocab_size: int
    hidden_size: int
    num_layers: int
    num_heads: int
    max_seq_length: int
    dropout: float
    activation: str
    normalization: str

class AdvancedModelArchitectures:
    def __init__(self):
        self.weights_dir = "weights/advanced_models"
        os.makedirs(self.weights_dir, exist_ok=True)
        
        # Predefined architectures
        self.architectures = {
            "gpt_mini": ModelConfig(
                model_type="transformer",
                vocab_size=32000,
                hidden_size=768,
                num_layers=12,
                num_heads=12,
                max_seq_length=1024,
                dropout=0.1,
                activation="gelu",
                normalization="layer_norm"
            ),
            "gpt_medium": ModelConfig(
                model_type="transformer",
                vocab_size=50000,
                hidden_size=1024,
                num_layers=24,
                num_heads=16,
                max_seq_length=2048,
                dropout=0.1,
                activation="gelu",
                normalization="layer_norm"
            ),
            "lstm_small": ModelConfig(
                model_type="lstm",
                vocab_size=10000,
                hidden_size=256,
                num_layers=3,
                num_heads=1,
                max_seq_length=512,
                dropout=0.2,
                activation="tanh",
                normalization="batch_norm"
            ),
            "cnn_text": ModelConfig(
                model_type="cnn",
                vocab_size=15000,
                hidden_size=128,
                num_layers=4,
                num_heads=1,
                max_seq_length=256,
                dropout=0.3,
                activation="relu",
                normalization="batch_norm"
            ),
            "rnn_vanilla": ModelConfig(
                model_type="rnn",
                vocab_size=8000,
                hidden_size=128,
                num_layers=2,
                num_heads=1,
                max_seq_length=128,
                dropout=0.1,
                activation="tanh",
                normalization="none"
            )
        }
    
    def get_architecture(self, name: str) -> ModelConfig:
        """Get predefined architecture by name"""
        if name not in self.architectures:
            raise ValueError(f"Unknown architecture: {name}. Available: {list(self.architectures.keys())}")
        return self.architectures[name]
    
    def create_custom_architecture(self, **kwargs) -> ModelConfig:
        """Create custom architecture with specified parameters"""
        default_config = ModelConfig(
            model_type="transformer",
            vocab_size=10000,
            hidden_size=256,
            num_layers=6,
            num_heads=8,
            max_seq_length=512,
            dropout=0.1,
            activation="gelu",
            normalization="layer_norm"
        )
        
        # Update with custom parameters
        for key, value in kwargs.items():
            if hasattr(default_config, key):
                setattr(default_config, key, value)
        
        return default_config
    
    def initialize_transformer_weights(self, config: ModelConfig) -> Dict[str, Any]:
        """Initialize weights for transformer architecture"""
        print(f"🔧 Initializing {config.model_type} weights...")
        
        weights = {}
        
        # Token embeddings
        weights["token_embedding"] = {
            "shape": [config.vocab_size, config.hidden_size],
            "data": "random_normal",
            "scale": 0.02
        }
        
        # Position embeddings
        weights["position_embedding"] = {
            "shape": [config.max_seq_length, config.hidden_size],
            "data": "random_normal",
            "scale": 0.02
        }
        
        # Transformer layers
        for layer in range(config.num_layers):
            layer_name = f"layer_{layer}"
            
            # Multi-head attention
            weights[f"{layer_name}_attention_q"] = {
                "shape": [config.hidden_size, config.hidden_size],
                "data": "random_normal",
                "scale": 0.02
            }
            weights[f"{layer_name}_attention_k"] = {
                "shape": [config.hidden_size, config.hidden_size],
                "data": "random_normal",
                "scale": 0.02
            }
            weights[f"{layer_name}_attention_v"] = {
                "shape": [config.hidden_size, config.hidden_size],
                "data": "random_normal",
                "scale": 0.02
            }
            weights[f"{layer_name}_attention_out"] = {
                "shape": [config.hidden_size, config.hidden_size],
                "data": "random_normal",
                "scale": 0.02
            }
            
            # Layer normalization
            weights[f"{layer_name}_ln1_weight"] = {
                "shape": [config.hidden_size],
                "data": "ones"
            }
            weights[f"{layer_name}_ln1_bias"] = {
                "shape": [config.hidden_size],
                "data": "zeros"
            }
            
            # Feed-forward network
            ffn_size = config.hidden_size * 4
            weights[f"{layer_name}_ffn_up"] = {
                "shape": [config.hidden_size, ffn_size],
                "data": "random_normal",
                "scale": 0.02
            }
            weights[f"{layer_name}_ffn_down"] = {
                "shape": [ffn_size, config.hidden_size],
                "data": "random_normal",
                "scale": 0.02
            }
            
            weights[f"{layer_name}_ln2_weight"] = {
                "shape": [config.hidden_size],
                "data": "ones"
            }
            weights[f"{layer_name}_ln2_bias"] = {
                "shape": [config.hidden_size],
                "data": "zeros"
            }
        
        # Output projection
        weights["output_projection"] = {
            "shape": [config.hidden_size, config.vocab_size],
            "data": "random_normal",
            "scale": 0.02
        }
        
        print(f"✅ Initialized {len(weights)} weight matrices for transformer")
        return weights
    
    def initialize_lstm_weights(self, config: ModelConfig) -> Dict[str, Any]:
        """Initialize weights for LSTM architecture"""
        print(f"🔧 Initializing {config.model_type} weights...")
        
        weights = {}
        
        # Embeddings
        weights["token_embedding"] = {
            "shape": [config.vocab_size, config.hidden_size],
            "data": "random_normal",
            "scale": 0.1
        }
        
        # LSTM layers
        for layer in range(config.num_layers):
            layer_name = f"lstm_layer_{layer}"
            input_size = config.hidden_size if layer > 0 else config.hidden_size
            
            # LSTM gates: input, forget, cell, output
            for gate in ["i", "f", "c", "o"]:
                weights[f"{layer_name}_{gate}_weight"] = {
                    "shape": [input_size, config.hidden_size],
                    "data": "random_normal",
                    "scale": 0.1
                }
                weights[f"{layer_name}_{gate}_bias"] = {
                    "shape": [config.hidden_size],
                    "data": "zeros"
                }
            
            # Hidden state projection
            weights[f"{layer_name}_h_weight"] = {
                "shape": [config.hidden_size, config.hidden_size],
                "data": "random_normal",
                "scale": 0.1
            }
            weights[f"{layer_name}_h_bias"] = {
                "shape": [config.hidden_size],
                "data": "zeros"
            }
        
        # Output projection
        weights["output_projection"] = {
            "shape": [config.hidden_size, config.vocab_size],
            "data": "random_normal",
            "scale": 0.1
        }
        
        print(f"✅ Initialized {len(weights)} weight matrices for LSTM")
        return weights
    
    def initialize_cnn_weights(self, config: ModelConfig) -> Dict[str, Any]:
        """Initialize weights for CNN architecture"""
        print(f"🔧 Initializing {config.model_type} weights...")
        
        weights = {}
        
        # Embeddings
        weights["token_embedding"] = {
            "shape": [config.vocab_size, config.hidden_size],
            "data": "random_normal",
            "scale": 0.1
        }
        
        # CNN layers with different kernel sizes
        kernel_sizes = [3, 4, 5]
        for layer in range(config.num_layers):
            layer_name = f"conv_layer_{layer}"
            kernel_size = kernel_sizes[layer % len(kernel_sizes)]
            
            weights[f"{layer_name}_conv"] = {
                "shape": [kernel_size, config.hidden_size, config.hidden_size],
                "data": "random_normal",
                "scale": 0.1
            }
            weights[f"{layer_name}_bias"] = {
                "shape": [config.hidden_size],
                "data": "zeros"
            }
            
            if config.normalization == "batch_norm":
                weights[f"{layer_name}_bn_weight"] = {
                    "shape": [config.hidden_size],
                    "data": "ones"
                }
                weights[f"{layer_name}_bn_bias"] = {
                    "shape": [config.hidden_size],
                    "data": "zeros"
                }
        
        # Global pooling and output
        weights["global_pool"] = {
            "shape": [config.hidden_size, config.hidden_size],
            "data": "random_normal",
            "scale": 0.1
        }
        
        weights["output_projection"] = {
            "shape": [config.hidden_size, config.vocab_size],
            "data": "random_normal",
            "scale": 0.1
        }
        
        print(f"✅ Initialized {len(weights)} weight matrices for CNN")
        return weights
    
    def initialize_rnn_weights(self, config: ModelConfig) -> Dict[str, Any]:
        """Initialize weights for vanilla RNN architecture"""
        print(f"🔧 Initializing {config.model_type} weights...")
        
        weights = {}
        
        # Embeddings
        weights["token_embedding"] = {
            "shape": [config.vocab_size, config.hidden_size],
            "data": "random_normal",
            "scale": 0.1
        }
        
        # RNN layers
        for layer in range(config.num_layers):
            layer_name = f"rnn_layer_{layer}"
            input_size = config.hidden_size if layer > 0 else config.hidden_size
            
            weights[f"{layer_name}_weight"] = {
                "shape": [input_size, config.hidden_size],
                "data": "random_normal",
                "scale": 0.1
            }
            weights[f"{layer_name}_bias"] = {
                "shape": [config.hidden_size],
                "data": "zeros"
            }
            
            weights[f"{layer_name}_hidden_weight"] = {
                "shape": [config.hidden_size, config.hidden_size],
                "data": "random_normal",
                "scale": 0.1
            }
            weights[f"{layer_name}_hidden_bias"] = {
                "shape": [config.hidden_size],
                "data": "zeros"
            }
        
        # Output projection
        weights["output_projection"] = {
            "shape": [config.hidden_size, config.vocab_size],
            "data": "random_normal",
            "scale": 0.1
        }
        
        print(f"✅ Initialized {len(weights)} weight matrices for RNN")
        return weights
    
    def initialize_weights(self, config: ModelConfig) -> Dict[str, Any]:
        """Initialize weights based on model type"""
        if config.model_type == "transformer":
            return self.initialize_transformer_weights(config)
        elif config.model_type == "lstm":
            return self.initialize_lstm_weights(config)
        elif config.model_type == "cnn":
            return self.initialize_cnn_weights(config)
        elif config.model_type == "rnn":
            return self.initialize_rnn_weights(config)
        else:
            raise ValueError(f"Unsupported model type: {config.model_type}")
    
    def save_architecture(self, config: ModelConfig, name: str):
        """Save architecture configuration"""
        config_path = os.path.join(self.weights_dir, f"{name}_config.json")
        
        config_dict = {
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
        
        with open(config_path, 'w') as f:
            json.dump(config_dict, f, indent=2)
        
        print(f"💾 Saved architecture config: {config_path}")
    
    def load_architecture(self, name: str) -> ModelConfig:
        """Load architecture configuration"""
        config_path = os.path.join(self.weights_dir, f"{name}_config.json")
        
        if not os.path.exists(config_path):
            raise FileNotFoundError(f"Architecture config not found: {config_path}")
        
        with open(config_path, 'r') as f:
            config_dict = json.load(f)
        
        config = ModelConfig(**config_dict)
        print(f"📂 Loaded architecture: {name}")
        return config
    
    def list_architectures(self) -> List[str]:
        """List all available architectures"""
        configs = []
        for filename in os.listdir(self.weights_dir):
            if filename.endswith("_config.json"):
                name = filename.replace("_config.json", "")
                configs.append(name)
        return configs
    
    def get_model_info(self, config: ModelConfig) -> Dict[str, Any]:
        """Get detailed model information"""
        total_params = 0
        
        # Calculate parameters for different architectures
        if config.model_type == "transformer":
            # Embeddings
            total_params += config.vocab_size * config.hidden_size
            total_params += config.max_seq_length * config.hidden_size
            
            # Transformer layers
            for layer in range(config.num_layers):
                # Attention
                total_params += 4 * config.hidden_size * config.hidden_size  # Q, K, V, O
                # Layer norm
                total_params += 2 * config.hidden_size  # weight + bias
                # FFN
                ffn_size = config.hidden_size * 4
                total_params += config.hidden_size * ffn_size + ffn_size * config.hidden_size
                total_params += 2 * config.hidden_size  # layer norm
            
            # Output
            total_params += config.hidden_size * config.vocab_size
            
        elif config.model_type == "lstm":
            total_params += config.vocab_size * config.hidden_size
            for layer in range(config.num_layers):
                input_size = config.hidden_size if layer > 0 else config.hidden_size
                total_params += 4 * (input_size * config.hidden_size + config.hidden_size)  # gates
                total_params += config.hidden_size * config.hidden_size + config.hidden_size  # hidden
            total_params += config.hidden_size * config.vocab_size
        
        return {
            "model_type": config.model_type,
            "total_parameters": total_params,
            "memory_mb": (total_params * 4) / (1024 * 1024),  # Assuming float32
            "config": config
        }

def main():
    """Test the advanced model architectures"""
    architectures = AdvancedModelArchitectures()
    
    print("🎯 ADVANCED MODEL ARCHITECTURES")
    print("=" * 50)
    
    # Show available architectures
    print("📚 Available architectures:")
    for name, config in architectures.architectures.items():
        info = architectures.get_model_info(config)
        print(f"  • {name}: {info['total_parameters']:,} params, {info['memory_mb']:.1f} MB")
    
    print("\n💡 Usage examples:")
    print("  • config = architectures.get_architecture('gpt_mini')")
    print("  • weights = architectures.initialize_weights(config)")
    print("  • architectures.save_architecture(config, 'my_model')")

if __name__ == "__main__":
    main()
