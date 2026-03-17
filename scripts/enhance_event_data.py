import json
import os
import re

# Core transition rules (should match AZL const EVENT_TRANSITIONS)
TRANSITION_RULES = {
    "azme.agent_message": ["azme.validate_agent"],
    "azme.validate_agent": ["azme.agent_validation_complete"],
    "azme.agent_validation_complete": ["azme.route_to_processor", "azme.agent_violation_detected"],
    "azme.route_to_processor": ["azme.process_agent_message"],
    "azme.process_agent_message": ["azme.message_processed"],
    "azme.agent.registered": ["azme.registration_complete"],
    "azme.task_shared": ["azme.task_sharing_complete"],
    "azme.memory_shared": ["azme.memory_sharing_complete"],
}

def extract_events_from_azl_code(content):
    """Extract emit statements and event patterns from AZL code"""
    events = []
    
    # Find emit statements
    emit_pattern = r'emit\s+([a-zA-Z_][a-zA-Z0-9_.]*)'
    emits = re.findall(emit_pattern, content)
    events.extend(emits)
    
    # Find listen for statements
    listen_pattern = r'listen\s+for\s+"([^"]+)"'
    listens = re.findall(listen_pattern, content)
    events.extend(listens)
    
    # Find on event handlers
    on_pattern = r'on\s+([a-zA-Z_][a-zA-Z0-9_.]*)'
    ons = re.findall(on_pattern, content)
    events.extend(ons)
    
    return list(set(events))  # Remove duplicates

def create_event_sequences_from_code(content):
    """Create event sequences based on code flow analysis"""
    sequences = []
    events = extract_events_from_azl_code(content)
    
    # Create training pairs from sequential events
    for i in range(len(events) - 1):
        current = events[i]
        next_event = events[i + 1]
        
        # Add semantic metadata
        sequence = {
            "input": current,
            "target": next_event,
            "semantic": {
                "input_module": current.split(".")[0] if "." in current else "unknown",
                "input_category": current.split(".")[1] if "." in current and len(current.split(".")) > 1 else "unknown",
                "input_action": current.split(".")[-1] if "." in current else current,
                "target_module": next_event.split(".")[0] if "." in next_event else "unknown",
                "target_category": next_event.split(".")[1] if "." in next_event and len(next_event.split(".")) > 1 else "unknown",
                "target_action": next_event.split(".")[-1] if "." in next_event else next_event
            },
            "valid_transitions": TRANSITION_RULES.get(current, []),
            "is_valid": next_event in TRANSITION_RULES.get(current, [next_event])
        }
        sequences.append(sequence)
    
    return sequences

def enhance_training_data(input_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    
    for filename in os.listdir(input_dir):
        if filename.endswith(".json"):
            input_path = os.path.join(input_dir, filename)
            output_path = os.path.join(output_dir, f"enhanced_{filename}")
            
            with open(input_path, "r") as f:
                data = json.load(f)
            
            enhanced_data = {
                "metadata": {
                    "original_file": filename,
                    "enhancement_version": "1.0",
                    "total_samples": 0,
                    "event_sequences": 0
                },
                "event_training_data": []
            }
            
            # Handle different data structures
            if isinstance(data, dict):
                # Process AZL samples and extract event sequences
                if "azl_samples" in data:
                    for sample in data["azl_samples"]:
                        if "content" in sample:
                            sequences = create_event_sequences_from_code(sample["content"])
                            for seq in sequences:
                                seq["source_file"] = sample.get("file_path", "unknown")
                                enhanced_data["event_training_data"].append(seq)
                
                # Process AZME samples
                if "azme_samples" in data:
                    for sample in data["azme_samples"]:
                        if "content" in sample:
                            sequences = create_event_sequences_from_code(sample["content"])
                            for seq in sequences:
                                seq["source_file"] = sample.get("file_path", "unknown")
                                enhanced_data["event_training_data"].append(seq)
                
                enhanced_data["metadata"]["total_samples"] = len(data.get("azl_samples", [])) + len(data.get("azme_samples", []))
            elif isinstance(data, list):
                # Handle list format - assume it's a list of samples with content
                for sample in data:
                    if isinstance(sample, dict) and "content" in sample:
                        sequences = create_event_sequences_from_code(sample["content"])
                        for seq in sequences:
                            seq["source_file"] = sample.get("file_path", "unknown")
                            enhanced_data["event_training_data"].append(seq)
                
                enhanced_data["metadata"]["total_samples"] = len(data)
            
            enhanced_data["metadata"]["event_sequences"] = len(enhanced_data["event_training_data"])
            
            with open(output_path, "w") as f:
                json.dump(enhanced_data, f, indent=2)
            
            print(f"Enhanced {filename}: {enhanced_data['metadata']['event_sequences']} event sequences generated")

if __name__ == "__main__":
    enhance_training_data("datasets/azl_azme_training", "datasets/azl_azme_training_enhanced")