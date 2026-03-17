#!/usr/bin/env python3
"""
Advanced Model Trainer for AZL/AZME
Trains advanced models with different architectures and capabilities
"""

import os
import torch
import torch.nn as nn
import torch.optim as optim
import json
import logging
from pathlib import Path
from typing import Dict, List, Optional
import argparse

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class AdvancedTransformerModel(nn.Module):
    """Advanced transformer model with enhanced capabilities"""
    
    def __init__(self, vocab_size=8000, embedding_dim=768, hidden_dim=3072, 
                 num_layers=12, num_heads=12, dropout=0.1, use_phase_attention=True):
        super().__init__()
        
        self.vocab_size = vocab_size
        self.embedding_dim = embedding_dim
        self.hidden_dim = hidden_dim
        self.num_layers = num_layers
        self.num_heads = num_heads
        self.use_phase_attention = use_phase_attention
        
        # Token embeddings
        self.tok_embed = nn.Embedding(vocab_size, embedding_dim)
        
        # Positional encoding
        self.pos_embed = nn.Parameter(torch.randn(1, 1024, embedding_dim))
        
        # Transformer layers
        if use_phase_attention:
            self.layers = nn.ModuleList([
                PhaseAttentionLayer(embedding_dim, hidden_dim, num_heads, dropout)
                for _ in range(num_layers)
            ])
        else:
            self.layers = nn.ModuleList([
                StandardTransformerLayer(embedding_dim, hidden_dim, num_heads, dropout)
                for _ in range(num_layers)
            ])
        
        # Final normalization and output
        self.norm = nn.LayerNorm(embedding_dim)
        self.output_head = nn.Linear(embedding_dim, vocab_size)
        
        # Dropout
        self.dropout = nn.Dropout(dropout)
        
        # Initialize weights
        self.apply(self._init_weights)
    
    def _init_weights(self, module):
        """Initialize model weights"""
        if isinstance(module, nn.Linear):
            torch.nn.init.normal_(module.weight, mean=0.0, std=0.02)
            if module.bias is not None:
                torch.nn.init.zeros_(module.bias)
        elif isinstance(module, nn.Embedding):
            torch.nn.init.normal_(module.weight, mean=0.0, std=0.02)
    
    def forward(self, input_ids, attention_mask=None):
        # Get sequence length
        seq_len = input_ids.size(1)
        
        # Embeddings
        x = self.tok_embed(input_ids)
        x = x + self.pos_embed[:, :seq_len, :]
        x = self.dropout(x)
        
        # Transformer layers
        for layer in self.layers:
            x = layer(x, attention_mask)
        
        # Final normalization and output
        x = self.norm(x)
        logits = self.output_head(x)
        
        return logits

class PhaseAttentionLayer(nn.Module):
    """Phase-augmented transformer layer"""
    
    def __init__(self, embedding_dim, hidden_dim, num_heads, dropout):
        super().__init__()
        
        # Multi-head attention with phase enhancement
        self.attention = nn.MultiheadAttention(embedding_dim, num_heads, dropout=dropout, batch_first=True)
        self.phase_proj = nn.Linear(embedding_dim, 64, bias=False)  # Phase projection
        self.alpha = nn.Parameter(torch.tensor(0.5, dtype=torch.float32))
        
        # Feed-forward network
        self.feed_forward = nn.Sequential(
            nn.Linear(embedding_dim, hidden_dim),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim, embedding_dim),
            nn.Dropout(dropout)
        )
        
        # Layer normalization
        self.norm1 = nn.LayerNorm(embedding_dim)
        self.norm2 = nn.LayerNorm(embedding_dim)
    
    def forward(self, x, attention_mask=None):
        # Phase-enhanced self-attention
        xn = self.norm1(x)
        
        # Standard attention
        attn_out, attn_weights = self.attention(xn, xn, xn, attn_mask=attention_mask, need_weights=True)
        
        # Phase coherence enhancement
        phase_vec = torch.tanh(self.phase_proj(xn))
        phase_coherence = torch.matmul(phase_vec, phase_vec.transpose(-2, -1))
        phase_coherence = (phase_coherence + 1.0) * 0.5  # Normalize to [0,1]
        
        # Blend attention with phase coherence
        blended_weights = torch.log(attn_weights + 1e-6) + self.alpha * phase_coherence
        blended_weights = torch.softmax(blended_weights, dim=-1)
        
        # Apply enhanced attention
        enhanced_context = torch.matmul(blended_weights, xn)
        x = x + enhanced_context
        
        # Feed-forward with residual connection
        ff_out = self.feed_forward(self.norm2(x))
        x = x + ff_out
        
        return x

class StandardTransformerLayer(nn.Module):
    """Standard transformer layer"""
    
    def __init__(self, embedding_dim, hidden_dim, num_heads, dropout):
        super().__init__()
        
        # Multi-head attention
        self.attention = nn.MultiheadAttention(embedding_dim, num_heads, dropout=dropout, batch_first=True)
        
        # Feed-forward network
        self.feed_forward = nn.Sequential(
            nn.Linear(embedding_dim, hidden_dim),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim, embedding_dim),
            nn.Dropout(dropout)
        )
        
        # Layer normalization
        self.norm1 = nn.LayerNorm(embedding_dim)
        self.norm2 = nn.LayerNorm(embedding_dim)
    
    def forward(self, x, attention_mask=None):
        # Self-attention with residual connection
        attn_out, _ = self.attention(self.norm1(x), self.norm1(x), self.norm1(x), attn_mask=attention_mask)
        x = x + attn_out
        
        # Feed-forward with residual connection
        ff_out = self.feed_forward(self.norm2(x))
        x = x + ff_out
        
        return x

class AdvancedDataset:
    """Advanced dataset for training"""
    
    def __init__(self, data_path, vocab_size=8000, max_seq_length=512):
        self.data_path = data_path
        self.vocab_size = vocab_size
        self.max_seq_length = max_seq_length
        self.data = self._load_data()
        self.vocab = self._build_vocab()
    
    def _load_data(self):
        """Load training data"""
        data = []
        
        if os.path.isdir(self.data_path):
            # Load from directory
            for file_path in Path(self.data_path).glob("*.json"):
                try:
                    with open(file_path, 'r') as f:
                        file_data = json.load(f)
                        if "event_training_data" in file_data:
                            data.extend(file_data["event_training_data"])
                except Exception as e:
                    logger.warning(f"Could not load {file_path}: {e}")
        else:
            # Load from single file
            try:
                with open(self.data_path, 'r') as f:
                    file_data = json.load(f)
                    if "event_training_data" in file_data:
                        data.extend(file_data["event_training_data"])
            except Exception as e:
                logger.error(f"Could not load {self.data_path}: {e}")
        
        logger.info(f"Loaded {len(data)} training samples")
        return data
    
    def _build_vocab(self):
        """Build vocabulary from data"""
        vocab = {"<PAD>": 0, "<UNK>": 1, "<BOS>": 2, "<EOS>": 3}
        
        # Collect all unique tokens
        tokens = set()
        for item in self.data:
            if "input" in item and "target" in item:
                tokens.add(item["input"])
                tokens.add(item["target"])
        
        # Add tokens to vocabulary
        for i, token in enumerate(sorted(tokens), start=len(vocab)):
            if i < self.vocab_size:
                vocab[token] = i
        
        logger.info(f"Built vocabulary with {len(vocab)} tokens")
        return vocab
    
    def __len__(self):
        return len(self.data)
    
    def __getitem__(self, idx):
        item = self.data[idx]
        
        # Encode input and target
        input_text = item.get("input", "")
        target_text = item.get("target", "")
        
        # Convert to token IDs
        input_ids = [self.vocab.get(token, self.vocab["<UNK>"]) for token in input_text.split()]
        target_ids = [self.vocab.get(token, self.vocab["<UNK>"]) for token in target_text.split()]
        
        # Pad or truncate to max_seq_length
        input_ids = input_ids[:self.max_seq_length-1] + [self.vocab["<EOS>"]]
        target_ids = target_ids[:self.max_seq_length-1] + [self.vocab["<EOS>"]]
        
        # Pad with PAD token
        while len(input_ids) < self.max_seq_length:
            input_ids.append(self.vocab["<PAD>"])
        while len(target_ids) < self.max_seq_length:
            target_ids.append(self.vocab["<PAD>"])
        
        return {
            "input_ids": torch.tensor(input_ids, dtype=torch.long),
            "target_ids": torch.tensor(target_ids, dtype=torch.long)
        }

def train_advanced_model(model_name: str, model_type: str = "phase_attention", 
                        steps: int = 2000, batch_size: int = 16, 
                        learning_rate: float = 1e-4):
    """Train an advanced model"""
    
    logger.info(f"🚀 Training Advanced Model: {model_name}")
    logger.info(f"Model Type: {model_type}")
    logger.info(f"Steps: {steps}")
    logger.info(f"Batch Size: {batch_size}")
    
    # Setup device
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    logger.info(f"Using device: {device}")
    
    # Create dataset
    dataset = AdvancedDataset("datasets/azl_azme_training_enhanced")
    dataloader = torch.utils.data.DataLoader(dataset, batch_size=batch_size, shuffle=True)
    
    # Create model
    if model_type == "phase_attention":
        model = AdvancedTransformerModel(
            vocab_size=len(dataset.vocab),
            embedding_dim=768,
            hidden_dim=3072,
            num_layers=12,
            num_heads=12,
            use_phase_attention=True
        )
    else:
        model = AdvancedTransformerModel(
            vocab_size=len(dataset.vocab),
            embedding_dim=768,
            hidden_dim=3072,
            num_layers=12,
            num_heads=12,
            use_phase_attention=False
        )
    
    model = model.to(device)
    
    # Setup optimizer and loss
    optimizer = optim.AdamW(model.parameters(), lr=learning_rate)
    criterion = nn.CrossEntropyLoss(ignore_index=dataset.vocab["<PAD>"])
    
    # Training loop
    model.train()
    total_loss = 0
    
    for step in range(steps):
        try:
            batch = next(iter(dataloader))
            input_ids = batch["input_ids"].to(device)
            target_ids = batch["target_ids"].to(device)
            
            # Forward pass
            logits = model(input_ids)
            loss = criterion(logits.view(-1, logits.size(-1)), target_ids.view(-1))
            
            # Backward pass
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            
            total_loss += loss.item()
            
            if (step + 1) % 100 == 0:
                avg_loss = total_loss / (step + 1)
                logger.info(f"Step {step + 1}/{steps}, Loss: {avg_loss:.4f}")
        
        except StopIteration:
            # Restart dataloader if it runs out
            dataloader = torch.utils.data.DataLoader(dataset, batch_size=batch_size, shuffle=True)
            continue
    
    # Save model
    output_dir = Path(f"/mnt/ssd4t/azl-training/{model_name}")
    output_dir.mkdir(exist_ok=True)
    
    model_path = output_dir / "model.pt"
    torch.save({
        'model_state_dict': model.state_dict(),
        'vocab': dataset.vocab,
        'model_config': {
            'vocab_size': len(dataset.vocab),
            'embedding_dim': model.embedding_dim,
            'hidden_dim': model.hidden_dim,
            'num_layers': model.num_layers,
            'num_heads': model.num_heads,
            'model_type': model_type
        }
    }, model_path)
    
    logger.info(f"✅ Model saved to: {model_path}")
    return model

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Advanced Model Trainer")
    parser.add_argument('--model-name', required=True, help='Name for the trained model')
    parser.add_argument('--model-type', choices=['phase_attention', 'standard'], 
                       default='phase_attention', help='Type of model to train')
    parser.add_argument('--steps', type=int, default=2000, help='Number of training steps')
    parser.add_argument('--batch-size', type=int, default=16, help='Batch size')
    parser.add_argument('--learning-rate', type=float, default=1e-4, help='Learning rate')
    
    args = parser.parse_args()
    
    # Train the model
    model = train_advanced_model(
        model_name=args.model_name,
        model_type=args.model_type,
        steps=args.steps,
        batch_size=args.batch_size,
        learning_rate=args.learning_rate
    )
    
    logger.info(f"🎉 Advanced model training completed: {args.model_name}")

if __name__ == "__main__":
    main()
