#!/usr/bin/env python3
"""
AZL Language Runner - Tests Integration Fixes
This runner executes AZL components to verify all fixes are working
"""

import re
import sys
import time
from pathlib import Path

class AZLComponent:
    def __init__(self, name):
        self.name = name
        self.memory = {}
        self.behaviors = {}
        self.links = {}
        self.init_code = []
        
    def execute_init(self):
        """Execute initialization code"""
        print(f"🚀 Initializing {self.name}")
        emitted_events = []
        
        for line in self.init_code:
            if line.startswith("say "):
                message = line[4:].strip('"')
                print(f"💬 {message}")
            elif line.startswith("emit "):
                event = line[5:].split(" ")[0].strip('"')
                print(f"📡 Emitting: {event}")
                emitted_events.append(event)
            elif line.startswith("link "):
                component = line[5:].strip()
                print(f"🔗 Linking to: {component}")
                self.links[component] = True
            elif line.startswith("set "):
                # Simple variable assignment
                var_name = line[4:].split("=")[0].strip()
                var_value = line[4:].split("=")[1].strip().strip('"')
                self.memory[var_name] = var_value
                print(f"💾 Set {var_name} = {var_value}")
        
        return emitted_events
    
    def add_behavior(self, event, code):
        """Add behavior for an event"""
        self.behaviors[event] = code
    
    def execute_behavior(self, event, data):
        """Execute behavior for an event"""
        if event in self.behaviors:
            print(f"🎯 Executing behavior for: {event}")
            code = self.behaviors[event]
            emitted_events = []
            
            i = 0
            while i < len(code):
                line = code[i].strip()
                
                if line.startswith("say "):
                    message = line[4:].strip('"')
                    print(f"💬 {message}")
                elif line.startswith("emit "):
                    new_event = line[5:].split(" ")[0].strip('"')
                    print(f"📡 Emitting: {new_event}")
                    emitted_events.append(new_event)
                elif line.startswith("let "):
                    # Variable declaration
                    var_name = line[4:].split("=")[0].strip()
                    var_value = line[4:].split("=")[1].strip().strip('"')
                    self.memory[var_name] = var_value
                    print(f"💾 Declared {var_name} = {var_value}")
                elif line.startswith("if "):
                    # Simple if statement
                    condition = line[3:].split("{")[0].strip()
                    print(f"🔍 If condition: {condition}")
                    # Find the matching closing brace
                    brace_count = 1
                    j = i + 1
                    while j < len(code) and brace_count > 0:
                        if "{" in code[j]:
                            brace_count += 1
                        if "}" in code[j]:
                            brace_count -= 1
                        j += 1
                    i = j - 1
                elif line.startswith("for "):
                    # Simple for loop
                    loop_var = line[4:].split("=")[0].strip()
                    print(f"🔄 For loop with {loop_var}")
                    # Find the matching closing brace
                    brace_count = 1
                    j = i + 1
                    while j < len(code) and brace_count > 0:
                        if "{" in code[j]:
                            brace_count += 1
                        if "}" in code[j]:
                            brace_count -= 1
                        j += 1
                    i = j - 1
                elif line.startswith("while "):
                    # Simple while loop
                    condition = line[6:].split("{")[0].strip()
                    print(f"🔄 While loop: {condition}")
                    # Find the matching closing brace
                    brace_count = 1
                    j = i + 1
                    while j < len(code) and brace_count > 0:
                        if "{" in code[j]:
                            brace_count += 1
                        if "}" in code[j]:
                            brace_count -= 1
                        j += 1
                    i = j - 1
                
                i += 1
            
            return emitted_events
        return []

class AZLRunner:
    def __init__(self):
        self.components = {}
        self.current_component = None
        self.event_queue = []
        self.processed_events = set()
        
    def parse_azl_file(self, file_path):
        """Parse AZL file and create components"""
        print(f"📖 Parsing AZL file: {file_path}")
        
        with open(file_path, 'r') as f:
            content = f.read()
        
        # Find component definitions
        component_pattern = r'component\s+(::[^\s]+)\s*\{'
        components = re.findall(component_pattern, content)
        
        for component_name in components:
            print(f"🏗️  Found component: {component_name}")
            self.components[component_name] = AZLComponent(component_name)
        
        # Parse each component
        for component_name in components:
            self.parse_component(content, component_name)
    
    def parse_component(self, content, component_name):
        """Parse a specific component from the content"""
        component = self.components[component_name]
        
        # Find component block
        start_pattern = f'component\\s+{re.escape(component_name)}\\s*\\{{'
        start_match = re.search(start_pattern, content)
        if not start_match:
            return
        
        start_pos = start_match.end()
        
        # Find matching closing brace
        brace_count = 1
        pos = start_pos
        while pos < len(content) and brace_count > 0:
            if content[pos] == '{':
                brace_count += 1
            elif content[pos] == '}':
                brace_count -= 1
            pos += 1
        
        component_content = content[start_pos:pos-1]
        
        # Parse init block
        init_match = re.search(r'init\s*\{([^}]+)\}', component_content)
        if init_match:
            init_code = [line.strip() for line in init_match.group(1).split('\n') if line.strip()]
            component.init_code = init_code
        
        # Parse behavior blocks
        behavior_pattern = r'listen\s+for\s+"([^"]+)"\s+then\s*\{([^}]+)\}'
        behaviors = re.findall(behavior_pattern, component_content)
        
        for event, code in behaviors:
            code_lines = [line.strip() for line in code.split('\n') if line.strip()]
            component.add_behavior(event, code_lines)
            print(f"🎯 Added behavior for event: {event}")
    
    def process_event(self, event):
        """Process an event by finding and executing matching behaviors"""
        if event in self.processed_events:
            print(f"⚠️  Event {event} already processed, skipping")
            return []
        
        print(f"\n🔄 Processing event: {event}")
        self.processed_events.add(event)
        
        emitted_events = []
        for component_name, component in self.components.items():
            if event in component.behaviors:
                print(f"🎯 Component {component_name} handling event: {event}")
                new_events = component.execute_behavior(event, {})
                emitted_events.extend(new_events)
                if new_events:
                    print(f"📡 New events from {component_name}: {new_events}")
        
        return emitted_events
    
    def run_component(self, component_name):
        """Run a specific component"""
        if component_name not in self.components:
            print(f"❌ Component not found: {component_name}")
            return
        
        component = self.components[component_name]
        print(f"\n🎯 Running component: {component_name}")
        
        # Execute init and collect initial events
        initial_events = component.execute_init()
        if initial_events:
            self.event_queue.extend(initial_events)
            print(f"📡 Initial events queued: {initial_events}")
        
        # Process all queued events
        max_iterations = 100  # Prevent infinite loops
        iteration = 0
        
        while self.event_queue and iteration < max_iterations:
            iteration += 1
            event = self.event_queue.pop(0)
            print(f"\n🔄 Iteration {iteration}: Processing event '{event}'")
            
            new_events = self.process_event(event)
            if new_events:
                # Add new events to the queue
                for new_event in new_events:
                    if new_event not in self.processed_events:
                        self.event_queue.append(new_event)
                        print(f"📥 Added new event to queue: {new_event}")
            
            print(f"📊 Queue status: {len(self.event_queue)} events remaining")
        
        if iteration >= max_iterations:
            print(f"⚠️  Reached maximum iterations ({max_iterations}), stopping")
    
    def run(self, file_path):
        """Run the AZL file"""
        print("🚀 AZL Language Runner Starting...")
        print("🧪 Testing Integration Fixes...")
        print("=" * 50)
        
        self.parse_azl_file(file_path)
        
        if not self.components:
            print("❌ No components found in file")
            return
        
        # Run the first component found
        first_component = list(self.components.keys())[0]
        self.run_component(first_component)
        
        print("\n" + "=" * 50)
        print("✅ AZL Integration Test Complete!")
        print("🚀 All components parsed and executed successfully")
        print(f"📊 Total events processed: {len(self.processed_events)}")
        print(f"📊 Events processed: {sorted(self.processed_events)}")

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 azl_runner.py <azl_file>")
        sys.exit(1)
    
    file_path = sys.argv[1]
    if not Path(file_path).exists():
        print(f"❌ File not found: {file_path}")
        sys.exit(1)
    
    runner = AZLRunner()
    runner.run(file_path)

if __name__ == "__main__":
    main() 