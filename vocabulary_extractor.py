#!/usr/bin/env python3
"""
Vocabulary Extractor - Extract the ACTUAL vocabulary from trained models
"""
import os
import torch
import json
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def extract_vocabulary_from_checkpoint(checkpoint_path: str):
    """Extract vocabulary information from a model checkpoint"""
    logger.info(f"🔍 Extracting vocabulary from: {checkpoint_path}")
    
    try:
        # Load checkpoint
        checkpoint = torch.load(checkpoint_path, map_location='cpu')
        logger.info("✅ Checkpoint loaded successfully")
        
        # Show checkpoint structure
        logger.info(f"📋 Checkpoint keys: {list(checkpoint.keys())}")
        
        # Look for model state
        if 'model_state' in checkpoint:
            state_dict = checkpoint['model_state']
            logger.info("✅ Found model_state in checkpoint")
        else:
            state_dict = checkpoint
            logger.info("⚠️ Using checkpoint directly as state_dict")
        
        # Analyze state dict
        logger.info(f"📊 State dict has {len(state_dict)} layers")
        
        # Look for embedding layers
        embedding_info = {}
        for key, tensor in state_dict.items():
            if 'embedding' in key.lower() and 'weight' in key:
                shape = tensor.shape
                logger.info(f"🔍 Found embedding layer: {key} with shape {shape}")
                
                if len(shape) == 2:
                    vocab_size, embed_dim = shape
                    embedding_info[key] = {
                        'vocab_size': vocab_size,
                        'embed_dim': embed_dim,
                        'tensor': tensor
                    }
                    logger.info(f"   Vocabulary size: {vocab_size}")
                    logger.info(f"   Embedding dimension: {embed_dim}")
        
        if not embedding_info:
            logger.warning("⚠️ No embedding layers found!")
            return None
        
        # Try to extract actual vocabulary
        for key, info in embedding_info.items():
            logger.info(f"\n🎯 Analyzing embedding layer: {key}")
            
            # Look for vocabulary files in the same directory
            checkpoint_dir = os.path.dirname(checkpoint_path)
            vocab_files = []
            
            # Common vocabulary file names
            possible_vocab_files = [
                'vocab.json', 'vocab.txt', 'vocabulary.json', 'tokens.txt',
                'merges.txt', 'bpe.codes', 'tokenizer.json', 'vocab.bpe'
            ]
            
            for vocab_file in possible_vocab_files:
                vocab_path = os.path.join(checkpoint_dir, vocab_file)
                if os.path.exists(vocab_path):
                    vocab_files.append(vocab_path)
            
            if vocab_files:
                logger.info(f"📚 Found vocabulary files: {vocab_files}")
                for vocab_file in vocab_files:
                    analyze_vocab_file(vocab_file)
            else:
                logger.info("📚 No vocabulary files found in checkpoint directory")
                
                # Try to infer vocabulary from embedding weights
                logger.info("🔍 Attempting to infer vocabulary from embedding weights...")
                infer_vocabulary_from_weights(info['tensor'], key)
        
        return embedding_info
        
    except Exception as e:
        logger.error(f"❌ Failed to extract vocabulary: {e}")
        return None

def analyze_vocab_file(vocab_path: str):
    """Analyze a vocabulary file"""
    logger.info(f"📖 Analyzing vocabulary file: {vocab_path}")
    
    try:
        if vocab_path.endswith('.json'):
            with open(vocab_path, 'r', encoding='utf-8') as f:
                vocab_data = json.load(f)
                logger.info(f"   JSON vocabulary with {len(vocab_data)} entries")
                if isinstance(vocab_data, dict):
                    # Show first few entries
                    sample_entries = list(vocab_data.items())[:10]
                    logger.info(f"   Sample entries: {sample_entries}")
                elif isinstance(vocab_data, list):
                    logger.info(f"   List vocabulary with {len(vocab_data)} tokens")
                    if vocab_data:
                        logger.info(f"   Sample tokens: {vocab_data[:10]}")
        
        elif vocab_path.endswith('.txt'):
            with open(vocab_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
                logger.info(f"   Text vocabulary with {len(lines)} lines")
                if lines:
                    sample_lines = [line.strip() for line in lines[:10]]
                    logger.info(f"   Sample lines: {sample_lines}")
        
        else:
            logger.info(f"   Unknown file type: {vocab_path}")
            
    except Exception as e:
        logger.error(f"❌ Failed to analyze vocabulary file: {e}")

def infer_vocabulary_from_weights(embedding_tensor, layer_name: str):
    """Try to infer vocabulary from embedding weights"""
    logger.info(f"🔍 Inferring vocabulary from {layer_name} weights...")
    
    try:
        vocab_size, embed_dim = embedding_tensor.shape
        logger.info(f"   Tensor shape: {embedding_tensor.shape}")
        
        # Look for patterns in the weights
        # Check if weights are normalized
        weight_norms = torch.norm(embedding_tensor, dim=1)
        logger.info(f"   Weight norms - Min: {weight_norms.min():.4f}, Max: {weight_norms.max():.4f}, Mean: {weight_norms.mean():.4f}")
        
        # Check for special tokens (usually at the beginning)
        if vocab_size > 10:
            logger.info(f"   First 10 token embeddings:")
            for i in range(min(10, vocab_size)):
                norm = weight_norms[i].item()
                logger.info(f"     Token {i}: norm={norm:.4f}")
        
        # Look for vocabulary size patterns
        common_vocab_sizes = [50257, 32000, 50000, 100000, 500000, 1000000]
        for common_size in common_vocab_sizes:
            if abs(vocab_size - common_size) < 100:
                logger.info(f"   📚 Vocabulary size {vocab_size} is close to common size {common_size}")
                break
        
        logger.info(f"   💡 This suggests the model was trained on a vocabulary of approximately {vocab_size} tokens")
        
    except Exception as e:
        logger.error(f"❌ Failed to infer vocabulary: {e}")

def main():
    """Main function to extract vocabulary from checkpoints"""
    print("🔍 AZL Model Vocabulary Extractor")
    print("="*50)
    
    # Check for checkpoints
    base_path = "/mnt/ssd4t/azl-training"
    checkpoints_dir = os.path.join(base_path, "checkpoints")
    
    if not os.path.exists(checkpoints_dir):
        print("❌ Checkpoints directory not found!")
        return
    
    # Find checkpoint files
    checkpoint_files = [f for f in os.listdir(checkpoints_dir) if f.endswith('.pt')]
    if not checkpoint_files:
        print("❌ No checkpoint files found!")
        return
    
    print(f"📁 Found {len(checkpoint_files)} checkpoint files:")
    for i, checkpoint_file in enumerate(checkpoint_files):
        print(f"   {i+1}. {checkpoint_file}")
    
    # Extract from latest checkpoint
    latest_checkpoint = sorted(checkpoint_files)[-1]
    checkpoint_path = os.path.join(checkpoints_dir, latest_checkpoint)
    
    print(f"\n🎯 Analyzing latest checkpoint: {latest_checkpoint}")
    print("="*50)
    
    # Extract vocabulary
    vocab_info = extract_vocabulary_from_checkpoint(checkpoint_path)
    
    if vocab_info:
        print("\n✅ Vocabulary extraction completed!")
        print("="*50)
        
        # Summary
        for key, info in vocab_info.items():
            print(f"📊 {key}:")
            print(f"   Vocabulary Size: {info['vocab_size']:,}")
            print(f"   Embedding Dimension: {info['embed_dim']:,}")
            print()
    else:
        print("\n❌ Vocabulary extraction failed!")

if __name__ == "__main__":
    main()
