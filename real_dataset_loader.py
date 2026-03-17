#!/usr/bin/env python3
"""
Real Dataset Loader
Loads and processes real datasets for training
"""

import os
import json
import csv
import pandas as pd
from pathlib import Path
import requests
from typing import List, Dict, Any

class RealDatasetLoader:
    def __init__(self):
        self.supported_formats = ['.txt', '.csv', '.json', '.jsonl']
        self.datasets_dir = "datasets"
        os.makedirs(self.datasets_dir, exist_ok=True)
    
    def load_text_file(self, file_path: str) -> List[str]:
        """Load text file with various encodings"""
        encodings = ['utf-8', 'latin-1', 'cp1252']
        
        for encoding in encodings:
            try:
                with open(file_path, 'r', encoding=encoding) as f:
                    lines = [line.strip() for line in f if line.strip()]
                print(f"✅ Loaded {len(lines)} lines from {file_path}")
                return lines
            except UnicodeDecodeError:
                continue
        
        raise ValueError(f"Could not read {file_path} with any encoding")
    
    def load_csv_file(self, file_path: str, text_column: str = None) -> List[str]:
        """Load CSV file and extract text data"""
        try:
            df = pd.read_csv(file_path)
            
            if text_column and text_column in df.columns:
                texts = df[text_column].dropna().astype(str).tolist()
            else:
                # Use first column if no specific column specified
                texts = df.iloc[:, 0].dropna().astype(str).tolist()
            
            print(f"✅ Loaded {len(texts)} rows from CSV {file_path}")
            return texts
        except Exception as e:
            print(f"❌ Error loading CSV {file_path}: {e}")
            return []
    
    def load_json_file(self, file_path: str, text_key: str = None) -> List[str]:
        """Load JSON file and extract text data"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            texts = []
            if isinstance(data, list):
                for item in data:
                    if isinstance(item, dict):
                        if text_key and text_key in item:
                            texts.append(str(item[text_key]))
                        else:
                            # Try to find any text-like field
                            for key, value in item.items():
                                if isinstance(value, str) and len(value) > 10:
                                    texts.append(value)
                                    break
                    elif isinstance(item, str):
                        texts.append(item)
            elif isinstance(data, dict):
                # Look for text fields in dict
                for key, value in data.items():
                    if isinstance(value, str) and len(value) > 10:
                        texts.append(value)
            
            print(f"✅ Loaded {len(texts)} texts from JSON {file_path}")
            return texts
        except Exception as e:
            print(f"❌ Error loading JSON {file_path}: {e}")
            return []
    
    def load_jsonl_file(self, file_path: str, text_key: str = None) -> List[str]:
        """Load JSONL (JSON Lines) file"""
        texts = []
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f, 1):
                    try:
                        data = json.loads(line.strip())
                        if isinstance(data, dict):
                            if text_key and text_key in data:
                                texts.append(str(data[text_key]))
                            else:
                                # Find any text field
                                for key, value in data.items():
                                    if isinstance(value, str) and len(value) > 10:
                                        texts.append(value)
                                        break
                        elif isinstance(data, str):
                            texts.append(data)
                    except json.JSONDecodeError:
                        print(f"⚠️  Skipping invalid JSON at line {line_num}")
                        continue
            
            print(f"✅ Loaded {len(texts)} texts from JSONL {file_path}")
            return texts
        except Exception as e:
            print(f"❌ Error loading JSONL {file_path}: {e}")
            return []
    
    def download_dataset(self, url: str, filename: str = None) -> str:
        """Download dataset from URL"""
        if not filename:
            filename = url.split('/')[-1]
        
        file_path = os.path.join(self.datasets_dir, filename)
        
        try:
            print(f"📥 Downloading dataset from {url}...")
            response = requests.get(url, stream=True)
            response.raise_for_status()
            
            with open(file_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
            
            print(f"✅ Downloaded {filename} to {file_path}")
            return file_path
        except Exception as e:
            print(f"❌ Error downloading dataset: {e}")
            return None
    
    def load_dataset(self, file_path: str, text_column: str = None, text_key: str = None) -> List[str]:
        """Load dataset from file with automatic format detection"""
        file_path = Path(file_path)
        
        if not file_path.exists():
            print(f"❌ File not found: {file_path}")
            return []
        
        file_extension = file_path.suffix.lower()
        
        if file_extension == '.txt':
            return self.load_text_file(str(file_path))
        elif file_extension == '.csv':
            return self.load_csv_file(str(file_path), text_column)
        elif file_extension == '.json':
            return self.load_json_file(str(file_path), text_key)
        elif file_extension == '.jsonl':
            return self.load_jsonl_file(str(file_path), text_key)
        else:
            print(f"❌ Unsupported file format: {file_extension}")
            print(f"Supported formats: {', '.join(self.supported_formats)}")
            return []
    
    def get_sample_datasets(self) -> Dict[str, str]:
        """Get list of available sample datasets"""
        sample_datasets = {
            "news_articles": "https://raw.githubusercontent.com/abhimishra91/insight/master/insight/Data/News_Final.csv",
            "twitter_sentiment": "https://raw.githubusercontent.com/kazanova/sentiment140/master/Data/training.1600000.processed.noemoticon.csv",
            "book_reviews": "https://raw.githubusercontent.com/sidooms/MovieTweetings/master/latest/movies.dat",
            "code_samples": "https://raw.githubusercontent.com/github/gitignore/master/Python.gitignore"
        }
        return sample_datasets
    
    def download_sample_dataset(self, dataset_name: str) -> str:
        """Download a sample dataset"""
        sample_datasets = self.get_sample_datasets()
        
        if dataset_name not in sample_datasets:
            print(f"❌ Unknown dataset: {dataset_name}")
            print(f"Available: {', '.join(sample_datasets.keys())}")
            return None
        
        url = sample_datasets[dataset_name]
        return self.download_dataset(url, f"{dataset_name}.csv")
    
    def preprocess_text(self, texts: List[str], min_length: int = 10, max_length: int = 1000) -> List[str]:
        """Preprocess and clean text data"""
        processed = []
        
        for text in texts:
            # Clean and filter text
            cleaned = text.strip()
            
            # Remove very short or very long texts
            if min_length <= len(cleaned) <= max_length:
                # Basic cleaning
                cleaned = cleaned.replace('\n', ' ').replace('\r', ' ')
                cleaned = ' '.join(cleaned.split())  # Normalize whitespace
                
                if cleaned:
                    processed.append(cleaned)
        
        print(f"✅ Preprocessed {len(processed)} texts (filtered from {len(texts)})")
        return processed
    
    def split_train_val(self, texts: List[str], val_split: float = 0.1) -> tuple:
        """Split data into training and validation sets"""
        import random
        random.shuffle(texts)
        
        split_idx = int(len(texts) * (1 - val_split))
        train_texts = texts[:split_idx]
        val_texts = texts[split_idx:]
        
        print(f"📊 Split: {len(train_texts)} training, {len(val_texts)} validation")
        return train_texts, val_texts

def main():
    """Test the dataset loader"""
    loader = RealDatasetLoader()
    
    print("🎯 REAL DATASET LOADER")
    print("=" * 40)
    
    # Show available sample datasets
    print("📚 Available sample datasets:")
    for name, url in loader.get_sample_datasets().items():
        print(f"  • {name}: {url}")
    
    print("\n💡 Usage examples:")
    print("  • loader.load_dataset('path/to/file.csv', text_column='text')")
    print("  • loader.load_dataset('path/to/file.json', text_key='content')")
    print("  • loader.download_sample_dataset('news_articles')")

if __name__ == "__main__":
    main()
