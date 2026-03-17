#!/usr/bin/env python3
"""
State Dict Analyzer - Analyze the actual structure of the model state dict
"""
import os
import torch
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def analyze_state_dict(checkpoint_path: str):
    """Analyze the structure of the state dict"""
    logger.info(f"🔍 Analyzing state dict from: {checkpoint_path}")
    
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
        
        # Show first 20 layer names to understand structure
        logger.info("🔍 First 20 layer names:")
        for i, (key, tensor) in enumerate(list(state_dict.items())[:20]):
            shape = list(tensor.shape) if hasattr(tensor, 'shape') else 'No shape'
            logger.info(f"   {i+1:2d}. {key}: {shape}")
        
        # Look for patterns in layer names
        logger.info("\n🔍 Analyzing layer name patterns:")
        
        # Count different types of layers
        layer_types = {}
        for key in state_dict.keys():
            # Extract layer type from key
            if '.' in key:
                layer_type = key.split('.')[0]
            else:
                layer_type = key
            
            if layer_type not in layer_types:
                layer_types[layer_type] = 0
            layer_types[layer_type] += 1
        
        logger.info("📊 Layer type distribution:")
        for layer_type, count in sorted(layer_types.items()):
            logger.info(f"   {layer_type}: {count} layers")
        
        # Look for embedding-related layers
        logger.info("\n🔍 Looking for embedding-related layers:")
        embedding_layers = []
        for key, tensor in state_dict.items():
            if any(term in key.lower() for term in ['embed', 'token', 'vocab', 'word']):
                shape = list(tensor.shape) if hasattr(tensor, 'shape') else 'No shape'
                embedding_layers.append((key, shape))
                logger.info(f"   Found: {key}: {shape}")
        
        if not embedding_layers:
            logger.info("   No obvious embedding layers found")
            
            # Look for layers with 2D tensors (potential embeddings)
            logger.info("\n🔍 Looking for 2D tensors (potential embeddings):")
            potential_embeddings = []
            for key, tensor in state_dict.items():
                if hasattr(tensor, 'shape') and len(tensor.shape) == 2:
                    shape = list(tensor.shape)
                    potential_embeddings.append((key, shape))
                    logger.info(f"   Found: {key}: {shape}")
            
            if potential_embeddings:
                logger.info(f"\n💡 Found {len(potential_embeddings)} potential embedding layers")
                
                # Analyze the largest one (likely the main embedding)
                largest_embedding = max(potential_embeddings, key=lambda x: x[1][0])
                key, shape = largest_embedding
                logger.info(f"🎯 Largest potential embedding: {key}: {shape}")
                logger.info(f"   This suggests vocabulary size: {shape[0]:,}")
                logger.info(f"   And embedding dimension: {shape[1]:,}")
        
        # Look for transformer-related layers
        logger.info("\n🔍 Looking for transformer-related layers:")
        transformer_layers = []
        for key, tensor in state_dict.items():
            if any(term in key.lower() for term in ['transformer', 'attention', 'self_attn', 'multihead']):
                shape = list(tensor.shape) if hasattr(tensor, 'shape') else 'No shape'
                transformer_layers.append((key, shape))
                logger.info(f"   Found: {key}: {shape}")
        
        if not transformer_layers:
            logger.info("   No obvious transformer layers found")
        
        return state_dict
        
    except Exception as e:
        logger.error(f"❌ Failed to analyze state dict: {e}")
        return None

def main():
    """Main function to analyze state dict"""
    print("🔍 AZL Model State Dict Analyzer")
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
    
    # Use latest checkpoint
    latest_checkpoint = sorted(checkpoint_files)[-1]
    checkpoint_path = os.path.join(checkpoints_dir, latest_checkpoint)
    
    print(f"🎯 Analyzing latest checkpoint: {latest_checkpoint}")
    print("="*50)
    
    # Analyze state dict
    state_dict = analyze_state_dict(checkpoint_path)
    
    if state_dict:
        print("\n✅ State dict analysis completed!")
        print("="*50)
    else:
        print("\n❌ State dict analysis failed!")

if __name__ == "__main__":
    main()
