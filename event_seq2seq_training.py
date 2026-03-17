#!/usr/bin/env python3
"""
Event Sequence-to-Sequence Training Script

This script trains a proper encoder-decoder model for event prediction,
where the encoder processes the prompt and the decoder generates the target.
"""

import json
import os
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from typing import List, Dict, Tuple
import argparse
import random


class EventSeq2SeqDataset(Dataset):
    """Dataset for event sequence-to-sequence training."""
    
    def __init__(self, events_file: str, max_prompt_len: int = 32, max_target_len: int = 32):
        self.max_prompt_len = max_prompt_len
        self.max_target_len = max_target_len
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
        
        # Encode prompt and target as bytes
        prompt_bytes = list(example['prompt'].encode('utf-8'))
        target_bytes = list(example['target'].encode('utf-8'))
        
        # Pad or truncate prompt
        if len(prompt_bytes) > self.max_prompt_len:
            prompt_bytes = prompt_bytes[:self.max_prompt_len]
        else:
            prompt_bytes.extend([0] * (self.max_prompt_len - len(prompt_bytes)))
        
        # Pad or truncate target
        if len(target_bytes) > self.max_target_len:
            target_bytes = target_bytes[:self.max_target_len]
        else:
            target_bytes.extend([0] * (self.max_target_len - len(target_bytes)))
        
        return {
            'prompt_ids': torch.tensor(prompt_bytes, dtype=torch.long),
            'target_ids': torch.tensor(target_bytes, dtype=torch.long),
            'target_length': min(len(example['target'].encode('utf-8')), self.max_target_len)
        }


class EventSeq2SeqModel(nn.Module):
    """Sequence-to-sequence model for event prediction."""
    
    def __init__(self, vocab_size: int = 256, d_model: int = 512, n_layers: int = 6, n_heads: int = 16):
        super().__init__()
        self.vocab_size = vocab_size
        self.d_model = d_model
        
        # Encoder
        self.encoder_embedding = nn.Embedding(vocab_size, d_model)
        self.encoder_pos_embedding = nn.Embedding(64, d_model)
        self.encoder_norm = nn.LayerNorm(d_model)
        
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model,
            nhead=n_heads,
            dim_feedforward=d_model * 4,
            dropout=0.1,
            batch_first=True,
            activation='gelu'
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=n_layers)
        
        # Decoder
        self.decoder_embedding = nn.Embedding(vocab_size, d_model)
        self.decoder_pos_embedding = nn.Embedding(64, d_model)
        self.decoder_norm = nn.LayerNorm(d_model)
        
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
        self.output_norm = nn.LayerNorm(d_model)
        self.output_projection = nn.Linear(d_model, vocab_size)
        
    def encode(self, prompt_ids):
        """Encode the prompt sequence."""
        batch_size, seq_len = prompt_ids.shape
        
        # Embeddings
        token_emb = self.encoder_embedding(prompt_ids)
        pos_emb = self.encoder_pos_embedding(torch.arange(seq_len, device=prompt_ids.device))
        
        # Combine and normalize
        x = token_emb + pos_emb
        x = self.encoder_norm(x)
        
        # Encode
        memory = self.encoder(x)
        return memory
    
    def decode(self, target_ids, memory):
        """Decode the target sequence given the encoded memory."""
        batch_size, seq_len = target_ids.shape
        
        # Embeddings
        token_emb = self.decoder_embedding(target_ids)
        pos_emb = self.decoder_pos_embedding(torch.arange(seq_len, device=target_ids.device))
        
        # Combine and normalize
        x = token_emb + pos_emb
        x = self.decoder_norm(x)
        
        # Decode
        x = self.decoder(x, memory)
        
        # Output projection
        x = self.output_norm(x)
        logits = self.output_projection(x)
        
        return logits
    
    def forward(self, prompt_ids, target_ids):
        """Forward pass for training."""
        # Encode prompt
        memory = self.encode(prompt_ids)
        
        # Decode target
        logits = self.decode(target_ids, memory)
        
        return logits


def train_seq2seq_model(events_file: str, output_dir: str, epochs: int = 10, batch_size: int = 32):
    """Train the sequence-to-sequence event prediction model."""
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Device
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"🚀 Training on device: {device}")
    
    # Dataset and dataloader
    dataset = EventSeq2SeqDataset(events_file, max_prompt_len=32, max_target_len=32)
    dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)
    
    # Model
    model = EventSeq2SeqModel(vocab_size=256, d_model=512, n_layers=6, n_heads=16)
    model.to(device)
    
    # Optimizer and loss
    optimizer = optim.AdamW(model.parameters(), lr=1e-4, weight_decay=0.01)
    criterion = nn.CrossEntropyLoss(ignore_index=0)  # Ignore padding tokens
    
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
            prompt_ids = batch['prompt_ids'].to(device)
            target_ids = batch['target_ids'].to(device)
            target_lengths = batch['target_length']
            
            # Forward pass
            logits = model(prompt_ids, target_ids)
            
            # Calculate loss (only on non-padding tokens)
            loss = criterion(logits.view(-1, logits.size(-1)), target_ids.view(-1))
            
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
                for i, length in enumerate(target_lengths):
                    if length > 0:
                        pred_seq = predictions[i, :length]
                        target_seq = target_ids[i, :length]
                        correct = (pred_seq == target_seq).sum().item()
                        correct_predictions += correct
                        total_predictions += length
            
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
        checkpoint_path = os.path.join(output_dir, f"seq2seq_event_model_epoch_{epoch+1}.pt")
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
    final_model_path = os.path.join(output_dir, "seq2seq_event_model_final.pt")
    torch.save({
        'model_state_dict': model.state_dict(),
        'vocab_size': model.vocab_size,
        'd_model': model.d_model,
        'n_layers': model.encoder.num_layers,
        'n_heads': model.encoder.layers[0].self_attn.num_heads
    }, final_model_path)
    print(f"🎯 Final model saved: {final_model_path}")
    
    return model


def test_seq2seq_model(model_path: str, events_file: str, num_examples: int = 10):
    """Test the trained sequence-to-sequence model."""
    
    # Load model
    checkpoint = torch.load(model_path, map_location='cpu')
    model = EventSeq2SeqModel(
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
    
    print(f"🧪 Testing sequence-to-sequence model on {len(examples)} examples...")
    
    correct = 0
    total = 0
    
    for i, example in enumerate(examples):
        prompt = example['prompt']
        target = example['target']
        
        # Encode prompt
        prompt_bytes = list(prompt.encode('utf-8'))
        prompt_ids = torch.tensor([prompt_bytes], dtype=torch.long).to(device)
        
        # Generate target sequence
        with torch.no_grad():
            # Encode prompt
            memory = model.encode(prompt_ids)
            
            # Start with start token (use 1 as start token)
            generated = [1]
            input_ids = torch.tensor([[1]], dtype=torch.long).to(device)
            
            for _ in range(50):  # Max 50 tokens
                # Decode
                logits = model.decode(input_ids, memory)
                next_token = torch.argmax(logits[:, -1, :], dim=-1)
                
                # Stop if we hit padding or special tokens
                if next_token.item() == 0:
                    break
                
                generated.append(next_token.item())
                input_ids = torch.cat([input_ids, next_token.unsqueeze(1)], dim=1)
        
        # Decode generated text (skip start token)
        generated_text = bytes(generated[1:]).decode('utf-8', errors='ignore')
        
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
    parser = argparse.ArgumentParser(description="Event Sequence-to-Sequence Training")
    parser.add_argument("--events", default="tools/event_eval.jsonl", help="Events file")
    parser.add_argument("--output", default="checkpoints/seq2seq_event_training", help="Output directory")
    parser.add_argument("--epochs", type=int, default=10, help="Number of epochs")
    parser.add_argument("--batch-size", type=int, default=32, help="Batch size")
    parser.add_argument("--test", action="store_true", help="Test mode")
    parser.add_argument("--model", help="Model path for testing")
    
    args = parser.parse_args()
    
    if args.test:
        if not args.model:
            print("❌ Please provide --model path for testing")
            return
        test_seq2seq_model(args.model, args.events)
    else:
        train_seq2seq_model(args.events, args.output, args.epochs, args.batch_size)


if __name__ == "__main__":
    main()
