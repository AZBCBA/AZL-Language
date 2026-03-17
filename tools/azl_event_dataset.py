#!/usr/bin/env python3
"""
AZL Event Dataset Creator

Creates training data for event prediction by extracting real AZL event names
from the codebase and creating simple prefix completion examples.
"""

import json
import os
import re
from pathlib import Path
from typing import List, Dict, Tuple


def extract_events_from_text(text: str) -> Tuple[List[str], Dict[str, int]]:
    """Extract event names from AZL code text."""
    events: set[str] = set()
    freq: Dict[str, int] = {}
    
    # Extract listen for events - look for clean event names
    for m in re.finditer(r'listen\s+for\s+"([a-zA-Z0-9._-]+)"', text):
        evt = m.group(1).strip()
        if evt and len(evt) > 2 and len(evt) < 50:  # Filter length and alphanumeric only
            events.add(evt)
            freq[evt] = freq.get(evt, 0) + 1
    
    # Extract emit events - look for clean event names
    for m in re.finditer(r'emit\s+"([a-zA-Z0-9._-]+)"', text):
        evt = m.group(1).strip()
        if evt and len(evt) > 2 and len(evt) < 50:  # Filter length and alphanumeric only
            events.add(evt)
            freq[evt] = freq.get(evt, 0) + 1
    
    # Extract wait for events - look for clean event names
    for m in re.finditer(r'wait\s+for\s+"([a-zA-Z0-9._-]+)"', text):
        evt = m.group(1).strip()
        if evt and len(evt) > 2 and len(evt) < 50:  # Filter length and alphanumeric only
            events.add(evt)
            freq[evt] = freq.get(evt, 0) + 1
    
    return sorted(events), freq


def create_simple_event_examples(events: List[str], freq: Dict[str, int], max_examples: int = 1000) -> List[Dict]:
    """Create simple event prediction examples with prefix completion."""
    examples = []
    
    for event in events:
        if len(examples) >= max_examples:
            break
        
        # Create examples with different prefix lengths
        for prefix_len in [3, 5, 8, 12]:
            if len(event) > prefix_len:
                prefix = event[:prefix_len]
                target = event
                
                examples.append({
                    "prompt": prefix,
                    "target": target,
                    "frequency": freq.get(event, 1),
                    "prefix_len": prefix_len
                })
        
        # Also create examples with common prefixes
        if '.' in event:
            parts = event.split('.')
            if len(parts) >= 2:
                # First part as prefix
                prefix = parts[0]
                target = event
                examples.append({
                    "prompt": prefix,
                    "target": target,
                    "frequency": freq.get(event, 1),
                    "prefix_len": len(prefix)
                })
                
                # First two parts as prefix
                if len(parts) >= 3:
                    prefix = '.'.join(parts[:2])
                    target = event
                    examples.append({
                        "prompt": prefix,
                        "target": target,
                        "frequency": freq.get(event, 1),
                        "prefix_len": len(prefix)
                    })
    
    return examples


def main():
    """Main function to create event dataset."""
    print("🔍 Creating AZL Event Dataset...")
    
    # Scan AZL codebase for events
    azl_dirs = ["azl", "azme"]
    all_text = ""
    
    for dir_name in azl_dirs:
        if os.path.exists(dir_name):
            print(f"📁 Scanning {dir_name}/ directory...")
            for root, dirs, files in os.walk(dir_name):
                for file in files:
                    if file.endswith('.azl'):
                        file_path = os.path.join(root, file)
                        try:
                            with open(file_path, 'r', encoding='utf-8') as f:
                                all_text += f.read() + "\n"
                        except Exception as e:
                            print(f"⚠️ Could not read {file_path}: {e}")
    
    print(f"📝 Total text length: {len(all_text):,} characters")
    
    # Extract events
    events, freq = extract_events_from_text(all_text)
    print(f"🎯 Found {len(events)} unique events")
    
    # Show top events by frequency
    top_events = sorted(freq.items(), key=lambda x: x[1], reverse=True)[:20]
    print("\n🏆 Top 20 events by frequency:")
    for event, count in top_events:
        print(f"  {event}: {count}")
    
    # Create training examples
    examples = create_simple_event_examples(events, freq, max_examples=1000)
    print(f"\n📊 Created {len(examples)} training examples")
    
    # Save to file
    output_file = "tools/event_eval.jsonl"
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    
    with open(output_file, 'w', encoding='utf-8') as f:
        for example in examples:
            f.write(json.dumps(example) + '\n')
    
    print(f"✅ Event dataset saved to {output_file}")
    
    # Show some examples
    print("\n📋 Sample examples:")
    for i, example in enumerate(examples[:5]):
        print(f"  {i+1}. Prompt: '{example['prompt']}'")
        print(f"     Target: '{example['target']}'")
        print(f"     Prefix length: {example['prefix_len']}")
        print(f"     Frequency: {example['frequency']}")
        print()


if __name__ == "__main__":
    main()


