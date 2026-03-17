#!/usr/bin/env python3
"""
Simple Event Training Script

This script trains a simple character-level language model for event prediction.
It learns to predict the next character given the previous characters.
"""

import json
import os
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from typing import List, Dict, Tuple
import argparse


class SimpleEventDataset(Dataset):
    """Dataset for simple character-level event prediction."""
    
    def __init__(self, events_file: str, context_length: int = 16):
        self.context_length = context_length
        self.examples = []
        
        # Load events and create character sequences
        with open(events_file, 'r', encoding='utf-8') as f:
            for line in f:
                data = json.loads(line)
                event = data['target']
                
                # Create character sequences for this event
                for i in range(len(event) - context_length):
                    context = event[i:i + context_length]
                    target = event[i + context_length]
                    self.examples.append({
                        'context': context,
                        'target': target
                    })
        
        print(f"📊 Created {len(self.examples)} character prediction examples")
    
    def __len__(self):
        return len(self.examples)
    
    def __getitem__(self, idx):
        example = self.examples[idx]
        
        # Convert characters to ASCII values
        context_chars = [ord(c) for c in example['context']]
        target_char = ord(example['target'])
        
        return {
            'context': torch.tensor(context_chars, dtype=torch.long),
            'target': torch.tensor(target_char, dtype=torch.long)
        }


class SimpleEventModel(nn.Module):
    """Simple character-level model for event prediction."""
    
    def __init__(self, vocab_size: int = 256, d_model: int = 256, n_layers: int = 4, n_heads: int = 8):
        super().__init__()
        self.vocab_size = vocab_size
        self.d_model = d_model
        
        # Embeddings
        self.char_embedding = nn.Embedding(vocab_size, d_model)
        self.pos_embedding = nn.Embedding(64, d_model)
        
        # Transformer
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model,
            nhead=n_heads,
            dim_feedforward=d_model * 4,
            dropout=0.1,
            batch_first=True,
            activation='gelu'
        )
        self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=n_layers)
        
        # Output projection
        self.output_projection = nn.Linear(d_model, vocab_size)
        
    def forward(self, context):
        batch_size, seq_len = context.shape
        
        # Embeddings
        char_emb = self.char_embedding(context)
        pos_emb = self.pos_embedding(torch.arange(seq_len, device=context.device))
        
        # Combine embeddings
        x = char_emb + pos_emb
        
        # Transformer
        x = self.transformer(x)
        
        # Output projection (predict next character)
        logits = self.output_projection(x[:, -1, :])  # Only last position
        
        return logits


def train_simple_model(events_file: str, output_dir: str, epochs: int = 10, batch_size: int = 64):
    """Train the simple character-level event prediction model."""
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Device
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"🚀 Training on device: {device}")
    
    # Dataset and dataloader
    dataset = SimpleEventDataset(events_file, context_length=16)
    dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)
    
    # Model
    model = SimpleEventModel(vocab_size=256, d_model=256, n_layers=4, n_heads=8)
    model.to(device)
    
    # Optimizer and loss
    optimizer = optim.AdamW(model.parameters(), lr=1e-3, weight_decay=0.01)
    criterion = nn.CrossEntropyLoss()
    
    # Training loop
    print(f"🎯 Starting training for {epochs} epochs...")
    
    for epoch in range(epochs):
        model.train()
        total_loss = 0.0
        correct_predictions = 0
        total_predictions = 0
        
        for batch_idx, batch in enumerate(dataloader):
            context = batch['context'].to(device)
            target = batch['target'].to(device)
            
            # Forward pass
            logits = model(context)
            
            # Calculate loss
            loss = criterion(logits, target)
            
            # Backward pass
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            
            total_loss += loss.item()
            
            # Calculate accuracy
            with torch.no_grad():
                predictions = torch.argmax(logits, dim=-1)
                correct = (predictions == target).sum().item()
                correct_predictions += correct
                total_predictions += target.size(0)
            
            if batch_idx % 100 == 0:
                print(f"  Epoch {epoch+1}/{epochs}, Batch {batch_idx}/{len(dataloader)}, "
                      f"Loss: {loss.item():.4f}")
        
        # Epoch summary
        avg_loss = total_loss / len(dataloader)
        accuracy = (correct_predictions / max(total_predictions, 1)) * 100
        
        print(f"📊 Epoch {epoch+1}/{epochs} - "
              f"Avg Loss: {avg_loss:.4f}, "
              f"Accuracy: {accuracy:.2f}%")
        
        # Save checkpoint
        checkpoint_path = os.path.join(output_dir, f"simple_event_model_epoch_{epoch+1}.pt")
        torch.save({
            'epoch': epoch + 1,
            'model_state_dict': model.state_dict(),
            'optimizer_state_dict': optimizer.state_dict(),
            'loss': avg_loss,
            'accuracy': accuracy
        }, checkpoint_path)
        print(f"💾 Saved checkpoint: {checkpoint_path}")
    
    print("✅ Training complete!")
    
    # Save final model
    final_model_path = os.path.join(output_dir, "simple_event_model_final.pt")
    torch.save({
        'model_state_dict': model.state_dict(),
        'vocab_size': model.vocab_size,
        'd_model': model.d_model,
        'n_layers': model.transformer.num_layers,
        'n_heads': model.transformer.layers[0].self_attn.num_heads
    }, final_model_path)
    print(f"🎯 Final model saved: {final_model_path}")
    
    return model


def test_simple_model(model_path: str, events_file: str, num_examples: int = 5):
    """Test the trained simple character-level model."""
    
    # Load model
    checkpoint = torch.load(model_path, map_location='cpu')
    model = SimpleEventModel(
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
    
    print(f"🧪 Testing simple character-level model on {len(examples)} examples...")
    
    for i, example in enumerate(examples):
        prompt = example['prompt']
        target = example['target']
        
        print(f"\n  Example {i+1}:")
        print(f"    Prompt: '{prompt}'")
        print(f"    Target: '{target}'")
        
        # Generate character by character
        generated = prompt
        context_length = 16
        
        for _ in range(50):  # Max 50 characters
            if len(generated) < context_length:
                # Pad with spaces
                context = generated + " " * (context_length - len(generated))
            else:
                context = generated[-context_length:]
            
            # Convert to tensor
            context_chars = [ord(c) for c in context]
            context_tensor = torch.tensor([context_chars], dtype=torch.long).to(device)
            
            # Predict next character
            with torch.no_grad():
                logits = model(context_tensor)
                next_char_idx = torch.argmax(logits, dim=-1).item()
                next_char = chr(next_char_idx)
            
            generated += next_char
            
            # Stop if we hit padding or special characters
            if next_char in ['\x00', '\x01', '\x02', '\x03']:
                break
        
        print(f"    Generated: '{generated}'")
        print(f"    Target in generated: {target in generated}")
    
    print("\n✅ Testing complete!")


def main():
    parser = argparse.ArgumentParser(description="Simple Event Training")
    parser.add_argument("--events", default="tools/event_eval.jsonl", help="Events file")
    parser.add_argument("--output", default="checkpoints/simple_event_training", help="Output directory")
    parser.add_argument("--epochs", type=int, default=10, help="Number of epochs")
    parser.add_argument("--batch-size", type=int, default=64, help="Batch size")
    parser.add_argument("--test", action="store_true", help="Test mode")
    parser.add_argument("--model", help="Model path for testing")
    
    args = parser.parse_args()
    
    if args.test:
        if not args.model:
            print("❌ Please provide --model path for testing")
            return
        test_simple_model(args.model, args.events)
    else:
        train_simple_model(args.events, args.output, args.epochs, args.batch_size)


if __name__ == "__main__":
    main()
