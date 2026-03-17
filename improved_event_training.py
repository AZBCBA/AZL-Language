#!/usr/bin/env python3
"""
Improved Event Training Script

This script trains a model to complete AZL event names from partial prompts.
It learns the semantic structure of event names, not just character patterns.
"""

import json
import os
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from typing import List, Dict, Tuple
import argparse
import re


class EventCompletionDataset(Dataset):
    """Dataset for event name completion from partial prompts."""
    
    def __init__(self, events_file: str, max_length: int = 64):
        self.max_length = max_length
        self.examples = []
        
        # Load events and create completion examples
        with open(events_file, 'r', encoding='utf-8') as f:
            for line in f:
                data = json.loads(line)
                prompt = data['prompt']
                target = data['target']
                
                # Create completion example
                self.examples.append({
                    'prompt': prompt,
                    'target': target,
                    'completion': target[len(prompt):],  # What needs to be completed
                    'frequency': data.get('frequency', 1)
                })
        
        print(f"📊 Created {len(self.examples)} event completion examples")
        
        # Analyze dataset
        completions = [ex['completion'] for ex in self.examples]
        avg_completion_len = sum(len(c) for c in completions) / len(completions)
        print(f"📈 Average completion length: {avg_completion_len:.1f} characters")
        print(f"📈 Completion length range: {min(len(c) for c in completions)} - {max(len(c) for c in completions)} characters")
    
    def __len__(self):
        return len(self.examples)
    
    def __getitem__(self, idx):
        example = self.examples[idx]
        
        # Convert to byte encoding (0-255)
        prompt_bytes = [ord(c) for c in example['prompt']]
        completion_bytes = [ord(c) for c in example['completion']]
        
        # Pad or truncate to max_length
        if len(prompt_bytes) < self.max_length:
            prompt_bytes.extend([0] * (self.max_length - len(prompt_bytes)))
        else:
            prompt_bytes = prompt_bytes[:self.max_length]
        
        if len(completion_bytes) < self.max_length:
            completion_bytes.extend([0] * (self.max_length - len(completion_bytes)))
        else:
            completion_bytes = completion_bytes[:self.max_length]
        
        return {
            'prompt': torch.tensor(prompt_bytes, dtype=torch.long),
            'completion': torch.tensor(completion_bytes, dtype=torch.long),
            'completion_length': len(example['completion']),
            'target_full': example['target']
        }


class EventCompletionModel(nn.Module):
    """Model for completing event names from partial prompts."""
    
    def __init__(self, vocab_size: int = 256, d_model: int = 512, n_layers: int = 8, n_heads: int = 16):
        super().__init__()
        self.vocab_size = vocab_size
        self.d_model = d_model
        
        # Embeddings
        self.byte_embedding = nn.Embedding(vocab_size, d_model)
        self.pos_embedding = nn.Embedding(128, d_model)
        
        # Transformer encoder for prompt understanding
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model,
            nhead=n_heads,
            dim_feedforward=d_model * 4,
            dropout=0.1,
            batch_first=True,
            activation='gelu'
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=n_layers)
        
        # Transformer decoder for completion generation
        decoder_layer = nn.TransformerDecoderLayer(
            d_model=d_model,
            nhead=n_heads,
            dim_feedforward=d_model * 4,
            dropout=0.1,
            batch_first=True,
            activation='gelu'
        )
        self.decoder = nn.TransformerDecoder(decoder_layer, num_layers=n_layers)
        
        # Output projection
        self.output_projection = nn.Linear(d_model, vocab_size)
        
        # Layer normalization
        self.layer_norm = nn.LayerNorm(d_model)
        
    def forward(self, prompt, completion=None):
        batch_size, seq_len = prompt.shape
        
        # Encode prompt
        prompt_emb = self.byte_embedding(prompt)
        pos_emb = self.pos_embedding(torch.arange(seq_len, device=prompt.device))
        prompt_emb = prompt_emb + pos_emb
        prompt_emb = self.layer_norm(prompt_emb)
        
        # Encode prompt through transformer
        encoded_prompt = self.encoder(prompt_emb)
        
        if completion is not None:
            # Training mode - use teacher forcing
            completion_emb = self.byte_embedding(completion)
            pos_emb_comp = self.pos_embedding(torch.arange(seq_len, device=completion.device))
            completion_emb = completion_emb + pos_emb_comp
            completion_emb = self.layer_norm(completion_emb)
            
            # Decode with encoded prompt as memory
            decoded = self.decoder(completion_emb, encoded_prompt)
            logits = self.output_projection(decoded)
            return logits
        else:
            # Inference mode - return encoded prompt for autoregressive generation
            return encoded_prompt
    
    def generate_completion(self, prompt, max_length=64, temperature=0.7, top_k=10, top_p=0.9):
        """Generate completion autoregressively."""
        self.eval()
        device = prompt.device
        
        # Encode prompt
        encoded_prompt = self.forward(prompt)
        
        # Start with empty completion
        completion = []
        current_input = torch.zeros(1, 1, dtype=torch.long, device=device)
        
        for _ in range(max_length):
            # Get embeddings for current input
            current_emb = self.byte_embedding(current_input)
            pos_emb = self.pos_embedding(torch.arange(current_input.size(1), device=device))
            current_emb = current_emb + pos_emb
            current_emb = self.layer_norm(current_emb)
            
            # Decode next token
            decoded = self.decoder(current_emb, encoded_prompt)
            logits = self.output_projection(decoded[:, -1, :])  # Last position
            
            # Apply temperature and sampling
            logits = logits / temperature
            
            # Top-k filtering
            if top_k > 0:
                top_k_logits, top_k_indices = torch.topk(logits, min(top_k, logits.size(-1)))
                logits = torch.full_like(logits, float('-inf'))
                logits.scatter_(-1, top_k_indices, top_k_logits)
            
            # Top-p (nucleus) sampling
            if top_p < 1.0:
                sorted_logits, sorted_indices = torch.sort(logits, descending=True)
                cumulative_probs = torch.cumsum(torch.softmax(sorted_logits, dim=-1), dim=-1)
                sorted_indices_to_remove = cumulative_probs > top_p
                sorted_indices_to_remove[..., 1:] = sorted_indices_to_remove[..., :-1].clone()
                sorted_indices_to_remove[..., 0] = 0
                indices_to_remove = sorted_indices_to_remove.scatter(1, sorted_indices, sorted_indices_to_remove)
                logits[indices_to_remove] = float('-inf')
            
            # Sample next token
            probs = torch.softmax(logits, dim=-1)
            next_token = torch.multinomial(probs, 1)
            
            # Stop if we hit padding or special characters
            if next_token.item() == 0 or next_token.item() in [1, 2, 3]:
                break
            
            completion.append(next_token.item())
            
            # Add next token to current input for next iteration
            current_input = torch.cat([current_input, next_token], dim=1)
        
        return completion


def train_completion_model(events_file: str, output_dir: str, epochs: int = 20, batch_size: int = 32):
    """Train the event completion model."""
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Device
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"🚀 Training on device: {device}")
    
    # Dataset and dataloader
    dataset = EventCompletionDataset(events_file, max_length=64)
    dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)
    
    # Model
    model = EventCompletionModel(vocab_size=256, d_model=512, n_layers=8, n_heads=16)
    model.to(device)
    
    # Optimizer and loss
    optimizer = optim.AdamW(model.parameters(), lr=1e-4, weight_decay=0.01)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    criterion = nn.CrossEntropyLoss(ignore_index=0)  # Ignore padding tokens
    
    # Training loop
    print(f"🎯 Starting training for {epochs} epochs...")
    best_accuracy = 0.0
    
    for epoch in range(epochs):
        model.train()
        total_loss = 0.0
        correct_predictions = 0
        total_predictions = 0
        
        for batch_idx, batch in enumerate(dataloader):
            prompt = batch['prompt'].to(device)
            completion = batch['completion'].to(device)
            
            # Forward pass
            logits = model(prompt, completion)
            
            # Reshape for loss calculation
            batch_size, seq_len, vocab_size = logits.shape
            logits = logits.view(-1, vocab_size)
            targets = completion.view(-1)
            
            # Calculate loss (ignore padding)
            loss = criterion(logits, targets)
            
            # Backward pass
            optimizer.zero_grad()
            loss.backward()
            
            # Gradient clipping
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            
            optimizer.step()
            
            total_loss += loss.item()
            
            # Calculate accuracy
            with torch.no_grad():
                predictions = torch.argmax(logits, dim=-1)
                # Only count non-padding tokens
                mask = targets != 0
                if mask.sum() > 0:
                    correct = (predictions[mask] == targets[mask]).sum().item()
                    correct_predictions += correct
                    total_predictions += mask.sum().item()
            
            if batch_idx % 50 == 0:
                print(f"  Epoch {epoch+1}/{epochs}, Batch {batch_idx}/{len(dataloader)}, "
                      f"Loss: {loss.item():.4f}")
        
        # Epoch summary
        avg_loss = total_loss / len(dataloader)
        accuracy = (correct_predictions / max(total_predictions, 1)) * 100
        
        print(f"📊 Epoch {epoch+1}/{epochs} - "
              f"Avg Loss: {avg_loss:.4f}, "
              f"Accuracy: {accuracy:.2f}%")
        
        # Learning rate scheduling
        scheduler.step()
        
        # Save checkpoint
        checkpoint_path = os.path.join(output_dir, f"completion_model_epoch_{epoch+1}.pt")
        torch.save({
            'epoch': epoch + 1,
            'model_state_dict': model.state_dict(),
            'optimizer_state_dict': optimizer.state_dict(),
            'scheduler_state_dict': scheduler.state_dict(),
            'loss': avg_loss,
            'accuracy': accuracy
        }, checkpoint_path)
        
        # Save best model
        if accuracy > best_accuracy:
            best_accuracy = accuracy
            best_model_path = os.path.join(output_dir, "completion_model_best.pt")
            torch.save({
                'model_state_dict': model.state_dict(),
                'vocab_size': model.vocab_size,
                'd_model': model.d_model,
                'n_layers': model.encoder.num_layers,
                'n_heads': model.encoder.layers[0].self_attn.num_heads,
                'accuracy': accuracy
            }, best_model_path)
            print(f"🏆 New best model saved with {accuracy:.2f}% accuracy!")
        
        print(f"💾 Saved checkpoint: {checkpoint_path}")
    
    print("✅ Training complete!")
    
    # Save final model
    final_model_path = os.path.join(output_dir, "completion_model_final.pt")
    torch.save({
        'model_state_dict': model.state_dict(),
        'vocab_size': model.vocab_size,
        'd_model': model.d_model,
        'n_layers': model.encoder.num_layers,
        'n_heads': model.encoder.layers[0].self_attn.num_heads
    }, final_model_path)
    print(f"🎯 Final model saved: {final_model_path}")
    
    return model


def test_completion_model(model_path: str, events_file: str, num_examples: int = 10):
    """Test the trained completion model."""
    
    # Load model
    checkpoint = torch.load(model_path, map_location='cpu')
    model = EventCompletionModel(
        vocab_size=checkpoint['vocab_size'],
        d_model=checkpoint['d_model'],
        n_layers=checkpoint['n_layers'],
        n_heads=checkpoint['n_heads']
    )
    model.load_state_dict(checkpoint['model_state_dict'])
    model.eval()
    
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device)
    
    # Load test examples
    with open(events_file, 'r', encoding='utf-8') as f:
        examples = [json.loads(line) for line in f][:num_examples]
    
    print(f"🧪 Testing completion model on {len(examples)} examples...")
    
    correct_completions = 0
    partial_matches = 0
    
    for i, example in enumerate(examples):
        prompt = example['prompt']
        target = example['target']
        expected_completion = example['target'][len(prompt):]
        
        print(f"\n  Example {i+1}:")
        print(f"    Prompt: '{prompt}'")
        print(f"    Expected: '{expected_completion}'")
        print(f"    Full Target: '{target}'")
        
        # Convert prompt to tensor
        prompt_bytes = [ord(c) for c in prompt]
        if len(prompt_bytes) < 64:
            prompt_bytes.extend([0] * (64 - len(prompt_bytes)))
        else:
            prompt_bytes = prompt_bytes[:64]
        
        prompt_tensor = torch.tensor([prompt_bytes], dtype=torch.long).to(device)
        
        # Generate completion
        with torch.no_grad():
            completion_bytes = model.generate_completion(
                prompt_tensor, 
                max_length=64, 
                temperature=0.3, 
                top_k=10, 
                top_p=0.9
            )
        
        # Convert bytes back to string
        generated_completion = ''.join([chr(b) for b in completion_bytes if b > 0])
        
        print(f"    Generated: '{generated_completion}'")
        
        # Check accuracy
        if generated_completion == expected_completion:
            correct_completions += 1
            print(f"    ✅ Perfect match!")
        elif expected_completion in generated_completion or generated_completion in expected_completion:
            partial_matches += 1
            print(f"    🔶 Partial match")
        else:
            print(f"    ❌ No match")
    
    # Calculate accuracy
    total_examples = len(examples)
    perfect_accuracy = (correct_completions / total_examples) * 100
    partial_accuracy = ((correct_completions + partial_matches) / total_examples) * 100
    
    print(f"\n📊 Results:")
    print(f"  Perfect matches: {correct_completions}/{total_examples} ({perfect_accuracy:.1f}%)")
    print(f"  Partial matches: {partial_matches}/{total_examples}")
    print(f"  Overall accuracy: {partial_accuracy:.1f}%")
    
    return perfect_accuracy, partial_accuracy


def main():
    parser = argparse.ArgumentParser(description="Improved Event Training")
    parser.add_argument("--events", default="tools/event_eval.jsonl", help="Events file")
    parser.add_argument("--output", default="checkpoints/completion_training", help="Output directory")
    parser.add_argument("--epochs", type=int, default=20, help="Number of epochs")
    parser.add_argument("--batch-size", type=int, default=32, help="Batch size")
    parser.add_argument("--test", action="store_true", help="Test mode")
    parser.add_argument("--model", help="Model path for testing")
    
    args = parser.parse_args()
    
    if args.test:
        if not args.model:
            print("❌ Please provide --model path for testing")
            return
        test_completion_model(args.model, args.events)
    else:
        train_completion_model(args.events, args.output, args.epochs, args.batch_size)


if __name__ == "__main__":
    main()
