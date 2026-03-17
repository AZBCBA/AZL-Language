#!/usr/bin/env python3
"""
AZL/AZME Model Evaluation Suite

Comprehensive evaluation of the trained model across multiple tasks:
- Code generation
- Event prediction
- Context understanding
- Memory retrieval integration
"""

import json
import os
import torch
import argparse
from pathlib import Path
from typing import List, Dict, Optional
import numpy as np


class AZLModelEvaluator:
    """Comprehensive evaluator for AZL/AZME trained models."""
    
    def __init__(self, config_path: str = "master_training_config.json"):
        self.config = self.load_config(config_path)
        self.model = None
        self.tokenizer = None
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        
        # Evaluation metrics
        self.evaluation_results = {
            "code_generation": {},
            "event_prediction": {},
            "context_understanding": {},
            "memory_integration": {},
            "overall_score": 0.0
        }
    
    def load_config(self, config_path: str) -> dict:
        """Load training configuration."""
        if os.path.exists(config_path):
            with open(config_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {}
    
    def load_model(self, checkpoint_path: str):
        """Load the trained model from checkpoint."""
        print(f"🔄 Loading model from {checkpoint_path}")
        
        try:
            # Load checkpoint
            checkpoint = torch.load(checkpoint_path, map_location=self.device)
            
            # Extract model configuration
            if "model_config" in checkpoint:
                model_config = checkpoint["model_config"]
            else:
                # Fallback to config file
                model_config = self.config.get("model", {}).get("config", {})
            
            # Build model with correct vocabulary size from checkpoint
            from real_training import build_model
            
            # Extract actual vocab size from checkpoint weights
            if "model_state" in checkpoint:
                state_dict = checkpoint["model_state"]
                # Get vocab size from embedding layer
                if "tok_embed.weight" in state_dict:
                    vocab_size = state_dict["tok_embed.weight"].shape[0]
                else:
                    vocab_size = model_config.get("vocab_size", 8000)
            else:
                vocab_size = model_config.get("vocab_size", 8000)
            
            seq_len = model_config.get("max_seq_length", 1024)
            
            self.model = build_model(self.config, vocab_size=vocab_size, seq_len=seq_len)
            self.model.load_state_dict(checkpoint["model_state"])
            self.model.to(self.device)
            self.model.eval()
            
            print(f"✅ Model loaded successfully")
            print(f"   - Vocab size: {vocab_size}")
            print(f"   - Hidden size: {model_config.get('hidden_size', 'N/A')}")
            print(f"   - Layers: {model_config.get('num_layers', 'N/A')}")
            
        except Exception as e:
            print(f"❌ Failed to load model: {e}")
            raise
    
    def evaluate_code_generation(self, test_prompts: List[str]) -> Dict:
        """Evaluate code generation capabilities."""
        print("\n🔍 Evaluating Code Generation...")
        
        results = {
            "total_prompts": len(test_prompts),
            "successful_generations": 0,
            "avg_length": 0.0,
            "syntax_validity": 0.0,
            "semantic_relevance": 0.0
        }
        
        generated_code = []
        
        for i, prompt in enumerate(test_prompts):
            try:
                # Generate code continuation
                generated = self.generate_code(prompt, max_tokens=100)
                generated_code.append(generated)
                
                # Basic metrics
                results["successful_generations"] += 1
                results["avg_length"] += len(generated)
                
                # Syntax validity (basic checks)
                syntax_score = self.check_syntax_validity(generated)
                results["syntax_validity"] += syntax_score
                
                # Semantic relevance
                semantic_score = self.check_semantic_relevance(prompt, generated)
                results["semantic_relevance"] += semantic_score
                
                print(f"  Prompt {i+1}: {prompt[:50]}...")
                print(f"    Generated: {generated[:100]}...")
                print(f"    Syntax: {syntax_score:.2f}, Semantic: {semantic_score:.2f}")
                
            except Exception as e:
                print(f"  ⚠️ Generation failed for prompt {i+1}: {e}")
        
        # Calculate averages
        if results["successful_generations"] > 0:
            results["avg_length"] /= results["successful_generations"]
            results["syntax_validity"] /= results["successful_generations"]
            results["semantic_relevance"] /= results["successful_generations"]
        
        self.evaluation_results["code_generation"] = results
        return results
    
    def evaluate_event_prediction(self, test_events: List[Dict]) -> Dict:
        """Evaluate event prediction accuracy."""
        print("\n🔍 Evaluating Event Prediction...")
        
        results = {
            "total_events": len(test_events),
            "exact_matches": 0,
            "partial_matches": 0,
            "avg_similarity": 0.0,
            "top_k_accuracy": {1: 0, 3: 0, 5: 0}
        }
        
        for i, event_data in enumerate(test_events):
            prompt = event_data["prompt"]
            target = event_data["target"]
            
            try:
                # Generate event prediction
                predicted = self.generate_event_prediction(prompt, max_tokens=20)
                
                # Exact match
                if predicted.strip() == target.strip():
                    results["exact_matches"] += 1
                
                # Partial match
                if target.strip() in predicted.strip() or predicted.strip() in target.strip():
                    results["partial_matches"] += 1
                
                # Similarity score
                similarity = self.compute_string_similarity(target, predicted)
                results["avg_similarity"] += similarity
                
                print(f"  Event {i+1}:")
                print(f"    Target: {target}")
                print(f"    Predicted: {predicted}")
                print(f"    Similarity: {similarity:.3f}")
                
            except Exception as e:
                print(f"  ⚠️ Event prediction failed for event {i+1}: {e}")
        
        # Calculate averages
        if results["total_events"] > 0:
            results["avg_similarity"] /= results["total_events"]
            results["exact_match_rate"] = results["exact_matches"] / results["total_events"]
            results["partial_match_rate"] = results["partial_matches"] / results["total_events"]
        
        self.evaluation_results["event_prediction"] = results
        return results
    
    def evaluate_context_understanding(self, context_tests: List[Dict]) -> Dict:
        """Evaluate context understanding capabilities."""
        print("\n🔍 Evaluating Context Understanding...")
        
        results = {
            "total_tests": len(context_tests),
            "context_aware_responses": 0,
            "avg_context_relevance": 0.0,
            "memory_retrieval_success": 0
        }
        
        for i, test in enumerate(context_tests):
            context = test["context"]
            query = test["query"]
            expected_response = test["expected"]
            
            try:
                # Generate context-aware response
                response = self.generate_context_aware_response(context, query)
                
                # Check if response is context-aware
                context_relevance = self.check_context_relevance(context, response)
                results["avg_context_relevance"] += context_relevance
                
                if context_relevance > 0.5:
                    results["context_aware_responses"] += 1
                
                print(f"  Context Test {i+1}:")
                print(f"    Context: {context[:100]}...")
                print(f"    Query: {query}")
                print(f"    Response: {response[:100]}...")
                print(f"    Context Relevance: {context_relevance:.3f}")
                
            except Exception as e:
                print(f"  ⚠️ Context understanding test failed for test {i+1}: {e}")
        
        # Calculate averages
        if results["total_tests"] > 0:
            results["avg_context_relevance"] /= results["total_tests"]
            results["context_awareness_rate"] = results["context_aware_responses"] / results["total_tests"]
        
        self.evaluation_results["context_understanding"] = results
        return results
    
    def generate_code(self, prompt: str, max_tokens: int = 100) -> str:
        """Generate code continuation from prompt."""
        # Tokenize prompt
        prompt_ids = self.encode_text(prompt)
        prompt_ids = prompt_ids.to(self.device)
        
        # Generate continuation using manual sampling
        with torch.no_grad():
            current_ids = prompt_ids.clone()
            
            for _ in range(max_tokens):
                # Get model output
                logits = self.model(current_ids)
                next_token_logits = logits[:, -1, :]
                
                # Apply temperature and sampling
                next_token_logits = next_token_logits / 0.7
                probs = torch.softmax(next_token_logits, dim=-1)
                
                # Sample next token
                next_token = torch.multinomial(probs, num_samples=1)
                
                # Append to sequence
                current_ids = torch.cat([current_ids, next_token], dim=1)
                
                # Stop if we hit padding or special tokens
                if next_token.item() == 0:
                    break
        
        # Decode generated text
        generated_text = self.decode_text(current_ids[0])
        return generated_text[len(prompt):]  # Return only the generated part
    
    def generate_event_prediction(self, prompt: str, max_tokens: int = 20) -> str:
        """Generate event prediction from prompt."""
        return self.generate_code(prompt, max_tokens)
    
    def generate_context_aware_response(self, context: str, query: str) -> str:
        """Generate context-aware response."""
        full_prompt = f"{context}\n\nQuery: {query}\nResponse:"
        return self.generate_code(full_prompt, max_tokens=50)
    
    def encode_text(self, text: str) -> torch.Tensor:
        """Encode text to token IDs."""
        # Simple byte-level encoding for now
        bytes_data = text.encode('utf-8')
        token_ids = [b for b in bytes_data]
        return torch.tensor([token_ids], dtype=torch.long)
    
    def decode_text(self, token_ids: torch.Tensor) -> str:
        """Decode token IDs back to text."""
        # Simple byte-level decoding
        bytes_data = bytes(token_ids.cpu().numpy())
        return bytes_data.decode('utf-8', errors='ignore')
    
    def check_syntax_validity(self, code: str) -> float:
        """Basic syntax validity check."""
        score = 0.0
        
        # Check for balanced braces
        brace_count = code.count('{') - code.count('}')
        if abs(brace_count) <= 1:
            score += 0.3
        
        # Check for balanced parentheses
        paren_count = code.count('(') - code.count(')')
        if abs(paren_count) <= 1:
            score += 0.3
        
        # Check for basic structure
        if 'function' in code or 'component' in code:
            score += 0.2
        
        if 'emit' in code or 'listen' in code:
            score += 0.2
        
        return min(score, 1.0)
    
    def check_semantic_relevance(self, prompt: str, generated: str) -> float:
        """Check semantic relevance between prompt and generated code."""
        # Simple keyword matching for now
        prompt_keywords = set(prompt.lower().split())
        generated_keywords = set(generated.lower().split())
        
        if not prompt_keywords:
            return 0.0
        
        overlap = len(prompt_keywords.intersection(generated_keywords))
        return min(overlap / len(prompt_keywords), 1.0)
    
    def compute_string_similarity(self, str1: str, str2: str) -> float:
        """Compute similarity between two strings."""
        if not str1 or not str2:
            return 0.0
        
        # Simple character-based similarity
        set1 = set(str1.lower())
        set2 = set(str2.lower())
        
        intersection = len(set1.intersection(set2))
        union = len(set1.union(set2))
        
        return intersection / union if union > 0 else 0.0
    
    def check_context_relevance(self, context: str, response: str) -> float:
        """Check if response is relevant to the given context."""
        # Simple keyword overlap
        context_words = set(context.lower().split())
        response_words = set(response.lower().split())
        
        if not context_words:
            return 0.0
        
        overlap = len(context_words.intersection(response_words))
        return min(overlap / len(context_words), 1.0)
    
    def run_comprehensive_evaluation(self, checkpoint_path: str):
        """Run comprehensive evaluation suite."""
        print("🚀 AZL/AZME Model Evaluation Suite")
        print("=" * 50)
        
        # Load model
        self.load_model(checkpoint_path)
        
        # Test prompts for code generation
        code_prompts = [
            "function initialize_component() {",
            "component ::azme.neural_network {",
            "emit \"training.started\" with {",
            "listen for \"memory.retrieved\" then {",
            "if ::quantum_enhancement {"
        ]
        
        # Test events for prediction
        test_events = [
            {"prompt": "listen for \"", "target": "component.loaded\""},
            {"prompt": "emit \"", "target": "training.complete\""},
            {"prompt": "wait for \"", "target": "memory.ready\""}
        ]
        
        # Test contexts for understanding
        context_tests = [
            {
                "context": "The quantum neural network is processing training data with enhanced memory retrieval.",
                "query": "What is the current system state?",
                "expected": "quantum neural network processing training data"
            },
            {
                "context": "LHA3 memory system has stored 6720 patterns with quantum enhancement enabled.",
                "query": "How many patterns are stored?",
                "expected": "6720 patterns"
            }
        ]
        
        # Run evaluations
        code_results = self.evaluate_code_generation(code_prompts)
        event_results = self.evaluate_event_prediction(test_events)
        context_results = self.evaluate_context_understanding(context_tests)
        
        # Calculate overall score
        overall_score = (
            code_results.get("syntax_validity", 0) * 0.3 +
            event_results.get("exact_match_rate", 0) * 0.4 +
            context_results.get("context_awareness_rate", 0) * 0.3
        )
        
        self.evaluation_results["overall_score"] = overall_score
        
        # Display final results
        print("\n📊 COMPREHENSIVE EVALUATION RESULTS")
        print("=" * 50)
        print(f"🎯 Overall Score: {overall_score:.3f}/1.0")
        print(f"📝 Code Generation: {code_results.get('syntax_validity', 0):.3f}")
        print(f"🔔 Event Prediction: {event_results.get('exact_match_rate', 0):.3f}")
        print(f"🧠 Context Understanding: {context_results.get('context_awareness_rate', 0):.3f}")
        
        # Save results
        self.save_evaluation_results()
        
        return self.evaluation_results
    
    def save_evaluation_results(self, output_path: str = "model_evaluation_results.json"):
        """Save evaluation results to file."""
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(self.evaluation_results, f, indent=2, ensure_ascii=False)
        
        print(f"\n✅ Evaluation results saved to {output_path}")


def main():
    parser = argparse.ArgumentParser(description="AZL/AZME Model Evaluation Suite")
    parser.add_argument("--checkpoint", required=True, help="Path to model checkpoint")
    parser.add_argument("--config", default="master_training_config.json", help="Path to config file")
    parser.add_argument("--output", default="model_evaluation_results.json", help="Output file for results")
    
    args = parser.parse_args()
    
    # Initialize evaluator
    evaluator = AZLModelEvaluator(args.config)
    
    # Run evaluation
    try:
        results = evaluator.run_comprehensive_evaluation(args.checkpoint)
        print(f"\n🎉 Evaluation completed successfully!")
        print(f"📁 Results saved to: {args.output}")
        
    except Exception as e:
        print(f"\n❌ Evaluation failed: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())
