#!/usr/bin/env python3
"""
Event-Only Training Script

This script trains the model exclusively on event prediction tasks,
without any other AZL code that could confuse the learning objective.
"""

import json
import os
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from typing import List, Dict, Tuple
import argparse


class EventDataset(Dataset):
    """Dataset for event prediction training."""
    
    def __init__(self, events_file: str, max_seq_len: int = 64):
        self.max_seq_len = max_seq_len
        self.examples = []
        
        # Load events
        with open(events_file, 'r', encoding='utf-8') as f:
            for line in f:
                data = json.loads(line)
                self.examples.append({
                    'prompt': data['prompt'],
                    'target': data['target']
                })
        
        print(f"📊 Loaded {len(self.examples)} event examples")
    
    def __len__(self):
        return len(self.examples)
    
    def __getitem__(self, idx):
        example = self.examples[idx]
        
        # Simple byte encoding
        prompt_bytes = example['prompt'].encode('utf-8')
        target_bytes = example['target'].encode('utf-8')
        
        # Create input sequence: prompt + target
        input_seq = list(prompt_bytes) + list(target_bytes)
        
        # Pad or truncate
        if len(input_seq) > self.max_seq_len:
            input_seq = input_seq[:self.max_seq_len]
        else:
            input_seq.extend([0] * (self.max_seq_len - len(input_seq)))
        
        # Create labels: -100 for prompt tokens, actual values for target tokens
        labels = [-100] * len(prompt_bytes) + list(target_bytes)
        
        # Pad labels
        if len(labels) > self.max_seq_len:
            labels = labels[:self.max_seq_len]
        else:
            labels.extend([-100] * (self.max_seq_len - len(labels)))
        
        return {
            'input_ids': torch.tensor(input_seq, dtype=torch.long),
            'labels': torch.tensor(labels, dtype=torch.long)
        }


class SimpleTransformer(nn.Module):
    """Simple transformer for event prediction."""
    
    def __init__(self, vocab_size: int = 256, d_model: int = 512, n_layers: int = 8, n_heads: int = 16):
        super().__init__()
        self.vocab_size = vocab_size
        self.d_model = d_model
        
        # Embeddings
        self.token_embedding = nn.Embedding(vocab_size, d_model)
        self.position_embedding = nn.Embedding(64, d_model)  # Max seq len 64
        
        # Layer normalization
        self.input_norm = nn.LayerNorm(d_model)
        
        # Transformer layers
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model,
            nhead=n_heads,
            dim_feedforward=d_model * 4,
            dropout=0.1,
            batch_first=True,
            activation='gelu'
        )
        self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=n_layers)
        
        # Output projection with layer norm
        self.output_norm = nn.LayerNorm(d_model)
        self.output_projection = nn.Linear(d_model, vocab_size)
        
    def forward(self, input_ids):
        batch_size, seq_len = input_ids.shape
        
        # Embeddings
        token_emb = self.token_embedding(input_ids)
        pos_emb = self.position_embedding(torch.arange(seq_len, device=input_ids.device))
        
        # Combine embeddings and normalize
        x = token_emb + pos_emb
        x = self.input_norm(x)
        
        # Transformer
        x = self.transformer(x)
        
        # Output projection with normalization
        x = self.output_norm(x)
        logits = self.output_projection(x)
        
        return logits


def train_event_model(events_file: str, output_dir: str, epochs: int = 10, batch_size: int = 32):
    """Train the event prediction model."""
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Device
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"🚀 Training on device: {device}")
    
    # Dataset and dataloader
    dataset = EventDataset(events_file, max_seq_len=64)
    dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)
    
    # Model
    model = SimpleTransformer(vocab_size=256, d_model=512, n_layers=8, n_heads=16)
    model.to(device)
    
    # Optimizer and loss
    optimizer = optim.AdamW(model.parameters(), lr=5e-5, weight_decay=0.01)
    criterion = nn.CrossEntropyLoss(ignore_index=-100)
    
    # Learning rate scheduler
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    
    # Training loop
    print(f"🎯 Starting training for {epochs} epochs...")
    
    for epoch in range(epochs):
        model.train()
        total_loss = 0.0
        correct_predictions = 0
        total_predictions = 0
        
        for batch_idx, batch in enumerate(dataloader):
            input_ids = batch['input_ids'].to(device)
            labels = batch['labels'].to(device)
            
            # Forward pass
            logits = model(input_ids)
            
            # Calculate loss
            loss = criterion(logits.view(-1, logits.size(-1)), labels.view(-1))
            
            # Backward pass
            optimizer.zero_grad()
            loss.backward()
            
            # Gradient clipping
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            
            optimizer.step()
            
            total_loss += loss.item()
            
            # Calculate accuracy (only on target tokens)
            with torch.no_grad():
                predictions = torch.argmax(logits, dim=-1)
                mask = labels != -100
                if mask.any():
                    correct = (predictions[mask] == labels[mask]).sum().item()
                    total = mask.sum().item()
                    correct_predictions += correct
                    total_predictions += total
            
            if batch_idx % 50 == 0:
                print(f"  Epoch {epoch+1}/{epochs}, Batch {batch_idx}/{len(dataloader)}, "
                      f"Loss: {loss.item():.4f}")
        
        # Epoch summary
        avg_loss = total_loss / len(dataloader)
        accuracy = (correct_predictions / max(total_predictions, 1)) * 100
        
        print(f"📊 Epoch {epoch+1}/{epochs} - "
              f"Avg Loss: {avg_loss:.4f}, "
              f"Accuracy: {accuracy:.2f}%")
        
        # Save checkpoint
        checkpoint_path = os.path.join(output_dir, f"event_model_epoch_{epoch+1}.pt")
        torch.save({
            'epoch': epoch + 1,
            'model_state_dict': model.state_dict(),
            'optimizer_state_dict': optimizer.state_dict(),
            'loss': avg_loss,
            'accuracy': accuracy
        }, checkpoint_path)
        print(f"💾 Saved checkpoint: {checkpoint_path}")
        
        # Step scheduler
        scheduler.step()
    
    print("✅ Training complete!")
    
    # Save final model
    final_model_path = os.path.join(output_dir, "event_model_final.pt")
    torch.save({
        'model_state_dict': model.state_dict(),
        'vocab_size': model.vocab_size,
        'd_model': model.d_model,
        'n_layers': model.transformer.num_layers,
        'n_heads': model.transformer.layers[0].self_attn.num_heads
    }, final_model_path)
    print(f"🎯 Final model saved: {final_model_path}")
    
    return model


def test_event_model(model_path: str, events_file: str, num_examples: int = 10):
    """Test the trained event model."""
    
    # Load model
    checkpoint = torch.load(model_path, map_location='cpu')
    model = SimpleTransformer(
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
    
    print(f"🧪 Testing model on {len(examples)} examples...")
    
    correct = 0
    total = 0
    
    for i, example in enumerate(examples):
        prompt = example['prompt']
        target = example['target']
        
        # Encode prompt
        prompt_bytes = list(prompt.encode('utf-8'))
        input_ids = torch.tensor([prompt_bytes], dtype=torch.long).to(device)
        
        # Generate completion
        with torch.no_grad():
            generated = []
            for _ in range(50):  # Max 50 tokens
                logits = model(input_ids)
                next_token = torch.argmax(logits[:, -1, :], dim=-1)
                generated.append(next_token.item())
                input_ids = torch.cat([input_ids, next_token.unsqueeze(1)], dim=1)
                
                # Stop if we hit padding or special tokens
                if next_token.item() == 0:
                    break
        
        # Decode generated text
        generated_text = bytes(generated).decode('utf-8', errors='ignore')
        
        # Check if target is in generated text
        is_correct = target in generated_text
        if is_correct:
            correct += 1
        total += 1
        
        print(f"  Example {i+1}:")
        print(f"    Prompt: '{prompt}'")
        print(f"    Target: '{target}'")
        print(f"    Generated: '{generated_text}'")
        print(f"    Correct: {is_correct}")
        print()
    
    accuracy = (correct / total) * 100
    print(f"🎯 Final Accuracy: {correct}/{total} = {accuracy:.2f}%")
    
    return accuracy


def main():
    parser = argparse.ArgumentParser(description="Event-Only Training")
    parser.add_argument("--events", default="tools/event_eval.jsonl", help="Events file")
    parser.add_argument("--output", default="checkpoints/event_only_training", help="Output directory")
    parser.add_argument("--epochs", type=int, default=10, help="Number of epochs")
    parser.add_argument("--batch-size", type=int, default=32, help="Batch size")
    parser.add_argument("--test", action="store_true", help="Test mode")
    parser.add_argument("--model", help="Model path for testing")
    
    args = parser.parse_args()
    
    if args.test:
        if not args.model:
            print("❌ Please provide --model path for testing")
            return
        test_event_model(args.model, args.events)
    else:
        train_event_model(args.events, args.output, args.epochs, args.batch_size)


if __name__ == "__main__":
    main()
