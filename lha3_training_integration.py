#!/usr/bin/env python3
"""
LHA3 Memory Integration with AZL/AZME Training Pipeline

This script integrates the LHA3 memory system with the training pipeline
to provide enhanced context retrieval and memory-augmented training.
"""

import json
import os
import torch
import numpy as np
from typing import List, Dict, Optional, Tuple
from pathlib import Path


class LHA3MemoryIntegration:
    """Integration layer between LHA3 memory system and PyTorch training."""
    
    def __init__(self, config_path: str = "master_training_config.json"):
        self.config = self.load_config(config_path)
        self.memory_store = {}
        self.code_embeddings = {}
        self.event_patterns = {}
        self.context_cache = {}
        self.retrieval_stats = {
            "total_queries": 0,
            "successful_retrievals": 0,
            "avg_retrieval_time": 0.0
        }
        
        # Load existing training data for memory population
        self.populate_memory_from_training_data()
    
    def load_config(self, config_path: str) -> dict:
        """Load training configuration."""
        if os.path.exists(config_path):
            with open(config_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {}
    
    def populate_memory_from_training_data(self):
        """Populate memory with existing training data."""
        dataset_path = self.config.get("dataset", {}).get("path")
        if not dataset_path or not os.path.exists(dataset_path):
            return
        
        print("🔄 Populating LHA3 memory from training dataset...")
        
        try:
            with open(dataset_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Extract code patterns and events
            self.extract_and_store_patterns(content)
            print(f"✅ LHA3 memory populated with {len(self.memory_store)} patterns")
            
        except Exception as e:
            print(f"⚠️ Failed to populate memory: {e}")
    
    def extract_and_store_patterns(self, content: str):
        """Extract code patterns and store in memory."""
        # Split content into manageable chunks
        chunks = self.split_content_into_chunks(content, max_chunk_size=1000)
        
        for i, chunk in enumerate(chunks):
            # Extract patterns from chunk
            patterns = self.extract_patterns_from_chunk(chunk)
            
            # Store in memory with metadata
            for pattern in patterns:
                self.store_pattern(pattern, {
                    "chunk_id": i,
                    "type": "code_pattern",
                    "length": len(pattern),
                    "complexity": self.compute_complexity(pattern)
                })
    
    def split_content_into_chunks(self, content: str, max_chunk_size: int) -> List[str]:
        """Split content into manageable chunks."""
        chunks = []
        lines = content.split('\n')
        current_chunk = []
        current_size = 0
        
        for line in lines:
            if current_size + len(line) > max_chunk_size and current_chunk:
                chunks.append('\n'.join(current_chunk))
                current_chunk = [line]
                current_size = len(line)
            else:
                current_chunk.append(line)
                current_size += len(line)
        
        if current_chunk:
            chunks.append('\n'.join(current_chunk))
        
        return chunks
    
    def extract_patterns_from_chunk(self, chunk: str) -> List[str]:
        """Extract meaningful patterns from a code chunk."""
        patterns = []
        
        # Extract function definitions
        import re
        function_patterns = re.findall(r'function\s+\w+\s*\([^)]*\)\s*\{[^}]*\}', chunk, re.DOTALL)
        patterns.extend(function_patterns)
        
        # Extract component definitions
        component_patterns = re.findall(r'component\s+[^{]*\{[^}]*\}', chunk, re.DOTALL)
        patterns.extend(component_patterns)
        
        # Extract event patterns
        event_patterns = re.findall(r'emit\s+"[^"]*"', chunk)
        patterns.extend(event_patterns)
        
        # Extract listen patterns
        listen_patterns = re.findall(r'listen\s+for\s+"[^"]*"', chunk)
        patterns.extend(listen_patterns)
        
        return patterns
    
    def store_pattern(self, pattern: str, metadata: dict):
        """Store a pattern in memory."""
        pattern_id = f"pattern_{len(self.memory_store)}"
        self.memory_store[pattern_id] = {
            "content": pattern,
            "metadata": metadata,
            "access_count": 0,
            "last_accessed": 0
        }
        
        # Compute and store embedding
        self.code_embeddings[pattern_id] = self.compute_embedding(pattern)
    
    def compute_embedding(self, text: str) -> np.ndarray:
        """Compute a simple embedding for the text."""
        # Simplified embedding using character frequency and position
        embedding = np.zeros(768)  # Match model hidden size
        
        # Character frequency features
        char_counts = {}
        for char in text:
            char_counts[char] = char_counts.get(char, 0) + 1
        
        # Fill embedding with character frequencies and positions
        for i, (char, count) in enumerate(char_counts.items()):
            if i < 256:  # ASCII range
                embedding[i] = count / len(text)
        
        # Position-based features
        for i, char in enumerate(text):
            if i < 512:  # Position limit
                embedding[256 + i] = ord(char) / 255.0
        
        # Normalize
        norm = np.linalg.norm(embedding)
        if norm > 0:
            embedding = embedding / norm
        
        return embedding
    
    def compute_complexity(self, code: str) -> float:
        """Compute code complexity score."""
        # Simple complexity metrics
        lines = code.split('\n')
        non_empty_lines = [line for line in lines if line.strip()]
        
        complexity = 0.0
        complexity += len(non_empty_lines) * 0.1  # Line count
        complexity += code.count('{') * 0.2  # Nesting
        complexity += code.count('function') * 0.3  # Function count
        complexity += code.count('if') * 0.2  # Conditional count
        complexity += code.count('for') * 0.2  # Loop count
        
        return min(complexity, 10.0)  # Cap at 10
    
    def retrieve_relevant_patterns(self, query: str, max_results: int = 5) -> List[Dict]:
        """Retrieve relevant patterns from memory."""
        import time
        start_time = time.time()
        
        query_embedding = self.compute_embedding(query)
        similarities = []
        
        # Compute similarities with all stored patterns
        for pattern_id, embedding in self.code_embeddings.items():
            similarity = self.compute_cosine_similarity(query_embedding, embedding)
            similarities.append((pattern_id, similarity))
        
        # Sort by similarity and return top results
        similarities.sort(key=lambda x: x[1], reverse=True)
        top_results = similarities[:max_results]
        
        # Prepare results with metadata
        results = []
        for pattern_id, similarity in top_results:
            pattern_data = self.memory_store[pattern_id]
            pattern_data["access_count"] += 1
            pattern_data["last_accessed"] = time.time()
            
            results.append({
                "pattern_id": pattern_id,
                "content": pattern_data["content"],
                "metadata": pattern_data["metadata"],
                "similarity": float(similarity),
                "access_count": pattern_data["access_count"]
            })
        
        # Update stats
        self.retrieval_stats["total_queries"] += 1
        self.retrieval_stats["successful_retrievals"] += len(results)
        
        retrieval_time = time.time() - start_time
        self.retrieval_stats["avg_retrieval_time"] = (
            (self.retrieval_stats["avg_retrieval_time"] * (self.retrieval_stats["total_queries"] - 1) + retrieval_time) /
            self.retrieval_stats["total_queries"]
        )
        
        return results
    
    def compute_cosine_similarity(self, emb1: np.ndarray, emb2: np.ndarray) -> float:
        """Compute cosine similarity between two embeddings."""
        dot_product = np.dot(emb1, emb2)
        norm1 = np.linalg.norm(emb1)
        norm2 = np.linalg.norm(emb2)
        
        if norm1 == 0 or norm2 == 0:
            return 0.0
        
        return dot_product / (norm1 * norm2)
    
    def get_memory_stats(self) -> Dict:
        """Get memory system statistics."""
        return {
            "total_patterns": len(self.memory_store),
            "total_embeddings": len(self.code_embeddings),
            "retrieval_stats": self.retrieval_stats.copy(),
            "memory_usage_mb": self.estimate_memory_usage()
        }
    
    def estimate_memory_usage(self) -> float:
        """Estimate memory usage in MB."""
        total_bytes = 0
        
        # Pattern storage
        for pattern_data in self.memory_store.values():
            total_bytes += len(pattern_data["content"].encode('utf-8'))
            total_bytes += len(str(pattern_data["metadata"]).encode('utf-8'))
        
        # Embeddings
        total_bytes += len(self.code_embeddings) * 768 * 8  # float64
        
        return total_bytes / (1024 * 1024)  # Convert to MB
    
    def export_memory_to_file(self, output_path: str):
        """Export memory contents to a file for inspection."""
        export_data = {
            "memory_store": self.memory_store,
            "stats": self.get_memory_stats(),
            "config": self.config
        }
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(export_data, f, indent=2, ensure_ascii=False)
        
        print(f"✅ LHA3 memory exported to {output_path}")


def integrate_with_training_pipeline():
    """Demonstrate integration with the training pipeline."""
    print("🚀 LHA3 Memory Integration with AZL/AZME Training")
    print("=" * 50)
    
    # Initialize memory system
    lha3 = LHA3MemoryIntegration()
    
    # Example queries to test retrieval
    test_queries = [
        "function component initialization",
        "event emission pattern",
        "memory management",
        "quantum enhancement",
        "neural network training"
    ]
    
    print("\n🔍 Testing Pattern Retrieval:")
    for query in test_queries:
        print(f"\nQuery: '{query}'")
        results = lha3.retrieve_relevant_patterns(query, max_results=3)
        
        if results:
            for i, result in enumerate(results):
                print(f"  {i+1}. Similarity: {result['similarity']:.3f}")
                print(f"     Content: {result['content'][:100]}...")
                print(f"     Access count: {result['access_count']}")
        else:
            print("  No relevant patterns found")
    
    # Display memory statistics
    print("\n📊 Memory System Statistics:")
    stats = lha3.get_memory_stats()
    for key, value in stats.items():
        if isinstance(value, dict):
            print(f"  {key}:")
            for sub_key, sub_value in value.items():
                print(f"    {sub_key}: {sub_value}")
        else:
            print(f"  {key}: {value}")
    
    # Export memory for inspection
    lha3.export_memory_to_file("lha3_memory_export.json")
    
    print("\n✅ LHA3 integration complete!")


if __name__ == "__main__":
    integrate_with_training_pipeline()
