#!/usr/bin/env python3
"""
AZL/AZME Dataset Creator
Creates training datasets from AZL and AZME code
"""

import os
import json
import glob
from pathlib import Path
from typing import List, Dict, Any

class AZLAZMEDatasetCreator:
    def __init__(self):
        self.azl_dir = "azl"
        self.azme_dir = "azme"
        self.output_dir = "datasets/azl_azme_training"
        
        # Create output directory
        os.makedirs(self.output_dir, exist_ok=True)
        
        # AZL file extensions
        self.azl_extensions = [".azl", ".az", ".azl_code"]
        
        # Code patterns to look for
        self.code_patterns = {
            "components": "component",
            "functions": "fn",
            "behavior": "behavior",
            "memory": "memory",
            "init": "init",
            "events": "emit",
            "listeners": "listen for",
            "variables": "set",
            "loops": "for",
            "conditionals": "if",
            "returns": "return"
        }
    
    def scan_azl_files(self) -> List[str]:
        """Scan for all AZL files in the project"""
        azl_files = []
        
        # Scan azl directory
        for root, dirs, files in os.walk(self.azl_dir):
            for file in files:
                if any(file.endswith(ext) for ext in self.azl_extensions):
                    file_path = os.path.join(root, file)
                    azl_files.append(file_path)
        
        # Scan root directory for AZL files
        for file in glob.glob("*.azl"):
            azl_files.append(file)
        
        # Scan for other AZL-related files
        for file in glob.glob("test_*.azl"):
            azl_files.append(file)
        
        for file in glob.glob("*_training.azl"):
            azl_files.append(file)
        
        print(f"🔍 Found {len(azl_files)} AZL files")
        return azl_files
    
    def scan_azme_files(self) -> List[str]:
        """Scan for AZME-related files"""
        azme_files = []
        
        # Scan azme directory
        for root, dirs, files in os.walk(self.azme_dir):
            for file in files:
                if file.endswith(('.py', '.azl', '.json', '.md')):
                    file_path = os.path.join(root, file)
                    azme_files.append(file_path)
        
        # Look for AZME-related files in root
        for file in glob.glob("*azme*"):
            if os.path.isfile(file):
                azme_files.append(file)
        
        print(f"🔍 Found {len(azme_files)} AZME-related files")
        return azme_files
    
    def read_file_content(self, file_path: str) -> str:
        """Read file content with error handling"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            return content
        except UnicodeDecodeError:
            try:
                with open(file_path, 'r', encoding='latin-1') as f:
                    content = f.read()
                return content
            except Exception as e:
                print(f"⚠️  Could not read {file_path}: {e}")
                return ""
        except Exception as e:
            print(f"❌ Error reading {file_path}: {e}")
            return ""
    
    def analyze_azl_code(self, content: str, file_path: str) -> Dict[str, Any]:
        """Analyze AZL code structure and patterns"""
        analysis = {
            "file_path": file_path,
            "content": content,
            "lines": len(content.split('\n')),
            "characters": len(content),
            "patterns_found": {},
            "component_count": 0,
            "function_count": 0,
            "complexity_score": 0
        }
        
        # Count patterns
        for pattern_name, pattern in self.code_patterns.items():
            count = content.count(pattern)
            analysis["patterns_found"][pattern_name] = count
        
        # Count components
        analysis["component_count"] = content.count("component")
        
        # Count functions
        analysis["function_count"] = content.count("fn")
        
        # Calculate complexity score
        complexity = 0
        complexity += content.count("component") * 10
        complexity += content.count("fn") * 5
        complexity += content.count("behavior") * 3
        complexity += content.count("emit") * 2
        complexity += content.count("listen for") * 2
        complexity += content.count("for") * 1
        complexity += content.count("if") * 1
        
        analysis["complexity_score"] = complexity
        
        return analysis
    
    def create_training_samples(self, azl_files: List[str], azme_files: List[str]) -> Dict[str, Any]:
        """Create training samples from AZL and AZME code"""
        training_data = {
            "azl_samples": [],
            "azme_samples": [],
            "combined_samples": [],
            "statistics": {
                "total_azl_files": len(azl_files),
                "total_azme_files": len(azme_files),
                "total_samples": 0,
                "total_lines": 0,
                "total_characters": 0
            }
        }
        
        # Process AZL files
        print("📚 Processing AZL files...")
        for file_path in azl_files:
            content = self.read_file_content(file_path)
            if content:
                analysis = self.analyze_azl_code(content, file_path)
                training_data["azl_samples"].append(analysis)
                
                # Create training sample
                sample = {
                    "type": "azl_code",
                    "source": file_path,
                    "content": content,
                    "analysis": analysis,
                    "training_target": "azl_language_understanding"
                }
                training_data["combined_samples"].append(sample)
        
        # Process AZME files
        print("🧠 Processing AZME files...")
        for file_path in azme_files:
            content = self.read_file_content(file_path)
            if content:
                analysis = self.analyze_azl_code(content, file_path)
                training_data["azme_samples"].append(analysis)
                
                # Create training sample
                sample = {
                    "type": "azme_code",
                    "source": file_path,
                    "content": content,
                    "analysis": analysis,
                    "training_target": "azme_system_understanding"
                }
                training_data["combined_samples"].append(sample)
        
        # Update statistics
        training_data["statistics"]["total_samples"] = len(training_data["combined_samples"])
        training_data["statistics"]["total_lines"] = sum(s["analysis"]["lines"] for s in training_data["combined_samples"])
        training_data["statistics"]["total_characters"] = sum(s["analysis"]["characters"] for s in training_data["combined_samples"])
        
        return training_data
    
    def save_training_dataset(self, training_data: Dict[str, Any]):
        """Save the training dataset in multiple formats"""
        
        # Save full dataset
        full_dataset_path = os.path.join(self.output_dir, "azl_azme_full_dataset.json")
        with open(full_dataset_path, 'w', encoding='utf-8') as f:
            json.dump(training_data, f, indent=2, ensure_ascii=False)
        
        # Save AZL-only samples
        azl_dataset_path = os.path.join(self.output_dir, "azl_only_dataset.json")
        with open(azl_dataset_path, 'w', encoding='utf-8') as f:
            json.dump(training_data["azl_samples"], f, indent=2, ensure_ascii=False)
        
        # Save AZME-only samples
        azme_dataset_path = os.path.join(self.output_dir, "azme_only_dataset.json")
        with open(azme_dataset_path, 'w', encoding='utf-8') as f:
            json.dump(training_data["azme_samples"], f, indent=2, ensure_ascii=False)
        
        # Save text-only version for simple training
        text_samples = []
        for sample in training_data["combined_samples"]:
            text_samples.append({
                "text": sample["content"],
                "type": sample["type"],
                "source": sample["source"]
            })
        
        text_dataset_path = os.path.join(self.output_dir, "azl_azme_text_dataset.json")
        with open(text_dataset_path, 'w', encoding='utf-8') as f:
            json.dump(text_samples, f, indent=2, ensure_ascii=False)
        
        # Save statistics
        stats_path = os.path.join(self.output_dir, "dataset_statistics.json")
        with open(stats_path, 'w', encoding='utf-8') as f:
            json.dump(training_data["statistics"], f, indent=2, ensure_ascii=False)
        
        print(f"💾 Saved datasets to {self.output_dir}:")
        print(f"  • Full dataset: {full_dataset_path}")
        print(f"  • AZL only: {azl_dataset_path}")
        print(f"  • AZME only: {azme_dataset_path}")
        print(f"  • Text only: {text_dataset_path}")
        print(f"  • Statistics: {stats_path}")
    
    def create_simple_training_file(self, training_data: Dict[str, Any]):
        """Create a simple text file for immediate training"""
        simple_file_path = os.path.join(self.output_dir, "azl_azme_training_data.txt")
        
        with open(simple_file_path, 'w', encoding='utf-8') as f:
            f.write("# AZL/AZME Training Dataset\n")
            f.write("# Generated for language model training\n\n")
            
            for i, sample in enumerate(training_data["combined_samples"], 1):
                f.write(f"=== SAMPLE {i} ===\n")
                f.write(f"Type: {sample['type']}\n")
                f.write(f"Source: {sample['source']}\n")
                f.write(f"Lines: {sample['analysis']['lines']}\n")
                f.write(f"Complexity: {sample['analysis']['complexity_score']}\n")
                f.write("-" * 50 + "\n")
                f.write(sample['content'])
                f.write("\n\n" + "=" * 80 + "\n\n")
        
        print(f"📝 Created simple training file: {simple_file_path}")
        return simple_file_path
    
    def generate_training_report(self, training_data: Dict[str, Any]):
        """Generate a comprehensive training report"""
        report_path = os.path.join(self.output_dir, "TRAINING_REPORT.md")
        
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write("# AZL/AZME Training Dataset Report\n\n")
            
            f.write("## 📊 Dataset Statistics\n\n")
            stats = training_data["statistics"]
            f.write(f"- **Total AZL files**: {stats['total_azl_files']}\n")
            f.write(f"- **Total AZME files**: {stats['total_azme_files']}\n")
            f.write(f"- **Total samples**: {stats['total_samples']}\n")
            f.write(f"- **Total lines**: {stats['total_lines']:,}\n")
            f.write(f"- **Total characters**: {stats['total_characters']:,}\n\n")
            
            f.write("## 🎯 Training Targets\n\n")
            f.write("### AZL Language Understanding\n")
            f.write("- Component definitions and behavior\n")
            f.write("- Function implementations\n")
            f.write("- Event system patterns\n")
            f.write("- Memory management\n")
            f.write("- Control flow structures\n\n")
            
            f.write("### AZME System Understanding\n")
            f.write("- Neural network architectures\n")
            f.write("- Cognitive processes\n")
            f.write("- Memory systems\n")
            f.write("- Learning algorithms\n")
            f.write("- Quantum computing integration\n\n")
            
            f.write("## 📁 Generated Files\n\n")
            f.write("The following files were created for training:\n\n")
            f.write("1. **azl_azme_full_dataset.json** - Complete dataset with analysis\n")
            f.write("2. **azl_only_dataset.json** - AZL code samples only\n")
            f.write("3. **azme_only_dataset.json** - AZME code samples only\n")
            f.write("4. **azl_azme_text_dataset.json** - Text-only version\n")
            f.write("5. **azl_azme_training_data.txt** - Simple text file\n")
            f.write("6. **dataset_statistics.json** - Statistical summary\n\n")
            
            f.write("## 🚀 Usage Instructions\n\n")
            f.write("### For Immediate Training:\n")
            f.write("```bash\n")
            f.write("# Use the simple text file\n")
            f.write("python3 master_training_launcher.py --action full\n")
            f.write("```\n\n")
            
            f.write("### For Advanced Training:\n")
            f.write("```python\n")
            f.write("from real_dataset_loader import RealDatasetLoader\n")
            f.write("loader = RealDatasetLoader()\n")
            f.write("texts = loader.load_dataset('datasets/azl_azme_training/azl_azme_text_dataset.json')\n")
            f.write("```\n\n")
            
            f.write("## 📈 Expected Training Outcomes\n\n")
            f.write("After training on this dataset, the model should:\n\n")
            f.write("1. **Understand AZL syntax** and patterns\n")
            f.write("2. **Generate valid AZL code** components\n")
            f.write("3. **Comprehend AZME systems** and architecture\n")
            f.write("4. **Assist in AZL/AZME development**\n")
            f.write("5. **Debug and optimize** existing code\n")
            f.write("6. **Generate new features** and components\n\n")
            
            f.write("## 🔄 Next Steps\n\n")
            f.write("1. **Start training** using the master launcher\n")
            f.write("2. **Monitor progress** and loss reduction\n")
            f.write("3. **Test generated code** for validity\n")
            f.write("4. **Iterate and improve** the training process\n")
            f.write("5. **Scale up** to larger models and datasets\n\n")
            
            f.write("---\n")
            f.write("*Generated automatically for AZL/AZME training system*\n")
        
        print(f"📋 Generated training report: {report_path}")
    
    def create_dataset(self):
        """Create the complete AZL/AZME training dataset"""
        print("🚀 AZL/AZME DATASET CREATOR")
        print("=" * 50)
        print("Creating training dataset from AZL and AZME code...")
        
        # Scan for files
        azl_files = self.scan_azl_files()
        azme_files = self.scan_azme_files()
        
        if not azl_files and not azme_files:
            print("❌ No AZL or AZME files found!")
            return False
        
        # Create training data
        training_data = self.create_training_samples(azl_files, azme_files)
        
        # Save datasets
        self.save_training_dataset(training_data)
        
        # Create simple training file
        simple_file = self.create_simple_training_file(training_data)
        
        # Generate report
        self.generate_training_report(training_data)
        
        # Print summary
        print("\n🎉 DATASET CREATION COMPLETE!")
        print("=" * 50)
        stats = training_data["statistics"]
        print(f"📊 Total samples: {stats['total_samples']}")
        print(f"📝 Total lines: {stats['total_lines']:,}")
        print(f"🔤 Total characters: {stats['total_characters']:,}")
        print(f"📁 Output directory: {self.output_dir}")
        
        print(f"\n🎯 Ready for training! Use:")
        print(f"  python3 master_training_launcher.py --action full")
        
        return True

def main():
    """Main function"""
    creator = AZLAZMEDatasetCreator()
    creator.create_dataset()

if __name__ == "__main__":
    main()
