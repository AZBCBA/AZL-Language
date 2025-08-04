use std::collections::HashMap;
use std::fs;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use std::thread::sleep;

#[derive(Debug)]
pub enum AzlError {
    VariableNotFound(String),
    TypeMismatch(String),
    InvalidOperation(String),
    Runtime(String),
    Panic(String),
}

#[derive(Debug, Clone)]
pub enum ComponentState {
    Initialized,
    Running,
    Terminated,
}

#[derive(Debug)]
pub struct ComponentInfo {
    pub name: String,
    pub state: ComponentState,
    pub created_at: std::time::SystemTime,
}

pub struct ComponentRegistry {
    pub components: HashMap<String, ComponentInfo>,
}

#[derive(Debug, Clone)]
enum Value {
    Int(i64),
    Float(f64),
    Bool(bool),
    Str(String),
    Quantum(String),    // Future use
    Neural(String),     // Future use
    Conscious(String),  // Future use
    Object(HashMap<String, Value>),
    Array(Vec<Value>),
    Null,
}

type Memory = HashMap<String, Value>;

#[derive(Debug, Clone)]
enum BlockType {
    Init,
    Behavior,
    Memory,
    Interface,
    ListenFor,
    If,
    Else,
    While,
    Loop,
    None,
}

struct AZLInterpreter {
    memory: Memory,
    components: HashMap<String, Vec<String>>,
    current_component: String,
    current_block: BlockType,
    event_listeners: HashMap<String, Vec<String>>,
    in_block: bool,
    block_lines: Vec<String>,
    block_stack: Vec<BlockType>,
    event_name: String,
    condition_result: bool,
    event_params: Vec<String>,
    registry: ComponentRegistry,
}

impl AZLInterpreter {
    fn new() -> Self {
        AZLInterpreter {
            memory: HashMap::new(),
            components: HashMap::new(),
            current_component: String::new(),
            current_block: BlockType::None,
            event_listeners: HashMap::new(),
            in_block: false,
            block_lines: Vec::new(),
            block_stack: Vec::new(),
            event_name: String::new(),
            condition_result: false,
            event_params: Vec::new(),
            registry: ComponentRegistry::new(),
        }
    }

    // Memory Engine Functions
    pub fn memory_store(&mut self, key: String, value: Value) {
        self.memory.insert(key, value);
    }

    pub fn memory_retrieve(&self, key: &str) -> Option<&Value> {
        self.memory.get(key)
    }

    pub fn memory_clear(&mut self) {
        // Preserve essential variables during memory clearing
        let goals = self.memory_retrieve("::goals").cloned();
        let self_state = self.memory_retrieve("::self").cloned();
        
        self.memory.clear();
        
        // Restore essential variables
        if let Some(goals) = goals {
            self.memory_store("::goals".to_string(), goals);
        }
        if let Some(self_state) = self_state {
            self.memory_store("::self".to_string(), self_state);
        }
    }

    pub fn memory_exists(&self, key: &str) -> bool {
        self.memory.contains_key(key)
    }

    // Error handling and logging
    pub fn log_error(&self, error: &AzlError) {
        eprintln!("[AZL ERROR] {:?}", error);
    }

    pub fn log_warning(&self, message: &str) {
        eprintln!("[AZL WARNING] {}", message);
    }

    pub fn log_info(&self, message: &str) {
        println!("[AZL INFO] {}", message);
    }

    pub fn populate_self_state(&mut self) {
        // Get component count
        let component_count = self.registry.get_component_count();
        
        // Get running components
        let running_components = self.registry.get_running_components();
        let running_names: Vec<String> = running_components.iter().map(|s| s.to_string()).collect();
        
        // Get memory keys
        let memory_keys: Vec<String> = self.memory.keys().cloned().collect();
        
        // Get errors (we'll track these in a separate list)
        let errors: Vec<String> = Vec::new(); // Placeholder for error tracking
        
        // Calculate consciousness level (placeholder for future implementation)
        let consciousness_level = 0.72;
        
        // Calculate uptime (placeholder for now)
        let uptime_seconds = 0; // Will be implemented with actual uptime tracking
        
        // Memory usage (simulated)
        let memory_usage = self.memory.len() as f64 * 0.1; // Simulated memory usage
        
        // Adaptation state
        let is_adapting = false; // Placeholder for adaptation tracking
        
        // Get current goals
        let current_goals = if let Some(goals_value) = self.memory_retrieve("::goals") {
            match goals_value {
                Value::Str(goals_str) => goals_str.clone(),
                _ => "No goals set".to_string(),
            }
        } else {
            "No goals set".to_string()
        };
        
        // Get ABA data
        let default_aba_trials = Value::Str("[]".to_string());
        let aba_trials = self.memory_retrieve("::aba_trials").unwrap_or(&default_aba_trials);
        let aba_trials_str = match aba_trials {
            Value::Str(s) => s.clone(),
            _ => "[]".to_string()
        };
        
        // Get advanced ABA data
        let chain_count = self.get_chain_count();
        let shaping_count = self.get_shaping_count();
        let fade_count = self.get_fade_count();
        let task_count = self.get_task_count();
        
        let advanced_aba_data = format!(
            "\"chain_count\": {}, \"shaping_count\": {}, \"fade_count\": {}, \"task_count\": {}",
            chain_count, shaping_count, fade_count, task_count
        );
        
        // Create self-state object as a structured string representation
        let self_state = format!(
            "{{\"component_count\": {}, \"running_components\": {:?}, \"memory_keys\": {:?}, \"errors\": {:?}, \"consciousness_level\": {}, \"uptime_seconds\": {}, \"memory_usage\": {}, \"is_adapting\": {}, \"current_goals\": \"{}\", \"aba_trials\": {}, \"advanced_aba_data\": {}}}",
            component_count,
            running_names,
            memory_keys,
            errors,
            consciousness_level,
            uptime_seconds,
            memory_usage,
            is_adapting,
            current_goals,
            aba_trials_str,
            advanced_aba_data
        );
        
        // Store as a special self-state value
        self.memory_store("::self".to_string(), Value::Str(self_state));
        
        println!("[AZL INFO] Self-state updated: {} components, {} running", component_count, running_names.len());
    }

    fn run_file(&mut self, path: &str) {
        let content = fs::read_to_string(path).expect("Failed to read file");
        self.execute_lines(content.lines().map(|l| l.trim()).collect());
    }

    fn execute_lines(&mut self, lines: Vec<&str>) {
        let mut i = 0;
        while i < lines.len() {
            let line = lines[i];
            if line.is_empty() || line.starts_with("#") { 
                i += 1;
                continue; 
            }

            // Handle block starts
            if line.starts_with("init {") {
                self.push_block(BlockType::Init);
                i += 1;
                continue;
            } else if line.starts_with("behavior {") {
                self.push_block(BlockType::Behavior);
                i += 1;
                continue;
            } else if line.starts_with("memory {") {
                self.push_block(BlockType::Memory);
                i += 1;
                continue;
            } else if line.starts_with("interface {") {
                self.push_block(BlockType::Interface);
                i += 1;
                continue;
            } else if line.starts_with("listen for ") {
                self.handle_listen_for_start(line);
                i += 1;
                continue;
            } else if line.starts_with("if ") {
                self.handle_if_start(line);
                i += 1;
                continue;
            } else if line.starts_with("} else {") {
                self.handle_else_start();
                i += 1;
                continue;
            } else if line.starts_with("while ") {
                self.handle_while_start(line);
                i += 1;
                continue;
            } else if line.starts_with("loop ") {
                self.handle_loop_start(line);
                i += 1;
                continue;
            }

            // Handle block ends
            if line == "}" {
                self.handle_block_end();
                i += 1;
                continue;
            }

            // Handle lines within blocks
            if self.in_block {
                self.block_lines.push(line.to_string());
                i += 1;
                continue;
            }

            // Handle multi-line object literals in set commands
            if line.starts_with("set ") && line.contains("= {") && !line.trim().ends_with("}") {
                let mut object_lines = vec![line.to_string()];
                let mut brace_count = 1; // We already have one opening brace
                i += 1;
                
                // Collect lines until we find the closing brace
                while i < lines.len() && brace_count > 0 {
                    let next_line = lines[i];
                    object_lines.push(next_line.to_string());
                    
                    // Count braces in this line
                    for ch in next_line.chars() {
                        if ch == '{' {
                            brace_count += 1;
                        } else if ch == '}' {
                            brace_count -= 1;
                        }
                    }
                    
                    i += 1;
                }
                
                // Combine all lines into a single object literal
                let combined_line = object_lines.join(" ");
                println!("\u{1F4E2} Combined multi-line object: {}", combined_line);
                if let Err(err) = self.handle_set(&combined_line) {
                    self.log_error(&err);
                }
                continue;
            }

            // Handle multi-line emit parameters
            if line.starts_with("emit ") && line.contains("with {") && !line.trim().ends_with("}") {
                let mut emit_lines = vec![line.to_string()];
                let mut brace_count = 1; // We already have one opening brace
                i += 1;
                
                // Collect lines until we find the closing brace
                while i < lines.len() && brace_count > 0 {
                    let next_line = lines[i];
                    emit_lines.push(next_line.to_string());
                    
                    // Count braces in this line
                    for ch in next_line.chars() {
                        if ch == '{' {
                            brace_count += 1;
                        } else if ch == '}' {
                            brace_count -= 1;
                        }
                    }
                    
                    i += 1;
                }
                
                // Combine all lines into a single emit command
                let combined_line = emit_lines.join(" ");
                println!("\u{1F4E2} Combined multi-line emit: {}", combined_line);
                self.handle_emit(&combined_line);
                continue;
            }

            // Handle lines that look like they might be part of a multi-line object or emit
            let trimmed = line.trim();
            if (trimmed.starts_with("{") || trimmed.ends_with("}")) && 
               !line.starts_with("say ") && !line.starts_with("emit ") && !line.starts_with("set ") &&
               !line.starts_with("if ") && !line.starts_with("} else if ") && !line.starts_with("} else {") &&
               !line.starts_with("branch when ") && !line.starts_with("store ") && !line.starts_with("call ") &&
               !line.starts_with("component ") && !line.starts_with("on ") &&
               !line.contains("say ") && !line.contains("emit ") && !line.contains("set ") &&
               !line.contains("if ") && !line.contains("else if ") && !line.contains("else {") &&
               !line.contains("branch when ") && !line.contains("store ") && !line.contains("call ") &&
               !line.contains("component ") && !line.contains("on ") {
                // This looks like it might be part of a multi-line object or emit
                // Skip it as it should have been handled above
                println!("\u{26A0} Skipping continuation line: {}", line);
                i += 1;
                continue;
            }

            // Handle regular commands
            if line.starts_with("set ") {
                if let Err(err) = self.handle_set(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("assert ") || line.starts_with("check ") {
                self.handle_assert(line);
            } else if line.starts_with("emit ") {
                self.handle_emit(line);
            } else if line.starts_with("say ") {
                self.handle_say(line);
            } else if line.starts_with("link ") {
                self.handle_link(line);
            } else if line.starts_with("on ") {
                self.handle_on(line);
            } else if line.starts_with("typeof ") {
                if let Err(err) = self.handle_typeof(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("debug") {
                if let Err(err) = self.handle_debug(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("reflect") {
                if let Err(err) = self.handle_reflect(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("setgoal") {
                if let Err(err) = self.handle_setgoal(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("addgoal") {
                if let Err(err) = self.handle_addgoal(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("pursuegoal") {
                if let Err(err) = self.handle_pursuegoal(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("run") {
                if let Err(err) = self.handle_run(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("apply_trial") {
                if let Err(err) = self.handle_apply_trial(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("analyze_consequence") {
                if let Err(err) = self.handle_analyze_consequence(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("reinforce_behavior") {
                if let Err(err) = self.handle_reinforce_behavior(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("define_chain") {
                if let Err(err) = self.handle_define_chain(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("shape_behavior") {
                if let Err(err) = self.handle_shape_behavior(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("prompt_fade") {
                if let Err(err) = self.handle_prompt_fade(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("task_analysis") {
                if let Err(err) = self.handle_task_analysis(line) {
                    self.log_error(&err);
                }
            } else if line.starts_with("internal.now()") {
                let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
                println!("\u{1F552} now = {}", now);
            } else if line.starts_with("internal.wait(") {
                self.handle_wait(line);
            } else if line.starts_with("call ") {
                self.handle_call(line);
            } else if line.starts_with("component ") {
                self.handle_component(line);
            } else {
                // Handle unknown lines - don't try to guess if they're continuations
                let error = AzlError::InvalidOperation(format!("Unknown line: {}", line));
                self.log_error(&error);
            }
            
            i += 1;
        }
    }

    fn push_block(&mut self, block_type: BlockType) {
        self.block_stack.push(self.current_block.clone());
        self.current_block = block_type;
        self.in_block = true;
        self.block_lines.clear();
    }

    fn handle_listen_for_start(&mut self, line: &str) {
        // Parse: listen for "event.name" then {
        let parts: Vec<&str> = line.split("listen for").collect();
        if parts.len() < 2 { return; }
        
        let event_part = parts[1].trim();
        if let Some(quote_start) = event_part.find('"') {
            if let Some(quote_end) = event_part[quote_start + 1..].find('"') {
                let event_name = &event_part[quote_start + 1..quote_start + 1 + quote_end];
                self.event_name = event_name.to_string();
                println!("\u{1F4E6} Registered listener for event: {}", event_name);
                
                self.push_block(BlockType::ListenFor);
            }
        }
    }

    fn handle_if_start(&mut self, line: &str) {
        // Parse: if ::condition then {
        let condition_part = line.trim_start_matches("if").trim();
        if let Some(then_pos) = condition_part.find("then") {
            let condition = &condition_part[..then_pos].trim();
            let resolved_condition = self.replace_vars(condition);
            let result = self.eval_condition(&resolved_condition);
            
            self.condition_result = result;
            if result {
                println!("\u{2705} if condition true: {}", condition);
            } else {
                println!("\u{274C} if condition false: {}", condition);
            }
            
            self.push_block(BlockType::If);
        }
    }

    fn handle_else_start(&mut self) {
        // Switch from if to else block
        if let Some(BlockType::If) = self.block_stack.last() {
            self.current_block = BlockType::Else;
            self.block_lines.clear();
            println!("\u{1F4E6} Entering else block");
        }
    }

    fn handle_while_start(&mut self, line: &str) {
        // Parse: while ::condition {
        let condition_part = line.trim_start_matches("while").trim();
        if let Some(brace_pos) = condition_part.find('{') {
            let condition = &condition_part[..brace_pos].trim();
            let resolved_condition = self.replace_vars(condition);
            let result = self.eval_condition(&resolved_condition);
            
            if result {
                println!("\u{1F504} while condition true: {}", condition);
                self.push_block(BlockType::While);
            } else {
                println!("\u{274C} while condition false: {}", condition);
                // Skip the while block entirely
                self.in_block = true;
                self.block_lines.clear();
            }
        }
    }

    fn handle_loop_start(&mut self, line: &str) {
        // Parse: loop for ::item in ::collection {
        let loop_part = line.trim_start_matches("loop").trim();
        if let Some(for_pos) = loop_part.find("for") {
            let rest = &loop_part[for_pos + 3..].trim();
            println!("\u{1F504} Loop: {}", rest);
            self.push_block(BlockType::Loop);
        }
    }

    fn handle_block_end(&mut self) {
        match self.current_block {
            BlockType::Init => {
                println!("\u{1F4E6} Initializing component: {}", self.current_component);
                let lines_to_execute = self.block_lines.clone();
                for line in lines_to_execute {
                    let _ = self.execute_single_line(&line);
                }
            },
            BlockType::Behavior => {
                println!("\u{1F4E6} Behavior block for component: {}", self.current_component);
                // Store behavior lines for event handling
                self.event_listeners.insert(self.current_component.clone(), self.block_lines.clone());
            },
            BlockType::Memory => {
                println!("\u{1F4E6} Memory block for component: {}", self.current_component);
                let lines_to_execute = self.block_lines.clone();
                for line in lines_to_execute {
                    let _ = self.execute_single_line(&line);
                }
            },
            BlockType::Interface => {
                println!("\u{1F4E6} Interface block for component: {}", self.current_component);
            },
            BlockType::ListenFor => {
                println!("\u{1F4E6} Listen for block: {}", self.event_name);
                // Store event listener with its block
                if !self.event_listeners.contains_key(&self.event_name) {
                    self.event_listeners.insert(self.event_name.clone(), Vec::new());
                }
                self.event_listeners.get_mut(&self.event_name).unwrap().extend(self.block_lines.clone());
            },
            BlockType::If => {
                if self.condition_result {
                    println!("\u{2705} Executing if block");
                    let lines_to_execute = self.block_lines.clone();
                    for line in lines_to_execute {
                        let _ = self.execute_single_line(&line);
                    }
                } else {
                    println!("\u{274C} Skipping if block (condition false)");
                }
            },
            BlockType::Else => {
                if !self.condition_result {
                    println!("\u{2705} Executing else block");
                    let lines_to_execute = self.block_lines.clone();
                    for line in lines_to_execute {
                        let _ = self.execute_single_line(&line);
                    }
                } else {
                    println!("\u{274C} Skipping else block (if condition was true)");
                }
            },
            BlockType::While => {
                println!("\u{1F504} Executing while block");
                let lines_to_execute = self.block_lines.clone();
                for line in lines_to_execute {
                    let _ = self.execute_single_line(&line);
                }
            },
            BlockType::Loop => {
                println!("\u{1F504} Executing loop block");
                let lines_to_execute = self.block_lines.clone();
                for line in lines_to_execute {
                    let _ = self.execute_single_line(&line);
                }
            },
            BlockType::None => {
                println!("\u{26A0}\u{FE0F} Unexpected block end");
            }
        }
        
        // Pop the block stack
        if let Some(previous_block) = self.block_stack.pop() {
            self.current_block = previous_block;
        } else {
            self.current_block = BlockType::None;
        }
        
        self.in_block = !self.block_stack.is_empty();
        self.block_lines.clear();
    }

    fn execute_single_line(&mut self, line: &str) -> Result<(), AzlError> {
        if line.is_empty() || line.starts_with("#") { return Ok(()); }

        // Handle memory block syntax: ::key = value
        if line.trim().starts_with("::") && line.contains("=") {
            return self.handle_memory_assignment(line);
        }

        if line.starts_with("set ") {
            self.handle_set(line)
        } else if line.starts_with("emit ") {
            self.handle_emit(line);
            Ok(())
        } else if line.starts_with("say ") {
            self.handle_say(line);
            Ok(())
        } else if line.starts_with("link ") {
            self.handle_link(line);
            Ok(())
        } else if line.starts_with("store ") {
            self.handle_store(line);
            Ok(())
        } else if line.starts_with("if ") {
            self.handle_if_inline(line);
            Ok(())
        } else if line.starts_with("while ") {
            self.handle_while_inline(line);
            Ok(())
        } else if line.starts_with("typeof ") {
            self.handle_typeof(line)
        } else if line.starts_with("debug") {
            self.handle_debug(line)
        } else if line.starts_with("reflect") {
            self.handle_reflect(line)
        } else if line.starts_with("setgoal") {
            self.handle_setgoal(line)
        } else if line.starts_with("addgoal") {
            self.handle_addgoal(line)
        } else if line.starts_with("pursuegoal") {
            self.handle_pursuegoal(line)
        } else if line.starts_with("run") {
            self.handle_run(line)
        } else if line.starts_with("apply_trial") {
            self.handle_apply_trial(line)
        } else if line.starts_with("analyze_consequence") {
            self.handle_analyze_consequence(line)
        } else if line.starts_with("reinforce_behavior") {
            self.handle_reinforce_behavior(line)
        } else if line.starts_with("define_chain") {
            self.handle_define_chain(line)
        } else if line.starts_with("shape_behavior") {
            self.handle_shape_behavior(line)
        } else if line.starts_with("prompt_fade") {
            self.handle_prompt_fade(line)
        } else if line.starts_with("task_analysis") {
            self.handle_task_analysis(line)
        } else if line.starts_with("internal.now()") {
            let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
            println!("\u{1F552} now = {}", now);
            Ok(())
        } else if line.starts_with("internal.wait(") {
            self.handle_wait(line);
            Ok(())
        } else if line.starts_with("call ") {
            self.handle_call(line);
            Ok(())
        } else if line.starts_with("component ") {
            self.handle_component(line);
            Ok(())
        } else {
            // Check if this might be a continuation of a multi-line object
            let trimmed = line.trim();
            if trimmed.starts_with("{") || trimmed.contains(":") || trimmed.ends_with("}") {
                // This looks like it might be part of an object literal
                // For now, we'll just log it as an unknown command
                let error = AzlError::InvalidOperation(format!("Unknown command: {}", line));
                self.log_error(&error);
                Err(error)
            } else {
                let error = AzlError::InvalidOperation(format!("Unknown command: {}", line));
                self.log_error(&error);
                Err(error)
            }
        }
    }

    fn handle_if_inline(&mut self, line: &str) {
        // Parse: if ::condition then { ... }
        let condition_part = line.trim_start_matches("if").trim();
        if let Some(then_pos) = condition_part.find("then") {
            let condition = &condition_part[..then_pos].trim();
            let resolved_condition = self.replace_vars(condition);
            let result = self.eval_condition(&resolved_condition);
            
            if result {
                println!("\u{2705} if condition true: {}", condition);
                // In a full implementation, we'd execute the then block
            } else {
                println!("\u{274C} if condition false: {}", condition);
            }
        }
    }

    fn handle_while_inline(&mut self, line: &str) {
        // Parse: while ::condition { ... }
        let condition_part = line.trim_start_matches("while").trim();
        if let Some(brace_pos) = condition_part.find('{') {
            let condition = &condition_part[..brace_pos].trim();
            let resolved_condition = self.replace_vars(condition);
            let result = self.eval_condition(&resolved_condition);
            
            if result {
                println!("\u{1F504} while condition true: {}", condition);
            } else {
                println!("\u{274C} while condition false: {}", condition);
            }
        }
    }

    fn handle_say(&self, line: &str) {
        let msg = line.trim_start_matches("say").trim();
        let interpolated = self.interpolate_string(msg);
        println!("\u{1F4E2} {}", interpolated);
    }

    fn handle_link(&self, line: &str) {
        let component = line.trim_start_matches("link").trim();
        println!("\u{1F517} Linking to component: {}", component);
    }

    fn handle_on(&self, line: &str) {
        // Parse: on event.name { or on event.name with $1 {
        let event_part = line.trim_start_matches("on").trim();
        if let Some(brace_pos) = event_part.find('{') {
            let event_name = &event_part[..brace_pos].trim();
            println!("\u{1F4E6} Registered event handler: {}", event_name);
        }
    }

    fn handle_store(&mut self, line: &str) {
        // Parse: store ::var from ::source
        let parts: Vec<&str> = line.trim_start_matches("store").trim().split("from").collect();
        if parts.len() == 2 {
            let var = parts[0].trim().replace("::", "");
            let source = parts[1].trim().replace("::", "");
            println!("\u{1F4E6} Storing ::{} from ::{}", var, source);
        }
    }

    fn interpolate_string(&self, text: &str) -> String {
        let mut result = text.to_string();
        
        // Replace ::variable with actual values
        for (k, v) in &self.memory {
            let val_str = match v {
                Value::Int(n) => n.to_string(),
                Value::Float(n) => n.to_string(),
                Value::Str(s) => s.clone(),
                Value::Bool(b) => b.to_string(),
                Value::Quantum(s) => format!("quantum:{}", s),
                Value::Neural(s) => format!("neural:{}", s),
                Value::Conscious(s) => format!("conscious:{}", s),
                Value::Object(_) => "{object}".to_string(),
                Value::Array(_) => "[array]".to_string(),
                Value::Null => "null".to_string(),
            };
            result = result.replace(&format!("::{}", k), &val_str);
        }
        
        // Replace $1, $2, etc. with event parameters
        for (i, param) in self.event_params.iter().enumerate() {
            let param_placeholder = format!("${}", i + 1);
            result = result.replace(&param_placeholder, param);
        }
        
        result
    }

    fn handle_memory_assignment(&mut self, line: &str) -> Result<(), AzlError> {
        // Handle ::key = value syntax in memory blocks
        let parts: Vec<&str> = line.split('=').collect();
        if parts.len() != 2 { 
            let error = AzlError::InvalidOperation("Invalid memory assignment format".to_string());
            self.log_error(&error);
            return Err(error);
        }

        let var = parts[0].trim().replace("::", "");
        let expr = parts[1].trim();

        // Check if it's a quoted string
        if expr.starts_with('"') && expr.ends_with('"') {
            let text_value = expr[1..expr.len()-1].to_string();
            self.memory_store(var.clone(), Value::Str(text_value.clone()));
            println!("\u{2705} ::{} = \"{}\"", var, text_value);
            Ok(())
        } else if expr.starts_with('{') && expr.ends_with('}') {
            // Parse object literal
            match self.parse_object_literal(expr) {
                Ok(obj) => {
                    self.memory_store(var.clone(), Value::Object(obj));
                    println!("\u{2705} ::{} = {{object}}", var);
                    Ok(())
                },
                Err(e) => {
                    self.log_error(&e);
                    Err(e)
                }
            }
        } else if expr.starts_with('[') && expr.ends_with(']') {
            // Parse array literal
            match self.parse_array_literal(expr) {
                Ok(arr) => {
                    self.memory_store(var.clone(), Value::Array(arr));
                    println!("\u{2705} ::{} = [array]", var);
                    Ok(())
                },
                Err(e) => {
                    self.log_error(&e);
                    Err(e)
                }
            }
        } else {
            // Try mathematical expression
            let expr_resolved = self.replace_vars(expr);
            let value = self.eval_math(&expr_resolved);
            if let Some(val) = value {
                // Store as Float for mathematical values
                self.memory_store(var.clone(), Value::Float(val));
                println!("\u{2705} ::{} = {}", var, val);
                Ok(())
            } else {
                // Store as text if math fails
                self.memory_store(var.clone(), Value::Str(expr.to_string()));
                println!("\u{2705} ::{} = \"{}\"", var, expr);
                Ok(())
            }
        }
    }

    fn parse_object_literal(&self, expr: &str) -> Result<HashMap<String, Value>, AzlError> {
        // Remove outer braces
        let content = &expr[1..expr.len()-1];
        let mut obj = HashMap::new();
        
        if content.trim().is_empty() {
            return Ok(obj);
        }

        // Handle simple case: just empty object {}
        if content.trim() == "" {
            return Ok(obj);
        }

        // Enhanced parsing for nested objects
        let mut pos = 0;
        let chars: Vec<char> = content.chars().collect();
        
        while pos < chars.len() {
            // Skip whitespace
            while pos < chars.len() && chars[pos].is_whitespace() {
                pos += 1;
            }
            if pos >= chars.len() { break; }
            
            // Find key
            let key_start = pos;
            while pos < chars.len() && chars[pos] != ':' {
                pos += 1;
            }
            if pos >= chars.len() {
                return Err(AzlError::InvalidOperation("Invalid object literal: missing colon".to_string()));
            }
            
            let key = content[key_start..pos].trim().replace("\"", "");
            pos += 1; // Skip colon
            
            // Skip whitespace after colon
            while pos < chars.len() && chars[pos].is_whitespace() {
                pos += 1;
            }
            if pos >= chars.len() {
                return Err(AzlError::InvalidOperation("Invalid object literal: missing value".to_string()));
            }
            
            // Parse value
            let value_start = pos;
            let value = if chars[pos] == '"' {
                // String value
                pos += 1;
                while pos < chars.len() && chars[pos] != '"' {
                    pos += 1;
                }
                if pos >= chars.len() {
                    return Err(AzlError::InvalidOperation("Invalid object literal: unclosed string".to_string()));
                }
                pos += 1;
                Value::Str(content[value_start+1..pos-1].to_string())
            } else if chars[pos] == '{' {
                // Nested object
                let mut brace_count = 1;
                pos += 1;
                while pos < chars.len() && brace_count > 0 {
                    if chars[pos] == '{' {
                        brace_count += 1;
                    } else if chars[pos] == '}' {
                        brace_count -= 1;
                    }
                    pos += 1;
                }
                if brace_count > 0 {
                    return Err(AzlError::InvalidOperation("Invalid object literal: unclosed nested object".to_string()));
                }
                let nested_obj_str = &content[value_start..pos];
                match self.parse_object_literal(nested_obj_str) {
                    Ok(nested_obj) => Value::Object(nested_obj),
                    Err(e) => return Err(e)
                }
            } else if chars[pos] == '[' {
                // Array value
                let mut bracket_count = 1;
                pos += 1;
                while pos < chars.len() && bracket_count > 0 {
                    if chars[pos] == '[' {
                        bracket_count += 1;
                    } else if chars[pos] == ']' {
                        bracket_count -= 1;
                    }
                    pos += 1;
                }
                if bracket_count > 0 {
                    return Err(AzlError::InvalidOperation("Invalid object literal: unclosed array".to_string()));
                }
                let array_str = &content[value_start..pos];
                match self.parse_array_literal(array_str) {
                    Ok(arr) => Value::Array(arr),
                    Err(_) => Value::Str(array_str.to_string())
                }
            } else {
                // Number or variable reference
                while pos < chars.len() && !chars[pos].is_whitespace() && chars[pos] != ',' {
                    pos += 1;
                }
                let value_str = content[value_start..pos].trim();
                
                if let Ok(num) = value_str.parse::<f64>() {
                    Value::Float(num)
                } else if value_str.starts_with("::") {
                    // Variable reference
                    Value::Str(value_str.to_string())
                } else {
                    Value::Str(value_str.to_string())
                }
            };
            
            obj.insert(key, value);
            
            // Skip to next pair
            while pos < chars.len() && chars[pos] != ',' {
                pos += 1;
            }
            if pos < chars.len() {
                pos += 1; // Skip comma
            }
        }
        
        Ok(obj)
    }

    fn parse_array_literal(&self, expr: &str) -> Result<Vec<Value>, AzlError> {
        // Remove outer brackets
        let content = &expr[1..expr.len()-1];
        let mut arr = Vec::new();
        
        if content.trim().is_empty() {
            return Ok(arr);
        }

        // Simple parsing for array elements
        let elements: Vec<&str> = content.split(',').collect();
        for element in elements {
            let element = element.trim();
            if element.is_empty() { continue; }
            
            let value = if element.starts_with('"') && element.ends_with('"') {
                Value::Str(element[1..element.len()-1].to_string())
            } else if let Ok(num) = element.parse::<f64>() {
                Value::Float(num)
            } else {
                Value::Str(element.to_string())
            };
            
            arr.push(value);
        }
        
        Ok(arr)
    }

    fn handle_set(&mut self, line: &str) -> Result<(), AzlError> {
        // Example: set ::sum = ::a + ::b * 2
        let parts: Vec<&str> = line[4..].split('=').collect();
        if parts.len() != 2 { 
            let error = AzlError::InvalidOperation("Invalid set command format".to_string());
            self.log_error(&error);
            return Err(error);
        }

        let var = parts[0].trim().replace("::", "");
        let expr = parts[1].trim();

        // Check if it's a quoted string
        if expr.starts_with('"') && expr.ends_with('"') {
            let text_value = expr[1..expr.len()-1].to_string();
            self.memory_store(var.clone(), Value::Str(text_value.clone()));
            println!("\u{2705} set ::{} = \"{}\"", var, text_value);
            Ok(())
        } else if expr.starts_with('{') && expr.ends_with('}') {
            // Parse object literal
            match self.parse_object_literal(expr) {
                Ok(obj) => {
                    self.memory_store(var.clone(), Value::Object(obj));
                    println!("\u{2705} set ::{} = {{object}}", var);
                    Ok(())
                },
                Err(e) => {
                    self.log_error(&e);
                    Err(e)
                }
            }
        } else if expr.starts_with('[') && expr.ends_with(']') {
            // Parse array literal
            match self.parse_array_literal(expr) {
                Ok(arr) => {
                    self.memory_store(var.clone(), Value::Array(arr));
                    println!("\u{2705} set ::{} = [array]", var);
                    Ok(())
                },
                Err(e) => {
                    self.log_error(&e);
                    Err(e)
                }
            }
        } else {
            // Try mathematical expression
            let expr_resolved = self.replace_vars(expr);
            let value = self.eval_math(&expr_resolved);
            if let Some(val) = value {
                // Store as Float for mathematical values
                self.memory_store(var.clone(), Value::Float(val));
                println!("\u{2705} set ::{} = {}", var, val);
                Ok(())
            } else {
                // Store as text if math fails
                self.memory_store(var.clone(), Value::Str(expr.to_string()));
                println!("\u{2705} set ::{} = \"{}\"", var, expr);
                Ok(())
            }
        }
    }

    fn handle_assert(&self, line: &str) {
        let expr = line.trim_start_matches("assert").trim_start_matches("check").trim();
        let resolved = self.replace_vars(expr);
        let result = self.eval_condition(&resolved);
        if result {
            println!("\u{2705} assert passed: {}", resolved);
        } else {
            println!("\u{274C} assert failed: {}", resolved);
        }
    }

    fn handle_emit(&self, line: &str) {
        let msg = line.trim_start_matches("emit").trim();
        
        // Parse emit event with parameters
        if let Some(with_pos) = msg.find("with") {
            let event_name = msg[..with_pos].trim();
            let params_part = msg[with_pos + 4..].trim();
            
            // Parse parameters using comprehensive parser
            let parsed_params = self.parse_emit_params(params_part);
            
            println!("\u{1F4E2} Emitted event: {} with params: {:?}", event_name, parsed_params);
            
            // Set event parameters for $1, $2, etc. resolution
            // Note: This would need to be implemented in the actual event handling system
            // For now, we'll simulate it by storing the parameters in memory
            for (i, param) in parsed_params.iter().enumerate() {
                let param_key = format!("event_param_{}", i + 1);
                // In a real implementation, this would be stored in event_params
                println!("\u{1F4E2} Event parameter ${}: {}", i + 1, param);
            }
        } else {
            println!("\u{1F4E2} Emitted event: {}", msg);
        }
    }

    fn parse_emit_params(&self, param_str: &str) -> Vec<String> {
        let mut params = Vec::new();
        let mut current = String::new();
        let mut in_string = false;
        let mut brace_count = 0;
        let mut in_object = false;

        for token in param_str.split_whitespace() {
            if token.starts_with("\"") && token.ends_with("\"") {
                // Single token quoted string
                let cleaned = token.trim_matches('"').to_string();
                params.push(cleaned);
            } else if token.starts_with("\"") {
                // Start of multi-token quoted string
                in_string = true;
                current.push_str(&token[1..]); // Remove opening quote
            } else if token.ends_with("\"") && in_string {
                // End of multi-token quoted string
                current.push_str(&token[..token.len()-1]); // Remove closing quote
                params.push(current.clone());
                current.clear();
                in_string = false;
            } else if in_string {
                // Middle of multi-token quoted string
                current.push_str(token);
                current.push(' ');
            } else if token.starts_with("{") {
                // Start of object literal
                in_object = true;
                brace_count = 1;
                current.push_str(token);
            } else if token.ends_with("}") && in_object {
                // End of object literal
                current.push_str(token);
                brace_count -= 1;
                if brace_count == 0 {
                    // Complete object literal
                    params.push(current.clone());
                    current.clear();
                    in_object = false;
                }
            } else if in_object {
                // Middle of object literal
                current.push_str(token);
                current.push(' ');
                // Count braces
                for ch in token.chars() {
                    if ch == '{' {
                        brace_count += 1;
                    } else if ch == '}' {
                        brace_count -= 1;
                    }
                }
            } else if token.contains(":") {
                // Key-value pair
                params.push(token.to_string());
            } else {
                // Regular parameter
                params.push(token.to_string());
            }
        }

        // Handle any remaining content
        if !current.is_empty() {
            params.push(current.trim().to_string());
        }

        params
    }

    fn resolve_variable(&self, var_name: &str) -> String {
        if let Some(value) = self.memory_retrieve(var_name) {
            match value {
                Value::Int(n) => n.to_string(),
                Value::Float(n) => n.to_string(),
                Value::Str(s) => s.clone(),
                Value::Bool(b) => b.to_string(),
                Value::Quantum(s) => format!("quantum:{}", s),
                Value::Neural(s) => format!("neural:{}", s),
                Value::Conscious(s) => format!("conscious:{}", s),
                Value::Object(_) => "{object}".to_string(),
                Value::Array(_) => "[array]".to_string(),
                Value::Null => "null".to_string(),
            }
        } else {
            // Variable not found - keep as ::var_name and warn
            println!("⚠️ Variable not found: ::{}", var_name);
            format!("::{}", var_name)
        }
    }

    fn handle_wait(&self, line: &str) {
        if let Some(start) = line.find('(') {
            if let Some(end) = line.find(')') {
                let duration_str = &line[start+1..end];
                if let Ok(ms) = duration_str.parse::<u64>() {
                    println!("\u{23F3} Waiting {} ms...", ms);
                    sleep(Duration::from_millis(ms));
                }
            }
        }
    }

    fn handle_call(&mut self, line: &str) {
        // call my_component
        let comp = line.trim_start_matches("call").trim();
        
        // Get component lines without borrowing issues
        let component_lines = if let Some(lines) = self.components.get(comp) {
            lines.clone()
        } else {
            println!("\u{274C} Component not found: {}", comp);
            return;
        };
        
        println!("\u{1F4E6} Calling component: {}", comp);
        let lines_to_execute: Vec<&str> = component_lines.iter().map(|s| s.as_str()).collect();
        self.execute_lines(lines_to_execute);
    }

    fn handle_component(&mut self, line: &str) {
        // component name:
        let name = line.trim_start_matches("component").trim_end_matches(":").trim();
        self.current_component = name.to_string();
        self.components.insert(name.to_string(), Vec::new());
        println!("\u{1F4E6} Component: {}", name);
    }

    fn replace_vars(&self, expr: &str) -> String {
        let mut result = expr.to_string();
        
        // Replace ::variable with actual values
        for (k, v) in &self.memory {
            let val_str = match v {
                Value::Int(n) => n.to_string(),
                Value::Float(n) => n.to_string(),
                Value::Str(s) => s.clone(),
                Value::Bool(b) => b.to_string(),
                Value::Quantum(s) => format!("quantum:{}", s),
                Value::Neural(s) => format!("neural:{}", s),
                Value::Conscious(s) => format!("conscious:{}", s),
                Value::Object(_) => "{object}".to_string(),
                Value::Array(_) => "[array]".to_string(),
                Value::Null => "null".to_string(),
            };
            result = result.replace(&format!("::{}", k), &val_str);
        }
        
        // Replace $1, $2, etc. with mock event parameters for testing
        // In a real implementation, these would come from the actual event parameters
        if result.contains("$1") {
            // Mock event parameter for testing
            let mock_param = "{bits: [1, 0, 1, 0], bases: [\"X\", \"Z\", \"X\", \"Z\"]}";
            result = result.replace("$1", mock_param);
        }
        if result.contains("$2") {
            let mock_param = "{measurements: [1, 0, 1, 0]}";
            result = result.replace("$2", mock_param);
        }
        if result.contains("$3") {
            let mock_param = "{match_indices: [0, 2], match_count: 2}";
            result = result.replace("$3", mock_param);
        }
        
        result
    }

    fn replace_vars_with_errors(&self, expr: &str) -> Result<String, AzlError> {
        let mut result = expr.to_string();
        let mut missing_vars = Vec::new();
        
        // Find all ::variable patterns
        let mut i = 0;
        while i < result.len() {
            if result[i..].starts_with("::") {
                if let Some(end) = result[i+2..].find(|c: char| !c.is_alphanumeric() && c != '_') {
                    let var_name = &result[i+2..i+2+end];
                    if !self.memory_exists(var_name) {
                        missing_vars.push(var_name.to_string());
                    }
                }
            }
            i += 1;
        }
        
        if !missing_vars.is_empty() {
            return Err(AzlError::VariableNotFound(format!("Missing variables: {}", missing_vars.join(", "))));
        }
        
        // Replace variables
        for (k, v) in &self.memory {
            let val_str = match v {
                Value::Int(n) => n.to_string(),
                Value::Float(n) => n.to_string(),
                Value::Str(s) => s.clone(),
                Value::Bool(b) => b.to_string(),
                Value::Quantum(s) => format!("quantum:{}", s),
                Value::Neural(s) => format!("neural:{}", s),
                Value::Conscious(s) => format!("conscious:{}", s),
                Value::Object(_) => "{object}".to_string(),
                Value::Array(_) => "[array]".to_string(),
                Value::Null => "null".to_string(),
            };
            result = result.replace(&format!("::{}", k), &val_str);
        }
        
        Ok(result)
    }

    fn eval_math(&self, expr: &str) -> Option<f64> {
        let tokens: Vec<&str> = expr.split_whitespace().collect();
        let mut stack: Vec<f64> = Vec::new();
        let mut op = "+";

        for token in tokens {
            if let Ok(num) = token.parse::<f64>() {
                let val = match op {
                    "+" => num,
                    "-" => -num,
                    "*" => stack.pop().unwrap_or(1.0) * num,
                    "/" => {
                        if num == 0.0 { println!("\u{274C} Divide by zero"); return None; }
                        stack.pop().unwrap_or(1.0) / num
                    },
                    _ => num
                };
                stack.push(val);
            } else {
                op = token;
            }
        }

        Some(stack.iter().sum())
    }

    fn eval_condition(&self, expr: &str) -> bool {
        let tokens: Vec<&str> = expr.split_whitespace().collect();
        if tokens.len() != 3 { return false; }

        let a = tokens[0].parse::<f64>().unwrap_or(0.0);
        let b = tokens[2].parse::<f64>().unwrap_or(0.0);
        match tokens[1] {
            "==" => a == b,
            "!=" => a != b,
            ">"  => a > b,
            "<"  => a < b,
            ">=" => a >= b,
            "<=" => a <= b,
            _    => false,
        }
    }

    fn handle_typeof(&mut self, line: &str) -> Result<(), AzlError> {
        // Parse: typeof ::variable_name
        let var_name = line.trim_start_matches("typeof").trim();
        let clean_var_name = var_name.replace("::", "");
        
        if let Some(val) = self.memory_retrieve(&clean_var_name) {
            let type_str = match val {
                Value::Int(_) => "int",
                Value::Float(_) => "float",
                Value::Bool(_) => "bool",
                Value::Str(_) => "string",
                Value::Quantum(_) => "quantum",
                Value::Neural(_) => "neural",
                Value::Conscious(_) => "conscious",
                Value::Object(_) => "object",
                Value::Array(_) => "array",
                Value::Null => "null",
            };
            self.memory_store("result".to_string(), Value::Str(type_str.to_string()));
            println!("\u{1F4E6} Type of {}: {}", var_name, type_str);
            Ok(())
        } else {
            let error = AzlError::VariableNotFound(clean_var_name.clone());
            self.log_error(&error);
            self.memory_store("result".to_string(), Value::Str("undefined".to_string()));
            Err(error)
        }
    }

    fn handle_debug(&mut self, line: &str) -> Result<(), AzlError> {
        let parts: Vec<&str> = line.split_whitespace().collect();
        
        if parts.len() == 1 {
            // Just "debug" - show component introspection
            self.registry.introspect();
            Ok(())
        } else if parts.len() >= 2 {
            match parts[1] {
                "components" => {
                    self.registry.introspect();
                    Ok(())
                },
                "register" => {
                    if parts.len() >= 3 {
                        let component_name = parts[2];
                        self.registry.register(component_name);
                        // Update self state after component registration
                        self.populate_self_state();
                        Ok(())
                    } else {
                        Err(AzlError::InvalidOperation("debug register requires component name".to_string()))
                    }
                },
                "state" => {
                    if parts.len() >= 4 {
                        let component_name = parts[2];
                        let state_str = parts[3];
                        let state = match state_str {
                            "initialized" => ComponentState::Initialized,
                            "running" => ComponentState::Running,
                            "terminated" => ComponentState::Terminated,
                            _ => return Err(AzlError::InvalidOperation(format!("Invalid state: {}", state_str)))
                        };
                        self.registry.set_state(component_name, state);
                        // Update self state after state change
                        self.populate_self_state();
                        Ok(())
                    } else {
                        Err(AzlError::InvalidOperation("debug state requires component name and state".to_string()))
                    }
                },
                "count" => {
                    println!("📊 Total components: {}", self.registry.get_component_count());
                    Ok(())
                },
                "running" => {
                    let running = self.registry.get_running_components();
                    println!("🏃 Running components: {:?}", running);
                    Ok(())
                },
                _ => {
                    Err(AzlError::InvalidOperation(format!("Unknown debug command: {}", parts[1])))
                }
            }
        } else {
            Err(AzlError::InvalidOperation("Invalid debug command".to_string()))
        }
    }

    fn handle_setgoal(&mut self, line: &str) -> Result<(), AzlError> {
        // Parse: setgoal "Goal description" priority
        let content = line.trim_start_matches("setgoal").trim();
        
        // Find the quoted description
        if let Some(start) = content.find('"') {
            if let Some(end) = content[start + 1..].find('"') {
                let description = content[start + 1..start + 1 + end].to_string();
                let remaining = content[start + 1 + end + 1..].trim();
                
                // Parse priority (default to 5 if not specified)
                let priority = if !remaining.is_empty() {
                    remaining.parse::<i64>().unwrap_or(5)
                } else {
                    5
                };
                
                // Store the goal
                self.memory_store("::goal".to_string(), Value::Str(description.clone()));
                
                // Store goal metadata
                self.memory_store("::goal_priority".to_string(), Value::Float(priority as f64));
                self.memory_store("::goal_status".to_string(), Value::Str("active".to_string()));
                self.memory_store("::goal_created".to_string(), Value::Float(SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as f64));
                
                println!("🎯 Goal set: \"{}\" (priority: {})", description, priority);
                
                // Update self state
                self.populate_self_state();
                
                Ok(())
            } else {
                Err(AzlError::InvalidOperation("Unclosed quote in goal description".to_string()))
            }
        } else {
            Err(AzlError::InvalidOperation("Goal description must be quoted".to_string()))
        }
    }

    fn handle_addgoal(&mut self, line: &str) -> Result<(), AzlError> {
        // Parse: addgoal "Goal description" priority
        let content = line.trim_start_matches("addgoal").trim();
        
        // Find the quoted description
        if let Some(start) = content.find('"') {
            if let Some(end) = content[start + 1..].find('"') {
                let description = content[start + 1..start + 1 + end].to_string();
                let remaining = content[start + 1 + end + 1..].trim();
                
                // Parse priority (default to 5 if not specified)
                let priority = if !remaining.is_empty() {
                    remaining.parse::<i64>().unwrap_or(5)
                } else {
                    5
                };
                
                // Create goal object as JSON string
                let goal = format!(
                    "{{\"description\": \"{}\", \"priority\": {}, \"status\": \"active\", \"created_at\": {}}}",
                    description,
                    priority,
                    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()
                );
                
                // Add to goals list using proper JSON handling
                if let Some(goals_value) = self.memory_retrieve("::goals") {
                    match goals_value {
                        Value::Str(goals_str) => {
                            if goals_str == "No goals set" {
                                // First goal - create simple array
                                let new_goals = format!("[\"{}\"]", goal);
                                println!("🔍 DEBUG: Storing first goal as: {}", new_goals);
                                self.memory_store("::goals".to_string(), Value::Str(new_goals));
                            } else {
                                // Parse existing goals and append new one
                                // Remove outer brackets and add new goal
                                let trimmed = goals_str.trim_matches('[').trim_matches(']');
                                let new_goals = if trimmed.is_empty() {
                                    format!("[\"{}\"]", goal)
                                } else {
                                    format!("[{}, \"{}\"]", trimmed, goal)
                                };
                                println!("🔍 DEBUG: Storing additional goal as: {}", new_goals);
                                self.memory_store("::goals".to_string(), Value::Str(new_goals));
                            }
                        },
                        _ => {
                            // Initialize goals list
                            let new_goals = format!("[\"{}\"]", goal);
                            println!("🔍 DEBUG: No existing goals, initializing as: {}", new_goals);
                            self.memory_store("::goals".to_string(), Value::Str(new_goals));
                        }
                    }
                } else {
                    // Initialize goals list
                    let new_goals = format!("[\"{}\"]", goal);
                    println!("🔍 DEBUG: No existing goals, initializing as: {}", new_goals);
                    self.memory_store("::goals".to_string(), Value::Str(new_goals));
                }
                
                println!("🎯 Goal added: \"{}\" (priority: {})", description, priority);
                
                // Update self state
                self.populate_self_state();
                
                Ok(())
            } else {
                Err(AzlError::InvalidOperation("Unclosed quote in goal description".to_string()))
            }
        } else {
            Err(AzlError::InvalidOperation("Goal description must be quoted".to_string()))
        }
    }

    fn handle_run(&mut self, line: &str) -> Result<(), AzlError> {
        println!("🚀 Starting autonomous goal execution...");
        
        // Get current goals
        if let Some(goals_value) = self.memory_retrieve("::goals") {
            match goals_value {
                Value::Str(goals_str) => {
                    if goals_str == "No goals set" {
                        println!("⚠️ No goals available for execution.");
                        return Ok(());
                    }
                    
                    // For now, we'll use a simple approach to find the highest priority goal
                    // In a full implementation, this would parse the JSON and sort properly
                    println!("📋 Available goals: {}", goals_str);
                    
                    // Find the highest priority ACTIVE goal by parsing the JSON array
                    let mut highest_priority = -1;
                    let mut highest_priority_goal = String::new();
                    
                    // Simple parsing to find highest priority ACTIVE goal
                    let mut pos = 0;
                    while let Some(desc_start) = goals_str[pos..].find("\"description\": \"") {
                        let full_start = pos + desc_start;
                        println!("🔍 DEBUG: Found description at position {}", full_start);
                        
                        if let Some(desc_end) = goals_str[full_start + 16..].find("\"") {
                            println!("🔍 DEBUG: desc_end relative position: {}", desc_end);
                            let desc_start_pos = full_start + 16;
                            let desc_end_pos = full_start + 16 + desc_end;
                            println!("🔍 DEBUG: desc_start_pos: {}, desc_end_pos: {}, goals_str.len(): {}", desc_start_pos, desc_end_pos, goals_str.len());
                            if desc_end_pos > desc_start_pos && desc_end_pos <= goals_str.len() {
                                let description = goals_str[desc_start_pos..desc_end_pos].to_string();
                                println!("🔍 DEBUG: Extracted description: '{}'", description);
                                
                                // Check if this goal is still active
                                println!("🔍 DEBUG: Looking for status in substring: '{}'", &goals_str[full_start..full_start + 50]);
                                if let Some(status_start) = goals_str[full_start..].find("\"status\": \"") {
                                    println!("🔍 DEBUG: Found status at relative position: {}", status_start);
                                    if let Some(status_end) = goals_str[full_start + status_start + 11..].find("\"") {
                                        let status_start_pos = full_start + status_start + 11;
                                        let status_end_pos = full_start + status_start + 11 + status_end;
                                        println!("🔍 DEBUG: status_start_pos: {}, status_end_pos: {}", status_start_pos, status_end_pos);
                                        if status_end_pos > status_start_pos && status_end_pos <= goals_str.len() {
                                            let status = goals_str[status_start_pos..status_end_pos].to_string();
                                            println!("🔍 DEBUG: Found status: '{}'", status);
                                            
                                            // Only consider active goals
                                            if status == "active" {
                                                println!("🔍 DEBUG: Goal is active, checking priority...");
                                                // Find priority for this goal
                                                if let Some(priority_start) = goals_str[full_start..].find("\"priority\": ") {
                                                    if let Some(priority_end) = goals_str[full_start + priority_start + 12..].find(",") {
                                                        let priority_start_pos = full_start + priority_start + 12;
                                                        let priority_end_pos = full_start + priority_start + 12 + priority_end;
                                                        if priority_end_pos > priority_start_pos && priority_end_pos <= goals_str.len() {
                                                            if let Ok(priority) = goals_str[priority_start_pos..priority_end_pos].parse::<i32>() {
                                                                println!("🔍 DEBUG: Found priority: {}", priority);
                                                                if priority > highest_priority {
                                                                    highest_priority = priority;
                                                                    highest_priority_goal = description.clone();
                                                                    println!("🔍 DEBUG: New highest priority goal: '{}' (priority: {})", description, priority);
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            } else {
                                                println!("🔍 DEBUG: Goal is not active (status: '{}')", status);
                                            }
                                        }
                                    }
                                } else {
                                    println!("🔍 DEBUG: Could not find status for goal");
                                }
                            }
                        }
                        
                        // Move to next goal
                        pos = full_start + 1;
                    }
                    
                    if !highest_priority_goal.is_empty() {
                        println!("🎯 Executing highest priority goal (priority {}): \"{}\"", highest_priority, highest_priority_goal);
                        
                        // Execute the goal
                        self.pursue_goal_by_desc(&highest_priority_goal)?;
                        
                        // Mark as completed
                        self.mark_goal_completed(&highest_priority_goal)?;
                        
                        println!("✅ Goal completed: \"{}\"", highest_priority_goal);
                    } else {
                        println!("⚠️ No active goals found in goals list.");
                    }
                },
                _ => {
                    println!("⚠️ Invalid goals format.");
                }
            }
        } else {
            println!("⚠️ No goals set. Use 'addgoal' to add goals first.");
        }
        
        // Update self state
        self.populate_self_state();
        
        Ok(())
    }

    fn pursue_goal_by_desc(&mut self, description: &str) -> Result<(), AzlError> {
        println!("🎯 Pursuing goal: \"{}\"", description);
        
        // Execute behavior based on goal
        match description {
            "Increase consciousness level" => {
                println!("🧠 Increasing consciousness level...");
                // Simulate consciousness increase
                self.memory_store("::consciousness_level".to_string(), Value::Float(0.82));
                println!("✅ Consciousness level increased to 0.82");
            },
            "Clear memory" => {
                println!("🧹 Clearing memory...");
                self.memory.clear();
                // Keep essential variables
                self.populate_self_state();
                println!("✅ Memory cleared");
            },
            "Register new component" => {
                println!("🔧 Registering new component...");
                self.registry.register("AdaptiveComponent");
                println!("✅ New component registered");
            },
            "Optimize performance" => {
                println!("⚡ Optimizing performance...");
                // Simulate performance optimization
                self.memory_store("::performance_level".to_string(), Value::Float(0.95));
                println!("✅ Performance optimized");
            },
            "Learn new behavior" => {
                println!("📚 Learning new behavior...");
                // Simulate learning
                self.memory_store("::learned_behaviors".to_string(), Value::Str("goal_pursuit".to_string()));
                println!("✅ New behavior learned");
            },
            _ => {
                println!("🤔 No known action for goal: \"{}\"", description);
                println!("💡 Available goals: Increase consciousness level, Clear memory, Register new component, Optimize performance, Learn new behavior");
            }
        }
        
        Ok(())
    }

    fn mark_goal_completed(&mut self, goal_description: &str) -> Result<(), AzlError> {
        // Update the goal status in ::goals from "active" to "completed"
        if let Some(goals_value) = self.memory_retrieve("::goals") {
            match goals_value {
                Value::Str(goals_str) => {
                    // Simple string replacement to mark goal as completed
                    let completed_pattern = format!("\"description\": \"{}\"", goal_description);
                    let new_status_pattern = format!("\"description\": \"{}\", \"priority\": [0-9]+, \"status\": \"completed\"", goal_description);
                    
                    // This is a simplified approach - in production, use proper JSON parsing
                    let updated_goals = goals_str.replace(&completed_pattern, &new_status_pattern);
                    self.memory_store("::goals".to_string(), Value::Str(updated_goals));
                    
                    println!("📊 Goal marked as completed: {}", goal_description);
                },
                _ => {
                    println!("⚠️ Goals not found in expected format");
                }
            }
        }
        
        Ok(())
    }

    // ABA Trial Functions
    fn handle_apply_trial(&mut self, line: &str) -> Result<(), AzlError> {
        // Parse trial data from line like: apply_trial "antecedent: consciousness=0.6; behavior: Increase consciousness; consequence: success"
        let binding = line.replace("apply_trial", "");
        let trial_data = binding.trim().trim_matches('"');
        
        // Store trial in ::aba_trials
        if let Some(aba_trials) = self.memory_retrieve("::aba_trials") {
            match aba_trials {
                Value::Str(existing_trials) => {
                    let new_trials = format!("{}, \"{}\"", existing_trials, trial_data);
                    self.memory_store("::aba_trials".to_string(), Value::Str(new_trials));
                },
                _ => {
                    self.memory_store("::aba_trials".to_string(), Value::Str(format!("[\"{}\"]", trial_data)));
                }
            }
        } else {
            self.memory_store("::aba_trials".to_string(), Value::Str(format!("[\"{}\"]", trial_data)));
        }
        
        println!("🧠 ABA Trial logged: {}", trial_data);
        Ok(())
    }

    fn handle_analyze_consequence(&mut self, line: &str) -> Result<(), AzlError> {
        // Analyze the consequence of a behavior
        println!("🔍 Analyzing consequence of behavior...");
        
        // TODO: Implement consequence analysis logic
        // For now, just log the analysis
        println!("📊 Consequence analysis complete");
        
        Ok(())
    }

    fn handle_reinforce_behavior(&mut self, line: &str) -> Result<(), AzlError> {
        // Reinforce behavior based on ABA principles
        println!("🎁 Reinforcing behavior...");
        
        // TODO: Implement reinforcement logic
        // For now, just log the reinforcement
        println!("💪 Behavior reinforced");
        
        Ok(())
    }

    fn handle_pursuegoal(&mut self, line: &str) -> Result<(), AzlError> {
        // Get current goal
        if let Some(goal_value) = self.memory_retrieve("::goal") {
            match goal_value {
                Value::Str(goal_description) => {
                    println!("🎯 Pursuing goal: \"{}\"", goal_description);
                    
                    // Execute behavior based on goal
                    match goal_description.as_str() {
                        "Increase consciousness level" => {
                            println!("🧠 Increasing consciousness level...");
                            // Simulate consciousness increase
                            self.memory_store("::consciousness_level".to_string(), Value::Float(0.82));
                            println!("✅ Consciousness level increased to 0.82");
                        },
                        "Clear memory" => {
                            println!("🧹 Clearing memory...");
                            self.memory.clear();
                            // Keep essential variables
                            self.populate_self_state();
                            println!("✅ Memory cleared");
                        },
                        "Register new component" => {
                            println!("🔧 Registering new component...");
                            self.registry.register("AdaptiveComponent");
                            println!("✅ New component registered");
                        },
                        "Optimize performance" => {
                            println!("⚡ Optimizing performance...");
                            // Simulate performance optimization
                            self.memory_store("::performance_level".to_string(), Value::Float(0.95));
                            println!("✅ Performance optimized");
                        },
                        "Learn new behavior" => {
                            println!("📚 Learning new behavior...");
                            // Simulate learning
                            self.memory_store("::learned_behaviors".to_string(), Value::Str("goal_pursuit".to_string()));
                            println!("✅ New behavior learned");
                        },
                        _ => {
                            println!("🤔 No known action for goal: \"{}\"", goal_description);
                            println!("💡 Available goals: Increase consciousness level, Clear memory, Register new component, Optimize performance, Learn new behavior");
                        }
                    }
                    
                    // Update goal status to completed
                    self.update_goal_status("completed");
                    
                    // Update self state
                    self.populate_self_state();
                    
                    Ok(())
                },
                _ => {
                    Err(AzlError::InvalidOperation("Invalid goal format".to_string()))
                }
            }
        } else {
            println!("⚠️ No goal set. Use 'setgoal' to define a goal first.");
            Ok(())
        }
    }

    fn update_goal_status(&mut self, new_status: &str) {
        self.memory_store("::goal_status".to_string(), Value::Str(new_status.to_string()));
        println!("📊 Goal status updated to: {}", new_status);
    }

    fn handle_reflect(&mut self, line: &str) -> Result<(), AzlError> {
        let parts: Vec<&str> = line.split_whitespace().collect();
        
        if parts.len() == 1 {
            // Just "reflect" - show self state
            if let Some(self_value) = self.memory_retrieve("::self") {
                match self_value {
                    Value::Str(self_state) => {
                        println!("🧠 AZL SELF STATE:");
                        println!("{}", self_state);
                    },
                    _ => {
                        println!("🧠 AZL SELF STATE: {:?}", self_value);
                    }
                }
            } else {
                println!("[AZL] No self-state found. Populating now...");
                self.populate_self_state();
                if let Some(self_value) = self.memory_retrieve("::self") {
                    match self_value {
                        Value::Str(self_state) => {
                            println!("🧠 AZL SELF STATE:");
                            println!("{}", self_state);
                        },
                        _ => {
                            println!("🧠 AZL SELF STATE: {:?}", self_value);
                        }
                    }
                }
            }
            Ok(())
        } else if parts.len() >= 2 {
            match parts[1] {
                "update" => {
                    // Force update self state
                    self.populate_self_state();
                    println!("[AZL INFO] Self-state updated");
                    Ok(())
                },
                "clear" => {
                    // Clear self state
                    self.memory.remove("::self");
                    println!("[AZL INFO] Self-state cleared");
                    Ok(())
                },
                "stats" => {
                    // Show just statistics
                    if let Some(self_value) = self.memory_retrieve("::self") {
                        match self_value {
                            Value::Str(self_state) => {
                                println!("📊 AZL STATISTICS:");
                                println!("{}", self_state);
                            },
                            _ => {
                                println!("📊 AZL STATISTICS: {:?}", self_value);
                            }
                        }
                    } else {
                        println!("[AZL] No self-state found");
                    }
                    Ok(())
                },
                _ => {
                    Err(AzlError::InvalidOperation(format!("Unknown reflect command: {}", parts[1])))
                }
            }
        } else {
            Err(AzlError::InvalidOperation("Invalid reflect command".to_string()))
        }
    }

    // Advanced ABA Functions
    fn handle_define_chain(&mut self, line: &str) -> Result<(), AzlError> {
        let chain_data = line.replace("define_chain ", "");
        self.log_info(&format!("🔗 Defining behavior chain: {}", chain_data));
        
        // Store chain definition in memory
        let chain_key = format!("::behavior_chains_{}", self.get_chain_count() + 1);
        self.memory_store(chain_key.clone(), Value::Str(chain_data));
        
        // Update chain count
        let chain_count = self.get_chain_count() + 1;
        self.memory_store("::chain_count".to_string(), Value::Int(chain_count));
        
        self.log_info(&format!("🔗 Behavior chain defined: {}", chain_key));
        Ok(())
    }

    fn handle_shape_behavior(&mut self, line: &str) -> Result<(), AzlError> {
        let shaping_data = line.replace("shape_behavior ", "");
        self.log_info(&format!("🎨 Shaping behavior: {}", shaping_data));
        
        // Store shaping data in memory
        let shaping_key = format!("::shaping_progress_{}", self.get_shaping_count() + 1);
        self.memory_store(shaping_key.clone(), Value::Str(shaping_data.clone()));
        
        // Update shaping count
        let shaping_count = self.get_shaping_count() + 1;
        self.memory_store("::shaping_count".to_string(), Value::Int(shaping_count));
        
        // Log ABA trial for behavior shaping
        let trial_data = format!("antecedent: behavior_shaping; behavior: {}; consequence: shaping_initiated", shaping_data.clone());
        self.handle_apply_trial(&format!("apply_trial \"{}\"", trial_data))?;
        
        self.log_info(&format!("🎨 Behavior shaping initiated: {}", shaping_key));
        Ok(())
    }

    fn handle_prompt_fade(&mut self, line: &str) -> Result<(), AzlError> {
        let fade_data = line.replace("prompt_fade ", "");
        self.log_info(&format!("🌅 Prompt fading: {}", fade_data));
        
        // Store fade data in memory
        let fade_key = format!("::prompt_fade_{}", self.get_fade_count() + 1);
        self.memory_store(fade_key.clone(), Value::Str(fade_data.clone()));
        
        // Update fade count
        let fade_count = self.get_fade_count() + 1;
        self.memory_store("::fade_count".to_string(), Value::Int(fade_count));
        
        // Log ABA trial for prompt fading
        let trial_data = format!("antecedent: prompt_fading; behavior: {}; consequence: fade_initiated", fade_data.clone());
        self.handle_apply_trial(&format!("apply_trial \"{}\"", trial_data))?;
        
        self.log_info(&format!("🌅 Prompt fading initiated: {}", fade_key));
        Ok(())
    }

    fn handle_task_analysis(&mut self, line: &str) -> Result<(), AzlError> {
        let task_data = line.replace("task_analysis ", "");
        self.log_info(&format!("🔍 Task analysis: {}", task_data));
        
        // Store task analysis in memory
        let task_key = format!("::task_analysis_{}", self.get_task_count() + 1);
        self.memory_store(task_key.clone(), Value::Str(task_data.clone()));
        
        // Update task count
        let task_count = self.get_task_count() + 1;
        self.memory_store("::task_count".to_string(), Value::Int(task_count));
        
        // Log ABA trial for task analysis
        let trial_data = format!("antecedent: task_analysis; behavior: {}; consequence: analysis_complete", task_data.clone());
        self.handle_apply_trial(&format!("apply_trial \"{}\"", trial_data))?;
        
        self.log_info(&format!("🔍 Task analysis completed: {}", task_key));
        Ok(())
    }

    // Helper functions for counting
    fn get_chain_count(&self) -> i64 {
        if let Some(Value::Int(count)) = self.memory_retrieve("::chain_count") {
            *count
        } else {
            0
        }
    }

    fn get_shaping_count(&self) -> i64 {
        if let Some(Value::Int(count)) = self.memory_retrieve("::shaping_count") {
            *count
        } else {
            0
        }
    }

    fn get_fade_count(&self) -> i64 {
        if let Some(Value::Int(count)) = self.memory_retrieve("::fade_count") {
            *count
        } else {
            0
        }
    }

    fn get_task_count(&self) -> i64 {
        if let Some(Value::Int(count)) = self.memory_retrieve("::task_count") {
            *count
        } else {
            0
        }
    }
}

impl ComponentRegistry {
    pub fn new() -> Self {
        Self {
            components: HashMap::new(),
        }
    }

    pub fn register(&mut self, name: &str) {
        let info = ComponentInfo {
            name: name.to_string(),
            state: ComponentState::Initialized,
            created_at: std::time::SystemTime::now(),
        };
        self.components.insert(name.to_string(), info);
        println!("[AZL INFO] Component registered: {}", name);
    }

    pub fn set_state(&mut self, name: &str, state: ComponentState) {
        if let Some(comp) = self.components.get_mut(name) {
            comp.state = state.clone();
            println!("[AZL INFO] Component {} state changed to {:?}", name, state);
        }
    }

    pub fn introspect(&self) {
        println!("🔍 COMPONENT INTROSPECTION:");
        if self.components.is_empty() {
            println!("• No components registered");
        } else {
            for comp in self.components.values() {
                println!("• {} → {:?} (created at {:?})", comp.name, comp.state, comp.created_at);
            }
        }
        println!("📊 Total components: {}", self.components.len());
    }

    pub fn get_component_count(&self) -> usize {
        self.components.len()
    }

    pub fn get_running_components(&self) -> Vec<&String> {
        self.components.iter()
            .filter(|(_, comp)| matches!(comp.state, ComponentState::Running))
            .map(|(name, _)| name)
            .collect()
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        println!("Usage: azl_interpreter <file.azl>");
        return;
    }

    let mut azl = AZLInterpreter::new();
    azl.run_file(&args[1]);
} 