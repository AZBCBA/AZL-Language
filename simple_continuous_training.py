#!/usr/bin/env python3
"""
Simple Continuous Training
Runs training in a continuous loop and saves weights
"""

import time
import os
import json
from datetime import datetime

class SimpleContinuousTraining:
    def __init__(self):
        self.weights_dir = "weights/continuous_training"
        self.log_file = "logs/simple_training.log"
        self.is_training = False
        self.current_step = 0
        self.best_loss = 999.0
        self.training_losses = []
        
        # Create directories
        os.makedirs(self.weights_dir, exist_ok=True)
        os.makedirs("logs", exist_ok=True)
        
    def log_message(self, message):
        """Log a message with timestamp"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] {message}"
        print(log_entry)
        
        # Also write to log file
        with open(self.log_file, 'a') as f:
            f.write(log_entry + "\n")
    
    def initialize_model(self):
        """Initialize a simple model"""
        self.log_message("🔧 Initializing simple model...")
        
        # Create a simple model structure
        self.model = {
            "layers": [],
            "embeddings": {},
            "output": {}
        }
        
        # Add some layers
        for i in range(6):  # Simplified model
            layer = {
                "attention": {
                    "q": f"weights_q_layer_{i}",
                    "k": f"weights_k_layer_{i}",
                    "v": f"weights_v_layer_{i}",
                    "out": f"weights_out_layer_{i}"
                },
                "ffn": {
                    "up": f"weights_ffn_up_layer_{i}",
                    "down": f"weights_ffn_down_layer_{i}"
                },
                "norm": {
                    "weight": f"norm_weight_layer_{i}",
                    "bias": f"norm_bias_layer_{i}"
                }
            }
            self.model["layers"].append(layer)
        
        # Add embeddings
        self.model["embeddings"] = {
            "token": "token_embedding_weights",
            "position": "position_embedding_weights"
        }
        
        # Add output
        self.model["output"] = {
            "projection": "output_projection_weights"
        }
        
        self.log_message("✅ Model initialized with 6 layers")
    
    def generate_training_data(self):
        """Generate simple training data"""
        self.log_message("📚 Generating training data...")
        
        # Simple training sequences
        self.training_data = []
        words = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", 
                "and", "then", "runs", "away", "from", "hunters", "who", "chase"]
        
        for i in range(50):
            sequence = ""
            for j in range(5 + (i % 10)):  # Variable length sequences
                word = words[(i + j) % len(words)]
                sequence += word + " "
            self.training_data.append(sequence.strip())
        
        self.log_message(f"✅ Generated {len(self.training_data)} training sequences")
    
    def simulate_training_step(self):
        """Simulate one training step"""
        if not self.is_training:
            return
        
        # Simulate forward pass
        batch_loss = 0.0
        batch_size = 4
        
        for i in range(batch_size):
            # Get sequence
            seq_idx = (self.current_step * batch_size + i) % len(self.training_data)
            sequence = self.training_data[seq_idx]
            
            # Simulate processing
            tokens = len(sequence.split())
            hidden_states = tokens * 768  # Simulate hidden size
            
            # Simulate loss calculation
            import random
            loss = random.uniform(0.1, 3.0)
            batch_loss += loss
        
        avg_loss = batch_loss / batch_size
        self.training_losses.append(avg_loss)
        
        # Update best loss
        if avg_loss < self.best_loss:
            self.best_loss = avg_loss
            self.log_message(f"🏆 New best loss: {avg_loss:.4f}")
        
        # Log progress
        if self.current_step % 10 == 0:
            self.log_message(f"📊 Step {self.current_step} - Loss: {avg_loss:.4f} - Best: {self.best_loss:.4f}")
        
        # Simulate weight updates
        self.update_model_weights()
        
        self.current_step += 1
    
    def update_model_weights(self):
        """Simulate updating model weights"""
        # In a real system, this would update actual weights
        # Here we just simulate the process
        
        # Update each layer
        for i, layer in enumerate(self.model["layers"]):
            # Simulate attention weight updates
            layer["attention"]["q"] = f"updated_q_layer_{i}_step_{self.current_step}"
            layer["attention"]["k"] = f"updated_k_layer_{i}_step_{self.current_step}"
            layer["attention"]["v"] = f"updated_v_layer_{i}_step_{self.current_step}"
            layer["attention"]["out"] = f"updated_out_layer_{i}_step_{self.current_step}"
            
            # Simulate FFN weight updates
            layer["ffn"]["up"] = f"updated_ffn_up_layer_{i}_step_{self.current_step}"
            layer["ffn"]["down"] = f"updated_ffn_down_layer_{i}_step_{self.current_step}"
            
            # Simulate norm weight updates
            layer["norm"]["weight"] = f"updated_norm_weight_layer_{i}_step_{self.current_step}"
            layer["norm"]["bias"] = f"updated_norm_bias_layer_{i}_step_{self.current_step}"
        
        # Update embeddings
        self.model["embeddings"]["token"] = f"updated_token_emb_step_{self.current_step}"
        self.model["embeddings"]["position"] = f"updated_pos_emb_step_{self.current_step}"
        
        # Update output
        self.model["output"]["projection"] = f"updated_output_proj_step_{self.current_step}"
    
    def save_checkpoint(self, name):
        """Save a checkpoint"""
        checkpoint_path = os.path.join(self.weights_dir, f"{name}.json")
        
        checkpoint_data = {
            "model": self.model,
            "training_state": {
                "current_step": self.current_step,
                "best_loss": self.best_loss,
                "current_loss": self.training_losses[-1] if self.training_losses else 0.0,
                "total_losses": len(self.training_losses)
            },
            "timestamp": datetime.now().isoformat(),
            "checkpoint_name": name
        }
        
        try:
            with open(checkpoint_path, 'w') as f:
                json.dump(checkpoint_data, f, indent=2)
            
            self.log_message(f"💾 Checkpoint saved: {checkpoint_path}")
            return True
        except Exception as e:
            self.log_message(f"❌ Failed to save checkpoint: {e}")
            return False
    
    def start_training(self, max_steps=1000, save_every=50):
        """Start continuous training"""
        self.log_message("🚀 Starting Simple Continuous Training")
        self.log_message(f"🎯 Target steps: {max_steps}")
        self.log_message(f"💾 Save every: {save_every} steps")
        
        self.is_training = True
        start_time = time.time()
        
        try:
            # Initialize
            self.initialize_model()
            self.generate_training_data()
            
            # Training loop
            while self.is_training and self.current_step < max_steps:
                # Run training step
                self.simulate_training_step()
                
                # Save checkpoint periodically
                if self.current_step % save_every == 0 and self.current_step > 0:
                    self.save_checkpoint(f"step_{self.current_step}")
                
                # Small delay to simulate real training
                time.sleep(0.1)
                
                # Check if we should stop
                if self.current_step >= max_steps:
                    self.log_message("🎯 Reached maximum steps")
                    break
            
            # Save final checkpoint
            self.save_checkpoint("final_checkpoint")
            
            # Log final metrics
            training_time = time.time() - start_time
            self.log_message("🎉 Training Complete!")
            self.log_message(f"📊 Final Metrics:")
            self.log_message(f"  Total Steps: {self.current_step}")
            self.log_message(f"  Best Loss: {self.best_loss:.4f}")
            self.log_message(f"  Training Time: {training_time:.2f} seconds")
            self.log_message(f"  Average Loss: {sum(self.training_losses) / len(self.training_losses):.4f}")
            
        except KeyboardInterrupt:
            self.log_message("🛑 Training interrupted by user")
            self.save_checkpoint("interrupted_checkpoint")
        except Exception as e:
            self.log_message(f"❌ Training error: {e}")
            self.save_checkpoint("error_checkpoint")
        finally:
            self.is_training = False
    
    def stop_training(self):
        """Stop training"""
        self.log_message("🛑 Stopping training...")
        self.is_training = False

def main():
    """Main function"""
    trainer = SimpleContinuousTraining()
    
    print("🚀 Simple Continuous Training System")
    print("This will run training for 1000 steps and save checkpoints every 50 steps")
    print("Press Ctrl+C to stop early")
    
    try:
        trainer.start_training(max_steps=1000, save_every=50)
    except KeyboardInterrupt:
        print("\n🛑 Interrupted by user")
        trainer.stop_training()

if __name__ == "__main__":
    main()
