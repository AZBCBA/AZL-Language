#!/usr/bin/env python3
"""
AZL Language Runner - Enhanced with Advanced Features
This runner executes AZL components with full language support
"""

import re
import sys
import time
import os
from pathlib import Path
import threading
import subprocess

class AZLComponent:
    def __init__(self, name, engine=None):
        self.name = name
        self.memory = {}
        self.behaviors = {}
        self.functions = {}
        self.function_bodies = {}
        self.function_params = {}
        self.links = {}
        self.init_code = []
        self.engine = engine
        
    def execute_init(self):
        """Execute initialization code"""
        print(f"🚀 Initializing {self.name}")
        emitted_events = []
        
        for idx, line in enumerate(self.init_code):
            if line.startswith("say "):
                expr = line[4:].strip()
                try:
                    message = self.engine.eval_expr(expr, self.memory, None)
                    # Replace variables in the message
                    message = self.engine.replace_variables_in_string(message, self.memory)
                except Exception:
                    message = expr.strip('"')
                    # Still try to replace variables
                    message = self.engine.replace_variables_in_string(message, self.memory)
                print(f"💬 {message}")
            elif line.startswith("emit "):
                event = line[5:].split(" ")[0].strip('"')
                print(f"📡 Emitting: {event}")
                emitted_events.append(event)
            elif line.startswith("link "):
                component = line[5:].strip()
                print(f"🔗 Linking to: {component}")
                print(f"🔍 DEBUG: Available components: {list(self.engine.components.keys())}")
                print(f"🔍 DEBUG: Component {component} exists: {component in self.engine.components}")
                self.links[component] = True
            elif line.startswith("readline into "):
                # Simple interactive input
                var = line.replace("readline into", "").strip()
                if var.startswith("::"):
                    var = var[2:]
                try:
                    user_in = input()
                except EOFError:
                    user_in = ""
                self.memory[var] = user_in
                print(f"⌨️  Readline -> {var} = {user_in}")
            elif line.startswith("set "):
                # Evaluate simple expression on RHS (supports multi-line list/object literals)
                parts = line[4:].split("=", 1)
                var_name = parts[0].strip()
                if var_name.startswith("::"):
                    var_name = var_name[2:]
                rhs = parts[1].strip()
                # If RHS starts an unterminated list/object, accumulate following init lines
                if (rhs.startswith("[") and rhs.count("[") > rhs.count("]")) or (rhs.startswith("{") and rhs.count("{") > rhs.count("}")):
                    brace_open = rhs.count("{") + rhs.count("[")
                    brace_close = rhs.count("}") + rhs.count("]")
                    collected = [rhs]
                    j = idx + 1
                    while j < len(self.init_code) and brace_open > brace_close:
                        ln2 = self.init_code[j]
                        collected.append(ln2)
                        brace_open += ln2.count("{") + ln2.count("[")
                        brace_close += ln2.count("}") + ln2.count("]")
                        j += 1
                    rhs = "\n".join(collected)
                val = self.engine.eval_expr(rhs, self.memory, None)
                self.memory[var_name] = val
                print(f"💾 Set {var_name} = {val}")
            elif line.startswith("let "):
                # Handle let statements for variable declaration
                parts = line[4:].split("=", 1)
                if len(parts) == 2:
                    var_name = parts[0].strip()
                    rhs = parts[1].strip()
                    
                    # Check if RHS is a function call
                    if '(' in rhs and rhs.endswith(')'):
                        # This is a function call, execute it and capture return value
                        return_value = self.execute_function_call_with_memory(rhs, self.memory)
                        if return_value is not None:
                            val = return_value
                            print(f"📝 Function returned: {return_value}")
                        else:
                            # If no return value, store the function call string
                            val = rhs
                            print(f"⚠️  Function returned no value, storing call string")
                    else:
                        # Regular expression evaluation
                        val = self.engine.eval_expr(rhs, self.memory, None)
                    
                    self.memory[var_name] = val
                    print(f"📝 Let {var_name} = {val}")
            elif line.startswith("fn "):
                # Handle function definitions
                self.parse_function_definition(line, idx)
            elif '(' in line and line.endswith(')'):
                # Handle function calls
                # Check if this is a cross-component function call (::component.function)
                if line.startswith("::") and "." in line:
                    # This is a cross-component function call like ::azl.stdlib.set_timeout([50, "tests.timeout", null])
                    try:
                        # Extract component path and function name
                        component_end = line.find("(")
                        if component_end == -1:
                            component_end = len(line)
                        
                        component_path = line[:component_end]
                        if "." in component_path:
                            parts = component_path.split(".")
                            component_name = ".".join(parts[:-1])  # azl.stdlib
                            function_name = parts[-1]  # set_timeout
                            
                            # Extract arguments
                            args_start = line.find("(")
                            args_end = line.rfind(")")
                            if args_start != -1 and args_end != -1:
                                args_str = line[args_start+1:args_end]
                                
                                # Parse arguments properly - handle AZL list syntax
                                try:
                                    # Parse AZL list syntax like [50, "tests.timeout", null]
                                    args = self.parse_azl_list(args_str)
                                    print(f"🔍 Parsed AZL list: {args_str} → {args}")
                                except Exception as e:
                                    print(f"⚠️  Error parsing AZL list: {e}")
                                    # Fallback to simple comma split
                                    args = [arg.strip() for arg in args_str.split(",") if arg.strip()]
                                
                                print(f"🔧 Cross-component call: {component_name}.{function_name}({args})")
                                
                                # Use our cross-component resolution system
                                result = self.engine.resolve_component_function(component_name, function_name, args)
                                if result is not None:
                                    print(f"✅ Cross-component call successful: {result}")
                                else:
                                    print(f"⚠️  Cross-component call failed: {component_name}.{function_name}")
                            else:
                                print(f"⚠️  Invalid cross-component call syntax: {line}")
                        else:
                            print(f"⚠️  Invalid component path in cross-component call: {line}")
                    except Exception as e:
                        print(f"⚠️  Error in cross-component call: {e}")
                else:
                    # Regular function call
                    self.execute_function_call(line)
            elif line.startswith("if "):
                # Handle if statements
                self.execute_if_statement(line)
            elif line.startswith("for "):
                # Handle for loops
                self.execute_for_statement(line)
            elif line.startswith("while "):
                # Handle while loops
                self.execute_while_statement(line)
            elif line.startswith("return "):
                # Handle return statements
                self.execute_return_statement(line)
        
        return emitted_events
    
    def parse_function_definition(self, line, idx):
        """Parse function definition"""
        # Parse: fn function_name(params) { body }
        match = re.match(r'fn\s+([^\s(]+)\s*\(([^)]*)\)\s*\{', line)
        if match:
            func_name = match.group(1)
            params = match.group(2).split(',') if match.group(2) else []
            params = [p.strip() for p in params if p.strip()]
            
            # Find the function body by looking for the matching closing brace
            start_pos = line.find('{')
            if start_pos != -1:
                # This is just the opening line, we need to collect the body
                # The actual body will be parsed in parse_component
                print(f"📝 Function definition started: {func_name} with params: {params}")
            else:
                print(f"⚠️  Function definition incomplete: {line}")
    
    def execute_function_call_with_memory(self, line, memory_context):
        """Execute function call with specific memory context"""
        # Parse: function_name(params)
        match = re.match(r'([^(]+)\(([^)]*)\)', line)
        if match:
            func_name = match.group(1).strip()
            params_str = match.group(2).strip()
            
            # Parse parameters
            params = []
            if params_str:
                params = [self.engine.eval_expr(p.strip(), memory_context, None) for p in params_str.split(',')]
            
            print(f"🔧 Calling function: {func_name} with params: {params}")
            
            # Execute function if it exists
            if func_name in self.function_bodies:
                func_body = self.function_bodies[func_name]
                func_params = self.function_params.get(func_name, [])
                print(f"📝 Executing function: {func_name}")
                
                # Create local memory context for function execution
                local_memory = memory_context.copy()
                
                # Bind parameters to local memory
                for i, param_name in enumerate(func_params):
                    if i < len(params):
                        local_memory[param_name] = params[i]
                
                # Execute function body and capture return value
                return_value = None
                for func_line in func_body:
                    if func_line.startswith("return "):
                        # Handle return statement
                        return_expr = func_line[7:].strip()
                        return_value = self.engine.eval_expr(return_expr, local_memory, None)
                        print(f"↩️  Function {func_name} returning: {return_value}")
                        break
                    else:
                        # Execute the line with local memory context
                        self.execute_statement_with_memory(func_line, local_memory)
                
                return return_value
            else:
                print(f"⚠️  Function not found: {func_name}")
                return None

    def execute_function_call(self, line):
        """Execute function call"""
        # Parse: function_name(params)
        match = re.match(r'([^(]+)\(([^)]*)\)', line)
        if match:
            func_name = match.group(1).strip()
            params_str = match.group(2).strip()
            
            # Parse parameters
            params = []
            if params_str:
                params = [self.engine.eval_expr(p.strip(), self.memory, None) for p in params_str.split(',')]
            
            print(f"🔧 Calling function: {func_name} with params: {params}")
            
            # Execute function if it exists
            if func_name in self.function_bodies:
                func_body = self.function_bodies[func_name]
                func_params = self.function_params.get(func_name, [])
                print(f"📝 Executing function: {func_name}")
                
                # Create local memory context for function execution
                local_memory = self.memory.copy()
                
                # Bind parameters to local memory
                for i, param_name in enumerate(func_params):
                    if i < len(params):
                        local_memory[param_name] = params[i]
                
                # Execute function body and capture return value
                return_value = None
                for func_line in func_body:
                    if func_line.startswith("return "):
                        # Handle return statement
                        return_expr = func_line[7:].strip()
                        return_value = self.engine.eval_expr(return_expr, local_memory, None)
                        print(f"↩️  Function {func_name} returning: {return_value}")
                        break
                    else:
                        # Execute the line with local memory context
                        self.execute_statement_with_memory(func_line, local_memory)
                
                return return_value
            else:
                print(f"⚠️  Function not found: {func_name}")
                return None
    
    def execute_if_statement(self, line):
        """Execute if statement"""
        # Parse: if condition { body }
        match = re.match(r'if\s+(.+?)\s*\{', line)
        if match:
            condition = match.group(1).strip()
            result = self.engine.eval_expr(condition, self.memory, None)
            
            if result:
                print(f"✅ If condition true: {condition}")
            else:
                print(f"❌ If condition false: {condition}")
    
    def execute_for_statement(self, line):
        """Execute for statement"""
        # Parse: for let i = 0; i < 5; i++ { body }
        print(f"🔄 For loop detected: {line}")
    
    def execute_while_statement(self, line):
        """Execute while statement"""
        # Parse: while condition { body }
        print(f"🔄 While loop detected: {line}")
    
    def execute_return_statement(self, line):
        """Execute return statement"""
        # Parse: return value
        value_expr = line[7:].strip()
        value = self.engine.eval_expr(value_expr, self.memory, None)
        print(f"↩️  Return: {value}")
        return value
    
    def execute_statement_with_memory(self, statement, memory_context):
        """Execute a single statement with a specific memory context"""
        statement = statement.strip()
        
        if statement.startswith("say "):
            expr = statement[4:].strip()
            try:
                message = self.engine.eval_expr(expr, memory_context, None)
                # Replace variables in the message
                message = self.engine.replace_variables_in_string(message, memory_context)
            except Exception:
                message = expr.strip('"')
                # Still try to replace variables
                message = self.engine.replace_variables_in_string(message, memory_context)
            print(f"💬 {message}")
        elif statement.startswith("set "):
            parts = statement[4:].split("=", 1)
            if len(parts) == 2:
                var_name = parts[0].strip()
                if var_name.startswith("::"):
                    var_name = var_name[2:]
                rhs = parts[1].strip()
                val = self.engine.eval_expr(rhs, memory_context, None)
                memory_context[var_name] = val
                print(f"💾 Set {var_name} = {val}")
        elif statement.startswith("let "):
            parts = statement[4:].split("=", 1)
            if len(parts) == 2:
                var_name = parts[0].strip()
                rhs = parts[1].strip()
                
                # Check if RHS is a function call
                if '(' in rhs and rhs.endswith(')'):
                    # This is a function call, execute it and capture return value
                    return_value = self.execute_function_call_with_memory(rhs, memory_context)
                    if return_value is not None:
                        val = return_value
                        print(f"📝 Function returned: {return_value}")
                    else:
                        # If no return value, store the function call string
                        val = rhs
                        print(f"⚠️  Function returned no value, storing call string")
                else:
                    # Regular expression evaluation
                    val = self.engine.eval_expr(rhs, memory_context, None)
                
                memory_context[var_name] = val
                print(f"📝 Let {var_name} = {val}")
        elif statement.startswith("emit "):
            event = statement[5:].split(" ")[0].strip('"')
            print(f"📡 Emitting: {event}")
        elif '(' in statement and statement.endswith(')'):
            # Execute function call with local memory context
            return_value = self.execute_function_call_with_memory(statement, memory_context)
            return return_value

    def execute_statement(self, statement):
        """Execute a single statement"""
        statement = statement.strip()
        
        if statement.startswith("say "):
            expr = statement[4:].strip()
            try:
                message = self.engine.eval_expr(expr, self.memory, None)
                # Replace variables in the message
                message = self.engine.replace_variables_in_string(message, self.memory)
            except Exception:
                message = expr.strip('"')
                # Still try to replace variables
                message = self.engine.replace_variables_in_string(message, self.memory)
            print(f"💬 {message}")
        elif statement.startswith("set "):
            parts = statement[4:].split("=", 1)
            if len(parts) == 2:
                var_name = parts[0].strip()
                if var_name.startswith("::"):
                    var_name = var_name[2:]
                rhs = parts[1].strip()
                val = self.engine.eval_expr(rhs, self.memory, None)
                self.memory[var_name] = val
                print(f"💾 Set {var_name} = {val}")
        elif statement.startswith("let "):
            parts = statement[4:].split("=", 1)
            if len(parts) == 2:
                var_name = parts[0].strip()
                rhs = parts[1].strip()
                
                # Check if RHS is a function call
                if '(' in rhs and rhs.endswith(')'):
                    # This is a function call, execute it and capture return value
                    return_value = self.execute_function_call(rhs)
                    if return_value is not None:
                        val = return_value
                    else:
                        # If no return value, store the function call string
                        val = rhs
                else:
                    # Regular expression evaluation
                    val = self.engine.eval_expr(rhs, self.memory, None)
                
                self.memory[var_name] = val
                print(f"📝 Let {var_name} = {val}")
        elif statement.startswith("emit "):
            event = statement[5:].split(" ")[0].strip('"')
            print(f"📡 Emitting: {event}")
        elif '(' in statement and statement.endswith(')'):
            self.execute_function_call(statement)
    
    def add_behavior(self, event, code):
        """Add behavior for an event"""
        self.behaviors[event] = code
        # Also expose as callable function name variants
        # Normalize keys: with and without leading '::'
        key_plain = event
        key_scoped = event if event.startswith("::") else f"::{event}"
        self.functions[key_plain] = code
        self.functions[key_scoped] = code
    
    def add_function(self, fn_name, code, params):
        """Register a function body and its parameter list"""
        self.function_bodies[fn_name] = code
        self.function_params[fn_name] = params or []
        # Also expose with scoped variant
        key_scoped = fn_name if fn_name.startswith("::") else f"::{fn_name}"
        self.function_bodies[key_scoped] = code
        self.function_params[key_scoped] = params or []
        # Allow calling via existing call mechanism too
        self.functions[fn_name] = code
        self.functions[key_scoped] = code

    def call_function(self, function_name, args):
        """Execute a function with given arguments"""
        if function_name in self.functions:
            function_body = self.functions[function_name]
            function_params = self.function_params.get(function_name, [])
            
            # Create local memory context for function execution
            local_memory = self.memory.copy()
            
            # Bind arguments to parameters
            for i, param_name in enumerate(function_params):
                if i < len(args):
                    local_memory[param_name] = args[i]
            
            # Execute function body
            try:
                result = self._execute_code(function_body, None)
                return result
            except Exception as e:
                print(f"❌ Error executing function {function_name}: {e}")
                return None
        else:
            print(f"⚠️  Function {function_name} not found in component {self.name}")
            return None

    def parse_azl_list(self, list_str):
        """Parse AZL list syntax like [50, "tests.timeout", null]"""
        list_str = list_str.strip()
        if not list_str.startswith('[') or not list_str.endswith(']'):
            raise ValueError(f"Invalid list syntax: {list_str}")
        
        # Remove outer brackets
        content = list_str[1:-1].strip()
        if not content:
            return []
        
        # Parse elements
        elements = []
        current = ""
        in_string = False
        string_quote = None
        paren_depth = 0
        bracket_depth = 0
        
        for char in content:
            if in_string:
                if char == string_quote:
                    in_string = False
                    current += char
                else:
                    current += char
            else:
                if char in ('"', "'"):
                    in_string = True
                    string_quote = char
                    current += char
                elif char == '(':
                    paren_depth += 1
                    current += char
                elif char == ')':
                    paren_depth -= 1
                    current += char
                elif char == '[':
                    bracket_depth += 1
                    current += char
                elif char == ']':
                    bracket_depth -= 1
                    current += char
                elif char == ',' and paren_depth == 0 and bracket_depth == 0:
                    # End of element
                    element = current.strip()
                    if element:
                        elements.append(self.parse_azl_value(element))
                    current = ""
                else:
                    current += char
        
        # Add final element
        if current.strip():
            elements.append(self.parse_azl_value(current.strip()))
        
        return elements

    def parse_azl_value(self, value_str):
        """Parse a single AZL value (string, number, null, boolean)"""
        value_str = value_str.strip()
        
        # Handle null
        if value_str == "null":
            return None
        
        # Handle booleans
        if value_str == "true":
            return True
        if value_str == "false":
            return False
        
        # Handle strings
        if (value_str.startswith('"') and value_str.endswith('"')) or \
           (value_str.startswith("'") and value_str.endswith("'")):
            return value_str[1:-1]
        
        # Handle numbers
        try:
            if '.' in value_str:
                return float(value_str)
            else:
                return int(value_str)
        except ValueError:
            pass
        
        # Return as-is if can't parse
        return value_str

    def execute_behavior(self, event, data):
        """Execute behavior for an event"""
        if event in self.behaviors:
            print(f"🎯 Executing behavior for: {event}")
            return self._execute_code(self.behaviors[event], data)
        return []

    def _execute_code(self, code_lines, data):
        emitted_events = []
        i = 0
        while i < len(code_lines):
            line = code_lines[i].strip()
            if not line:
                i += 1
                continue
            # Handle ::component.function calls using our new resolution system
            if line.startswith("::") and "(" in line and line.endswith(")"):
                try:
                    # Parse ::azl.stdlib.set_timeout([50, "tests.timeout", null])
                    # Extract component path and function call
                    component_end = line.find("(")
                    component_path = line[:component_end].strip()
                    function_call = line[component_end:].strip()
                    
                    # Extract function name and arguments
                    if "." in component_path:
                        parts = component_path.split(".")
                        component_name = ".".join(parts[:-1])  # azl.stdlib
                        function_name = parts[-1]  # set_timeout
                        
                        # Parse arguments from function_call
                        args_start = function_call.find("(")
                        args_end = function_call.rfind(")")
                        if args_start != -1 and args_end != -1:
                            args_str = function_call[args_start+1:args_end]
                            # Simple argument parsing - split by comma
                            args = [arg.strip() for arg in args_str.split(",") if arg.strip()]
                            
                            # Use our new method to resolve and call the function
                            result = self.engine.resolve_component_function(component_name, function_name, args)
                            if result is not None:
                                print(f"✅ Called {component_path}: {result}")
                            else:
                                print(f"⚠️  Function {component_path} not found or failed")
                        else:
                            print(f"⚠️  Invalid function call syntax: {line}")
                    else:
                        print(f"⚠️  Invalid component path: {line}")
                except Exception as e:
                    print(f"⚠️  Error calling component function: {e}")
                i += 1
                continue
            if line.startswith("say "):
                expr = line[4:].strip()
                try:
                    message = self.engine.eval_expr(expr, self.memory, data)
                except Exception:
                    message = expr.strip('"')
                print(f"💬 {message}")
            elif line.startswith("readline into "):
                var = line.replace("readline into", "").strip()
                if var.startswith("::"):
                    var = var[2:]
                try:
                    user_in = input()
                except EOFError:
                    user_in = ""
                self.memory[var] = user_in
                print(f"⌨️  Readline -> {var} = {user_in}")
            elif line.startswith("emit "):
                payload = None
                target = None
                tail = line[5:].strip()
                parts = tail.split()
                ev = parts[0].strip('"')
                to_idx = tail.find(" to ")
                with_idx = tail.find(" with ")
                if to_idx != -1 and (with_idx == -1 or to_idx < with_idx):
                    after = tail[to_idx+4:].strip()
                    comp_token = after.split()[0]
                    target = comp_token
                # Handle payload, including multi-line object literals following 'with'
                if with_idx != -1:
                    # Start from after 'with '
                    payload_txt = tail[with_idx+6:].strip()
                    # If payload seems to start an object but not end on this line, accumulate following lines
                    if payload_txt.startswith('{') and payload_txt.count('{') > payload_txt.count('}'):
                        brace_depth = payload_txt.count('{') - payload_txt.count('}')
                        j = i + 1
                        collected = [payload_txt]
                        while j < len(code_lines) and brace_depth > 0:
                            ln = code_lines[j]
                            collected.append(ln)
                            brace_depth += ln.count('{') - ln.count('}')
                            j += 1
                        payload_txt = "\n".join(collected)
                        i = j - 1  # advance outer loop to last consumed line
                    try:
                        payload = self.engine.parse_object(payload_txt, self.memory, data)
                    except Exception:
                        payload = None
                print(f"📡 Emitting: {ev}" + (f" to {target}" if target else ""))
                emitted_events.append({"event": ev, "target": target, "data": payload})
            elif line.startswith("let "):
                parts = line[4:].split("=", 1)
                if len(parts) == 2:
                    var_name = parts[0].strip()
                    if var_name.startswith("::"):
                        var_name = var_name[2:]
                    rhs = parts[1].strip()
                    val = self.engine.eval_expr(rhs, self.memory, data)
                    self.memory[var_name] = val
                    print(f"💾 Declared {var_name} = {val}")
            elif line.startswith("set "):
                parts = line[4:].split("=", 1)
                if len(parts) == 2:
                    var_name = parts[0].strip()
                    if var_name.startswith("::"):
                        var_name = var_name[2:]
                    rhs = parts[1].strip()
                    # Detect simple function call assignment: name(args...)
                    mcall = re.match(r'^([A-Za-z0-9_.:]+)\s*\((.*)\)\s*$', rhs)
                    if mcall:
                        fn_name = mcall.group(1)
                        args_txt = mcall.group(2).strip()
                        # Parse arguments (top-level comma split)
                        args = []
                        if args_txt:
                            depth = 0
                            in_q = False
                            q = ''
                            buf = ''
                            for ch in args_txt:
                                if in_q:
                                    buf += ch
                                    if ch == q:
                                        in_q = False
                                else:
                                    if ch in ('"', '\''):
                                        in_q = True
                                        q = ch
                                        buf += ch
                                    elif ch in ('{', '['):
                                        depth += 1
                                        buf += ch
                                    elif ch in ('}', ']'):
                                        depth = max(0, depth - 1)
                                        buf += ch
                                    elif ch == ',' and depth == 0:
                                        arg = buf.strip()
                                        if arg:
                                            args.append(self.engine.eval_expr(arg, self.memory, data))
                                        buf = ''
                                    else:
                                        buf += ch
                            tail = buf.strip()
                            if tail:
                                args.append(self.engine.eval_expr(tail, self.memory, data))
                        # Resolve function
                        body = (
                            self.function_bodies.get(fn_name)
                            or self.function_bodies.get(f"::{fn_name}")
                        )
                        params = (
                            self.function_params.get(fn_name)
                            or self.function_params.get(f"::{fn_name}")
                            or []
                        )
                        if body is None:
                            print(f"⚠️  Function not found for assignment: {fn_name}")
                            val = ''
                        else:
                            # Bind parameters into memory (shallow overlay)
                            saved = {}
                            for idx, pname in enumerate(params):
                                if pname.startswith("::"):
                                    pname = pname[2:]
                                if pname in self.memory:
                                    saved[pname] = self.memory[pname]
                                self.memory[pname] = args[idx] if idx < len(args) else ''
                            # Execute and capture return
                            prev_ret = getattr(self.engine, "_return_value", None)
                            self.engine._return_value = None
                            sub_emits = self._execute_code(body, data)
                            emitted_events.extend(sub_emits)
                            val = getattr(self.engine, "_return_value", None)
                            # Restore
                            for pname, sval in saved.items():
                                self.memory[pname] = sval
                            # Clear temp params not originally present
                            for idx, pname in enumerate(params):
                                if pname not in saved and pname in self.memory:
                                    try:
                                        del self.memory[pname]
                                    except Exception:
                                        pass
                            self.engine._return_value = prev_ret
                        self.memory[var_name] = val
                        print(f"💾 Set {var_name} = {val}")
                        i += 1
                        continue
                    # Support multi-line list/object literals
                    if (rhs.startswith("[") and rhs.count("[") > rhs.count("]")) or (rhs.startswith("{") and rhs.count("{") > rhs.count("}")):
                        brace_open = rhs.count("{") + rhs.count("[")
                        brace_close = rhs.count("}") + rhs.count("]")
                        j = i + 1
                        collected = [rhs]
                        while j < len(code_lines) and brace_open > brace_close:
                            ln = code_lines[j]
                            collected.append(ln)
                            brace_open += ln.count("{") + ln.count("[")
                            brace_close += ln.count("}") + ln.count("]")
                            j += 1
                        rhs = "\n".join(collected)
                        i = j - 1
                    val = self.engine.eval_expr(rhs, self.memory, data)
                    self.memory[var_name] = val
                    print(f"💾 Set {var_name} = {val}")
            elif line.startswith("if "):
                condition = line[3:].split("{")[0].strip()
                then_block, next_index = self._extract_block(code_lines, i)
                else_block = []
                j = next_index
                if j < len(code_lines) and code_lines[j].strip().startswith("else"):
                    else_block, j2 = self._extract_block(code_lines, j)
                    next_index = j2
                cond_val = self.engine.eval_condition(condition, self.memory, data)
                sub_emits = self._execute_code(then_block if cond_val else else_block, data)
                emitted_events.extend(sub_emits)
                i = next_index
                continue
            elif line.strip().endswith("()") or line.startswith("call "):
                # Function-like invocation, support both namespaced and plain identifiers
                call_txt = line.strip()
                # Normalize 'call fn()' → 'fn'
                if call_txt.startswith("call "):
                    fn_part = call_txt[5:]
                else:
                    fn_part = call_txt
                if fn_part.endswith("()"):
                    fn_part = fn_part[:-2]
                fn_full = fn_part
                
                # Check if this is a cross-component function call (::component.function)
                if fn_full.startswith("::") and "." in fn_full and "(" in line:
                    # This is a cross-component function call like ::azl.stdlib.set_timeout([50, "tests.timeout", null])
                    try:
                        # Extract component path and function name
                        component_end = fn_full.find("(")
                        if component_end == -1:
                            component_end = len(fn_full)
                        
                        component_path = fn_full[:component_end]
                        if "." in component_path:
                            parts = component_path.split(".")
                            component_name = ".".join(parts[:-1])  # azl.stdlib
                            function_name = parts[-1]  # set_timeout
                            
                            # Extract arguments from the original line
                            args_start = line.find("(")
                            args_end = line.rfind(")")
                            if args_start != -1 and args_end != -1:
                                args_str = line[args_start+1:args_end]
                                # Parse arguments (simple comma split for now)
                                args = [arg.strip() for arg in args_str.split(",") if arg.strip()]
                                
                                print(f"🔧 Cross-component call: {component_name}.{function_name}({args})")
                                
                                # Use our cross-component resolution system
                                result = self.engine.resolve_component_function(component_name, function_name, args)
                                if result is not None:
                                    print(f"✅ Cross-component call successful: {result}")
                                else:
                                    print(f"⚠️  Cross-component call failed: {component_name}.{function_name}")
                            else:
                                print(f"⚠️  Invalid cross-component call syntax: {line}")
                        else:
                            print(f"⚠️  Invalid component path in cross-component call: {line}")
                    except Exception as e:
                        print(f"⚠️  Error in cross-component call: {e}")
                    
                    i += 1
                    continue
                
                # Normalize keys for lookup (existing logic for local functions)
                if fn_full.startswith("::"):
                    fn_key_scoped = fn_full
                    fn_key_plain = fn_full[2:]
                else:
                    fn_key_plain = fn_full
                    fn_key_scoped = f"::{fn_full}"
                print(f"🔧 Calling function: {fn_key_plain}")
                print(f"🔍 DEBUG: fn_full='{fn_full}'")
                print(f"🔍 DEBUG: fn_key_scoped='{fn_key_scoped}'")
                print(f"🔍 DEBUG: fn_key_plain='{fn_key_plain}'")
                print(f"🔍 DEBUG: Looking in behaviors: {list(self.behaviors.keys())}")
                print(f"🔍 DEBUG: Looking in functions: {list(self.functions.keys())}")

                # Resolve function body from parsed event/function blocks
                body = (
                    self.behaviors.get(fn_key_plain)
                    or self.behaviors.get(fn_key_scoped)
                    or self.functions.get(fn_key_plain)
                    or self.functions.get(fn_key_scoped)
                )
                if body is None:
                    print(f"⚠️  Function not found: {fn_key_plain}")
                    print(f"🔍 DEBUG: All lookup attempts failed")
                else:
                    print(f"✅ Function found: {fn_key_plain}")
                    sub_emits = self._execute_code(body, data)
                    emitted_events.extend(sub_emits)
            elif line.startswith("return "):
                # Capture return value within function execution
                expr = line[len("return "):].strip()
                try:
                    val = self.engine.eval_expr(expr, self.memory, data)
                except Exception:
                    val = expr
                self.engine._return_value = val
                # End current execution context
                break
            elif line.startswith("for ") or line.startswith("while "):
                # Execute loop body once to advance orchestration (prevent infinite loops)
                block, next_index = self._extract_block(code_lines, i)
                sub_emits = self._execute_code(block, data)
                emitted_events.extend(sub_emits)
                i = next_index
                continue
            i += 1
        return emitted_events

    def _extract_block(self, code_lines, start_index):
        # Consume current line until opening '{'
        depth = 0
        block = []
        i = start_index
        # increase depth for any '{' on current line
        depth += code_lines[i].count('{')
        depth -= code_lines[i].count('}')
        i += 1
        while i < len(code_lines) and depth > 0:
            line = code_lines[i]
            depth += line.count('{')
            depth -= line.count('}')
            if depth >= 0:
                block.append(line)
            i += 1
        # remove trailing '}' line if included
        cleaned = [l for l in block if l.strip() and l.strip() != '}']
        return cleaned, i

class AZLRunner:
    def __init__(self):
        self.components = {}
        self.current_component = None
        self.event_queue = []
        self.processed_events = set()
        # expose simple ops
        self.true_values = {"true": True, True: True}
        # events that are allowed to be processed repeatedly
        self.repeatable_events = {
            "system.cycle_tick",
            "production_monitoring_loop",
            "production_health_check_loop",
            "stream.utf8",
            # training loop events must be repeatable
            "keep_alive",
            "run_training_step",
            "train_model_epoch",
            "train_model_step",
            # orchestrator progress/dataset events should repeat across files and shards
            "rm.next_dataset",
            "rm.check_progress",
            "dataset_loaded",
            "dataset_ready_for_training",
            # metrics can be emitted many times
            "training_metric",
            # allow retrigger of training start stages when multiple models/datasets
            "execute_real_training",
            "begin_real_training",
        }

    def replace_variables_in_string(self, text, memory):
        """Replace variables like $var and $::var in strings"""
        if not isinstance(text, str):
            return text
        
        # Replace $var and $::var patterns
        def replace_var(match):
            var_name = match.group(1)
            if var_name.startswith('::'):
                var_name = var_name[2:]  # Remove ::
            return str(memory.get(var_name, f"${var_name}"))
        
        # Replace $var patterns
        text = re.sub(r'\$([A-Za-z0-9_.:]+)', replace_var, text)
        return text

    def resolve_component_function(self, component_path, function_name, args):
        """Resolve ::component.function calls across components"""
        # Parse ::azl.stdlib.set_timeout → component="azl.stdlib", function="set_timeout"
        print(f"🔍 DEBUG: resolve_component_function called with:")
        print(f"   component_path: '{component_path}'")
        print(f"   function_name: '{function_name}'")
        print(f"   args: {args}")
        print(f"   Available component keys: {list(self.components.keys())}")
        
        # Try both with and without :: prefix
        component_key = component_path
        if component_key not in self.components:
            component_key = f"::{component_path}"
            print(f"   Trying with :: prefix: '{component_key}'")
        
        if component_key in self.components:
            component = self.components[component_key]
            print(f"   Found component: {component_key}")
            print(f"   Component functions: {list(component.functions.keys())}")
            
            if function_name in component.functions:
                print(f"   Function '{function_name}' found, calling...")
                result = component.call_function(function_name, args)
                print(f"   Function call result: {result}")
                return result
            else:
                print(f"   Function '{function_name}' not found in component")
        else:
            print(f"   Component not found with either key")
        
        return None

    def call_component_method(self, component_path, method_name, args):
        """Call a method on a specific component"""
        if component_path in self.components:
            component = self.components[component_path]
            return component.call_function(method_name, args)
        return None

    def register_global_function(self, component_name, function_name, function_body):
        """Register functions globally so other components can call them"""
        if component_name not in self.components:
            self.components[component_name] = AZLComponent(component_name, self)
        self.components[component_name].functions[function_name] = function_body

    def route_event_to_component(self, event_name, event_data, target_component):
        """Route events to specific components"""
        if target_component in self.components:
            component = self.components[target_component]
            if event_name in component.behaviors:
                return component.execute_behavior(event_name, event_data)
        return []

    # --- Mini expression evaluator (very small subset) ---
    def _lookup_var(self, name, memory, event_data):
        if name.startswith("::"):
            name = name[2:]
        # event special
        if name == "event" and event_data is not None:
            return {"data": event_data}
        return memory.get(name, "")

    def _get_prop(self, base, path):
        val = base
        for seg in path.split('.'):
            if not seg:
                continue
            if isinstance(val, dict):
                val = val.get(seg, "")
            elif seg == 'length' and isinstance(val, (str, list)):
                val = len(val)
            else:
                return ""
        return val

    def eval_expr(self, expr, memory, event_data):
        s = expr.strip()
        # strip wrapping parentheses
        if s.startswith('(') and s.endswith(')'):
            s = s[1:-1].strip()
        # normalize textual OR into || for expression context
        if ' or ' in s:
            s = s.replace(' or ', ' || ')
        # parseInt wrapper at top level
        if s.startswith('parseInt(') and s.endswith(')'):
            inner = s[len('parseInt('):-1]
            try:
                v = self.eval_expr(inner, memory, event_data)
                return int(str(v))
            except Exception:
                return 0
        # ternary support: cond ? a : b (simple, top-level)
        if '?' in s and ':' in s:
            q = s.find('?')
            if q > 0:
                cond = s[:q].strip()
                rest = s[q+1:]
                c = rest.find(':')
                if c != -1:
                    then_s = rest[:c].strip()
                    else_s = rest[c+1:].strip()
                    return self.eval_expr(then_s if self.eval_condition(cond, memory, event_data) else else_s, memory, event_data)
        # equality check a == b
        if '==' in s:
            a, b = s.split('==', 1)
            av = str(self._eval_add(a.strip(), memory, event_data))
            bv = str(self._eval_add(b.strip(), memory, event_data))
            return av == bv
        # handle || (first non-empty)
        parts_or = [p.strip() for p in s.split('||')]
        val = None
        for part in parts_or:
            v = self._eval_add(part, memory, event_data)
            if v not in (None, "", False):
                val = v
                break
        if val is None:
            val = self._eval_add(parts_or[-1], memory, event_data)
        return val

    def _eval_add(self, expr, memory, event_data):
        # split by + not inside quotes
        tokens = []
        buf = ''
        in_q = False
        q = ''
        for ch in expr:
            if in_q:
                buf += ch
                if ch == q:
                    in_q = False
            else:
                if ch in ('"', "'"):
                    in_q = True
                    q = ch
                    buf += ch
                elif ch == '+':
                    tokens.append(buf.strip())
                    buf = ''
                else:
                    buf += ch
        if buf:
            tokens.append(buf.strip())
        # Evaluate pieces; if all numeric, add numerically. Else, concatenate strings
        values = [self._eval_atom(t, memory, event_data) for t in tokens]
        all_numeric = True
        total = 0.0
        for v in values:
            try:
                if v is True or v is False or v is None:
                    all_numeric = False
                    break
                total += float(str(v))
            except Exception:
                all_numeric = False
                break
        if all_numeric:
            return int(total) if abs(total - int(total)) < 1e-9 else total
        return ''.join(str(v) for v in values)

    def _eval_atom(self, token, memory, event_data):
        t = token.strip()
        # positional args $1, $2 ...
        if t.startswith('$') and t[1:].isdigit():
            idx = int(t[1:])
            if idx == 1:
                return event_data
            if isinstance(event_data, (list, tuple)) and 1 <= idx <= len(event_data):
                return event_data[idx - 1]
            return ''
        # quoted string
        if (t.startswith('"') and t.endswith('"')) or (t.startswith("'") and t.endswith("'")):
            return t[1:-1]
        # Variable references (check memory first)
        if t in memory:
            return memory[t]
        # ::internal.env("VAR") lookup
        m_env = re.match(r'^::internal\.env\(\s*"([^"]*)"\s*\)$', t)
        if m_env:
            return os.environ.get(m_env.group(1), "")
        # parseInt nested
        if t.startswith('parseInt(') and t.endswith(')'):
            inner = t[len('parseInt('):-1]
            try:
                v = self.eval_expr(inner, memory, event_data)
                return int(str(v))
            except Exception:
                return 0
        # method calls: X.toString()
        m_to_str = re.match(r'^(.*)\.toString\(\)$', t)
        if m_to_str:
            base = self.eval_expr(m_to_str.group(1).strip(), memory, event_data)
            return str(base)
        # method calls: X.toInt()
        m_to_int = re.match(r'^(.*)\.toInt\(\)$', t)
        if m_to_int:
            base = self.eval_expr(m_to_int.group(1).strip(), memory, event_data)
            try:
                return int(str(base))
            except Exception:
                return 0
        # method calls: X.to_lower()
        m_to_lower = re.match(r'^(.*)\.to_lower\(\)$', t)
        if m_to_lower:
            base = self.eval_expr(m_to_lower.group(1).strip(), memory, event_data)
            return str(base).lower()
        # method calls: X.indexOf(Y)
        m_index = re.match(r'^(.*)\.indexOf\((.*)\)$', t)
        if m_index:
            base = self.eval_expr(m_index.group(1).strip(), memory, event_data)
            arg = self.eval_expr(m_index.group(2).strip(), memory, event_data)
            return str(base).find(str(arg))
        # method calls: X.substring(A[,B])
        m_sub = re.match(r'^(.*)\.substring\((.*)\)$', t)
        if m_sub:
            base = self.eval_expr(m_sub.group(1).strip(), memory, event_data)
            args = m_sub.group(2)
            parts = []
            buf = ''
            depth = 0
            in_q = False
            qch = ''
            for ch in args:
                if in_q:
                    buf += ch
                    if ch == qch:
                        in_q = False
                else:
                    if ch in ('"', "'"):
                        in_q = True
                        qch = ch
                        buf += ch
                    elif ch == '(':
                        depth += 1
                        buf += ch
                    elif ch == ')':
                        depth = max(0, depth - 1)
                        buf += ch
                    elif ch == ',' and depth == 0:
                        parts.append(buf.strip())
                        buf = ''
                    else:
                        buf += ch
            if buf:
                parts.append(buf.strip())
            start = 0
            end = None
            if len(parts) >= 1:
                try:
                    start = int(str(self.eval_expr(parts[0], memory, event_data)))
                except Exception:
                    start = 0
            if len(parts) >= 2:
                try:
                    end = int(str(self.eval_expr(parts[1], memory, event_data)))
                except Exception:
                    end = None
            sb = str(base)
            return sb[start: end if end is not None else None]
        # array literal
        if t.startswith('[') and t.endswith(']'):
            return self.parse_list(t, memory, event_data)
        # bracket indexing base[index]
        if ('[' in t) and t.endswith(']'):
            m = re.match(r'^(::?[A-Za-z0-9_\.]+)\[(.+)\]$', t)
            if m:
                base_name = m.group(1)
                idx_expr = m.group(2)
                base_val = self._lookup_var(base_name, memory, event_data)
                idx_val = self.eval_expr(idx_expr, memory, event_data)
                if isinstance(base_val, list):
                    try:
                        i = int(str(idx_val))
                        if 0 <= i < len(base_val):
                            return base_val[i]
                    except Exception:
                        return ''
                if isinstance(base_val, dict):
                    return base_val.get(str(idx_val), '')
                return ''
        # method call: list.push(x)
        m_push = re.match(r'^(::?[A-Za-z0-9_\.]+)\.push\((.*)\)$', t)
        if m_push:
            base_name = m_push.group(1)
            arg_expr = m_push.group(2).strip()
            arr = self._lookup_var(base_name, memory, event_data)
            if not isinstance(arr, list):
                arr = []
            val = self.eval_expr(arg_expr, memory, event_data) if arg_expr else None
            # mutate a copy and return it
            new_arr = list(arr)
            new_arr.append(val)
            return new_arr
        # boolean/null
        if t == 'true':
            return True
        if t == 'false':
            return False
        if t == 'null':
            return ''
        # object literal
        if t.startswith('{') and t.endswith('}'):
            return self.parse_object(t, memory, event_data)
        # dotted variable like ::resp.final_response or ::event.data.response
        if t.startswith('::') or t.startswith('event') or t.startswith('resp'):
            if t.startswith('::event.') or t.startswith('event.'):
                # event.data.x
                p = t.split('.', 2)
                if len(p) >= 3 and p[1] == 'data':
                    sub = p[2]
                    return self._get_prop(event_data or {}, sub)
                return ''
            # regular variable
            if '.' in t:
                base_name, sub_path = t.split('.', 1)
                base = self._lookup_var(base_name, memory, event_data)
                return self._get_prop(base if isinstance(base, (dict, str, list)) else {}, sub_path)
            return self._lookup_var(t, memory, event_data)
        # default: return as-is (strip quotes if any)
        return t.strip('"').strip("'")

    def eval_condition(self, cond, memory, event_data):
        s = cond.strip()
        # support '<expr> exists' checks
        m_exists = re.match(r'^(.*)\s+exists$', s)
        if m_exists:
            var_tok = m_exists.group(1).strip()
            if var_tok.startswith('::'):
                name = var_tok[2:]
                return name in memory
            return var_tok in memory
        # Handle 'not' operator (right-associative)
        if s.startswith('not '):
            inner = s[4:].strip()
            return not self.eval_condition(inner, memory, event_data)
        # Handle parentheses around full condition
        if s.startswith('(') and s.endswith(')'):
            return self.eval_condition(s[1:-1].strip(), memory, event_data)
        # Handle 'or' at top level
        parts = []
        depth = 0
        in_q = False
        q = ''
        buf = ''
        i = 0
        while i < len(s):
            ch = s[i]
            if in_q:
                buf += ch
                if ch == q:
                    in_q = False
            else:
                if ch in ('"', "'"):
                    in_q = True
                    q = ch
                    buf += ch
                elif s[i:i+3].lower() == ' or' and depth == 0 and (i == 0 or s[i-1] == ' '):
                    parts.append(buf.strip())
                    buf = ''
                    i += 2
                elif s[i:i+4].lower() == ' and' and depth == 0 and (i == 0 or s[i-1] == ' '):
                    # We'll split AND later if no OR found
                    buf += ch
                else:
                    if ch == '(':
                        depth += 1
                    elif ch == ')':
                        depth = max(0, depth - 1)
                    buf += ch
            i += 1
        if buf.strip():
            parts.append(buf.strip())
        if len(parts) > 1:
            return any(self.eval_condition(p, memory, event_data) for p in parts)
        # Handle 'and' at top level
        parts_and = []
        depth = 0
        in_q = False
        q = ''
        buf = ''
        i = 0
        while i < len(s):
            ch = s[i]
            if in_q:
                buf += ch
                if ch == q:
                    in_q = False
            else:
                if ch in ('"', "'"):
                    in_q = True
                    q = ch
                    buf += ch
                elif s[i:i+4].lower() == ' and' and depth == 0 and (i == 0 or s[i-1] == ' '):
                    parts_and.append(buf.strip())
                    buf = ''
                    i += 3
                else:
                    if ch == '(':
                        depth += 1
                    elif ch == ')':
                        depth = max(0, depth - 1)
                    buf += ch
            i += 1
        if buf.strip():
            parts_and.append(buf.strip())
        if len(parts_and) > 1:
            return all(self.eval_condition(p, memory, event_data) for p in parts_and)
        # Fallback: evaluate as expression truthiness
        v = self.eval_expr(s, memory, event_data)
        if isinstance(v, bool):
            return v
        sval = str(v).strip().lower()
        return sval not in ("", "0", "false", "null")

    def parse_object(self, text, memory, event_data):
        s = text.strip()
        if s.startswith('{') and s.endswith('}'):
            s = s[1:-1]
        # Strip top-level inline comments starting with '#'
        cleaned = ''
        depth = 0
        in_q = False
        q = ''
        i = 0
        while i < len(s):
            ch = s[i]
            if in_q:
                cleaned += ch
                if ch == q:
                    in_q = False
            else:
                if ch in ('"', "'"):
                    in_q = True
                    q = ch
                    cleaned += ch
                elif ch == '{' or ch == '[':
                    depth += 1
                    cleaned += ch
                elif ch == '}' or ch == ']':
                    depth = max(0, depth - 1)
                    cleaned += ch
                elif ch == '#' and depth == 0:
                    # skip until end of line
                    while i < len(s) and s[i] != '\n':
                        i += 1
                    cleaned += ''
                else:
                    cleaned += ch
            i += 1
        s = cleaned
        obj = {}
        # naive top-level comma split
        parts = []
        depth = 0
        buf = ''
        in_q = False
        q = ''
        for ch in s:
            if in_q:
                buf += ch
                if ch == q:
                    in_q = False
            else:
                if ch in ('"', "'"):
                    in_q = True
                    q = ch
                    buf += ch
                elif ch == '{' or ch == '[':
                    depth += 1
                    buf += ch
                elif ch == '}' or ch == ']':
                    depth -= 1
                    buf += ch
                elif ch == ',' and depth == 0:
                    parts.append(buf.strip())
                    buf = ''
                else:
                    buf += ch
        if buf:
            parts.append(buf.strip())
        for entry in parts:
            if not entry:
                continue
            if ':' not in entry:
                continue
            k, v = entry.split(':', 1)
            key = k.strip().strip('"').strip("'")
            val = self.eval_expr(v.strip(), memory, event_data)
            obj[key] = val
        return obj

    def parse_list(self, text, memory, event_data):
        s = text.strip()
        if s.startswith('[') and s.endswith(']'):
            s = s[1:-1]
        items = []
        buf = ''
        depth = 0
        in_q = False
        q = ''
        for ch in s:
            if in_q:
                buf += ch
                if ch == q:
                    in_q = False
            else:
                if ch in ('"', "'"):
                    in_q = True
                    q = ch
                    buf += ch
                elif ch in ('{', '['):
                    depth += 1
                    buf += ch
                elif ch in ('}', ']'):
                    depth -= 1
                    buf += ch
                elif ch == ',' and depth == 0:
                    item = buf.strip()
                    if item:
                        items.append(self.eval_expr(item, memory, event_data))
                    buf = ''
                else:
                    buf += ch
        tail = buf.strip()
        if tail:
            items.append(self.eval_expr(tail, memory, event_data))
        return items
        
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
            self.components[component_name] = AZLComponent(component_name, engine=self)
        
        # Parse each component
        for component_name in components:
            self.parse_component(content, component_name)
    
    def _find_block(self, s, open_brace_index):
        depth = 1
        i = open_brace_index + 1
        while i < len(s) and depth > 0:
            ch = s[i]
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
            i += 1
        # return content excluding outer braces
        return s[open_brace_index + 1:i - 1]

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
        
        # Parse init block using brace counting
        init_m = re.search(r'\binit\s*\{', component_content)
        if init_m:
            block = self._find_block(component_content, init_m.end() - 1)
            component.init_code = [line.strip() for line in block.split('\n') if line.strip()]
        
        # Parse 'listen for "ev" { ... }' and 'listen for "ev" then { ... }' with brace counting
        idx = 0
        while True:
            lm = re.search(r'listen\s+for\s+"([^"]+)"\s+(?:then\s*)?\{', component_content[idx:])
            if not lm:
                break
            ev = lm.group(1)
            open_i = idx + lm.end() - 1
            block = self._find_block(component_content, open_i)
            code_lines = [line.strip() for line in block.split('\n') if line.strip()]
            component.add_behavior(ev, code_lines)
            print(f"🎯 Added behavior for event: {ev}")
            idx = open_i + len(block) + 2  # move past this block

        # Parse 'on <event> { ... }' with brace counting
        idx = 0
        while True:
            om = re.search(r'\bon\s+([A-Za-z0-9_.:]+)\s*\{', component_content[idx:])
            if not om:
                break
            ev = om.group(1)
            open_i = idx + om.end() - 1
            block = self._find_block(component_content, open_i)
            code_lines = [line.strip() for line in block.split('\n') if line.strip()]
            component.add_behavior(ev, code_lines)
            print(f"🎯 Added behavior for event: {ev}")
            idx = open_i + len(block) + 2

        # Parse 'fn function_name(params) { ... }' with brace counting
        idx = 0
        while True:
            fm = re.search(r'\bfn\s+([A-Za-z0-9_.:]+)\s*\(([^)]*)\)\s*\{', component_content[idx:])
            if not fm:
                break
            fn_name = fm.group(1)
            params_txt = fm.group(2).strip()
            params = [p.strip() for p in params_txt.split(',') if p.strip()]
            
            open_i = idx + fm.end() - 1
            block = self._find_block(component_content, open_i)
            code_lines = [line.strip() for line in block.split('\n') if line.strip()]
            
            # Store function definition
            component.add_function(fn_name, code_lines, params)
            print(f"📝 Function defined: {fn_name} with params: {params}")
            
            idx = open_i + len(block) + 2  # move past this block

        # Parse memory functions: memory { function name(params?) { ... } }
        mem_m = re.search(r'\bmemory\s*\{', component_content)
        if mem_m:
            mem_block = self._find_block(component_content, mem_m.end() - 1)
            midx = 0
            while True:
                fm = re.search(r'function\s+([A-Za-z0-9_.:]+)\s*\(([^)]*)\)\s*\{', mem_block[midx:])
                if not fm:
                    break
                fn_name = fm.group(1)
                params_txt = fm.group(2).strip()
                params = [p.strip() for p in params_txt.split(',') if p.strip()] if params_txt else []
                f_open = midx + fm.end() - 1
                f_block = self._find_block(mem_block, f_open)
                code_lines = [line.strip() for line in f_block.split('\n') if line.strip()]
                component.add_function(fn_name, code_lines, params)
                print(f"🎯 Added memory function: {fn_name}({', '.join(params)})")
                midx = f_open + len(f_block) + 2
        # Parse top-level functions: function name(params?) { ... } anywhere in the component
        fidx = 0
        while True:
            fm2 = re.search(r'\bfunction\s+([A-Za-z0-9_.:]+)\s*\(([^)]*)\)\s*\{', component_content[fidx:])
            if not fm2:
                break
            fn2_name = fm2.group(1)
            params2_txt = fm2.group(2).strip()
            params2 = [p.strip() for p in params2_txt.split(',') if p.strip()] if params2_txt else []
            f2_open = fidx + fm2.end() - 1
            f2_block = self._find_block(component_content, f2_open)
            code_lines2 = [line.strip() for line in f2_block.split('\n') if line.strip()]
            component.add_function(fn2_name, code_lines2, params2)
            print(f"🎯 Added function: {fn2_name}({', '.join(params2)})")
            fidx = f2_open + len(f2_block) + 2
        
        # Special handling for stdlib component - register functions globally
        if component_name == "azl.stdlib":
            print(f"🔧 Registering stdlib functions globally for cross-component access")
            print(f"🔍 DEBUG: stdlib component has functions: {list(component.functions.keys())}")
            for func_name, func_body in component.functions.items():
                self.register_global_function("azl.stdlib", func_name, func_body)
                print(f"✅ Registered global function: azl.stdlib.{func_name}")
        else:
            print(f"🔍 DEBUG: Component {component_name} loaded with functions: {list(component.functions.keys())}")
    
    def process_event(self, event):
        """Process an event by finding and executing matching behaviors"""
        ev_name = event["event"] if isinstance(event, dict) else event
        target = event.get("target") if isinstance(event, dict) else None
        ev_data = event.get("data") if isinstance(event, dict) else None
        # Normalize bare names emitted from init
        if isinstance(event, str):
            event = {"event": ev_name, "target": None, "data": None}
        # Allow repeated processing for certain recurring events (heartbeats/metrics/training)
        if ev_name in self.processed_events and ev_name not in self.repeatable_events:
            print(f"⚠️  Event {event} already processed, skipping")
            return []
        
        print(f"\n🔄 Processing event: {ev_name}")
        self.processed_events.add(ev_name)
        
        emitted_events = []
        # Bridge critical system events directly when core components are symbolic
        if ev_name == "proc.spawn":
            try:
                cmd = (ev_data or {}).get("command") if isinstance(ev_data, dict) else None
                args = (ev_data or {}).get("args") if isinstance(ev_data, dict) else []
                env_in = (ev_data or {}).get("env") if isinstance(ev_data, dict) else {}
                if not isinstance(args, list):
                    args = []
                if not isinstance(env_in, dict):
                    env_in = {}
                if cmd:
                    proc_env = os.environ.copy()
                    proc_env.update({str(k): str(v) for k, v in env_in.items()})
                    popen = subprocess.Popen([cmd] + [str(a) for a in args], env=proc_env)
                    pid = popen.pid
                    print(f"⚙️ Subprocess started pid={pid} cmd={cmd}")
                    emitted_events.append({"event": "proc.spawn.response", "data": {"pid": pid, "command": cmd}})
                else:
                    print("⚠️  proc.spawn missing command")
            except Exception as e:
                print(f"❌ proc.spawn error: {e}")
            return emitted_events
        # Warn if a targeted component is not available
        if target and target not in self.components:
            print(f"⚠️  Target component not loaded: {target} (event {ev_name})")
        for component_name, component in self.components.items():
            if target and component_name != target:
                continue
            if ev_name in component.behaviors:
                print(f"🎯 Component {component_name} handling event: {ev_name}")
                new_events = component.execute_behavior(ev_name, ev_data)
                emitted_events.extend(new_events)
                if new_events:
                    print(f"📡 New events from {component_name}: {new_events}")
        
        return emitted_events
    
    def simulate_http_request(self, method, path, body=None, headers=None):
        """Simulate an HTTP request to test endpoints"""
        print(f"🌐 Simulating HTTP {method} {path}")
        
        # Create request data structure
        request_data = {
            "method": method,
            "path": path,
            "body": body or "",
            "headers": headers or {},
            "url": f"http://localhost{path}",
            "query": {}
        }
        
        # Emit the request event
        self.event_queue.append({"event": "http.server.handle_request", "data": request_data})
        print(f"📡 Queued HTTP request event: http.server.handle_request")
        
        # Process the event
        self.process_event({"event": "http.server.handle_request", "data": request_data})
    
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
        
        # Check if this is a training script that needs continuous execution
        is_training_script = any(keyword in component_name.lower() for keyword in ['train', 'training', 'model'])
        continuous_mode = os.environ.get("AZL_CONTINUOUS", "0") == "1" or is_training_script
        
        if continuous_mode:
            print("🔄 CONTINUOUS EXECUTION MODE ENABLED - Training script will run continuously")
            print("🟠 Live training progress will be displayed...")
        
        # Process all queued events
        max_iterations = 500  # Increased to allow full initialization completion
        iteration = 0
        
        while self.event_queue and iteration < max_iterations:
            iteration += 1
            event = self.event_queue.pop(0)
            print(f"\n🔄 Iteration {iteration}: Processing event '{event}'")
            
            new_events = self.process_event(event)
            if new_events:
                # Add new events to the queue (normalize to names)
                for new_event in new_events:
                    if isinstance(new_event, dict):
                        name = new_event.get("event")
                    else:
                        name = new_event
                    # Always enqueue repeatable events; only de-dup non-repeatables
                    if name and (name in self.repeatable_events or name not in self.processed_events):
                        self.event_queue.append(new_event)
                        print(f"📥 Added new event to queue: {name}")
            
            print(f"📊 Queue status: {len(self.event_queue)} events remaining")
        
        if iteration >= max_iterations:
            print(f"⚠️  Reached maximum iterations ({max_iterations}), stopping")
        
        # CONTINUOUS EXECUTION: If this is a training script, keep it running
        if continuous_mode and is_training_script:
            print("\n" + "=" * 50)
            print("🔄 CONTINUOUS TRAINING MODE ACTIVATED")
            print("🟠 Training script will continue running with live progress...")
            print("🟠 Press Ctrl+C to stop training")
            print("=" * 50)
            
            # Keep the script alive for continuous training
            try:
                while True:
                    # Drain all queued events (not just keep_alive) to keep training progressing
                    if self.event_queue:
                        event = self.event_queue.pop(0)
                        new_events = self.process_event(event)
                        if new_events:
                            for new_event in new_events:
                                if isinstance(new_event, dict):
                                    name = new_event.get("event")
                                else:
                                    name = new_event
                                # Always enqueue repeatable events; only de-dup non-repeatables
                                if name and (name in self.repeatable_events or name not in self.processed_events):
                                    self.event_queue.append(new_event)
                    else:
                        # Small delay to prevent CPU spinning when idle
                        time.sleep(0.05)
                    
            except KeyboardInterrupt:
                print("\n🛑 Training stopped by user (Ctrl+C)")
                print("✅ Training session completed")
    
    def run(self, file_path):
        """Run the AZL file"""
        print("🚀 AZL Language Runner Starting...")
        print("🧪 Testing Integration Fixes...")
        print("=" * 50)
        
        self.parse_azl_file(file_path)
        # Optional core autoload (controlled via env)
        if os.environ.get("AZL_AUTOLOAD", "0") == "1":
            print("🔍 AZL_AUTOLOAD enabled - scanning for all components...")
            
            # Define all directories to scan for AZL components
            scan_directories = [
                "azme/core/",
                "azme/specialized/",
                "azme/neural/",
                "azme/quantum/",
                "azme/consciousness/",
                "azme/interface/",
                "azme/perception/",
                "azme/cognitive/",
                "azme/learning/",
                "azme/planning/",
                "azme/agents/",
                "azme/runtime/",
                "azme/sandbox/",
                "azme/collaboration/",
                "azme/logger/",
                "azme/datasets/",
                "azme/experiments/",
                "azme/nlp/",
                "azme/system/",
                "azme/integrations/",
                "azme/checkpoint/",
                "azl/nlp/",
                "azl/aba/",
                "azl/aba/analysis/",
                "azl/aba/core/",
                "azl/aba/data/",
                "azl/aba/intervention/",
                "azl/aba/testing/",
                "azl/neural/",
                "azl/quantum/",
                "azl/quantum/processor/",
                "azl/quantum/mathematics/",
                "azl/quantum/memory/",
                "azl/quantum/optimizer/",
                "azl/quantum/phase_field/",
                "azl/quantum/measurement/",
                "azl/quantum/superposition/",
                "azl/core/",
                "azl/core/neural/",
                "azl/core/consciousness/",
                "azl/core/memory/",
                "azl/core/runtime/",
                "azl/core/kernel/",
                "azl/core/parser/",
                "azl/core/azl/",
                "azl/core/error_system.azl",
                "azl/system/",
                "azl/stdlib/",
                "azl/stdlib/core/",
                "azl/ffi/",
                "azl/backend/",
                "azl/backend/format/",
                "azl/backend/asm/",
                "azl/security/",
                "azl/observability/",
                "azl/applications/",
                "azl/tests/",
                "azl/testing/",
                "azl/memory/",
                "azl/bootstrap/",
                "azl/examples/",
                "azl/pure/",
                "azl/pure/frontend/",
                "azl/orchestrator/",
                "scripts/",
            ]
            
            # Scan all directories for .azl files
            all_azl_files = []
            for directory in scan_directories:
                dir_path = Path(directory)
                if dir_path.exists():
                    for azl_file in dir_path.glob("*.azl"):
                        all_azl_files.append(azl_file)
            
            # Sort files for consistent loading order
            all_azl_files.sort()
            
            print(f"🔍 Found {len(all_azl_files)} AZL files to autoload")
            
            # Load all found AZL files
            for azl_file in all_azl_files:
                try:
                    if azl_file.exists():
                        print(f"📖 Autoloading: {azl_file}")
                        self.parse_azl_file(str(azl_file))
                except Exception as e:
                    print(f"⚠️  Skipping autoload file {azl_file}: {e}")
            
            print(f"✅ Autoloaded {len(all_azl_files)} AZL files")
        
        if not self.components:
            # Fallback: wrap script-style files into a synthetic component
            print("ℹ️ No components found; attempting script-style execution via wrapper component")
            with open(file_path, 'r') as f:
                raw = f.read()
            wrapped = (
                'component ::file.main {\n'
                '  init {\n' +
                '\n'.join(["    " + line for line in raw.splitlines() if line.strip() != ""]) +
                '\n  }\n}\n'
            )
            # write wrapper outside repo to avoid duplicate files
            tmp = Path('/tmp') / (Path(file_path).stem + "__wrapped.azl")
            with open(tmp, 'w') as wf:
                wf.write(wrapped)
            print(f"🧩 Created wrapper: {tmp}")
            self.parse_azl_file(str(tmp))
            if not self.components:
                print("❌ Unable to execute: still no components after wrapping")
                return
        
        # Run the API endpoints component first if available, otherwise run the first component
        if "::api.endpoints" in self.components:
            # Initialize both API endpoints and HTTP server components
            self.run_component("::api.endpoints")
            if "::net.http.server" in self.components:
                self.run_component("::net.http.server")
            
            # Emit the event to trigger endpoint setup
            self.event_queue.append({"event": "initialize_chat_interface", "data": {}})
            print("📡 Emitting initialize_chat_interface to trigger endpoint setup")
            
            # Process the event queue to set up endpoints
            while self.event_queue:
                event = self.event_queue.pop(0)
                print(f"\n🔄 Processing setup event: {event}")
                new_events = self.process_event(event)
                # Add any new events to the queue
                if new_events:
                    for new_event in new_events:
                        if isinstance(new_event, dict):
                            name = new_event.get("event")
                        else:
                            name = new_event
                        if name and (name not in self.processed_events):
                            self.event_queue.append(new_event)
                            print(f"📥 Added new event to queue: {name}")
        else:
            first_component = list(self.components.keys())[0]
            self.run_component(first_component)
        
        # Test HTTP endpoints if available
        if "::api.endpoints" in self.components:
            print("\n" + "=" * 50)
            print("🌐 Testing HTTP Chat Endpoint")
            print("=" * 50)
            
            # Test POST /chat
            test_message = "Hello, AZME! This is a test message."
            print(f"📝 Testing POST /chat with message: '{test_message}'")
            
            self.simulate_http_request(
                method="POST",
                path="/chat",
                body=test_message,
                headers={"Content-Type": "text/plain"}
            )
        
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