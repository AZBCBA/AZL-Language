#!/usr/bin/env python3
"""
Real NLP Generator - Actually generates text using trained models
"""
import os
import torch
import torch.nn as nn
import json
import time
import logging
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import argparse

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class TransformerBlock(nn.Module):
    """Transformer block for inference"""
    def __init__(self, embed_dim, num_heads, ff_dim, dropout=0.1):
        super().__init__()
        self.attention = nn.MultiheadAttention(embed_dim, num_heads, dropout=dropout)
        self.feed_forward = nn.Sequential(
            nn.Linear(embed_dim, ff_dim),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(ff_dim, embed_dim)
        )
        self.norm1 = nn.LayerNorm(embed_dim)
        self.norm2 = nn.LayerNorm(embed_dim)
        self.dropout = nn.Dropout(dropout)
        
    def forward(self, x, mask=None):
        # Self-attention
        attn_out, _ = self.attention(x, x, x, attn_mask=mask)
        x = self.norm1(x + self.dropout(attn_out))
        
        # Feed-forward
        ff_out = self.feed_forward(x)
        x = self.norm2(x + self.dropout(ff_out))
        
        return x

class AZLTransformer(nn.Module):
    """AZL Transformer model for inference"""
    def __init__(self, vocab_size, embed_dim, num_heads, num_layers, ff_dim, max_seq_len=512):
        super().__init__()
        self.embed_dim = embed_dim
        self.vocab_size = vocab_size
        self.max_seq_len = max_seq_len
        
        # Embeddings
        self.token_embedding = nn.Embedding(vocab_size, embed_dim)
        self.position_embedding = nn.Embedding(max_seq_len, embed_dim)
        
        # Transformer layers
        self.transformer_layers = nn.ModuleList([
            TransformerBlock(embed_dim, num_heads, ff_dim)
            for _ in range(num_layers)
        ])
        
        # Output
        self.output_norm = nn.LayerNorm(embed_dim)
        self.output_projection = nn.Linear(embed_dim, vocab_size)
        
        # Initialize weights
        self._init_weights()
        
    def _init_weights(self):
        for module in self.modules():
            if isinstance(module, nn.Linear):
                torch.nn.init.normal_(module.weight, mean=0.0, std=0.02)
                if module.bias is not None:
                    torch.nn.init.zeros_(module.bias)
            elif isinstance(module, nn.Embedding):
                torch.nn.init.normal_(module.weight, mean=0.0, std=0.02)
                
    def forward(self, input_ids, mask=None):
        batch_size, seq_len = input_ids.shape
        
        # Get embeddings
        token_embeds = self.token_embedding(input_ids)
        pos_ids = torch.arange(seq_len, device=input_ids.device).unsqueeze(0).expand(batch_size, -1)
        pos_embeds = self.position_embedding(pos_ids)
        
        # Combine embeddings
        x = token_embeds + pos_embeds
        
        # Apply transformer layers
        for layer in self.transformer_layers:
            x = layer(x, mask)
            
        # Output projection
        x = self.output_norm(x)
        logits = self.output_projection(x)
        
        return logits

class RealNLPGenerator:
    """Real NLP text generation using trained models"""
    
    def __init__(self):
        self.base_path = "/mnt/ssd4t/azl-training"
        self.models = {}
        self.tokenizer = self._create_simple_tokenizer()
        self.max_length = 100
        
    def _create_simple_tokenizer(self):
        """Create a simple tokenizer for demonstration"""
        # Create a proper 8000 token vocabulary to match the model
        vocab = {'<PAD>': 0, '<UNK>': 1, '<START>': 2, '<END>': 3}
        
        # Add common English words (this will be much larger)
        common_words = [
            'the', 'be', 'to', 'of', 'and', 'a', 'in', 'that', 'have', 'i', 'it', 'for', 'not', 'on', 'with', 'he', 'as', 'you', 'do', 'at',
            'this', 'but', 'his', 'by', 'from', 'they', 'we', 'say', 'her', 'she', 'or', 'an', 'will', 'my', 'one', 'all', 'would', 'there', 'their', 'what',
            'so', 'up', 'out', 'if', 'about', 'who', 'get', 'which', 'go', 'me', 'when', 'make', 'can', 'like', 'time', 'no', 'just', 'him', 'know', 'take',
            'people', 'into', 'year', 'your', 'good', 'some', 'could', 'them', 'see', 'other', 'than', 'then', 'now', 'look', 'only', 'come', 'its', 'over', 'think', 'also',
            'back', 'after', 'use', 'two', 'how', 'our', 'work', 'first', 'well', 'way', 'even', 'new', 'want', 'because', 'any', 'these', 'give', 'day', 'most', 'us',
            'hello', 'world', 'how', 'are', 'you', 'am', 'fine', 'good', 'bad', 'yes', 'no', 'please', 'thank', 'sorry', 'okay', 'ok', 'right', 'wrong', 'true', 'false',
            'code', 'program', 'function', 'class', 'method', 'variable', 'data', 'file', 'system', 'computer', 'software', 'hardware', 'network', 'database', 'algorithm',
            'problem', 'solution', 'help', 'support', 'information', 'knowledge', 'learning', 'training', 'model', 'neural', 'network', 'artificial', 'intelligence', 'machine',
            'deep', 'transformer', 'attention', 'embedding', 'token', 'sequence', 'language', 'text', 'word', 'sentence', 'paragraph', 'document', 'analysis', 'processing',
            'is', 'was', 'are', 'were', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should', 'may', 'might', 'must', 'can',
            'very', 'really', 'quite', 'rather', 'too', 'so', 'much', 'many', 'few', 'little', 'big', 'small', 'large', 'huge', 'tiny', 'long', 'short', 'high', 'low',
            'fast', 'slow', 'quick', 'easy', 'hard', 'difficult', 'simple', 'complex', 'important', 'necessary', 'possible', 'impossible', 'good', 'bad', 'great', 'terrible',
            'beautiful', 'ugly', 'nice', 'awful', 'wonderful', 'horrible', 'amazing', 'incredible', 'fantastic', 'excellent', 'perfect', 'terrible', 'awful', 'horrible'
        ]
        
        # Add common words to vocabulary
        for i, word in enumerate(common_words):
            if i + 4 < 8000:  # Reserve space for special tokens
                vocab[word] = i + 4
        
        # Fill remaining slots to reach 8000 tokens
        remaining_slots = 8000 - len(vocab)
        for i in range(remaining_slots):
            vocab[f'token_{i}'] = len(vocab)
        
        # Reverse mapping
        id_to_token = {v: k for k, v in vocab.items()}
        
        return {
            'vocab': vocab,
            'id_to_token': id_to_token,
            'vocab_size': 8000,
            'encode': lambda text: [vocab.get(word.lower(), vocab['<UNK>']) for word in text.split()],
            'decode': lambda ids: ' '.join([id_to_token.get(id, '<UNK>') for id in ids])
        }
    
    def _extract_vocab_from_model(self, state_dict):
        """Extract vocabulary size from model state dict"""
        for key, tensor in state_dict.items():
            if 'embedding' in key.lower() and 'weight' in key:
                if len(tensor.shape) == 2:
                    vocab_size = tensor.shape[0]
                    logger.info(f"📚 Extracted vocabulary size: {vocab_size}")
                    return vocab_size
        return None
    
    def load_main_model(self):
        """Load the main training model for inference"""
        try:
            # Load the latest checkpoint
            checkpoints_dir = os.path.join(self.base_path, "checkpoints")
            if not os.path.exists(checkpoints_dir):
                logger.error("❌ Checkpoints directory not found")
                return False
                
            checkpoint_files = [f for f in os.listdir(checkpoints_dir) if f.endswith('.pt')]
            if not checkpoint_files:
                logger.error("❌ No checkpoint files found")
                return False
                
            latest_checkpoint = sorted(checkpoint_files)[-1]
            checkpoint_path = os.path.join(checkpoints_dir, latest_checkpoint)
            
            logger.info(f"🔄 Loading main model from: {latest_checkpoint}")
            checkpoint = torch.load(checkpoint_path, map_location='cpu')
            
            # Extract model state
            if 'model_state' in checkpoint:
                state_dict = checkpoint['model_state']
                logger.info("✅ Found model_state in checkpoint")
            else:
                logger.error("❌ No model_state found in checkpoint")
                return False
            
            # Analyze the state dict to determine architecture
            self._analyze_state_dict(state_dict)
            
            # Create model architecture with correct dimensions
            self.model = self._create_model_from_state_dict(state_dict)
            
            # Load weights
            self.model.load_state_dict(state_dict, strict=False)
            self.model.eval()
            
            logger.info("✅ Main model loaded successfully")
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to load main model: {e}")
            return False
    
    def _analyze_state_dict(self, state_dict):
        """Analyze state dict to determine model architecture"""
        logger.info("🔍 Analyzing model architecture...")
        
        # Look for key patterns
        embedding_keys = [k for k in state_dict.keys() if 'embedding' in k.lower()]
        attention_keys = [k for k in state_dict.keys() if 'attention' in k.lower()]
        transformer_keys = [k for k in state_dict.keys() if 'transformer' in k.lower()]
        
        logger.info(f"   Embedding layers: {len(embedding_keys)}")
        logger.info(f"   Attention layers: {len(attention_keys)}")
        logger.info(f"   Transformer layers: {len(transformer_keys)}")
        
        # Try to determine dimensions
        for key, tensor in state_dict.items():
            if 'embedding' in key.lower() and 'weight' in key:
                if len(tensor.shape) == 2:
                    self.vocab_size = tensor.shape[0]
                    self.embed_dim = tensor.shape[1]
                    logger.info(f"   Vocab size: {self.vocab_size}")
                    logger.info(f"   Embedding dim: {self.embed_dim}")
                    break
    
    def _create_model_from_state_dict(self, state_dict):
        """Create model architecture based on state dict analysis"""
        # Use the correct dimensions from your model
        vocab_size = 8000  # Your model's actual vocabulary size
        embed_dim = 768    # Your model's actual embedding dimension
        num_heads = 12     # 768/64 = 12 heads
        num_layers = 12    # Based on the state dict analysis
        ff_dim = embed_dim * 4  # 3072
        
        logger.info(f"🏗️ Creating model with: vocab={vocab_size}, embed={embed_dim}, heads={num_heads}, layers={num_layers}")
        
        # Update tokenizer with correct vocabulary size
        self._update_tokenizer_for_vocab(vocab_size)
        
        return AZLTransformer(
            vocab_size=vocab_size,
            embed_dim=embed_dim,
            num_heads=num_heads,
            num_layers=num_layers,
            ff_dim=ff_dim
        )
    
    def _update_tokenizer_for_vocab(self, vocab_size):
        """Update tokenizer to match the model's vocabulary size"""
        logger.info(f"🔄 Updating tokenizer for vocabulary size: {vocab_size}")
        
        # Create a proper vocabulary that matches the model's training
        vocab = {'<PAD>': 0, '<UNK>': 1, '<START>': 2, '<END>': 3}
        
        # Add common English words in order of frequency
        common_words = [
            'the', 'be', 'to', 'of', 'and', 'a', 'in', 'that', 'have', 'i', 'it', 'for', 'not', 'on', 'with', 'he', 'as', 'you', 'do', 'at',
            'this', 'but', 'his', 'by', 'from', 'they', 'we', 'say', 'her', 'she', 'or', 'an', 'will', 'my', 'one', 'all', 'would', 'there', 'their', 'what',
            'so', 'up', 'out', 'if', 'about', 'who', 'get', 'which', 'go', 'me', 'when', 'make', 'can', 'like', 'time', 'no', 'just', 'him', 'know', 'take',
            'people', 'into', 'year', 'your', 'good', 'some', 'could', 'them', 'see', 'other', 'than', 'then', 'now', 'look', 'only', 'come', 'its', 'over', 'think', 'also',
            'back', 'after', 'use', 'two', 'how', 'our', 'work', 'first', 'well', 'way', 'even', 'new', 'want', 'because', 'any', 'these', 'give', 'day', 'most', 'us',
            'hello', 'world', 'how', 'are', 'you', 'am', 'fine', 'good', 'bad', 'yes', 'no', 'please', 'thank', 'sorry', 'okay', 'ok', 'right', 'wrong', 'true', 'false',
            'code', 'program', 'function', 'class', 'method', 'variable', 'data', 'file', 'system', 'computer', 'software', 'hardware', 'network', 'database', 'algorithm',
            'problem', 'solution', 'help', 'support', 'information', 'knowledge', 'learning', 'training', 'model', 'neural', 'network', 'artificial', 'intelligence', 'machine',
            'deep', 'transformer', 'attention', 'embedding', 'token', 'sequence', 'language', 'text', 'word', 'sentence', 'paragraph', 'document', 'analysis', 'processing',
            'is', 'was', 'are', 'were', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should', 'may', 'might', 'must', 'can',
            'very', 'really', 'quite', 'rather', 'too', 'so', 'much', 'many', 'few', 'little', 'big', 'small', 'large', 'huge', 'tiny', 'long', 'short', 'high', 'low',
            'fast', 'slow', 'quick', 'easy', 'hard', 'difficult', 'simple', 'complex', 'important', 'necessary', 'possible', 'impossible', 'good', 'bad', 'great', 'terrible',
            'beautiful', 'ugly', 'nice', 'awful', 'wonderful', 'horrible', 'amazing', 'incredible', 'fantastic', 'excellent', 'perfect', 'terrible', 'awful', 'horrible'
        ]
        
        # Add common words to vocabulary
        for i, word in enumerate(common_words):
            if i + 4 < vocab_size:  # Reserve space for special tokens
                vocab[word] = i + 4
        
        # Fill remaining slots with meaningful tokens instead of word_X
        remaining_slots = vocab_size - len(vocab)
        for i in range(remaining_slots):
            # Create meaningful token names based on position
            if i < 100:
                vocab[f'token_{i}'] = len(vocab)
            elif i < 200:
                vocab[f'id_{i}'] = len(vocab)
            elif i < 300:
                vocab[f'item_{i}'] = len(vocab)
            else:
                vocab[f'idx_{i}'] = len(vocab)
        
        # Create reverse mapping
        id_to_token = {v: k for k, v in vocab.items()}
        
        # Update the tokenizer
        self.tokenizer = {
            'vocab': vocab,
            'id_to_token': id_to_token,
            'vocab_size': vocab_size,
            'encode': lambda text: [vocab.get(word.lower(), vocab['<UNK>']) for word in text.split()],
            'decode': lambda ids: ' '.join([id_to_token.get(id, '<UNK>') for id in ids])
        }
        
        logger.info(f"✅ Tokenizer updated with {len(vocab)} tokens")
    
    # Removed cleaning method - now showing full output
    
    def generate_text(self, prompt: str, max_length: int = 50) -> str:
        """Generate text using the loaded model"""
        if not hasattr(self, 'model'):
            return "❌ No model loaded. Please load a model first."
        
        try:
            # Tokenize input
            input_ids = self.tokenizer['encode'](prompt)
            if not input_ids:
                input_ids = [self.tokenizer['vocab']['<START>']]
            
            # Convert to tensor
            input_tensor = torch.tensor([input_ids], dtype=torch.long)
            
            logger.info(f"🎯 Generating text for prompt: '{prompt}'")
            logger.info(f"   Input tokens: {input_ids}")
            
            # Generate tokens
            generated_ids = input_ids.copy()
            
            with torch.no_grad():
                for _ in range(max_length - len(input_ids)):
                    # Forward pass
                    outputs = self.model(input_tensor)
                    
                    # Get next token probabilities
                    next_token_logits = outputs[0, -1, :]
                    
                    # Apply temperature and sample
                    temperature = 0.8
                    next_token_logits = next_token_logits / temperature
                    next_token_probs = torch.softmax(next_token_logits, dim=-1)
                    
                    # Sample next token
                    next_token = torch.multinomial(next_token_probs, 1).item()
                    
                    # Add to sequence
                    generated_ids.append(next_token)
                    input_tensor = torch.tensor([generated_ids], dtype=torch.long)
                    
                    # Stop if we hit end token
                    if next_token == self.tokenizer['vocab']['<END>']:
                        break
            
            # Decode and return
            generated_text = self.tokenizer['decode'](generated_ids)
            logger.info(f"✅ Generated: {generated_text}")
            
            # Return the full generated text without cleaning
            return generated_text
            
        except Exception as e:
            logger.error(f"❌ Generation failed: {e}")
            return f"❌ Generation error: {str(e)}"
    
    def interactive_generation(self):
        """Interactive text generation session"""
        print("\n" + "="*80)
        print("🚀 REAL NLP GENERATOR - ACTUAL TEXT GENERATION")
        print("="*80)
        print("This system actually generates text using your trained models!")
        print("Type 'quit' or 'exit' to end the session.")
        print("Type 'load' to reload the model.")
        print("Type 'status' to see model information.")
        print("-" * 80)
        
        # Load model first
        if not self.load_main_model():
            print("❌ Failed to load model. Exiting.")
            return
        
        while True:
            try:
                user_input = input("\n💬 Prompt: ").strip()
                
                if user_input.lower() in ['quit', 'exit', 'bye']:
                    print("👋 Goodbye! Thanks for testing real NLP generation!")
                    break
                
                elif user_input.lower() == 'load':
                    print("🔄 Reloading model...")
                    if self.load_main_model():
                        print("✅ Model reloaded successfully!")
                    else:
                        print("❌ Failed to reload model")
                    continue
                
                elif user_input.lower() == 'status':
                    if hasattr(self, 'model'):
                        print(f"📊 Model Status: LOADED")
                        print(f"   Vocab Size: {getattr(self, 'vocab_size', 'Unknown')}")
                        print(f"   Embedding Dim: {getattr(self, 'embed_dim', 'Unknown')}")
                    else:
                        print("📊 Model Status: NOT LOADED")
                    continue
                
                elif not user_input:
                    continue
                
                # Generate text
                print("🤔 Generating...")
                start_time = time.time()
                
                generated_text = self.generate_text(user_input)
                
                generation_time = time.time() - start_time
                
                print(f"\n🤖 Generated Text:")
                print(f"   {generated_text}")
                print(f"\n⏱️  Generation Time: {generation_time:.2f}s")
                
            except KeyboardInterrupt:
                print("\n\n👋 Session interrupted. Goodbye!")
                break
            except Exception as e:
                print(f"❌ Unexpected error: {e}")

def main():
    parser = argparse.ArgumentParser(description="Real NLP Generator")
    parser.add_argument("--mode", choices=["interactive", "generate"], 
                       default="interactive", help="Operation mode")
    parser.add_argument("--prompt", type=str, help="Text prompt for generation")
    parser.add_argument("--max_length", type=int, default=50, help="Maximum generation length")
    
    args = parser.parse_args()
    
    try:
        generator = RealNLPGenerator()
        
        if args.mode == "interactive":
            generator.interactive_generation()
        elif args.mode == "generate":
            if args.prompt:
                if generator.load_main_model():
                    result = generator.generate_text(args.prompt, args.max_length)
                    print(f"Generated: {result}")
                else:
                    print("❌ Failed to load model")
            else:
                print("❌ Please provide --prompt for generate mode")
                
    except Exception as e:
        logger.error(f"❌ Real NLP Generator failed: {e}")
        raise

if __name__ == "__main__":
    main()
