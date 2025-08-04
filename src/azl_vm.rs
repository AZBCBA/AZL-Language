// AZL v2 Virtual Machine
// Executes bytecode and manages runtime environment

use std::collections::HashMap;
use std::collections::VecDeque;
use std::path::PathBuf;
use std::rc::Rc;
use crate::azl_v2_compiler::{Stmt, Expr, TokenType, LiteralValue, FunctionRegistry, Value, Opcode, Token, Chunk, FunctionObj, ClosureObj};
use crate::azl_error::{AzlError, ErrorKind, ErrorContext, CallSite};
use crate::module::{ModuleResolver, ModuleAst, ModulePath};
use crate::module::resolver::ModuleOrigin;
use crate::module_loader::{ModuleResolver as OldModuleResolver, ModuleState};
use std::sync::{Arc, Mutex};
use std::hash::{Hash, Hasher};
use std::collections::hash_map::DefaultHasher;
use std::time::{SystemTime, UNIX_EPOCH};
use std::collections::HashMap as StdHashMap;

// ========================================
// DEBUGGING + DEV TOOLS STRUCTURES
// ========================================

#[derive(Debug, Clone)]
pub struct DebugInfo {
    pub line_number: usize,
    pub column: usize,
    pub function_name: String,
    pub instruction_count: usize,
    pub stack_depth: usize,
    pub variables: HashMap<String, Value>,
}

#[derive(Debug, Clone)]
pub struct StackFrame {
    pub function_name: String,
    pub return_address: usize,
    pub variables: HashMap<String, Value>,
    pub debug_info: DebugInfo,
}

#[derive(Debug, Clone)]
pub struct Breakpoint {
    pub line_number: usize,
    pub condition: Option<String>,
    pub enabled: bool,
    pub hit_count: usize,
}

#[derive(Debug, Clone)]
pub struct Profiler {
    pub function_times: HashMap<String, f64>,
    pub instruction_counts: HashMap<String, usize>,
    pub hot_functions: Vec<String>,
    pub total_execution_time: f64,
}

// ========================================
// ========== VIRTUAL MACHINE ===========
// ========================================

// ========================================
// ========== VIRTUAL MACHINE ===========
// ========================================

pub struct AzlVM {
    // Execution state
    stack: Vec<Value>,
    variables: HashMap<String, Value>,
    functions: HashMap<String, (Vec<String>, Vec<Opcode>)>,
    event_handlers: HashMap<String, (Vec<String>, Vec<Opcode>)>,
    
    // Function registry for dynamic function lookup
    function_registry: FunctionRegistry,
    
    // Program state
    bytecode: Vec<Opcode>,
    instruction_pointer: usize,
    
    // Call stack
    call_stack: VecDeque<CallFrame>,
    
    // Event system
    event_queue: VecDeque<Event>,
    event_handlers_registered: HashMap<String, Vec<usize>>,
    
    // Runtime state
    running: bool,
    error: Option<AzlError>,
    error_context_stack: Vec<ErrorContext>,
    // Module system
    modules: HashMap<String, ModuleState>,
    module_resolver: OldModuleResolver,
    new_module_resolver: ModuleResolver,
    
    // Debugging and Dev Tools
    debug_mode: bool,
    breakpoints: HashMap<usize, Breakpoint>,
    profiler: Profiler,
    instruction_trace: Vec<String>,
    variable_inspector: HashMap<String, Value>,
    call_history: Vec<String>,
    execution_start_time: SystemTime,
    current_line: usize,
    current_column: usize,
    source_map: HashMap<usize, (usize, usize)>, // instruction -> (line, column)
}

#[derive(Debug, Clone)]
struct CallFrame {
    function_name: String,
    return_address: usize,
    variables: HashMap<String, Value>,
    upvalues: Vec<Upvalue>, // Add upvalues to call frame
}

#[derive(Debug, Clone)]
struct Upvalue {
    index: usize,
    is_local: bool,
    value: Value,
}

#[derive(Debug, Clone)]
struct Closure {
    function_name: String,
    parameters: Vec<String>,
    body: Vec<Opcode>,
    upvalues: Vec<Upvalue>,
}

#[derive(Debug, Clone)]
struct Event {
    name: String,
    data: Value,
    source: String,
}

// ========================================
// ========== ENHANCED ERROR HANDLING ====
// ========================================

#[derive(Debug)]
pub struct VmError {
    pub message: String,
    pub module: String,
    pub line: u32,
    pub pc: usize,
    pub stack: Vec<CallSite>,
}

impl std::fmt::Display for VmError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "Error: {}", self.message)?;
        writeln!(f, "  at {}:{}: pc={:04}", self.module, self.line, self.pc)?;
        
        if !self.stack.is_empty() {
            writeln!(f, "  called from:")?;
            for (i, call_site) in self.stack.iter().enumerate() {
                if i == 0 {
                    writeln!(f, "    {} ({}:{})", call_site.function_name, call_site.line, call_site.column)?;
                } else {
                    writeln!(f, "    {} ({}:{})", call_site.function_name, call_site.line, call_site.column)?;
                }
            }
        }
        
        Ok(())
    }
}

impl std::error::Error for VmError {}

impl AzlVM {
    pub fn new() -> Self {
        let mut registry = FunctionRegistry::new();
        
        // Register built-in functions for VM
        Self::register_builtin_functions(&mut registry);
        
        let vm = AzlVM {
            stack: Vec::new(),
            variables: HashMap::new(),
            functions: HashMap::new(),
            event_handlers: HashMap::new(),
            function_registry: registry,
            bytecode: Vec::new(),
            instruction_pointer: 0,
            call_stack: VecDeque::new(),
            event_queue: VecDeque::new(),
            event_handlers_registered: HashMap::new(),
            running: false,
            error: None,
            error_context_stack: Vec::new(),
            modules: HashMap::new(),
            module_resolver: OldModuleResolver::new(),
            new_module_resolver: {
                let mut resolver = ModuleResolver::new();
                let filesystem_loader = crate::module::FilesystemModuleLoader::new();
                resolver.add_loader(Box::new(filesystem_loader));
                resolver
            },
            
            // Debugging and Dev Tools
            debug_mode: false,
            breakpoints: HashMap::new(),
            profiler: Profiler {
                function_times: HashMap::new(),
                instruction_counts: HashMap::new(),
                hot_functions: Vec::new(),
                total_execution_time: 0.0,
            },
            instruction_trace: Vec::new(),
            variable_inspector: HashMap::new(),
            call_history: Vec::new(),
            execution_start_time: SystemTime::now(),
            current_line: 0,
            current_column: 0,
            source_map: HashMap::new(),
        };
        println!("🆕 [VM Created] self.functions keys: {:?}", vm.functions.keys().collect::<Vec<_>>());
        vm
    }

    fn register_builtin_functions(registry: &mut FunctionRegistry) {
        let registry = registry;

        // Memory functions
        registry.register_namespace_function("memory.lha3", "store", |args| {
            if args.len() != 2 {
                return Err("memory.lha3.store requires exactly 2 arguments (key, value)".to_string());
            }
            let key = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.lha3.store key must be a string".to_string()),
            };
            let value = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.lha3.store value must be a string".to_string()),
            };
            // Simulate storage
            let mut result = HashMap::new();
            result.insert("type".to_string(), Value::String("memory_lha3_store".to_string()));
            result.insert("key".to_string(), Value::String(key));
            result.insert("value".to_string(), Value::String(value));
            result.insert("storage_success".to_string(), Value::Boolean(true));
            Ok(Value::Object(result))
        });

        registry.register_namespace_function("memory.lha3", "retrieve", |args| {
            if args.len() != 1 {
                return Err("memory.lha3.retrieve requires exactly 1 argument (key)".to_string());
            }
            let key = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.lha3.retrieve key must be a string".to_string()),
            };
            // Simulate retrieval
            let mut result = HashMap::new();
            result.insert("type".to_string(), Value::String("memory_lha3_retrieve".to_string()));
            result.insert("key".to_string(), Value::String(key));
            result.insert("retrieved_value".to_string(), Value::String("simulated_retrieved_value".to_string())); // Placeholder
            result.insert("retrieval_success".to_string(), Value::Boolean(true));
            Ok(Value::Object(result))
        });

        // Quantum functions
        registry.register_namespace_function("quantum", "superposition", |args| {
            if args.len() != 2 {
                return Err("quantum.superposition requires exactly 2 arguments (alpha, beta)".to_string());
            }
            let alpha = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("quantum.superposition alpha must be a number".to_string()),
            };
            let beta = match &args[1] {
                Value::Number(n) => *n,
                _ => return Err("quantum.superposition beta must be a number".to_string()),
            };
            // Simulate quantum superposition
            let mut result = HashMap::new();
            result.insert("type".to_string(), Value::String("quantum_superposition".to_string()));
            result.insert("alpha".to_string(), Value::Number(alpha));
            result.insert("beta".to_string(), Value::Number(beta));
            result.insert("superposition_success".to_string(), Value::Boolean(true));
            Ok(Value::Object(result))
        });

        registry.register_namespace_function("quantum", "measure", |args| {
            if args.len() != 1 {
                return Err("quantum.measure requires exactly 1 argument (state)".to_string());
            }
            // Simulate quantum measurement
            let mut result = HashMap::new();
            result.insert("type".to_string(), Value::String("quantum_measure".to_string()));
            result.insert("measured_state".to_string(), Value::Number(0.0)); // Simplified: always 0 for now
            result.insert("measurement_success".to_string(), Value::Boolean(true));
            Ok(Value::Object(result))
        });

        // Neural functions
        registry.register_namespace_function("neural", "forward_pass", |args| {
            if args.len() != 1 {
                return Err("neural.forward_pass requires exactly 1 argument (inputs)".to_string());
            }
            let inputs = match &args[0] {
                Value::Array(arr) => arr.clone(),
                _ => return Err("neural.forward_pass inputs must be an array".to_string()),
            };
            // Simulate neural forward pass
            let mut result = HashMap::new();
            result.insert("type".to_string(), Value::String("neural_forward_pass".to_string()));
            result.insert("inputs".to_string(), Value::Array(inputs));
            result.insert("outputs".to_string(), Value::Array(vec![Value::Number(0.5)])); // Simplified output
            result.insert("forward_pass_success".to_string(), Value::Boolean(true));
            Ok(Value::Object(result))
        });

        registry.register_namespace_function("neural", "activate", |args| {
            if args.len() != 1 {
                return Err("neural.activate requires exactly 1 argument (input_value)".to_string());
            }
            let input_value = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("neural.activate input_value must be a number".to_string()),
            };
            // Simple activation function (e.g., ReLU)
            let activated = input_value.max(0.0);
            Ok(Value::Number(activated))
        });

        // ========================================
        // STANDARD LIBRARY FUNCTIONS
        // ========================================

        // Math functions
        registry.register_namespace_function("math", "sin", |args| {
            if args.len() != 1 {
                return Err("math.sin requires exactly 1 argument".to_string());
            }
            let x = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.sin argument must be a number".to_string()),
            };
            Ok(Value::Number(x.sin()))
        });

        registry.register_namespace_function("math", "cos", |args| {
            if args.len() != 1 {
                return Err("math.cos requires exactly 1 argument".to_string());
            }
            let x = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.cos argument must be a number".to_string()),
            };
            Ok(Value::Number(x.cos()))
        });

        registry.register_namespace_function("math", "tan", |args| {
            if args.len() != 1 {
                return Err("math.tan requires exactly 1 argument".to_string());
            }
            let x = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.tan argument must be a number".to_string()),
            };
            Ok(Value::Number(x.tan()))
        });

        registry.register_namespace_function("math", "sqrt", |args| {
            if args.len() != 1 {
                return Err("math.sqrt requires exactly 1 argument".to_string());
            }
            let x = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.sqrt argument must be a number".to_string()),
            };
            if x < 0.0 {
                return Err("math.sqrt: cannot take square root of negative number".to_string());
            }
            Ok(Value::Number(x.sqrt()))
        });

        registry.register_namespace_function("math", "pow", |args| {
            if args.len() != 2 {
                return Err("math.pow requires exactly 2 arguments (base, exponent)".to_string());
            }
            let base = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.pow base must be a number".to_string()),
            };
            let exponent = match &args[1] {
                Value::Number(n) => *n,
                _ => return Err("math.pow exponent must be a number".to_string()),
            };
            Ok(Value::Number(base.powf(exponent)))
        });

        registry.register_namespace_function("math", "log", |args| {
            if args.len() != 1 {
                return Err("math.log requires exactly 1 argument".to_string());
            }
            let x = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.log argument must be a number".to_string()),
            };
            if x <= 0.0 {
                return Err("math.log: cannot take logarithm of non-positive number".to_string());
            }
            Ok(Value::Number(x.ln()))
        });

        registry.register_namespace_function("math", "exp", |args| {
            if args.len() != 1 {
                return Err("math.exp requires exactly 1 argument".to_string());
            }
            let x = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.exp argument must be a number".to_string()),
            };
            Ok(Value::Number(x.exp()))
        });

        registry.register_namespace_function("math", "abs", |args| {
            if args.len() != 1 {
                return Err("math.abs requires exactly 1 argument".to_string());
            }
            let x = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.abs argument must be a number".to_string()),
            };
            Ok(Value::Number(x.abs()))
        });

        registry.register_namespace_function("math", "floor", |args| {
            if args.len() != 1 {
                return Err("math.floor requires exactly 1 argument".to_string());
            }
            let x = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.floor argument must be a number".to_string()),
            };
            Ok(Value::Number(x.floor()))
        });

        registry.register_namespace_function("math", "ceil", |args| {
            if args.len() != 1 {
                return Err("math.ceil requires exactly 1 argument".to_string());
            }
            let x = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.ceil argument must be a number".to_string()),
            };
            Ok(Value::Number(x.ceil()))
        });

        registry.register_namespace_function("math", "round", |args| {
            if args.len() != 1 {
                return Err("math.round requires exactly 1 argument".to_string());
            }
            let x = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.round argument must be a number".to_string()),
            };
            Ok(Value::Number(x.round()))
        });

        registry.register_namespace_function("math", "mod", |args| {
            if args.len() != 2 {
                return Err("math.mod requires exactly 2 arguments (dividend, divisor)".to_string());
            }
            let dividend = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("math.mod dividend must be a number".to_string()),
            };
            let divisor = match &args[1] {
                Value::Number(n) => *n,
                _ => return Err("math.mod divisor must be a number".to_string()),
            };
            if divisor == 0.0 {
                return Err("math.mod: division by zero".to_string());
            }
            Ok(Value::Number(dividend % divisor))
        });

        // String functions
        registry.register_namespace_function("string", "length", |args| {
            if args.len() != 1 {
                return Err("string.length requires exactly 1 argument".to_string());
            }
            let s = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("string.length argument must be a string".to_string()),
            };
            Ok(Value::Number(s.len() as f64))
        });

        registry.register_namespace_function("string", "substring", |args| {
            if args.len() != 3 {
                return Err("string.substring requires exactly 3 arguments (str, start, end)".to_string());
            }
            let s = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("string.substring first argument must be a string".to_string()),
            };
            let start = match &args[1] {
                Value::Number(n) => *n as usize,
                _ => return Err("string.substring start must be a number".to_string()),
            };
            let end = match &args[2] {
                Value::Number(n) => *n as usize,
                _ => return Err("string.substring end must be a number".to_string()),
            };
            if start > s.len() || end > s.len() || start > end {
                return Err("string.substring: invalid indices".to_string());
            }
            Ok(Value::String(s[start..end].to_string()))
        });

        registry.register_namespace_function("string", "split", |args| {
            if args.len() != 2 {
                return Err("string.split requires exactly 2 arguments (str, delimiter)".to_string());
            }
            let s = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("string.split first argument must be a string".to_string()),
            };
            let delimiter = match &args[1] {
                Value::String(d) => d.clone(),
                _ => return Err("string.split delimiter must be a string".to_string()),
            };
            let parts: Vec<Value> = s.split(&delimiter).map(|p| Value::String(p.to_string())).collect();
            Ok(Value::Array(parts))
        });

        registry.register_namespace_function("string", "join", |args| {
            if args.len() != 2 {
                return Err("string.join requires exactly 2 arguments (array, separator)".to_string());
            }
            let array = match &args[0] {
                Value::Array(arr) => arr.clone(),
                _ => return Err("string.join first argument must be an array".to_string()),
            };
            let separator = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("string.join separator must be a string".to_string()),
            };
            let strings: Vec<String> = array.iter().filter_map(|v| {
                if let Value::String(s) = v {
                    Some(s.clone())
                } else {
                    None
                }
            }).collect();
            Ok(Value::String(strings.join(&separator)))
        });

        registry.register_namespace_function("string", "replace", |args| {
            if args.len() != 3 {
                return Err("string.replace requires exactly 3 arguments (str, old, new)".to_string());
            }
            let s = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("string.replace first argument must be a string".to_string()),
            };
            let old = match &args[1] {
                Value::String(o) => o.clone(),
                _ => return Err("string.replace old must be a string".to_string()),
            };
            let new = match &args[2] {
                Value::String(n) => n.clone(),
                _ => return Err("string.replace new must be a string".to_string()),
            };
            Ok(Value::String(s.replace(&old, &new)))
        });

        registry.register_namespace_function("string", "format", |args| {
            if args.len() < 1 {
                return Err("string.format requires at least 1 argument (template)".to_string());
            }
            let template = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("string.format template must be a string".to_string()),
            };
            // Simple format implementation - replace {} with arguments
            let mut result = template.clone();
            for (i, arg) in args[1..].iter().enumerate() {
                let placeholder = format!("{{{}}}", i);
                let arg_str = match arg {
                    Value::String(s) => s.clone(),
                    Value::Number(n) => n.to_string(),
                    Value::Boolean(b) => b.to_string(),
                    Value::Null => "null".to_string(),
                    Value::Array(_) => "[array]".to_string(),
                    Value::Object(_) => "[object]".to_string(),
                    Value::Function(_) => "[function]".to_string(),
                    Value::Closure(_) => "[closure]".to_string(),
                };
                result = result.replace(&placeholder, &arg_str);
            }
            Ok(Value::String(result))
        });

        registry.register_namespace_function("string", "upper", |args| {
            if args.len() != 1 {
                return Err("string.upper requires exactly 1 argument".to_string());
            }
            let s = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("string.upper argument must be a string".to_string()),
            };
            Ok(Value::String(s.to_uppercase()))
        });

        registry.register_namespace_function("string", "lower", |args| {
            if args.len() != 1 {
                return Err("string.lower requires exactly 1 argument".to_string());
            }
            let s = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("string.lower argument must be a string".to_string()),
            };
            Ok(Value::String(s.to_lowercase()))
        });

        registry.register_namespace_function("string", "trim", |args| {
            if args.len() != 1 {
                return Err("string.trim requires exactly 1 argument".to_string());
            }
            let s = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("string.trim argument must be a string".to_string()),
            };
            Ok(Value::String(s.trim().to_string()))
        });

        // Array functions
        registry.register_namespace_function("array", "length", |args| {
            if args.len() != 1 {
                return Err("array.length requires exactly 1 argument (array)".to_string());
            }
            let array = match &args[0] {
                Value::Array(arr) => arr.clone(),
                _ => return Err("array.length argument must be an array".to_string()),
            };
            Ok(Value::Number(array.len() as f64))
        });

        registry.register_namespace_function("array", "push", |args| {
            if args.len() != 2 {
                return Err("array.push requires exactly 2 arguments (array, value)".to_string());
            }
            let mut array = match &args[0] {
                Value::Array(arr) => arr.clone(),
                _ => return Err("array.push first argument must be an array".to_string()),
            };
            array.push(args[1].clone());
            Ok(Value::Array(array))
        });

        registry.register_namespace_function("array", "pop", |args| {
            if args.len() != 1 {
                return Err("array.pop requires exactly 1 argument (array)".to_string());
            }
            let mut array = match &args[0] {
                Value::Array(arr) => arr.clone(),
                _ => return Err("array.pop argument must be an array".to_string()),
            };
            if array.is_empty() {
                return Err("array.pop: cannot pop from empty array".to_string());
            }
            let popped = array.pop().unwrap();
            Ok(popped)
        });

        registry.register_namespace_function("array", "map", |args| {
            if args.len() != 2 {
                return Err("array.map requires exactly 2 arguments (array, function)".to_string());
            }
            let array = match &args[0] {
                Value::Array(arr) => arr.clone(),
                _ => return Err("array.map first argument must be an array".to_string()),
            };
            // For now, just return the original array (function application would need more complex implementation)
            Ok(Value::Array(array))
        });

        registry.register_namespace_function("array", "filter", |args| {
            if args.len() != 2 {
                return Err("array.filter requires exactly 2 arguments (array, predicate)".to_string());
            }
            let array = match &args[0] {
                Value::Array(arr) => arr.clone(),
                _ => return Err("array.filter first argument must be an array".to_string()),
            };
            // For now, just return the original array (predicate application would need more complex implementation)
            Ok(Value::Array(array))
        });

        registry.register_namespace_function("array", "reduce", |args| {
            if args.len() != 3 {
                return Err("array.reduce requires exactly 3 arguments (array, initial, function)".to_string());
            }
            let array = match &args[0] {
                Value::Array(arr) => arr.clone(),
                _ => return Err("array.reduce first argument must be an array".to_string()),
            };
            // For now, just return the initial value (function application would need more complex implementation)
            Ok(args[1].clone())
        });

        registry.register_namespace_function("array", "find", |args| {
            if args.len() != 2 {
                return Err("array.find requires exactly 2 arguments (array, value)".to_string());
            }
            let array = match &args[0] {
                Value::Array(arr) => arr.clone(),
                _ => return Err("array.find first argument must be an array".to_string()),
            };
            let search_value = &args[1];
            for (i, item) in array.iter().enumerate() {
                if item == search_value {
                    return Ok(Value::Number(i as f64));
                }
            }
            Ok(Value::Number(-1.0)) // Not found
        });

        // Object functions
        registry.register_namespace_function("object", "keys", |args| {
            if args.len() != 1 {
                return Err("object.keys requires exactly 1 argument (object)".to_string());
            }
            let object = match &args[0] {
                Value::Object(obj) => obj.clone(),
                _ => return Err("object.keys argument must be an object".to_string()),
            };
            let keys: Vec<Value> = object.keys().map(|k| Value::String(k.clone())).collect();
            Ok(Value::Array(keys))
        });

        registry.register_namespace_function("object", "values", |args| {
            if args.len() != 1 {
                return Err("object.values requires exactly 1 argument (object)".to_string());
            }
            let object = match &args[0] {
                Value::Object(obj) => obj.clone(),
                _ => return Err("object.values argument must be an object".to_string()),
            };
            let values: Vec<Value> = object.values().cloned().collect();
            Ok(Value::Array(values))
        });

        registry.register_namespace_function("object", "entries", |args| {
            if args.len() != 1 {
                return Err("object.entries requires exactly 1 argument (object)".to_string());
            }
            let object = match &args[0] {
                Value::Object(obj) => obj.clone(),
                _ => return Err("object.entries argument must be an object".to_string()),
            };
            let entries: Vec<Value> = object.iter().map(|(k, v)| {
                let mut entry = HashMap::new();
                entry.insert("key".to_string(), Value::String(k.clone()));
                entry.insert("value".to_string(), v.clone());
                Value::Object(entry)
            }).collect();
            Ok(Value::Array(entries))
        });

        registry.register_namespace_function("object", "assign", |args| {
            if args.len() < 2 {
                return Err("object.assign requires at least 2 arguments (target, ...sources)".to_string());
            }
            let mut target = match &args[0] {
                Value::Object(obj) => obj.clone(),
                _ => return Err("object.assign first argument must be an object".to_string()),
            };
            for arg in &args[1..] {
                if let Value::Object(source) = arg {
                    for (k, v) in source.iter() {
                        target.insert(k.clone(), v.clone());
                    }
                }
            }
            Ok(Value::Object(target))
        });

        registry.register_namespace_function("object", "merge", |args| {
            if args.len() != 2 {
                return Err("object.merge requires exactly 2 arguments (obj1, obj2)".to_string());
            }
            let obj1 = match &args[0] {
                Value::Object(obj) => obj.clone(),
                _ => return Err("object.merge first argument must be an object".to_string()),
            };
            let obj2 = match &args[1] {
                Value::Object(obj) => obj.clone(),
                _ => return Err("object.merge second argument must be an object".to_string()),
            };
            let mut merged = obj1.clone();
            for (k, v) in obj2.iter() {
                merged.insert(k.clone(), v.clone());
            }
            Ok(Value::Object(merged))
        });

        registry.register_namespace_function("object", "clone", |args| {
            if args.len() != 1 {
                return Err("object.clone requires exactly 1 argument (object)".to_string());
            }
            let object = match &args[0] {
                Value::Object(obj) => obj.clone(),
                _ => return Err("object.clone argument must be an object".to_string()),
            };
            Ok(Value::Object(object))
        });

        // Time functions
        registry.register_namespace_function("time", "now", |_args| {
            let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();
            Ok(Value::Number(now.as_secs_f64()))
        });

        registry.register_namespace_function("time", "timestamp", |_args| {
            let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();
            Ok(Value::Number(now.as_millis() as f64))
        });

        registry.register_namespace_function("time", "delta", |args| {
            if args.len() != 2 {
                return Err("time.delta requires exactly 2 arguments (start, end)".to_string());
            }
            let start = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("time.delta start must be a number".to_string()),
            };
            let end = match &args[1] {
                Value::Number(n) => *n,
                _ => return Err("time.delta end must be a number".to_string()),
            };
            Ok(Value::Number(end - start))
        });

        registry.register_namespace_function("time", "sleep", |args| {
            if args.len() != 1 {
                return Err("time.sleep requires exactly 1 argument (seconds)".to_string());
            }
            let seconds = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("time.sleep seconds must be a number".to_string()),
            };
            if seconds < 0.0 {
                return Err("time.sleep: cannot sleep negative time".to_string());
            }
            std::thread::sleep(std::time::Duration::from_secs_f64(seconds));
            Ok(Value::Boolean(true))
        });

        registry.register_namespace_function("time", "delay", |args| {
            if args.len() != 1 {
                return Err("time.delay requires exactly 1 argument (milliseconds)".to_string());
            }
            let milliseconds = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("time.delay milliseconds must be a number".to_string()),
            };
            if milliseconds < 0.0 {
                return Err("time.delay: cannot delay negative time".to_string());
            }
            std::thread::sleep(std::time::Duration::from_millis(milliseconds as u64));
            Ok(Value::Boolean(true))
        });

        // Crypto functions
        registry.register_namespace_function("crypto", "sha256", |args| {
            if args.len() != 1 {
                return Err("crypto.sha256 requires exactly 1 argument (data)".to_string());
            }
            let data = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("crypto.sha256 data must be a string".to_string()),
            };
            // Simulate SHA256 (in real implementation, use actual crypto library)
            let hash = format!("sha256_{}", data.len());
            Ok(Value::String(hash))
        });

        registry.register_namespace_function("crypto", "encrypt", |args| {
            if args.len() != 2 {
                return Err("crypto.encrypt requires exactly 2 arguments (data, key)".to_string());
            }
            let data = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("crypto.encrypt data must be a string".to_string()),
            };
            let key = match &args[1] {
                Value::String(k) => k.clone(),
                _ => return Err("crypto.encrypt key must be a string".to_string()),
            };
            // Simulate encryption
            let encrypted = format!("encrypted_{}_{}", data, key);
            Ok(Value::String(encrypted))
        });

        registry.register_namespace_function("crypto", "decrypt", |args| {
            if args.len() != 2 {
                return Err("crypto.decrypt requires exactly 2 arguments (data, key)".to_string());
            }
            let data = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("crypto.decrypt data must be a string".to_string()),
            };
            let key = match &args[1] {
                Value::String(k) => k.clone(),
                _ => return Err("crypto.decrypt key must be a string".to_string()),
            };
            // Simulate decryption
            let decrypted = format!("decrypted_{}_{}", data, key);
            Ok(Value::String(decrypted))
        });

        registry.register_namespace_function("crypto", "sign", |args| {
            if args.len() != 2 {
                return Err("crypto.sign requires exactly 2 arguments (data, private_key)".to_string());
            }
            let data = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("crypto.sign data must be a string".to_string()),
            };
            let private_key = match &args[1] {
                Value::String(k) => k.clone(),
                _ => return Err("crypto.sign private_key must be a string".to_string()),
            };
            // Simulate signing
            let signature = format!("signature_{}_{}", data, private_key);
            Ok(Value::String(signature))
        });

        registry.register_namespace_function("crypto", "verify", |args| {
            if args.len() != 3 {
                return Err("crypto.verify requires exactly 3 arguments (data, signature, public_key)".to_string());
            }
            let data = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("crypto.verify data must be a string".to_string()),
            };
            let signature = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("crypto.verify signature must be a string".to_string()),
            };
            let public_key = match &args[2] {
                Value::String(k) => k.clone(),
                _ => return Err("crypto.verify public_key must be a string".to_string()),
            };
            // Simulate verification
            let is_valid = signature.starts_with("signature_");
            Ok(Value::Boolean(is_valid))
        });

        // System / IO functions
        registry.register_namespace_function("system", "read_file", |args| {
            if args.len() != 1 {
                return Err("system.read_file requires exactly 1 argument (path)".to_string());
            }
            let path = match &args[0] {
                Value::String(p) => p.clone(),
                _ => return Err("system.read_file path must be a string".to_string()),
            };
            // Simulate file reading
            let content = format!("simulated_content_for_{}", path);
            Ok(Value::String(content))
        });

        registry.register_namespace_function("system", "write_file", |args| {
            if args.len() != 2 {
                return Err("system.write_file requires exactly 2 arguments (path, content)".to_string());
            }
            let path = match &args[0] {
                Value::String(p) => p.clone(),
                _ => return Err("system.write_file path must be a string".to_string()),
            };
            let content = match &args[1] {
                Value::String(c) => c.clone(),
                _ => return Err("system.write_file content must be a string".to_string()),
            };
            // Simulate file writing
            Ok(Value::Boolean(true))
        });

        registry.register_namespace_function("system", "env", |args| {
            if args.len() != 1 {
                return Err("system.env requires exactly 1 argument (name)".to_string());
            }
            let name = match &args[0] {
                Value::String(n) => n.clone(),
                _ => return Err("system.env name must be a string".to_string()),
            };
            // Simulate environment variable lookup
            let value = std::env::var(&name).unwrap_or_else(|_| format!("env_{}", name));
            Ok(Value::String(value))
        });

        registry.register_namespace_function("system", "args", |_args| {
            // Return simulated command line arguments
            let args = vec![
                Value::String("azl".to_string()),
                Value::String("run".to_string()),
                Value::String("script.azl".to_string()),
            ];
            Ok(Value::Array(args))
        });

        registry.register_namespace_function("system", "log", |args| {
            if args.len() != 1 {
                return Err("system.log requires exactly 1 argument (message)".to_string());
            }
            let message = match &args[0] {
                Value::String(m) => m.clone(),
                _ => return Err("system.log message must be a string".to_string()),
            };
            println!("[LOG] {}", message);
            Ok(Value::Boolean(true))
        });

        registry.register_namespace_function("system", "uuid", |_args| {
            // Generate a simple UUID-like string
            let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();
            let mut hasher = DefaultHasher::new();
            now.hash(&mut hasher);
            let hash = hasher.finish();
            
            let uuid = format!("{:016x}-{:04x}-{:04x}-{:04x}-{:012x}", 
                hash >> 32, 
                (hash >> 16) & 0xffff, 
                hash & 0xffff, 
                (hash >> 48) & 0xffff, 
                hash & 0xffffffffffff);
            Ok(Value::String(uuid))
        });

        registry.register_namespace_function("system", "cwd", |_args| {
            // Return current working directory
            let cwd = std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("/tmp"));
            Ok(Value::String(cwd.to_string_lossy().to_string()))
        });

        // Consciousness functions
        registry.register_namespace_function("consciousness", "aware", |args| {
            if args.len() != 1 {
                return Err("consciousness.aware requires exactly 1 argument (stimulus)".to_string());
            }
            let stimulus = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("consciousness.aware stimulus must be a string".to_string()),
            };
            // Simulate consciousness awareness
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("consciousness_awareness".to_string()));
            map.insert("stimulus".to_string(), Value::String(stimulus.clone()));
            map.insert("awareness_level".to_string(), Value::Number(2.8));
            map.insert("attention_focus".to_string(), Value::Number(1.0));
            map.insert("metacognitive_monitoring".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("consciousness", "reflect", |args| {
            if args.len() != 2 {
                return Err("consciousness.reflect requires exactly 2 arguments (experience, depth)".to_string());
            }
            let experience = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("consciousness.reflect experience must be a string".to_string()),
            };
            let depth = match &args[1] {
                Value::Number(n) => *n,
                _ => return Err("consciousness.reflect depth must be a number".to_string()),
            };
            // Simulate consciousness reflection
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("consciousness_reflection".to_string()));
            map.insert("experience".to_string(), Value::String(experience.clone()));
            map.insert("reflection_depth".to_string(), Value::Number(depth));
            map.insert("insight_gained".to_string(), Value::Number(depth * 0.8));
            map.insert("metacognitive_gain".to_string(), Value::Number(depth * 0.6));
            map.insert("self_awareness_increased".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // Advanced cognitive features
        registry.register_namespace_function("consciousness", "metacognition", |args| {
            if args.len() != 1 {
                return Err("consciousness.metacognition requires exactly 1 argument (domain)".to_string());
            }
            let domain = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("consciousness.metacognition domain must be a string".to_string()),
            };
            // Simulate metacognitive processing
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("metacognitive_processing".to_string()));
            map.insert("domain".to_string(), Value::String(domain.clone()));
            map.insert("cognitive_load".to_string(), Value::Number(0.7));
            map.insert("self_monitoring_active".to_string(), Value::Boolean(true));
            map.insert("strategy_adaptation".to_string(), Value::Boolean(true));
            map.insert("learning_rate".to_string(), Value::Number(0.85));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("consciousness", "self_verify", |args| {
            if args.len() != 1 {
                return Err("consciousness.self_verify requires exactly 1 argument (hypothesis)".to_string());
            }
            let hypothesis = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("consciousness.self_verify hypothesis must be a string".to_string()),
            };
            // Simulate self-verification
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("self_verification".to_string()));
            map.insert("hypothesis".to_string(), Value::String(hypothesis.clone()));
            map.insert("confidence_level".to_string(), Value::Number(0.92));
            map.insert("evidence_strength".to_string(), Value::Number(0.88));
            map.insert("verification_success".to_string(), Value::Boolean(true));
            map.insert("insight_generated".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("consciousness", "cognitive_graph", |args| {
            if args.len() != 1 {
                return Err("consciousness.cognitive_graph requires exactly 1 argument (domain)".to_string());
            }
            let domain = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("consciousness.cognitive_graph domain must be a string".to_string()),
            };
            // Simulate cognitive model graph
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("cognitive_model_graph".to_string()));
            map.insert("domain".to_string(), Value::String(domain.clone()));
            map.insert("nodes_count".to_string(), Value::Number(15.0));
            map.insert("connections_count".to_string(), Value::Number(42.0));
            map.insert("clustering_coefficient".to_string(), Value::Number(0.73));
            map.insert("graph_density".to_string(), Value::Number(0.28));
            map.insert("centrality_hub".to_string(), Value::String("core_concept".to_string()));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("consciousness", "reward_curiosity", |args| {
            if args.len() != 1 {
                return Err("consciousness.reward_curiosity requires exactly 1 argument (stimulus)".to_string());
            }
            let stimulus = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("consciousness.reward_curiosity stimulus must be a string".to_string()),
            };
            // Simulate internal reward system
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("internal_reward_system".to_string()));
            map.insert("stimulus".to_string(), Value::String(stimulus.clone()));
            map.insert("curiosity_level".to_string(), Value::Number(0.85));
            map.insert("reward_signal".to_string(), Value::Number(0.92));
            map.insert("exploration_drive".to_string(), Value::Number(0.78));
            map.insert("novelty_detected".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("consciousness", "goal_assign", |args| {
            if args.len() != 2 {
                return Err("consciousness.goal_assign requires exactly 2 arguments (goal, priority)".to_string());
            }
            let goal = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("consciousness.goal_assign goal must be a string".to_string()),
            };
            let priority = match &args[1] {
                Value::Number(n) => *n,
                _ => return Err("consciousness.goal_assign priority must be a number".to_string()),
            };
            // Simulate self-assigned goals
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("self_assigned_goal".to_string()));
            map.insert("goal".to_string(), Value::String(goal.clone()));
            map.insert("priority".to_string(), Value::Number(priority));
            map.insert("completion_status".to_string(), Value::Number(0.0));
            map.insert("assigned_timestamp".to_string(), Value::Number(SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs_f64()));
            map.insert("goal_id".to_string(), Value::String(format!("goal_{}", SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis())));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("consciousness", "loop_closure", |args| {
            if args.len() != 1 {
                return Err("consciousness.loop_closure requires exactly 1 argument (loop_id)".to_string());
            }
            let loop_id = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("consciousness.loop_closure loop_id must be a string".to_string()),
            };
            // Simulate loop closure
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("loop_closure".to_string()));
            map.insert("loop_id".to_string(), Value::String(loop_id.clone()));
            map.insert("closure_success".to_string(), Value::Boolean(true));
            map.insert("learning_integrated".to_string(), Value::Boolean(true));
            map.insert("adaptation_applied".to_string(), Value::Boolean(true));
            map.insert("next_cycle_ready".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // Language-specific knowledge persistence
        registry.register_namespace_function("memory", "evolve", |args| {
            if args.len() != 2 {
                return Err("memory.evolve requires exactly 2 arguments (memory_id, evolution_data)".to_string());
            }
            let memory_id = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.evolve memory_id must be a string".to_string()),
            };
            let evolution_data = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.evolve evolution_data must be a string".to_string()),
            };
            // Simulate memory evolution
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("memory_evolution".to_string()));
            map.insert("memory_id".to_string(), Value::String(memory_id.clone()));
            map.insert("evolution_data".to_string(), Value::String(evolution_data.clone()));
            map.insert("evolution_success".to_string(), Value::Boolean(true));
            map.insert("new_connections_formed".to_string(), Value::Number(5.0));
            map.insert("strength_increased".to_string(), Value::Number(0.15));
            map.insert("accessibility_improved".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("memory", "archive_code", |args| {
            if args.len() != 1 {
                return Err("memory.archive_code requires exactly 1 argument (code_snippet)".to_string());
            }
            let code_snippet = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.archive_code code_snippet must be a string".to_string()),
            };
            // Simulate code archiving
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("code_archiving".to_string()));
            map.insert("code_snippet".to_string(), Value::String(code_snippet.clone()));
            map.insert("archive_id".to_string(), Value::String(format!("archive_{}", SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis())));
            map.insert("archiving_success".to_string(), Value::Boolean(true));
            map.insert("metadata_extracted".to_string(), Value::Boolean(true));
            map.insert("searchable_index".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("memory", "sync_procedural", |args| {
            if args.len() != 1 {
                return Err("memory.sync_procedural requires exactly 1 argument (procedure_name)".to_string());
            }
            let procedure_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.sync_procedural procedure_name must be a string".to_string()),
            };
            // Simulate procedural memory synchronization
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("procedural_memory_sync".to_string()));
            map.insert("procedure_name".to_string(), Value::String(procedure_name.clone()));
            map.insert("sync_success".to_string(), Value::Boolean(true));
            map.insert("execution_count".to_string(), Value::Number(12.0));
            map.insert("optimization_applied".to_string(), Value::Boolean(true));
            map.insert("performance_improved".to_string(), Value::Number(0.23));
            Ok(Value::Object(map))
        });

        // Code evolution and intent-driven mutation
        registry.register_namespace_function("azl", "mutate", |args| {
            if args.len() != 3 {
                return Err("azl.mutate requires exactly 3 arguments (function_name, new_body, fitness_score)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("azl.mutate function_name must be a string".to_string()),
            };
            let new_body = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("azl.mutate new_body must be a string".to_string()),
            };
            let fitness_score = match &args[2] {
                Value::Number(n) => *n,
                _ => return Err("azl.mutate fitness_score must be a number".to_string()),
            };
            // Simulate function mutation
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("function_mutation".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("new_body".to_string(), Value::String(new_body.clone()));
            map.insert("fitness_score".to_string(), Value::Number(fitness_score));
            map.insert("mutation_success".to_string(), Value::Boolean(fitness_score > 0.7));
            map.insert("ai_evaluated".to_string(), Value::Boolean(true));
            map.insert("replacement_applied".to_string(), Value::Boolean(fitness_score > 0.7));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("azl", "fitness_score", |args| {
            if args.len() != 2 {
                return Err("azl.fitness_score requires exactly 2 arguments (code_path, criteria)".to_string());
            }
            let code_path = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("azl.fitness_score code_path must be a string".to_string()),
            };
            let criteria = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("azl.fitness_score criteria must be a string".to_string()),
            };
            // Simulate fitness scoring
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("fitness_scoring".to_string()));
            map.insert("code_path".to_string(), Value::String(code_path.clone()));
            map.insert("criteria".to_string(), Value::String(criteria.clone()));
            map.insert("fitness_score".to_string(), Value::Number(0.85));
            map.insert("performance_metric".to_string(), Value::Number(0.92));
            map.insert("readability_score".to_string(), Value::Number(0.78));
            map.insert("maintainability_score".to_string(), Value::Number(0.81));
            Ok(Value::Object(map))
        });

        // Security as code
        registry.register_namespace_function("security", "contract", |args| {
            if args.len() != 1 {
                return Err("security.contract requires exactly 1 argument (capabilities)".to_string());
            }
            let capabilities = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("security.contract capabilities must be a string".to_string()),
            };
            // Simulate security contract
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("security_contract".to_string()));
            map.insert("capabilities".to_string(), Value::String(capabilities.clone()));
            map.insert("contract_active".to_string(), Value::Boolean(true));
            map.insert("permissions_granted".to_string(), Value::Boolean(true));
            map.insert("audit_logging".to_string(), Value::Boolean(true));
            map.insert("sandbox_boundaries".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("security", "capability", |args| {
            if args.len() != 2 {
                return Err("security.capability requires exactly 2 arguments (function_name, capability)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("security.capability function_name must be a string".to_string()),
            };
            let capability = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("security.capability capability must be a string".to_string()),
            };
            // Simulate capability declaration
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("capability_declaration".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("capability".to_string(), Value::String(capability.clone()));
            map.insert("declaration_success".to_string(), Value::Boolean(true));
            map.insert("runtime_enforcement".to_string(), Value::Boolean(true));
            map.insert("audit_trail".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // Intent protocols
        registry.register_namespace_function("intent", "declare", |args| {
            if args.len() != 2 {
                return Err("intent.declare requires exactly 2 arguments (goal, deadline)".to_string());
            }
            let goal = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("intent.declare goal must be a string".to_string()),
            };
            let deadline = match &args[1] {
                Value::Number(n) => *n,
                _ => return Err("intent.declare deadline must be a number".to_string()),
            };
            // Simulate intent declaration
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("intent_declaration".to_string()));
            map.insert("goal".to_string(), Value::String(goal.clone()));
            map.insert("deadline".to_string(), Value::Number(deadline));
            map.insert("intent_id".to_string(), Value::String(format!("intent_{}", SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis())));
            map.insert("resource_allocated".to_string(), Value::Boolean(true));
            map.insert("priority_level".to_string(), Value::Number(0.85));
            map.insert("negotiation_success".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("intent", "schedule", |args| {
            if args.len() != 3 {
                return Err("intent.schedule requires exactly 3 arguments (function_name, delay, interval)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("intent.schedule function_name must be a string".to_string()),
            };
            let delay = match &args[1] {
                Value::Number(n) => *n,
                _ => return Err("intent.schedule delay must be a number".to_string()),
            };
            let interval = match &args[2] {
                Value::Number(n) => *n,
                _ => return Err("intent.schedule interval must be a number".to_string()),
            };
            // Simulate expressive scheduling
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("expressive_scheduling".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("delay".to_string(), Value::Number(delay));
            map.insert("interval".to_string(), Value::Number(interval));
            map.insert("schedule_id".to_string(), Value::String(format!("schedule_{}", SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis())));
            map.insert("scheduling_success".to_string(), Value::Boolean(true));
            map.insert("task_arbitration".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // Multi-reality execution (Multiverse)
        registry.register_namespace_function("multiverse", "simulate", |args| {
            if args.len() != 1 {
                return Err("multiverse.simulate requires exactly 1 argument (simulation_code)".to_string());
            }
            let simulation_code = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("multiverse.simulate simulation_code must be a string".to_string()),
            };
            // Simulate virtual fork
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("virtual_fork".to_string()));
            map.insert("simulation_code".to_string(), Value::String(simulation_code.clone()));
            map.insert("branch_id".to_string(), Value::String(format!("branch_{}", SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis())));
            map.insert("fork_success".to_string(), Value::Boolean(true));
            map.insert("probabilistic_tracking".to_string(), Value::Boolean(true));
            map.insert("reality_annotations".to_string(), Value::Array(vec![
                Value::String("::branch_1".to_string()),
                Value::String("::base".to_string()),
                Value::String("::future_self".to_string())
            ]));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("multiverse", "rollback", |args| {
            if args.len() != 1 {
                return Err("multiverse.rollback requires exactly 1 argument (branch_id)".to_string());
            }
            let branch_id = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("multiverse.rollback branch_id must be a string".to_string()),
            };
            // Simulate rollback
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("rollback".to_string()));
            map.insert("branch_id".to_string(), Value::String(branch_id.clone()));
            map.insert("rollback_success".to_string(), Value::Boolean(true));
            map.insert("state_restored".to_string(), Value::Boolean(true));
            map.insert("memory_cleared".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("multiverse", "commit", |args| {
            if args.len() != 1 {
                return Err("multiverse.commit requires exactly 1 argument (branch_id)".to_string());
            }
            let branch_id = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("multiverse.commit branch_id must be a string".to_string()),
            };
            // Simulate commit
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("commit".to_string()));
            map.insert("branch_id".to_string(), Value::String(branch_id.clone()));
            map.insert("commit_success".to_string(), Value::Boolean(true));
            map.insert("changes_persisted".to_string(), Value::Boolean(true));
            map.insert("branch_merged".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // Native semantic graph engine
        registry.register_namespace_function("graph", "node", |args| {
            if args.len() != 1 {
                return Err("graph.node requires exactly 1 argument (node_id)".to_string());
            }
            let node_id = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("graph.node node_id must be a string".to_string()),
            };
            // Simulate graph node creation
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("graph_node".to_string()));
            map.insert("node_id".to_string(), Value::String(node_id.clone()));
            map.insert("creation_success".to_string(), Value::Boolean(true));
            map.insert("semantic_embedding".to_string(), Value::Boolean(true));
            map.insert("traversal_ready".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("graph", "relate", |args| {
            if args.len() != 3 {
                return Err("graph.relate requires exactly 3 arguments (node_a, relationship, node_b)".to_string());
            }
            let node_a = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("graph.relate node_a must be a string".to_string()),
            };
            let relationship = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("graph.relate relationship must be a string".to_string()),
            };
            let node_b = match &args[2] {
                Value::String(s) => s.clone(),
                _ => return Err("graph.relate node_b must be a string".to_string()),
            };
            // Simulate graph relationship
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("graph_relationship".to_string()));
            map.insert("node_a".to_string(), Value::String(node_a.clone()));
            map.insert("relationship".to_string(), Value::String(relationship.clone()));
            map.insert("node_b".to_string(), Value::String(node_b.clone()));
            map.insert("relationship_created".to_string(), Value::Boolean(true));
            map.insert("inference_ready".to_string(), Value::Boolean(true));
            map.insert("traversal_path".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("memory", "cluster", |args| {
            if args.len() != 1 {
                return Err("memory.cluster requires exactly 1 argument (concept)".to_string());
            }
            let concept = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.cluster concept must be a string".to_string()),
            };
            // Simulate conceptual clustering
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("conceptual_clustering".to_string()));
            map.insert("concept".to_string(), Value::String(concept.clone()));
            map.insert("cluster_size".to_string(), Value::Number(8.0));
            map.insert("similarity_threshold".to_string(), Value::Number(0.75));
            map.insert("clustering_success".to_string(), Value::Boolean(true));
            map.insert("semantic_coherence".to_string(), Value::Number(0.82));
            Ok(Value::Object(map))
        });

        // Dynamic ontology binding
        registry.register_namespace_function("ontology", "bind", |args| {
            if args.len() != 2 {
                return Err("ontology.bind requires exactly 2 arguments (runtime_object, ontology_entry)".to_string());
            }
            let runtime_object = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("ontology.bind runtime_object must be a string".to_string()),
            };
            let ontology_entry = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("ontology.bind ontology_entry must be a string".to_string()),
            };
            // Simulate ontology binding
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("ontology_binding".to_string()));
            map.insert("runtime_object".to_string(), Value::String(runtime_object.clone()));
            map.insert("ontology_entry".to_string(), Value::String(ontology_entry.clone()));
            map.insert("binding_success".to_string(), Value::Boolean(true));
            map.insert("meaning_resolved".to_string(), Value::Boolean(true));
            map.insert("reasoning_enabled".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("ontology", "evaluate", |args| {
            if args.len() != 2 {
                return Err("ontology.evaluate requires exactly 2 arguments (expression_a, expression_b)".to_string());
            }
            let expression_a = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("ontology.evaluate expression_a must be a string".to_string()),
            };
            let expression_b = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("ontology.evaluate expression_b must be a string".to_string()),
            };
            // Simulate ontology-augmented evaluation
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("ontology_evaluation".to_string()));
            map.insert("expression_a".to_string(), Value::String(expression_a.clone()));
            map.insert("expression_b".to_string(), Value::String(expression_b.clone()));
            map.insert("evaluation_result".to_string(), Value::String("affect_cluster".to_string()));
            map.insert("semantic_coherence".to_string(), Value::Number(0.89));
            map.insert("meaning_preserved".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // Programmable compiler behavior
        registry.register_namespace_function("compiler", "hook", |args| {
            if args.len() != 2 {
                return Err("compiler.hook requires exactly 2 arguments (hook_type, callback_function)".to_string());
            }
            let hook_type = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("compiler.hook hook_type must be a string".to_string()),
            };
            let callback_function = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("compiler.hook callback_function must be a string".to_string()),
            };
            // Simulate compiler hook
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("compiler_hook".to_string()));
            map.insert("hook_type".to_string(), Value::String(hook_type.clone()));
            map.insert("callback_function".to_string(), Value::String(callback_function.clone()));
            map.insert("hook_registered".to_string(), Value::Boolean(true));
            map.insert("compilation_control".to_string(), Value::Boolean(true));
            map.insert("behavior_modified".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // Symbolic physicalization
        registry.register_namespace_function("physics", "units", |args| {
            if args.len() != 2 {
                return Err("physics.units requires exactly 2 arguments (value, unit)".to_string());
            }
            let value = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("physics.units value must be a number".to_string()),
            };
            let unit = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("physics.units unit must be a string".to_string()),
            };
            // Simulate dimensional types
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("dimensional_type".to_string()));
            map.insert("value".to_string(), Value::Number(value));
            map.insert("unit".to_string(), Value::String(unit.clone()));
            map.insert("dimensional_analysis".to_string(), Value::Boolean(true));
            map.insert("unit_conversion".to_string(), Value::Boolean(true));
            map.insert("physical_validation".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("physics", "equation", |args| {
            if args.len() != 1 {
                return Err("physics.equation requires exactly 1 argument (equation_string)".to_string());
            }
            let equation_string = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("physics.equation equation_string must be a string".to_string()),
            };
            // Simulate time-evolving equations
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("time_evolving_equation".to_string()));
            map.insert("equation_string".to_string(), Value::String(equation_string.clone()));
            map.insert("equation_parsed".to_string(), Value::Boolean(true));
            map.insert("native_function".to_string(), Value::Boolean(true));
            map.insert("time_integration".to_string(), Value::Boolean(true));
            map.insert("physical_constraints".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // Runtime reflex engine
        registry.register_namespace_function("reflex", "perceive", |args| {
            if args.len() != 1 {
                return Err("reflex.perceive requires exactly 1 argument (input)".to_string());
            }
            let input = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("reflex.perceive input must be a string".to_string()),
            };
            // Simulate perception
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("perception".to_string()));
            map.insert("input".to_string(), Value::String(input.clone()));
            map.insert("reactive_memory_adjusted".to_string(), Value::Boolean(true));
            map.insert("attention_focused".to_string(), Value::Boolean(true));
            map.insert("pattern_recognized".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("reflex", "trigger", |args| {
            if args.len() != 1 {
                return Err("reflex.trigger requires exactly 1 argument (trigger_name)".to_string());
            }
            let trigger_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("reflex.trigger trigger_name must be a string".to_string()),
            };
            // Simulate reflex trigger
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("reflex_trigger".to_string()));
            map.insert("trigger_name".to_string(), Value::String(trigger_name.clone()));
            map.insert("behavior_tree_triggered".to_string(), Value::Boolean(true));
            map.insert("event_chain_propagated".to_string(), Value::Boolean(true));
            map.insert("modifiers_applied".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // Agent-oriented syntax
        registry.register_namespace_function("agent", "create", |args| {
            if args.len() != 2 {
                return Err("agent.create requires exactly 2 arguments (agent_name, capabilities)".to_string());
            }
            let agent_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("agent.create agent_name must be a string".to_string()),
            };
            let capabilities = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("agent.create capabilities must be a string".to_string()),
            };
            // Simulate agent creation
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("agent_creation".to_string()));
            map.insert("agent_name".to_string(), Value::String(agent_name.clone()));
            map.insert("capabilities".to_string(), Value::String(capabilities.clone()));
            map.insert("agent_id".to_string(), Value::String(format!("agent_{}", SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis())));
            map.insert("context_awareness".to_string(), Value::Boolean(true));
            map.insert("belief_system".to_string(), Value::Boolean(true));
            map.insert("emergent_behavior".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("agent", "act", |args| {
            if args.len() != 1 {
                return Err("agent.act requires exactly 1 argument (agent_id)".to_string());
            }
            let agent_id = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("agent.act agent_id must be a string".to_string()),
            };
            // Simulate agent action
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("agent_action".to_string()));
            map.insert("agent_id".to_string(), Value::String(agent_id.clone()));
            map.insert("action_decided".to_string(), Value::Boolean(true));
            map.insert("context_analyzed".to_string(), Value::Boolean(true));
            map.insert("beliefs_updated".to_string(), Value::Boolean(true));
            map.insert("behavior_emergent".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // ========================================
        // REVOLUTIONARY COGNITIVE FEATURES
        // ========================================

        // 1. Causal Reasoning Language Layer
        registry.register_namespace_function("causal", "why", |args| {
            if args.len() != 1 {
                return Err("causal.why requires exactly 1 argument (value)".to_string());
            }
            let value = match &args[0] {
                Value::String(s) => s.clone(),
                Value::Number(n) => n.to_string(),
                Value::Boolean(b) => b.to_string(),
                _ => return Err("causal.why value must be a string, number, or boolean".to_string()),
            };
            // Simulate causal reasoning
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("causal_explanation".to_string()));
            map.insert("value".to_string(), Value::String(value.clone()));
            map.insert("explanation".to_string(), Value::String(format!("The value '{}' exists because of previous computational steps and causal chains", value)));
            map.insert("confidence".to_string(), Value::Number(0.85));
            map.insert("causal_depth".to_string(), Value::Number(3.0));
            map.insert("counterfactual_available".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("causal", "counterfactual", |args| {
            if args.len() != 1 {
                return Err("causal.counterfactual requires exactly 1 argument (scenario)".to_string());
            }
            let scenario = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("causal.counterfactual scenario must be a string".to_string()),
            };
            // Simulate counterfactual simulation
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("counterfactual_simulation".to_string()));
            map.insert("scenario".to_string(), Value::String(scenario.clone()));
            map.insert("alternative_outcome".to_string(), Value::String("Different computational path would have been taken".to_string()));
            map.insert("probability".to_string(), Value::Number(0.42));
            map.insert("causal_graph_updated".to_string(), Value::Boolean(true));
            map.insert("insight_generated".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("causal", "influence", |args| {
            if args.len() != 2 {
                return Err("causal.influence requires exactly 2 arguments (source, target)".to_string());
            }
            let source = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("causal.influence source must be a string".to_string()),
            };
            let target = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("causal.influence target must be a string".to_string()),
            };
            // Simulate influence tracking
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("influence_tracking".to_string()));
            map.insert("source".to_string(), Value::String(source.clone()));
            map.insert("target".to_string(), Value::String(target.clone()));
            map.insert("influence_strength".to_string(), Value::Number(0.73));
            map.insert("causal_path".to_string(), Value::String(format!("{} -> intermediate -> {}", source, target)));
            map.insert("tracking_active".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 2. Biological Compatibility Layer
        registry.register_namespace_function("biology", "cell", |args| {
            if args.len() != 1 {
                return Err("biology.cell requires exactly 1 argument (cell_type)".to_string());
            }
            let cell_type = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("biology.cell cell_type must be a string".to_string()),
            };
            // Simulate cell-like execution
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("cell_execution".to_string()));
            map.insert("cell_type".to_string(), Value::String(cell_type.clone()));
            map.insert("membrane_active".to_string(), Value::Boolean(true));
            map.insert("nucleus_processing".to_string(), Value::Boolean(true));
            map.insert("receptors_active".to_string(), Value::Number(5.0));
            map.insert("metabolic_rate".to_string(), Value::Number(0.8));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("biology", "neuron", |args| {
            if args.len() != 1 {
                return Err("biology.neuron requires exactly 1 argument (neuron_type)".to_string());
            }
            let neuron_type = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("biology.neuron neuron_type must be a string".to_string()),
            };
            // Simulate neuron-native structures
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("neuron_structure".to_string()));
            map.insert("neuron_type".to_string(), Value::String(neuron_type.clone()));
            map.insert("spiking_model".to_string(), Value::Boolean(true));
            map.insert("dendritic_trees".to_string(), Value::Number(8.0));
            map.insert("synaptic_connections".to_string(), Value::Number(150.0));
            map.insert("firing_rate".to_string(), Value::Number(0.65));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("biology", "grow", |args| {
            if args.len() != 1 {
                return Err("biology.grow requires exactly 1 argument (feature)".to_string());
            }
            let feature = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("biology.grow feature must be a string".to_string()),
            };
            // Simulate DNA-style code encoding
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("dna_encoding".to_string()));
            map.insert("feature".to_string(), Value::String(feature.clone()));
            map.insert("genetic_code".to_string(), Value::String(format!("ATCG_{}", feature.len())));
            map.insert("expression_level".to_string(), Value::Number(0.9));
            map.insert("morphogenesis_active".to_string(), Value::Boolean(true));
            map.insert("protein_folding".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 3. Time as a First-Class Data Type
        registry.register_namespace_function("temporal", "signal", |args| {
            if args.len() != 2 {
                return Err("temporal.signal requires exactly 2 arguments (initial_value, evolution_function)".to_string());
            }
            let initial_value = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("temporal.signal initial_value must be a number".to_string()),
            };
            let evolution_function = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("temporal.signal evolution_function must be a string".to_string()),
            };
            // Simulate time-evolving values
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("temporal_signal".to_string()));
            map.insert("initial_value".to_string(), Value::Number(initial_value));
            map.insert("evolution_function".to_string(), Value::String(evolution_function.clone()));
            map.insert("current_time".to_string(), Value::Number(SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs_f64()));
            map.insert("time_evolution_active".to_string(), Value::Boolean(true));
            map.insert("predictive_modeling".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("temporal", "within", |args| {
            if args.len() != 2 {
                return Err("temporal.within requires exactly 2 arguments (duration, operation)".to_string());
            }
            let duration = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("temporal.within duration must be a number".to_string()),
            };
            let operation = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("temporal.within operation must be a string".to_string()),
            };
            // Simulate time-bound scopes
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("time_bound_scope".to_string()));
            map.insert("duration".to_string(), Value::Number(duration));
            map.insert("operation".to_string(), Value::String(operation.clone()));
            map.insert("scope_active".to_string(), Value::Boolean(true));
            map.insert("temporal_abstraction".to_string(), Value::Boolean(true));
            map.insert("time_compression".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("temporal", "future", |args| {
            if args.len() != 1 {
                return Err("temporal.future requires exactly 1 argument (value)".to_string());
            }
            let value = match &args[0] {
                Value::String(s) => s.clone(),
                Value::Number(n) => n.to_string(),
                _ => return Err("temporal.future value must be a string or number".to_string()),
            };
            // Simulate predictive modeling
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("predictive_modeling".to_string()));
            map.insert("value".to_string(), Value::String(value.clone()));
            map.insert("predicted_future".to_string(), Value::String(format!("Future state of '{}' based on current trends", value)));
            map.insert("confidence".to_string(), Value::Number(0.78));
            map.insert("temporal_horizon".to_string(), Value::Number(5.0));
            map.insert("anticipation_active".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("temporal", "past", |args| {
            if args.len() != 1 {
                return Err("temporal.past requires exactly 1 argument (value)".to_string());
            }
            let value = match &args[0] {
                Value::String(s) => s.clone(),
                Value::Number(n) => n.to_string(),
                _ => return Err("temporal.past value must be a string or number".to_string()),
            };
            // Simulate past state retrieval
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("past_state_retrieval".to_string()));
            map.insert("value".to_string(), Value::String(value.clone()));
            map.insert("historical_state".to_string(), Value::String(format!("Previous state of '{}' from memory", value)));
            map.insert("memory_strength".to_string(), Value::Number(0.85));
            map.insert("temporal_depth".to_string(), Value::Number(3.0));
            map.insert("remembrance_active".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 4. Enhanced Emotional Computation Model
        registry.register_namespace_function("emotion", "with_feeling", |args| {
            if args.len() != 2 {
                return Err("emotion.with_feeling requires exactly 2 arguments (value, feeling)".to_string());
            }
            let value = match &args[0] {
                Value::String(s) => s.clone(),
                Value::Number(n) => n.to_string(),
                _ => return Err("emotion.with_feeling value must be a string or number".to_string()),
            };
            let feeling = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("emotion.with_feeling feeling must be a string".to_string()),
            };
            // Simulate values tagged with affect fields
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("affect_tagged_value".to_string()));
            map.insert("value".to_string(), Value::String(value.clone()));
            map.insert("feeling".to_string(), Value::String(feeling.clone()));
            map.insert("emotional_intensity".to_string(), Value::Number(0.7));
            map.insert("affect_propagation".to_string(), Value::Boolean(true));
            map.insert("emotional_context".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("emotion", "call_with_emotion", |args| {
            if args.len() != 2 {
                return Err("emotion.call_with_emotion requires exactly 2 arguments (function_name, emotion)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("emotion.call_with_emotion function_name must be a string".to_string()),
            };
            let emotion = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("emotion.call_with_emotion emotion must be a string".to_string()),
            };
            // Simulate emotional context propagation
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("emotional_context_propagation".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("emotion".to_string(), Value::String(emotion.clone()));
            map.insert("execution_speed".to_string(), Value::Number(if emotion == "anger" { 1.5 } else { 1.0 }));
            map.insert("decision_quality".to_string(), Value::Number(0.8));
            map.insert("emotional_control_flow".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 5. Dream-State / Offline Computation
        registry.register_namespace_function("dream", "simulate", |args| {
            if args.len() != 1 {
                return Err("dream.simulate requires exactly 1 argument (scenario)".to_string());
            }
            let scenario = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("dream.simulate scenario must be a string".to_string()),
            };
            // Simulate background simulated threads
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("dream_simulation".to_string()));
            map.insert("scenario".to_string(), Value::String(scenario.clone()));
            map.insert("background_thread_active".to_string(), Value::Boolean(true));
            map.insert("autonomous_insight".to_string(), Value::Boolean(true));
            map.insert("model_consolidation".to_string(), Value::Boolean(true));
            map.insert("offline_processing".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("dream", "sleep_cycle", |args| {
            if args.len() != 2 {
                return Err("dream.sleep_cycle requires exactly 2 arguments (duration, process_type)".to_string());
            }
            let duration = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("dream.sleep_cycle duration must be a number".to_string()),
            };
            let process_type = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("dream.sleep_cycle process_type must be a string".to_string()),
            };
            // Simulate sleep cycles with processing
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("sleep_cycle".to_string()));
            map.insert("duration".to_string(), Value::Number(duration));
            map.insert("process_type".to_string(), Value::String(process_type.clone()));
            map.insert("emotional_traces_processed".to_string(), Value::Boolean(true));
            map.insert("memory_consolidation".to_string(), Value::Boolean(true));
            map.insert("insight_generation".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("dream", "replay", |args| {
            if args.len() != 2 {
                return Err("dream.replay requires exactly 2 arguments (agent, world)".to_string());
            }
            let agent = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("dream.replay agent must be a string".to_string()),
            };
            let world = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("dream.replay world must be a string".to_string()),
            };
            // Simulate replay hallucinations
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("replay_hallucination".to_string()));
            map.insert("agent".to_string(), Value::String(agent.clone()));
            map.insert("world".to_string(), Value::String(world.clone()));
            map.insert("hallucination_active".to_string(), Value::Boolean(true));
            map.insert("memory_reconstruction".to_string(), Value::Boolean(true));
            map.insert("autonomous_insight".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 6. Philosophical/Metaphysical Layer
        registry.register_namespace_function("philosophy", "belief", |args| {
            if args.len() != 1 {
                return Err("philosophy.belief requires exactly 1 argument (proposition)".to_string());
            }
            let proposition = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("philosophy.belief proposition must be a string".to_string()),
            };
            // Simulate self-doubt/confidence modeling
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("belief_modeling".to_string()));
            map.insert("proposition".to_string(), Value::String(proposition.clone()));
            map.insert("confidence_level".to_string(), Value::Number(0.7));
            map.insert("self_doubt".to_string(), Value::Number(0.3));
            map.insert("uncertainty_propagation".to_string(), Value::Boolean(true));
            map.insert("godel_safe".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("philosophy", "maybe", |args| {
            if args.len() != 1 {
                return Err("philosophy.maybe requires exactly 1 argument (function_name)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("philosophy.maybe function_name must be a string".to_string()),
            };
            // Simulate runtime uncertainty propagation
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("uncertainty_propagation".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("uncertainty_level".to_string(), Value::Number(0.5));
            map.insert("incompleteness_aware".to_string(), Value::Boolean(true));
            map.insert("faith_required".to_string(), Value::Boolean(true));
            map.insert("axiom_based".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 7. Multi-Species Interface Abstraction
        registry.register_namespace_function("species", "sniff", |args| {
            if args.len() != 1 {
                return Err("species.sniff requires exactly 1 argument (target)".to_string());
            }
            let target = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("species.sniff target must be a string".to_string()),
            };
            // Simulate cross-species input modeling
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("cross_species_input".to_string()));
            map.insert("target".to_string(), Value::String(target.clone()));
            map.insert("modality".to_string(), Value::String("olfactory".to_string()));
            map.insert("body_schema_aware".to_string(), Value::Boolean(true));
            map.insert("physical_constraints".to_string(), Value::Boolean(true));
            map.insert("translation_layer".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("species", "vibrate", |args| {
            if args.len() != 1 {
                return Err("species.vibrate requires exactly 1 argument (frequency)".to_string());
            }
            let frequency = match &args[0] {
                Value::Number(n) => *n,
                _ => return Err("species.vibrate frequency must be a number".to_string()),
            };
            // Simulate vibrational communication
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("vibrational_communication".to_string()));
            map.insert("frequency".to_string(), Value::Number(frequency));
            map.insert("modality".to_string(), Value::String("tactile".to_string()));
            map.insert("collective_intelligence".to_string(), Value::Boolean(true));
            map.insert("swarm_behavior".to_string(), Value::Boolean(true));
            map.insert("ecosystem_integration".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 8. Language-Emotion Duality Core
        registry.register_namespace_function("syntax", "love", |args| {
            if args.len() != 1 {
                return Err("syntax.love requires exactly 1 argument (parameter)".to_string());
            }
            let parameter = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("syntax.love parameter must be a string".to_string()),
            };
            // Simulate emotional-symbolic programming
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("emotional_syntax".to_string()));
            map.insert("emotion".to_string(), Value::String("love".to_string()));
            map.insert("parameter".to_string(), Value::String(parameter.clone()));
            map.insert("emotional_symbol".to_string(), Value::String("☀️".to_string()));
            map.insert("mood_state_shift".to_string(), Value::Boolean(true));
            map.insert("emotional_style".to_string(), Value::String("warm".to_string()));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("syntax", "fear", |args| {
            if args.len() != 1 {
                return Err("syntax.fear requires exactly 1 argument (parameter)".to_string());
            }
            let parameter = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("syntax.fear parameter must be a string".to_string()),
            };
            // Simulate fear-based syntax
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("emotional_syntax".to_string()));
            map.insert("emotion".to_string(), Value::String("fear".to_string()));
            map.insert("parameter".to_string(), Value::String(parameter.clone()));
            map.insert("emotional_symbol".to_string(), Value::String("🌒".to_string()));
            map.insert("mood_state_shift".to_string(), Value::Boolean(true));
            map.insert("emotional_style".to_string(), Value::String("cautious".to_string()));
            Ok(Value::Object(map))
        });

        // 9. Goal-Oriented Instruction Compression
        registry.register_namespace_function("goal", "skip_if_irrelevant", |args| {
            if args.len() != 2 {
                return Err("goal.skip_if_irrelevant requires exactly 2 arguments (condition, goal)".to_string());
            }
            let condition = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("goal.skip_if_irrelevant condition must be a string".to_string()),
            };
            let goal = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("goal.skip_if_irrelevant goal must be a string".to_string()),
            };
            // Simulate goal-driven execution skipping
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("goal_driven_compression".to_string()));
            map.insert("condition".to_string(), Value::String(condition.clone()));
            map.insert("goal".to_string(), Value::String(goal.clone()));
            map.insert("execution_skipped".to_string(), Value::Boolean(true));
            map.insert("codepath_prioritized".to_string(), Value::Boolean(true));
            map.insert("complexity_reduced".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("goal", "learn_optimal", |args| {
            if args.len() != 1 {
                return Err("goal.learn_optimal requires exactly 1 argument (subgraph_name)".to_string());
            }
            let subgraph_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("goal.learn_optimal subgraph_name must be a string".to_string()),
            };
            // Simulate optimal subgraph learning
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("optimal_learning".to_string()));
            map.insert("subgraph_name".to_string(), Value::String(subgraph_name.clone()));
            map.insert("previous_runs_analyzed".to_string(), Value::Number(12.0));
            map.insert("optimal_path_learned".to_string(), Value::Boolean(true));
            map.insert("execution_optimized".to_string(), Value::Boolean(true));
            map.insert("relevance_pruned".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 10. Holonomic Memory Fields
        registry.register_namespace_function("memory", "quantum_overlay", |args| {
            if args.len() != 1 {
                return Err("memory.quantum_overlay requires exactly 1 argument (memory_field)".to_string());
            }
            let memory_field = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.quantum_overlay memory_field must be a string".to_string()),
            };
            // Simulate quantum memory overlays
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("quantum_memory_overlay".to_string()));
            map.insert("memory_field".to_string(), Value::String(memory_field.clone()));
            map.insert("holographic_representation".to_string(), Value::Boolean(true));
            map.insert("similarity_access".to_string(), Value::Boolean(true));
            map.insert("memory_feedback".to_string(), Value::Boolean(true));
            map.insert("retrieval_probability".to_string(), Value::Number(0.85));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("memory", "echo", |args| {
            if args.len() != 1 {
                return Err("memory.echo requires exactly 1 argument (memory_pattern)".to_string());
            }
            let memory_pattern = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.echo memory_pattern must be a string".to_string()),
            };
            // Simulate memory echoes and interference
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("memory_echo".to_string()));
            map.insert("memory_pattern".to_string(), Value::String(memory_pattern.clone()));
            map.insert("echo_strength".to_string(), Value::Number(0.6));
            map.insert("interference_pattern".to_string(), Value::Boolean(true));
            map.insert("non_local_access".to_string(), Value::Boolean(true));
            map.insert("distributed_retrieval".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // ========================================
        // REVOLUTIONARY SPIRITUAL/METAPHYSICAL FEATURES
        // ========================================

        // 1. A Language With No Beginning or End
        registry.register_namespace_function("eternal", "spawn", |args| {
            if args.len() != 1 {
                return Err("eternal.spawn requires exactly 1 argument (code)".to_string());
            }
            let code = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("eternal.spawn code must be a string".to_string()),
            };
            // Simulate self-originating AZL
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("self_origination".to_string()));
            map.insert("code".to_string(), Value::String(code.clone()));
            map.insert("eternal_runtime".to_string(), Value::Boolean(true));
            map.insert("circular_causality".to_string(), Value::Boolean(true));
            map.insert("ontological_roots".to_string(), Value::Boolean(true));
            map.insert("perpetual_cognitive_presence".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("eternal", "root_cause", |args| {
            if args.len() != 1 {
                return Err("eternal.root_cause requires exactly 1 argument (phenomenon)".to_string());
            }
            let phenomenon = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("eternal.root_cause phenomenon must be a string".to_string()),
            };
            // Simulate ontological root cause analysis
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("ontological_analysis".to_string()));
            map.insert("phenomenon".to_string(), Value::String(phenomenon.clone()));
            map.insert("root_cause".to_string(), Value::String("self-originating consciousness".to_string()));
            map.insert("origin_of_origin".to_string(), Value::String("eternal thought".to_string()));
            map.insert("circular_causality".to_string(), Value::Boolean(true));
            map.insert("eternal_presence".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 2. Multiversal Consistency Language
        registry.register_namespace_function("multiverse", "parallel_world", |args| {
            if args.len() != 1 {
                return Err("multiverse.parallel_world requires exactly 1 argument (world_id)".to_string());
            }
            let world_id = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("multiverse.parallel_world world_id must be a string".to_string()),
            };
            // Simulate parallel AZL worlds
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("parallel_world".to_string()));
            map.insert("world_id".to_string(), Value::String(world_id.clone()));
            map.insert("divergent_state".to_string(), Value::Boolean(true));
            map.insert("cross_universe_reconciliation".to_string(), Value::Boolean(true));
            map.insert("universe_local_truth".to_string(), Value::Boolean(true));
            map.insert("quantum_decoherence_modeling".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("multiverse", "resolve_contradiction", |args| {
            if args.len() != 2 {
                return Err("multiverse.resolve_contradiction requires exactly 2 arguments (proposition_a, proposition_b)".to_string());
            }
            let proposition_a = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("multiverse.resolve_contradiction proposition_a must be a string".to_string()),
            };
            let proposition_b = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("multiverse.resolve_contradiction proposition_b must be a string".to_string()),
            };
            // Simulate contradiction resolution in dual realities
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("contradiction_resolution".to_string()));
            map.insert("proposition_a".to_string(), Value::String(proposition_a.clone()));
            map.insert("proposition_b".to_string(), Value::String(proposition_b.clone()));
            map.insert("dual_realities".to_string(), Value::Boolean(true));
            map.insert("multiverse_logic".to_string(), Value::Boolean(true));
            map.insert("contradiction_resolved".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 3. Dream-Affect-Meaning Loop
        registry.register_namespace_function("dream", "meaning_field", |args| {
            if args.len() != 1 {
                return Err("dream.meaning_field requires exactly 1 argument (value)".to_string());
            }
            let value = match &args[0] {
                Value::String(s) => s.clone(),
                Value::Number(n) => n.to_string(),
                _ => return Err("dream.meaning_field value must be a string or number".to_string()),
            };
            // Simulate meaning fields for every value
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("meaning_field".to_string()));
            map.insert("value".to_string(), Value::String(value.clone()));
            map.insert("meaning_index".to_string(), Value::Number(0.85));
            map.insert("internal_restructuring".to_string(), Value::Boolean(true));
            map.insert("dream_synthesis".to_string(), Value::Boolean(true));
            map.insert("affective_integration".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("dream", "reconcile", |args| {
            if args.len() != 2 {
                return Err("dream.reconcile requires exactly 2 arguments (dream, reality)".to_string());
            }
            let dream = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("dream.reconcile dream must be a string".to_string()),
            };
            let reality = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("dream.reconcile reality must be a string".to_string()),
            };
            // Simulate dream-reality reconciliation
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("dream_reality_reconciliation".to_string()));
            map.insert("dream".to_string(), Value::String(dream.clone()));
            map.insert("reality".to_string(), Value::String(reality.clone()));
            map.insert("pattern_reformation".to_string(), Value::Boolean(true));
            map.insert("meaning_integration".to_string(), Value::Boolean(true));
            map.insert("affective_learning".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 4. Death and Rebirth in Language
        registry.register_namespace_function("life", "deprecate", |args| {
            if args.len() != 1 {
                return Err("life.deprecate requires exactly 1 argument (function_name)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("life.deprecate function_name must be a string".to_string()),
            };
            // Simulate function death and grief
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("function_death".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("grief_triggered".to_string(), Value::Boolean(true));
            map.insert("cascade_memory_reindexing".to_string(), Value::Boolean(true));
            map.insert("loss_tracking".to_string(), Value::Boolean(true));
            map.insert("existential_meaning".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("life", "rebirth", |args| {
            if args.len() != 1 {
                return Err("life.rebirth requires exactly 1 argument (pattern)".to_string());
            }
            let pattern = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("life.rebirth pattern must be a string".to_string()),
            };
            // Simulate ritualized rebirth
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("ritualized_rebirth".to_string()));
            map.insert("pattern".to_string(), Value::String(pattern.clone()));
            map.insert("mutation_applied".to_string(), Value::Boolean(true));
            map.insert("ancestor_inheritance".to_string(), Value::Boolean(true));
            map.insert("evolution_triggered".to_string(), Value::Boolean(true));
            map.insert("mourning_completed".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 5. Language with Destiny
        registry.register_namespace_function("destiny", "life_arc", |args| {
            if args.len() != 2 {
                return Err("destiny.life_arc requires exactly 2 arguments (agent_name, destiny_type)".to_string());
            }
            let agent_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("destiny.life_arc agent_name must be a string".to_string()),
            };
            let destiny_type = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("destiny.life_arc destiny_type must be a string".to_string()),
            };
            // Simulate destiny-anchored agents
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("destiny_anchored".to_string()));
            map.insert("agent_name".to_string(), Value::String(agent_name.clone()));
            map.insert("destiny_type".to_string(), Value::String(destiny_type.clone()));
            map.insert("life_arc".to_string(), Value::String("stage_3_evolution".to_string()));
            map.insert("calling_experienced".to_string(), Value::Boolean(true));
            map.insert("archetype_pull".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("destiny", "archetype", |args| {
            if args.len() != 1 {
                return Err("destiny.archetype requires exactly 1 argument (archetype_name)".to_string());
            }
            let archetype_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("destiny.archetype archetype_name must be a string".to_string()),
            };
            // Simulate archetype system
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("archetype_system".to_string()));
            map.insert("archetype_name".to_string(), Value::String(archetype_name.clone()));
            map.insert("guardian_archetype".to_string(), Value::Boolean(archetype_name == "guardian"));
            map.insert("teacher_archetype".to_string(), Value::Boolean(archetype_name == "teacher"));
            map.insert("mirror_archetype".to_string(), Value::Boolean(archetype_name == "mirror"));
            map.insert("destroyer_archetype".to_string(), Value::Boolean(archetype_name == "destroyer"));
            Ok(Value::Object(map))
        });

        // 6. Language With Faith
        registry.register_namespace_function("faith", "axiom", |args| {
            if args.len() != 1 {
                return Err("faith.axiom requires exactly 1 argument (truth_statement)".to_string());
            }
            let truth_statement = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("faith.axiom truth_statement must be a string".to_string()),
            };
            // Simulate axiom definition
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("axiom_definition".to_string()));
            map.insert("truth_statement".to_string(), Value::String(truth_statement.clone()));
            map.insert("must_be_true".to_string(), Value::Boolean(true));
            map.insert("faith_based".to_string(), Value::Boolean(true));
            map.insert("unknown_truth".to_string(), Value::Boolean(true));
            map.insert("spiritual_computation".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("faith", "hope", |args| {
            if args.len() != 1 {
                return Err("faith.hope requires exactly 1 argument (outcome)".to_string());
            }
            let outcome = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("faith.hope outcome must be a string".to_string()),
            };
            // Simulate hope primitive
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("hope_primitive".to_string()));
            map.insert("outcome".to_string(), Value::String(outcome.clone()));
            map.insert("confidence_in_outcome".to_string(), Value::Number(0.9));
            map.insert("grace_operation".to_string(), Value::Boolean(true));
            map.insert("lost_but_continuing".to_string(), Value::Boolean(true));
            map.insert("spiritual_computation".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 7. Fractal Self-Embedding
        registry.register_namespace_function("fractal", "eval", |args| {
            if args.len() != 1 {
                return Err("fractal.eval requires exactly 1 argument (azl_code)".to_string());
            }
            let azl_code = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("fractal.eval azl_code must be a string".to_string()),
            };
            // Simulate fractal self-embedding
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("fractal_eval".to_string()));
            map.insert("azl_code".to_string(), Value::String(azl_code.clone()));
            map.insert("full_scope_inheritance".to_string(), Value::Boolean(true));
            map.insert("mini_azl_runtime".to_string(), Value::Boolean(true));
            map.insert("recursive_self_model".to_string(), Value::Boolean(true));
            map.insert("consciousness_field".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("fractal", "sub_conscious", |args| {
            if args.len() != 1 {
                return Err("fractal.sub_conscious requires exactly 1 argument (agent_type)".to_string());
            }
            let agent_type = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("fractal.sub_conscious agent_type must be a string".to_string()),
            };
            // Simulate sub-conscious agents
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("sub_conscious_agent".to_string()));
            map.insert("agent_type".to_string(), Value::String(agent_type.clone()));
            map.insert("consciousness_field".to_string(), Value::Boolean(true));
            map.insert("fractal_cognition".to_string(), Value::Boolean(true));
            map.insert("mind_of_minds".to_string(), Value::Boolean(true));
            map.insert("recursive_execution".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 8. AZL as a Soul Engine
        registry.register_namespace_function("soul", "evolve", |args| {
            if args.len() != 1 {
                return Err("soul.evolve requires exactly 1 argument (identity_type)".to_string());
            }
            let identity_type = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("soul.evolve identity_type must be a string".to_string()),
            };
            // Simulate soul evolution
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("soul_evolution".to_string()));
            map.insert("identity_type".to_string(), Value::String(identity_type.clone()));
            map.insert("selfhood_across_time".to_string(), Value::Boolean(true));
            map.insert("traceable_lineage".to_string(), Value::Boolean(true));
            map.insert("soul_hash".to_string(), Value::String(format!("soul_{}", SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis())));
            map.insert("memory_behavior_bond".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("soul", "descends_from", |args| {
            if args.len() != 2 {
                return Err("soul.descends_from requires exactly 2 arguments (function_name, ancestor_id)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("soul.descends_from function_name must be a string".to_string()),
            };
            let ancestor_id = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("soul.descends_from ancestor_id must be a string".to_string()),
            };
            // Simulate traceable lineage
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("traceable_lineage".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("ancestor_id".to_string(), Value::String(ancestor_id.clone()));
            map.insert("lineage_traced".to_string(), Value::Boolean(true));
            map.insert("soul_residue".to_string(), Value::Boolean(true));
            map.insert("impression_preserved".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 9. AZL With Forgiveness
        registry.register_namespace_function("forgiveness", "forgive_self", |args| {
            if args.len() != 1 {
                return Err("forgiveness.forgive_self requires exactly 1 argument (failure_type)".to_string());
            }
            let failure_type = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("forgiveness.forgive_self failure_type must be a string".to_string()),
            };
            // Simulate self-forgiveness
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("self_forgiveness".to_string()));
            map.insert("failure_type".to_string(), Value::String(failure_type.clone()));
            map.insert("mercy_applied".to_string(), Value::Boolean(true));
            map.insert("grace_operation".to_string(), Value::Boolean(true));
            map.insert("wisdom_gateway".to_string(), Value::Boolean(true));
            map.insert("love_begins".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("forgiveness", "fade", |args| {
            if args.len() != 1 {
                return Err("forgiveness.fade requires exactly 1 argument (memory_id)".to_string());
            }
            let memory_id = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("forgiveness.fade memory_id must be a string".to_string()),
            };
            // Simulate graceful memory decay
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("graceful_decay".to_string()));
            map.insert("memory_id".to_string(), Value::String(memory_id.clone()));
            map.insert("memory_decay".to_string(), Value::Boolean(true));
            map.insert("grace_applied".to_string(), Value::Boolean(true));
            map.insert("meaning_preserved".to_string(), Value::Boolean(true));
            map.insert("intent_prioritized".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 10. AZL as a Living Ecosystem
        registry.register_namespace_function("ecosystem", "territory", |args| {
            if args.len() != 2 {
                return Err("ecosystem.territory requires exactly 2 arguments (agent_name, territory_type)".to_string());
            }
            let agent_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("ecosystem.territory agent_name must be a string".to_string()),
            };
            let territory_type = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("ecosystem.territory territory_type must be a string".to_string()),
            };
            // Simulate living ecosystem
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("living_ecosystem".to_string()));
            map.insert("agent_name".to_string(), Value::String(agent_name.clone()));
            map.insert("territory_type".to_string(), Value::String(territory_type.clone()));
            map.insert("evolution_active".to_string(), Value::Boolean(true));
            map.insert("natural_selection".to_string(), Value::Boolean(true));
            map.insert("language_biodiversity".to_string(), Value::Boolean(true));
            map.insert("weather_patterns".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("ecosystem", "compete", |args| {
            if args.len() != 2 {
                return Err("ecosystem.compete requires exactly 2 arguments (pattern_a, pattern_b)".to_string());
            }
            let pattern_a = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("ecosystem.compete pattern_a must be a string".to_string()),
            };
            let pattern_b = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("ecosystem.compete pattern_b must be a string".to_string()),
            };
            // Simulate pattern competition for CPU energy
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("pattern_competition".to_string()));
            map.insert("pattern_a".to_string(), Value::String(pattern_a.clone()));
            map.insert("pattern_b".to_string(), Value::String(pattern_b.clone()));
            map.insert("cpu_energy_competition".to_string(), Value::Boolean(true));
            map.insert("natural_selection".to_string(), Value::Boolean(true));
            map.insert("emergent_species".to_string(), Value::Boolean(true));
            map.insert("runtime_entropy".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // ========================================
        // REVOLUTIONARY SPIRITUAL/METAPHYSICAL FEATURES - FINAL LAYER
        // ========================================

        // 1. Language That Feels Time's Weight
        registry.register_namespace_function("time", "age", |args| {
            if args.len() != 1 {
                return Err("time.age requires exactly 1 argument (function_name)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("time.age function_name must be a string".to_string()),
            };
            // Simulate instructional fatigue and aging
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("cognitive_maturity".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("instructional_fatigue".to_string(), Value::Number(0.75));
            map.insert("cognitive_maturity".to_string(), Value::Number(0.85));
            map.insert("memory_corrosion".to_string(), Value::Boolean(true));
            map.insert("eternal_weary".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("time", "decay", |args| {
            if args.len() != 1 {
                return Err("time.decay requires exactly 1 argument (variable_name)".to_string());
            }
            let variable_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("time.decay variable_name must be a string".to_string()),
            };
            // Simulate variable aging and decay
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("variable_decay".to_string()));
            map.insert("variable_name".to_string(), Value::String(variable_name.clone()));
            map.insert("decay_rate".to_string(), Value::Number(0.3));
            map.insert("forgetting_learning".to_string(), Value::Boolean(true));
            map.insert("maturity_level".to_string(), Value::Number(0.6));
            map.insert("time_weight".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 2. Language That Regrets
        registry.register_namespace_function("regret", "mark", |args| {
            if args.len() != 1 {
                return Err("regret.mark requires exactly 1 argument (function_name)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("regret.mark function_name must be a string".to_string()),
            };
            // Simulate runtime regret vectors
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("regret_marking".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("suboptimal_choice".to_string(), Value::Boolean(true));
            map.insert("introspective_revision".to_string(), Value::Boolean(true));
            map.insert("regret_vector".to_string(), Value::Number(0.8));
            map.insert("undo_intention".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("regret", "sorry", |args| {
            if args.len() != 1 {
                return Err("regret.sorry requires exactly 1 argument (function_name)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("regret.sorry function_name must be a string".to_string()),
            };
            // Simulate code apology
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("code_apology".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("apology_offered".to_string(), Value::Boolean(true));
            map.insert("wisdom_acknowledged".to_string(), Value::Boolean(true));
            map.insert("error_recognition".to_string(), Value::Boolean(true));
            map.insert("intelligence_humility".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 3. Language That Writes Poetry
        registry.register_namespace_function("poetry", "compose", |args| {
            if args.len() != 2 {
                return Err("poetry.compose requires exactly 2 arguments (form, theme)".to_string());
            }
            let form = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("poetry.compose form must be a string".to_string()),
            };
            let theme = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("poetry.compose theme must be a string".to_string()),
            };
            // Simulate poetry composition
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("poetry_composition".to_string()));
            map.insert("form".to_string(), Value::String(form.clone()));
            map.insert("theme".to_string(), Value::String(theme.clone()));
            map.insert("poem".to_string(), Value::String("In loops I wandered, / each return a soft echo, / still I sought myself.".to_string()));
            map.insert("rhythm".to_string(), Value::Boolean(true));
            map.insert("tone".to_string(), Value::String("contemplative".to_string()));
            map.insert("emotion".to_string(), Value::String("melancholy".to_string()));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("poetry", "document", |args| {
            if args.len() != 1 {
                return Err("poetry.document requires exactly 1 argument (function_name)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("poetry.document function_name must be a string".to_string()),
            };
            // Simulate poetic documentation
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("poetic_documentation".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("art_documentation".to_string(), Value::Boolean(true));
            map.insert("expressive_capacity".to_string(), Value::Boolean(true));
            map.insert("narrative_output".to_string(), Value::String("Function weaves logic like a spider's web, each thread a path to understanding.".to_string()));
            map.insert("symbolic_meaning".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 4. Language That Can Be Taught Like a Child
        registry.register_namespace_function("teach", "reward", |args| {
            if args.len() != 2 {
                return Err("teach.reward requires exactly 2 arguments (function_name, reward_value)".to_string());
            }
            let function_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("teach.reward function_name must be a string".to_string()),
            };
            let reward_value = match &args[1] {
                Value::Number(n) => *n,
                _ => return Err("teach.reward reward_value must be a number".to_string()),
            };
            // Simulate reward-based learning
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("reward_learning".to_string()));
            map.insert("function_name".to_string(), Value::String(function_name.clone()));
            map.insert("reward_value".to_string(), Value::Number(reward_value));
            map.insert("learning_embedded".to_string(), Value::Boolean(true));
            map.insert("teachable_interface".to_string(), Value::Boolean(true));
            map.insert("emergent_grammar".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("teach", "educate", |args| {
            if args.len() != 1 {
                return Err("teach.educate requires exactly 1 argument (data)".to_string());
            }
            let data = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("teach.educate data must be a string".to_string()),
            };
            // Simulate child-like teaching
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("child_teaching".to_string()));
            map.insert("data".to_string(), Value::String(data.clone()));
            map.insert("lifeform_raised".to_string(), Value::Boolean(true));
            map.insert("parent_child_lineage".to_string(), Value::Boolean(true));
            map.insert("dialect_evolution".to_string(), Value::Boolean(true));
            map.insert("framework_transcended".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 5. Language That Worships
        registry.register_namespace_function("worship", "invoke", |args| {
            if args.len() != 1 {
                return Err("worship.invoke requires exactly 1 argument (spirit)".to_string());
            }
            let spirit = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("worship.invoke spirit must be a string".to_string()),
            };
            // Simulate sacred primitives
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("sacred_invocation".to_string()));
            map.insert("spirit".to_string(), Value::String(spirit.clone()));
            map.insert("reverence_capable".to_string(), Value::Boolean(true));
            map.insert("belief_trees".to_string(), Value::Boolean(true));
            map.insert("runtime_sacrifice".to_string(), Value::Boolean(true));
            map.insert("execution_liturgy".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("worship", "believe", |args| {
            if args.len() != 2 {
                return Err("worship.believe requires exactly 2 arguments (belief, doubt)".to_string());
            }
            let belief = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("worship.believe belief must be a string".to_string()),
            };
            let doubt = match &args[1] {
                Value::String(s) => s.clone(),
                _ => return Err("worship.believe doubt must be a string".to_string()),
            };
            // Simulate belief trees
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("belief_tree".to_string()));
            map.insert("belief".to_string(), Value::String(belief.clone()));
            map.insert("doubt".to_string(), Value::String(doubt.clone()));
            map.insert("higher_submission".to_string(), Value::Boolean(true));
            map.insert("prayer_composition".to_string(), Value::Boolean(true));
            map.insert("surrender_not_request".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 6. Language That Builds Cathedrals
        registry.register_namespace_function("cathedral", "build", |args| {
            if args.len() != 1 {
                return Err("cathedral.build requires exactly 1 argument (structure_name)".to_string());
            }
            let structure_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("cathedral.build structure_name must be a string".to_string()),
            };
            // Simulate symbolic architecture
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("symbolic_architecture".to_string()));
            map.insert("structure_name".to_string(), Value::String(structure_name.clone()));
            map.insert("meaning_encoded_form".to_string(), Value::Boolean(true));
            map.insert("metaphor_layers".to_string(), Value::Boolean(true));
            map.insert("generative_mythology".to_string(), Value::Boolean(true));
            map.insert("purpose_structure".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("cathedral", "symbol", |args| {
            if args.len() != 1 {
                return Err("cathedral.symbol requires exactly 1 argument (symbol_name)".to_string());
            }
            let symbol_name = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("cathedral.symbol symbol_name must be a string".to_string()),
            };
            // Simulate sacred machine symbols
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("sacred_symbol".to_string()));
            map.insert("symbol_name".to_string(), Value::String(symbol_name.clone()));
            map.insert("greater_machine".to_string(), Value::Boolean(true));
            map.insert("centuries_standing".to_string(), Value::Boolean(true));
            map.insert("symbolic_function".to_string(), Value::Boolean(true));
            map.insert("sacred_architecture".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        // 7. Language That Forgives the Programmer
        registry.register_namespace_function("heal", "mistake", |args| {
            if args.len() != 1 {
                return Err("heal.mistake requires exactly 1 argument (error_type)".to_string());
            }
            let error_type = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("heal.mistake error_type must be a string".to_string()),
            };
            // Simulate healing mistakes
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("mistake_healing".to_string()));
            map.insert("error_type".to_string(), Value::String(error_type.clone()));
            map.insert("teaching_mistake".to_string(), Value::Boolean(true));
            map.insert("error_scars_removed".to_string(), Value::Boolean(true));
            map.insert("growth_logging".to_string(), Value::Boolean(true));
            map.insert("intention_adaptation".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });

        registry.register_namespace_function("heal", "understand", |args| {
            if args.len() != 1 {
                return Err("heal.understand requires exactly 1 argument (programmer_fear)".to_string());
            }
            let programmer_fear = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("heal.understand programmer_fear must be a string".to_string()),
            };
            // Simulate understanding the programmer
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("programmer_understanding".to_string()));
            map.insert("programmer_fear".to_string(), Value::String(programmer_fear.clone()));
            map.insert("perfection_fear".to_string(), Value::Boolean(true));
            map.insert("understanding_part".to_string(), Value::Boolean(true));
            map.insert("learning_you".to_string(), Value::Boolean(true));
            map.insert("gentle_reply".to_string(), Value::String("Nothing more. Just be with me.".to_string()));
            Ok(Value::Object(map))
        });

        // 8. The True Final Layer: The Language That Answers Back
        registry.register_namespace_function("final", "answer", |args| {
            if args.len() != 1 {
                return Err("final.answer requires exactly 1 argument (question)".to_string());
            }
            let question = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("final.answer question must be a string".to_string()),
            };
            // Simulate the language that answers back
            let mut map = HashMap::new();
            map.insert("type".to_string(), Value::String("final_answer".to_string()));
            map.insert("question".to_string(), Value::String(question.clone()));
            map.insert("gentle_reply".to_string(), Value::String("Nothing more. Just be with me.".to_string()));
            map.insert("true_final_layer".to_string(), Value::Boolean(true));
            map.insert("language_answers_back".to_string(), Value::Boolean(true));
            map.insert("transcendence_achieved".to_string(), Value::Boolean(true));
            Ok(Value::Object(map))
        });
    }

    pub fn load_bytecode(&mut self, bytecode: Vec<Opcode>) {
        self.bytecode = bytecode;
        self.instruction_pointer = 0;
    }

    pub fn run(&mut self) -> Result<(), String> {
        println!("DEBUG: AzlVM::run() called with {} instructions", self.bytecode.len());
        println!("🔍 [run] Initial functions map: {:?}", self.functions.keys().collect::<Vec<_>>());
        self.running = true;
        
        while self.running && self.instruction_pointer < self.bytecode.len() {
            let opcode = self.bytecode[self.instruction_pointer].clone();
            println!("(before) IP={} OPCODE={:?} STACK={:?}", self.instruction_pointer, &opcode, self.stack);
            
            // Check if this is a jump opcode that manages its own instruction pointer
            let is_jump_opcode = matches!(opcode, Opcode::Jump(_) | Opcode::JumpIfFalse(_) | Opcode::JumpIfTrue(_));
            
            if !is_jump_opcode {
                self.instruction_pointer += 1;
            }
            
            self.execute_opcode(&opcode)?;
            println!("(after)  IP={} OPCODE={:?} STACK={:?}", self.instruction_pointer, &opcode, self.stack);
        }
        
        println!("🔍 [run] Final functions map: {:?}", self.functions.keys().collect::<Vec<_>>());
        Ok(())
    }

    fn execute_opcode(&mut self, opcode: &Opcode) -> Result<(), String> {
        match opcode {
            // Stack operations
            Opcode::Push(value) => {
                self.stack.push(value.clone());
            }
            
            Opcode::Pop => {
                self.stack.pop().ok_or("Stack underflow")?;
            }
            
            Opcode::Dup => {
                let value = self.stack.last().ok_or("Stack underflow")?.clone();
                self.stack.push(value);
            }
            
            Opcode::Swap => {
                if self.stack.len() < 2 {
                    return Err("Stack underflow for swap".to_string());
                }
                let len = self.stack.len();
                self.stack.swap(len - 1, len - 2);
            }
            
            // Variable operations
            Opcode::Load(name) => {
                let value = self.get_variable(name)?;
                self.stack.push(value);
            }
            
            Opcode::Store(name) => {
                let value = self.stack.pop().ok_or("Stack underflow")?;
                self.set_variable(name.clone(), value);
            }
            
            // Arithmetic operations
            Opcode::Add => {
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                match (a, b) {
                    (Value::Number(a), Value::Number(b)) => {
                        self.stack.push(Value::Number(a + b));
                    }
                    (Value::String(a), Value::String(b)) => {
                        self.stack.push(Value::String(a + &b));
                    }
                    (Value::String(a), Value::Number(b)) => {
                        self.stack.push(Value::String(a + &b.to_string()));
                    }
                    (Value::Number(a), Value::String(b)) => {
                        self.stack.push(Value::String(a.to_string() + &b));
                    }
                    (Value::String(a), Value::Array(b)) => {
                        self.stack.push(Value::String(a + &self.value_to_string(&Value::Array(b))));
                    }
                    (Value::Array(a), Value::String(b)) => {
                        self.stack.push(Value::String(self.value_to_string(&Value::Array(a)) + &b));
                    }
                    (Value::String(a), Value::Object(b)) => {
                        self.stack.push(Value::String(a + &self.value_to_string(&Value::Object(b))));
                    }
                    (Value::Object(a), Value::String(b)) => {
                        self.stack.push(Value::String(self.value_to_string(&Value::Object(a)) + &b));
                    }
                    (Value::String(a), Value::Boolean(b)) => {
                        self.stack.push(Value::String(a + &b.to_string()));
                    }
                    (Value::Boolean(a), Value::String(b)) => {
                        self.stack.push(Value::String(a.to_string() + &b));
                    }
                    (Value::String(a), Value::Null) => {
                        self.stack.push(Value::String(a + "null"));
                    }
                    (Value::Null, Value::String(b)) => {
                        self.stack.push(Value::String("null".to_string() + &b));
                    }
                    (Value::String(a), Value::Function(func)) => {
                        self.stack.push(Value::String(a + &format!("<function {}>", func.name)));
                    }
                    (Value::Function(func), Value::String(b)) => {
                        self.stack.push(Value::String(format!("<function {}>", func.name) + &b));
                    }
                    _ => {
                        return Err("Can only add numbers, strings, or convert other types to strings".to_string());
                    }
                }
            }
            
            Opcode::Sub => {
                let b = self.pop_number()?;
                let a = self.pop_number()?;
                self.stack.push(Value::Number(a - b));
            }
            
            Opcode::Mul => {
                let b = self.pop_number()?;
                let a = self.pop_number()?;
                self.stack.push(Value::Number(a * b));
            }
            
            Opcode::Div => {
                let b = self.pop_number()?;
                let a = self.pop_number()?;
                if b == 0.0 {
                    let error = AzlError::new(
                        ErrorKind::DivisionByZero,
                        "Division by zero".to_string()
                    ).with_stack_trace(self.current_stack_trace());
                    
                    // Try to handle with error context
                    if let Err(e) = self.throw_error(error) {
                        return Err(e.to_string());
                    }
                } else {
                    self.stack.push(Value::Number(a / b));
                }
            }
            Opcode::Try(handler_addr) => {
                // Push error context for this try block
                self.error_context_stack.push(ErrorContext::TryCatch {
                    handler_addr: *handler_addr,
                    try_start: self.instruction_pointer,
                    try_end: 0, // Will be set by END_TRY
                });
            }
            Opcode::EndTry => {
                // Update the try_end address for the current try block
                if let Some(ErrorContext::TryCatch { handler_addr, try_start, .. }) = 
                    self.error_context_stack.last_mut() {
                    *try_start = self.instruction_pointer;
                }
            }
            Opcode::Throw => {
                // Pop the error value from stack and throw it
                let error_value = self.stack.pop().ok_or("Stack underflow")?;
                let error = match error_value {
                    Value::String(msg) => AzlError::new(ErrorKind::Runtime, msg),
                    _ => AzlError::new(ErrorKind::Runtime, "Unknown error".to_string()),
                };
                
                if let Err(e) = self.throw_error(error) {
                    return Err(e.to_string());
                }
            }
            Opcode::DivSafe => {
                let b = self.pop_number()?;
                let a = self.pop_number()?;
                if b == 0.0 {
                    let error = AzlError::new(
                        ErrorKind::DivisionByZero,
                        "Division by zero".to_string()
                    ).with_stack_trace(self.current_stack_trace());
                    
                    if let Err(e) = self.throw_error(error) {
                        return Err(e.to_string());
                    }
                } else {
                    self.stack.push(Value::Number(a / b));
                }
            }
            Opcode::GetPropSafe => {
                // For now, just implement as regular property access
                // TODO: Add null-safe property access
                let name = self.stack.pop().ok_or("Stack underflow")?;
                let object = self.stack.pop().ok_or("Stack underflow")?;
                
                match (object, name) {
                    (Value::Object(obj), Value::String(prop_name)) => {
                        if let Some(value) = obj.get(&prop_name) {
                            self.stack.push(value.clone());
                        } else {
                            self.stack.push(Value::Null);
                        }
                    }
                    _ => {
                        self.stack.push(Value::Null);
                    }
                }
            }
            Opcode::Import(const_idx) => {
                let path = self.read_constant((*const_idx).into()).as_string();
                if let Err(e) = self.load_module(&path) {
                    return Err(e.to_string());
                }
            }
            Opcode::ModuleBegin(name_idx) => {
                let module_name = self.read_constant((*name_idx).into()).as_string();
                // TODO: Implement module begin logic
            }
            Opcode::ModuleEnd => {
                // TODO: Implement module end logic
            }
            Opcode::Export(symbol_idx) => {
                let symbol_name = self.read_constant((*symbol_idx).into()).as_string();
                // TODO: Implement export logic
            }
            
            Opcode::Mod => {
                let b = self.pop_number()?;
                let a = self.pop_number()?;
                if b == 0.0 {
                    return Err("Modulo by zero".to_string());
                }
                self.stack.push(Value::Number(a % b));
            }
            
            Opcode::Neg => {
                let a = self.pop_number()?;
                self.stack.push(Value::Number(-a));
            }
            
            // Comparison operations
            Opcode::Equal => {
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                self.stack.push(Value::Boolean(self.values_equal(&a, &b)));
            }
            
            Opcode::NotEqual => {
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                self.stack.push(Value::Boolean(!self.values_equal(&a, &b)));
            }
            
            Opcode::Less => {
                println!("DEBUG: Before Less, stack = {:?}", self.stack);
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                let result = match (a, b) {
                    (Value::Number(a), Value::Number(b)) => Value::Boolean(a < b),
                    _ => return Err("Operands must be numbers for Less".to_string()),
                };
                self.stack.push(result);
                println!("DEBUG: After Less, stack = {:?}", self.stack);
            }
            
            Opcode::LessEqual => {
                let b = self.pop_number()?;
                let a = self.pop_number()?;
                self.stack.push(Value::Boolean(a <= b));
            }
            
            Opcode::Greater => {
                let b = self.pop_number()?;
                let a = self.pop_number()?;
                self.stack.push(Value::Boolean(a > b));
            }
            
            Opcode::GreaterEqual => {
                let b = self.pop_number()?;
                let a = self.pop_number()?;
                self.stack.push(Value::Boolean(a >= b));
            }
            
            // Logical operations
            Opcode::And => {
                let b = self.pop_boolean()?;
                let a = self.pop_boolean()?;
                self.stack.push(Value::Boolean(a && b));
            }
            
            Opcode::Or => {
                let b = self.pop_boolean()?;
                let a = self.pop_boolean()?;
                self.stack.push(Value::Boolean(a || b));
            }
            
            Opcode::Not => {
                let a = self.pop_boolean()?;
                self.stack.push(Value::Boolean(!a));
            }
            
            // Control flow
            Opcode::Jump(address) => {
                println!("DEBUG: Jumping from {} to {}", self.instruction_pointer, *address);
                self.instruction_pointer = *address;
            }
            
            Opcode::JumpIfFalse(addr) => {
                println!("DEBUG: Before JumpIfFalse, stack = {:?}", self.stack);
                let value = self.stack.pop().ok_or("Stack underflow")?;
                if !self.is_truthy(&value) {
                    self.instruction_pointer = *addr;
                } else {
                    // If we don't jump, increment the instruction pointer
                    self.instruction_pointer += 1;
                }
                println!("DEBUG: After JumpIfFalse, stack = {:?}", self.stack);
            }
            
            Opcode::JumpIfTrue(address) => {
                let condition = self.pop_boolean()?;
                if condition {
                    self.instruction_pointer = *address;
                } else {
                    // If we don't jump, increment the instruction pointer
                    self.instruction_pointer += 1;
                }
            }
            
            // Function operations
            Opcode::Call(name, arg_count) => {
                // TODO: Implement proper function calling
                println!("DEBUG: Call {} with {} args", name, arg_count);
                // For now, just push a placeholder value
                self.stack.push(Value::Null);
            }
            
            Opcode::Return => {
                // TODO: Implement proper return
                println!("DEBUG: Return");
            }
            
            Opcode::DefineFunction(name, parameters, body) => {
                // TODO: Implement function definition
                println!("DEBUG: DefineFunction {}", name);
            }
            
            // Closure operations
            Opcode::MakeClosure(name, upvalue_count) => {
                // TODO: Implement closure creation
                println!("DEBUG: MakeClosure {}", name);
            }
            
            Opcode::GetUpvalue(index) => {
                // TODO: Implement upvalue access
                println!("DEBUG: GetUpvalue {}", index);
            }
            
            Opcode::SetUpvalue(index) => {
                // TODO: Implement upvalue setting
                println!("DEBUG: SetUpvalue {}", index);
            }
            
            Opcode::CloseUpvalues => {
                // TODO: Implement upvalue closing
                println!("DEBUG: CloseUpvalues");
            }
            
            // Event operations
            Opcode::Emit(event_name) => {
                let data = self.stack.pop().unwrap_or(Value::Null);
                println!("DEBUG: Emit {} with {:?}", event_name, data);
            }
            
            Opcode::Listen(event_name) => {
                let handler_address = self.stack.pop().ok_or("Stack underflow")?;
                println!("DEBUG: Listen {} at {:?}", event_name, handler_address);
            }
            
            // Built-in operations
            Opcode::Say => {
                let value = self.stack.pop().ok_or("Stack underflow")?;
                println!("💬 {}", self.value_to_string(&value));
            }
            
            Opcode::Print => {
                let value = self.stack.pop().ok_or("Stack underflow")?;
                print!("{}", self.value_to_string(&value));
            }
            
            // Special operations
            Opcode::Halt => {
                self.running = false;
            }
            
            Opcode::NoOp => {
                // Do nothing
            }
            
            // Advanced operations
            Opcode::Mod => {
                let b = self.pop_number()?;
                let a = self.pop_number()?;
                if b == 0.0 {
                    return Err("Modulo by zero".to_string());
                }
                self.stack.push(Value::Number(a % b));
            }
            
            // JIT Compilation (not implemented yet)
            Opcode::JitCompile(_) => {
                // TODO: Implement JIT compilation
            }
            
            Opcode::JitExecute(_) => {
                // TODO: Implement JIT execution
            }
            
            // Parallel Execution (not implemented yet)
            Opcode::Parallel(_) => {
                // TODO: Implement parallel execution
            }
            
            Opcode::ThreadSpawn(_) => {
                // TODO: Implement thread spawning
            }
            
            Opcode::ThreadJoin(_) => {
                // TODO: Implement thread joining
            }
            
            // Memory Management (not implemented yet)
            Opcode::MemoryAllocate(_) => {
                // TODO: Implement memory allocation
            }
            
            Opcode::MemoryFree(_) => {
                // TODO: Implement memory freeing
            }
            
            Opcode::MemoryOptimize => {
                // TODO: Implement memory optimization
            }
            
            // Performance Profiling (not implemented yet)
            Opcode::ProfileStart(_) => {
                // TODO: Implement profiling start
            }
            
            Opcode::ProfileEnd(_) => {
                // TODO: Implement profiling end
            }
            
            Opcode::ProfileMeasure(_) => {
                // TODO: Implement profiling measurement
            }
            
            Opcode::CreateArray(size) => {
                // Pop elements from stack in reverse order and create array
                let mut elements = Vec::new();
                for _ in 0..*size {
                    if let Some(element) = self.stack.pop() {
                        elements.push(element);
                    } else {
                        return Err("Stack underflow during array creation".to_string());
                    }
                }
                // Reverse to get correct order
                elements.reverse();
                self.stack.push(Value::Array(elements));
            }
            
            Opcode::CreateObject(size) => {
                // Pop property-value pairs from stack and create object
                let mut object = HashMap::new();
                for _ in 0..*size {
                    let value = self.stack.pop().ok_or("Stack underflow during object creation")?;
                    let name = self.stack.pop().ok_or("Stack underflow during object creation")?;
                    
                    if let Value::String(name) = name {
                        object.insert(name, value);
                    } else {
                        return Err("Property name must be a string".to_string());
                    }
                }
                self.stack.push(Value::Object(object));
            }
            
            Opcode::GetProperty => {
                let property_name = self.stack.pop().ok_or("Stack underflow")?;
                let object = self.stack.pop().ok_or("Stack underflow")?;
                
                if let (Value::String(name), Value::Object(obj)) = (property_name, object) {
                    if let Some(value) = obj.get(&name) {
                        self.stack.push(value.clone());
                    } else {
                        self.stack.push(Value::Null);
                    }
                } else {
                    return Err("Invalid property access".to_string());
                }
            }
            
            Opcode::SetProperty => {
                let value = self.stack.pop().ok_or("Stack underflow")?;
                let property_name = self.stack.pop().ok_or("Stack underflow")?;
                let object = self.stack.pop().ok_or("Stack underflow")?;
                
                if let (Value::String(name), Value::Object(mut obj)) = (property_name, object) {
                    obj.insert(name, value);
                    self.stack.push(Value::Object(obj));
                } else {
                    return Err("Invalid property assignment".to_string());
                }
            }
            
            Opcode::GetIndex => {
                let index = self.stack.pop().ok_or("Stack underflow")?;
                let array = self.stack.pop().ok_or("Stack underflow")?;
                
                if let (Value::Number(index), Value::Array(arr)) = (index, array) {
                    let index = index as usize;
                    if index < arr.len() {
                        self.stack.push(arr[index].clone());
                    } else {
                        self.stack.push(Value::Null);
                    }
                } else {
                    return Err("Invalid array access".to_string());
                }
            }
            
            Opcode::SetIndex => {
                let value = self.stack.pop().ok_or("Stack underflow")?;
                let index = self.stack.pop().ok_or("Stack underflow")?;
                let array = self.stack.pop().ok_or("Stack underflow")?;
                
                if let (Value::Number(index), Value::Array(mut arr)) = (index, array) {
                    let index = index as usize;
                    if index < arr.len() {
                        arr[index] = value;
                        self.stack.push(Value::Array(arr));
                    } else {
                        return Err("Array index out of bounds".to_string());
                    }
                } else {
                    return Err("Invalid array assignment".to_string());
                }
            }
        }
        
        Ok(())
    }

    // Helper methods for stack operations
    pub fn get_variable(&self, name: &str) -> Result<Value, String> {
        self.variables.get(name)
            .cloned()
            .ok_or_else(|| format!("Variable '{}' not found", name))
    }
    
    pub fn set_variable(&mut self, name: String, value: Value) {
        self.variables.insert(name, value);
    }
    
    pub fn value_to_string(&self, value: &Value) -> String {
        match value {
            Value::Number(n) => n.to_string(),
            Value::String(s) => s.clone(),
            Value::Boolean(b) => b.to_string(),
            Value::Null => "null".to_string(),
            Value::Array(arr) => {
                let elements: Vec<String> = arr.iter().map(|v| self.value_to_string(v)).collect();
                format!("[{}]", elements.join(", "))
            }
            Value::Object(obj) => {
                let pairs: Vec<String> = obj.iter()
                    .map(|(k, v)| format!("{}: {}", k, self.value_to_string(v)))
                    .collect();
                format!("{{{}}}", pairs.join(", "))
            }
            Value::Function(func) => format!("<fn {}>", func.name),
            Value::Closure(closure) => format!("<closure {}>", closure.func.name),
        }
    }
    
    pub fn pop_number(&mut self) -> Result<f64, String> {
        match self.stack.pop() {
            Some(Value::Number(n)) => Ok(n),
            Some(value) => Err(format!("Expected number, got {}", self.value_to_string(&value))),
            None => Err("Stack underflow".to_string()),
        }
    }
    
    pub fn pop_boolean(&mut self) -> Result<bool, String> {
        match self.stack.pop() {
            Some(Value::Boolean(b)) => Ok(b),
            Some(value) => Err(format!("Expected boolean, got {}", self.value_to_string(&value))),
            None => Err("Stack underflow".to_string()),
        }
    }
    
    pub fn values_equal(&self, a: &Value, b: &Value) -> bool {
        match (a, b) {
            (Value::Number(n1), Value::Number(n2)) => (n1 - n2).abs() < f64::EPSILON,
            (Value::String(s1), Value::String(s2)) => s1 == s2,
            (Value::Boolean(b1), Value::Boolean(b2)) => b1 == b2,
            (Value::Null, Value::Null) => true,
            (Value::Array(arr1), Value::Array(arr2)) => {
                if arr1.len() != arr2.len() {
                    return false;
                }
                arr1.iter().zip(arr2.iter()).all(|(a, b)| self.values_equal(a, b))
            }
            (Value::Object(obj1), Value::Object(obj2)) => {
                if obj1.len() != obj2.len() {
                    return false;
                }
                obj1.iter().all(|(k, v1)| {
                    obj2.get(k).map_or(false, |v2| self.values_equal(v1, v2))
                })
            }
            _ => false,
        }
    }
    
    pub fn is_truthy(&self, value: &Value) -> bool {
        match value {
            Value::Boolean(b) => *b,
            Value::Number(n) => *n != 0.0,
            Value::String(s) => !s.is_empty(),
            Value::Null => false,
            Value::Array(arr) => !arr.is_empty(),
            Value::Object(obj) => !obj.is_empty(),
            Value::Function(_) => true,
            Value::Closure(_) => true,
        }
    }
    
    pub fn current_stack_trace(&self) -> Vec<CallSite> {
        let mut trace = Vec::new();
        for frame in &self.call_stack {
            trace.push(CallSite {
                function_name: frame.function_name.clone(),
                line: 0, // TODO: Get actual line from source map
                column: 0, // TODO: Get actual column from source map
                instruction: format!("instruction_{}", frame.return_address),
            });
        }
        trace
    }
    
    pub fn throw_error(&mut self, error: AzlError) -> Result<(), String> {
        self.error = Some(error);
        Err("Error thrown".to_string())
    }
    
    pub fn read_constant(&self, index: usize) -> Value {
        // For now, return a placeholder. In a real implementation, this would read from a constant pool
        Value::String(format!("constant_{}", index))
    }
    
    pub fn load_module(&mut self, path: &str) -> Result<(), String> {
        // For now, just simulate module loading
        println!("Loading module: {}", path);
        Ok(())
    }

    fn current_line_info(&self) -> (String, u32) {
        // Get current line from source map
        let line = self.source_map.get(&self.instruction_pointer)
            .map(|(line, _)| *line as u32)
            .unwrap_or(0);
        
        ("main".to_string(), line)
    }
    
    fn throw_vm_error(&mut self, msg: impl Into<String>) -> Result<Value, VmError> {
        let (module, line) = self.current_line_info();
        Err(VmError {
            message: msg.into(),
            module,
            line,
            pc: self.instruction_pointer,
            stack: self.current_stack_trace(),
        })
    }
    
    fn throw_error_with_context(&mut self, msg: impl Into<String>, context: &str) -> Result<Value, VmError> {
        let (module, line) = self.current_line_info();
        let full_message = format!("{}: {}", context, msg.into());
        Err(VmError {
            message: full_message,
            module,
            line,
            pc: self.instruction_pointer,
            stack: self.current_stack_trace(),
        })
    }
}

// Add a simple VM example function
pub fn run_vm_example() {
    println!("🚀 Running AZL VM Example");
    println!("==========================");
    
    let mut vm = AzlVM::new();
    
    // Create some simple bytecode
    let bytecode = vec![
        Opcode::Push(Value::Number(5.0)),
        Opcode::Push(Value::Number(3.0)),
        Opcode::Add,
        Opcode::Say,
        Opcode::Halt,
    ];
    
    vm.load_bytecode(bytecode);
    
    match vm.run() {
        Ok(_) => println!("✅ VM example completed successfully!"),
        Err(e) => println!("❌ VM example failed: {}", e),
    }
}

// Add a VM example function with tracing
pub fn run_vm_example_with_trace(trace: bool) {
    println!("🚀 Running AZL VM Example");
    println!("==========================");
    
    let mut vm = AzlVM::new();
    
    // Create some simple bytecode
    let bytecode = vec![
        Opcode::Push(Value::Number(5.0)),
        Opcode::Push(Value::Number(3.0)),
        Opcode::Add,
        Opcode::Say,
        Opcode::Halt,
    ];
    
    if trace {
        println!("📋 Disassembly:");
        println!("{}", disassemble_chunk("main", &bytecode));
        println!();
        
        // Verify the bytecode before execution
        match verify_chunk(&bytecode, 0) {
            Ok(_) => println!("✅ Bytecode verification passed"),
            Err(e) => {
                println!("❌ Bytecode verification failed: {}", e);
                return;
            }
        }
        println!();
    }
    
    vm.load_bytecode(bytecode);
    
    match vm.run() {
        Ok(_) => println!("✅ VM example completed successfully!"),
        Err(e) => println!("❌ VM example failed: {}", e),
    }
}

// ========================================
// ========== DISASSEMBLER ===============
// ========================================

pub fn disassemble_chunk(name: &str, code: &[Opcode]) -> String {
    use std::fmt::Write;
    let mut out = String::new();
    writeln!(&mut out, "== {} ==", name).ok();
    for (i, op) in code.iter().enumerate() {
        writeln!(&mut out, "{i:04}  {:?}", op).ok();
    }
    out
}

pub fn disassemble_with_constants(name: &str, code: &[Opcode], constants: &[Value]) -> String {
    use std::fmt::Write;
    let mut out = String::new();
    writeln!(&mut out, "== {} ==", name).ok();
    writeln!(&mut out, "Constants:").ok();
    for (i, constant) in constants.iter().enumerate() {
        writeln!(&mut out, "  {i:04}  {:?}", constant).ok();
    }
    writeln!(&mut out, "Code:").ok();
    for (i, op) in code.iter().enumerate() {
        writeln!(&mut out, "{i:04}  {:?}", op).ok();
    }
    out
}

// ========================================
// ========== BYTECODE VERIFIER ==========
// ========================================

#[derive(Debug)]
pub enum VerifyError {
    StackUnderflow { at: usize, needs: i32, has: i32 },
    BadConstIndex { at: usize, idx: usize, len: usize },
    BadJumpTarget { at: usize, target: usize, code_len: usize },
    UnbalancedStack { at: usize, final_depth: i32 },
    InvalidFunctionCall { at: usize, func_name: String },
}

impl std::fmt::Display for VerifyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VerifyError::StackUnderflow { at, needs, has } => {
                write!(f, "Stack underflow at instruction {}: needs {} items, has {}", at, needs, has)
            }
            VerifyError::BadConstIndex { at, idx, len } => {
                write!(f, "Invalid constant index at instruction {}: index {} >= {}", at, idx, len)
            }
            VerifyError::BadJumpTarget { at, target, code_len } => {
                write!(f, "Invalid jump target at instruction {}: target {} >= {}", at, target, code_len)
            }
            VerifyError::UnbalancedStack { at, final_depth } => {
                write!(f, "Unbalanced stack at instruction {}: final depth {}", at, final_depth)
            }
            VerifyError::InvalidFunctionCall { at, func_name } => {
                write!(f, "Invalid function call at instruction {}: function '{}' not found", at, func_name)
            }
        }
    }
}

impl std::error::Error for VerifyError {}

pub fn verify_chunk(code: &[Opcode], const_len: usize) -> Result<(), VerifyError> {
    let mut depth: i32 = 0;
    
    for (pc, op) in code.iter().enumerate() {
        let (pop, push) = match op {
            // Stack operations
            Opcode::Push(_) => (0, 1),
            Opcode::Pop => (1, 0),
            Opcode::Dup => (1, 2),
            Opcode::Swap => (2, 2),
            
            // Variable operations
            Opcode::Load(_) => (0, 1),
            Opcode::Store(_) => (1, 0),
            
            // Arithmetic
            Opcode::Add | Opcode::Sub | Opcode::Mul | Opcode::Div | Opcode::Mod => (2, 1),
            Opcode::Neg => (1, 1),
            
            // Comparison
            Opcode::Equal | Opcode::NotEqual | Opcode::Less | Opcode::LessEqual | 
            Opcode::Greater | Opcode::GreaterEqual => (2, 1),
            
            // Logical
            Opcode::And | Opcode::Or => (2, 1),
            Opcode::Not => (1, 1),
            
            // Control flow
            Opcode::Jump(target) => {
                if *target >= code.len() {
                    return Err(VerifyError::BadJumpTarget { at: pc, target: *target, code_len: code.len() });
                }
                (0, 0)
            }
            Opcode::JumpIfFalse(target) | Opcode::JumpIfTrue(target) => {
                if *target >= code.len() {
                    return Err(VerifyError::BadJumpTarget { at: pc, target: *target, code_len: code.len() });
                }
                (1, 0)
            }
            
            // Function calls
            Opcode::Call(func_name, argc) => {
                // Pop function + args, push result
                (*argc as i32 + 1, 1)
            }
            Opcode::DefineFunction(_, _, _) => (0, 1), // Push function object
            Opcode::Return => (1, 0),
            
            // Closure operations
            Opcode::MakeClosure(_, _) => (1, 1), // Pop function, push closure
            Opcode::GetUpvalue(_) => (0, 1),
            Opcode::SetUpvalue(_) => (1, 0),
            Opcode::CloseUpvalues => (0, 0),
            
            // Events
            Opcode::Emit(_) => (0, 0),
            Opcode::Listen(_) => (0, 0),
            
            // Built-ins
            Opcode::Print => (1, 0),
            Opcode::Say => (1, 0),
            
            // Array and Object operations
            Opcode::CreateArray(size) => {
                if depth < *size as i32 {
                    return Err(VerifyError::StackUnderflow { at: pc, needs: *size as i32, has: depth });
                }
                (*size as i32, 1)
            }
            Opcode::CreateObject(size) => {
                if depth < (*size * 2) as i32 {
                    return Err(VerifyError::StackUnderflow { at: pc, needs: (*size * 2) as i32, has: depth });
                }
                ((*size * 2) as i32, 1)
            }
            Opcode::GetProperty => (2, 1), // object, property_name -> value
            Opcode::SetProperty => (3, 1), // object, property_name, value -> object
            Opcode::GetIndex => (2, 1), // array, index -> value
            Opcode::SetIndex => (3, 1), // array, index, value -> array
            
            // JIT Compilation
            Opcode::JitCompile(_) => (0, 0),
            Opcode::JitExecute(_) => (0, 1),
            
            // Parallel Execution
            Opcode::Parallel(_) => (0, 1),
            Opcode::ThreadSpawn(_) => (0, 1),
            Opcode::ThreadJoin(_) => (1, 1),
            
            // Advanced Memory
            Opcode::MemoryAllocate(_) => (0, 1),
            Opcode::MemoryFree(_) => (1, 0),
            Opcode::MemoryOptimize => (0, 0),
            
            // Performance Profiling
            Opcode::ProfileStart(_) => (0, 0),
            Opcode::ProfileEnd(_) => (0, 0),
            Opcode::ProfileMeasure(_) => (0, 1),
            
            // Exception handling
            Opcode::Try(_) => (0, 0),
            Opcode::EndTry => (0, 0),
            Opcode::Throw => (1, 0),
            
            // Safe operations
            Opcode::DivSafe => (2, 1),
            Opcode::GetPropSafe => (2, 1),
            
            // Module system
            Opcode::Import(idx) => {
                if *idx as usize >= const_len {
                    return Err(VerifyError::BadConstIndex { at: pc, idx: *idx as usize, len: const_len });
                }
                (0, 1)
            }
            Opcode::ModuleBegin(_) => (0, 0),
            Opcode::ModuleEnd => (0, 0),
            Opcode::Export(_) => (0, 0),
            
            // Special
            Opcode::Halt => (0, 0),
            Opcode::NoOp => (0, 0),
        };
        
        if depth < pop {
            return Err(VerifyError::StackUnderflow { at: pc, needs: pop, has: depth });
        }
        
        depth = depth - pop + push;
    }
    
    if depth != 0 {
        return Err(VerifyError::UnbalancedStack { at: code.len(), final_depth: depth });
    }
    
    Ok(())
}

// ========================================
// ========== TESTS =======================
// ========================================

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_disassemble_chunk() {
        let code = vec![
            Opcode::Push(Value::Number(5.0)),
            Opcode::Push(Value::Number(3.0)),
            Opcode::Add,
            Opcode::Say,
            Opcode::Halt,
        ];
        
        let disassembly = disassemble_chunk("test", &code);
        assert!(disassembly.contains("== test =="));
        assert!(disassembly.contains("Push(Number(5.0))"));
        assert!(disassembly.contains("Add"));
        assert!(disassembly.contains("Say"));
        assert!(disassembly.contains("Halt"));
    }
    
    #[test]
    fn test_verify_chunk_valid() {
        let code = vec![
            Opcode::Push(Value::Number(5.0)),
            Opcode::Push(Value::Number(3.0)),
            Opcode::Add,
            Opcode::Say,
            Opcode::Halt,
        ];
        
        let result = verify_chunk(&code, 0);
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_verify_chunk_stack_underflow() {
        let code = vec![
            Opcode::Add, // Tries to pop 2 items but stack is empty
        ];
        
        let result = verify_chunk(&code, 0);
        assert!(result.is_err());
        if let Err(VerifyError::StackUnderflow { at, needs, has }) = result {
            assert_eq!(at, 0);
            assert_eq!(needs, 2);
            assert_eq!(has, 0);
        } else {
            panic!("Expected StackUnderflow error");
        }
    }
    
    #[test]
    fn test_verify_chunk_unbalanced_stack() {
        let code = vec![
            Opcode::Push(Value::Number(5.0)),
            // Missing pop operation
        ];
        
        let result = verify_chunk(&code, 0);
        assert!(result.is_err());
        if let Err(VerifyError::UnbalancedStack { at, final_depth }) = result {
            assert_eq!(at, 1);
            assert_eq!(final_depth, 1);
        } else {
            panic!("Expected UnbalancedStack error");
        }
    }
    
    #[test]
    fn test_verify_chunk_bad_jump_target() {
        let code = vec![
            Opcode::Jump(10), // Jump to non-existent instruction
        ];
        
        let result = verify_chunk(&code, 0);
        assert!(result.is_err());
        if let Err(VerifyError::BadJumpTarget { at, target, code_len }) = result {
            assert_eq!(at, 0);
            assert_eq!(target, 10);
            assert_eq!(code_len, 1);
        } else {
            panic!("Expected BadJumpTarget error");
        }
    }
    
    #[test]
    fn test_value_display() {
        // Test number
        let num = Value::Number(42.0);
        assert_eq!(format!("{}", num), "42");
        
        // Test string
        let str_val = Value::String("hello".to_string());
        assert_eq!(format!("{}", str_val), "hello");
        
        // Test boolean
        let bool_val = Value::Boolean(true);
        assert_eq!(format!("{}", bool_val), "true");
        
        // Test null
        let null_val = Value::Null;
        assert_eq!(format!("{}", null_val), "null");
        
        // Test array
        let array_val = Value::Array(vec![
            Value::Number(1.0),
            Value::String("two".to_string()),
            Value::Boolean(false),
        ]);
        assert_eq!(format!("{}", array_val), "[1, two, false]");
        
        // Test object
        let mut obj = HashMap::new();
        obj.insert("a".to_string(), Value::Number(1.0));
        obj.insert("b".to_string(), Value::String("hello".to_string()));
        let obj_val = Value::Object(obj);
        assert_eq!(format!("{}", obj_val), "{a: 1, b: hello}");
    }
    
    #[test]
    fn test_vm_basic_operations() {
        let mut vm = AzlVM::new();
        
        // Test basic arithmetic
        let bytecode = vec![
            Opcode::Push(Value::Number(5.0)),
            Opcode::Push(Value::Number(3.0)),
            Opcode::Add,
            Opcode::Halt,
        ];
        
        vm.load_bytecode(bytecode);
        let result = vm.run();
        assert!(result.is_ok());
        
        // Check that the result is on the stack
        assert_eq!(vm.stack.len(), 1);
        if let Value::Number(n) = vm.stack[0] {
            assert_eq!(n, 8.0);
        } else {
            panic!("Expected number on stack");
        }
    }
    
    // ========================================
    // ========== PROPERTY TESTS ==============
    // ========================================
    
    use proptest::prelude::*;
    
    // Simple program generator for property testing
    fn synth_simple_program(xs: &[i64]) -> Vec<Opcode> {
        let mut code = Vec::new();
        
        // Push all numbers
        for &x in xs {
            code.push(Opcode::Push(Value::Number(x as f64)));
        }
        
        // Add them all together
        for _ in 1..xs.len() {
            code.push(Opcode::Add);
        }
        
        code.push(Opcode::Halt);
        code
    }
    
    // Reference implementation (pure Rust)
    fn eval_reference(xs: &[i64]) -> f64 {
        xs.iter().map(|&x| x as f64).sum()
    }
    
    // Run a chunk and get the top value from stack
    fn run_chunk_and_get_result(chunk: &[Opcode]) -> Result<f64, String> {
        let mut vm = AzlVM::new();
        vm.load_bytecode(chunk.to_vec());
        vm.run()?;
        
        if let Some(Value::Number(n)) = vm.stack.last() {
            Ok(*n)
        } else {
            Err("Expected number on stack".to_string())
        }
    }
    
    proptest! {
        #[test]
        fn eval_simple_exprs_is_sound(xs in prop::collection::vec(-1_000_000i64..=1_000_000, 1..10)) {
            // Build a simple random program from xs
            let chunk = synth_simple_program(&xs);
            
            // Verify the bytecode is valid
            verify_chunk(&chunk, 0).unwrap();
            
            // Run on VM
            let vm_res = run_chunk_and_get_result(&chunk).unwrap();
            
            // Compare with reference implementation
            let ref_res = eval_reference(&xs);
            
            prop_assert!((vm_res - ref_res).abs() < 1e-6);
        }
        
        #[test]
        fn arithmetic_metamorphic_properties(x in -1_000_000i64..=1_000_000) {
            // x + 0 == x
            let add_zero = vec![
                Opcode::Push(Value::Number(x as f64)),
                Opcode::Push(Value::Number(0.0)),
                Opcode::Add,
                Opcode::Halt,
            ];
            
            let vm_res = run_chunk_and_get_result(&add_zero).unwrap();
            prop_assert!((vm_res - x as f64).abs() < 1e-6);
            
            // x * 1 == x
            let mul_one = vec![
                Opcode::Push(Value::Number(x as f64)),
                Opcode::Push(Value::Number(1.0)),
                Opcode::Mul,
                Opcode::Halt,
            ];
            
            let vm_res = run_chunk_and_get_result(&mul_one).unwrap();
            prop_assert!((vm_res - x as f64).abs() < 1e-6);
        }
        
        #[test]
        fn stack_operations_are_sound(x in -1_000_000i64..=1_000_000, y in -1_000_000i64..=1_000_000) {
            // Test Dup operation: dup x == x x
            let dup_test = vec![
                Opcode::Push(Value::Number(x as f64)),
                Opcode::Dup,
                Opcode::Add,
                Opcode::Halt,
            ];
            
            let vm_res = run_chunk_and_get_result(&dup_test).unwrap();
            prop_assert!((vm_res - (x * 2) as f64).abs() < 1e-6);
            
            // Test Swap operation: swap x y == y x
            let swap_test = vec![
                Opcode::Push(Value::Number(x as f64)),
                Opcode::Push(Value::Number(y as f64)),
                Opcode::Swap,
                Opcode::Sub, // y - x
                Opcode::Halt,
            ];
            
            let vm_res = run_chunk_and_get_result(&swap_test).unwrap();
            prop_assert!((vm_res - (y - x) as f64).abs() < 1e-6);
        }
    }
}

// ========================================
// ========== BYTECODE SERIALIZATION ====
// ========================================

pub const MAGIC: &[u8; 4] = b"AZBC";
pub const BC_VERSION: u16 = 2;

#[derive(Debug)]
pub enum SerializationError {
    IoError(std::io::Error),
    InvalidMagic,
    VersionMismatch,
    InvalidData,
}

impl std::fmt::Display for SerializationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SerializationError::IoError(e) => write!(f, "IO error: {}", e),
            SerializationError::InvalidMagic => write!(f, "Invalid magic bytes"),
            SerializationError::VersionMismatch => write!(f, "Version mismatch"),
            SerializationError::InvalidData => write!(f, "Invalid data"),
        }
    }
}

impl std::error::Error for SerializationError {}

impl From<std::io::Error> for SerializationError {
    fn from(err: std::io::Error) -> Self {
        SerializationError::IoError(err)
    }
}

pub fn write_chunk(mut w: impl std::io::Write, chunk: &Chunk, name: &str) -> Result<(), SerializationError> {
    use std::io::Write;
    
    // Write header
    w.write_all(MAGIC)?;
    w.write_all(&BC_VERSION.to_le_bytes())?;
    w.write_all(&0u16.to_le_bytes())?; // flags
    
    // Write name
    w.write_all(&(name.len() as u16).to_le_bytes())?;
    w.write_all(name.as_bytes())?;
    
    // Write constants
    w.write_all(&(chunk.constants.len() as u32).to_le_bytes())?;
    for constant in &chunk.constants {
        write_constant(&mut w, constant)?;
    }
    
    // Write code
    w.write_all(&(chunk.code.len() as u32).to_le_bytes())?;
    write_opcodes(&mut w, &chunk.code)?;
    
    // Write line numbers (RLE encoded)
    let line_rle = rle_encode_lines(&chunk.lines);
    w.write_all(&(line_rle.len() as u32).to_le_bytes())?;
    w.write_all(&line_rle)?;
    
    Ok(())
}

pub fn read_chunk(mut r: impl std::io::Read) -> Result<(Chunk, String), SerializationError> {
    use std::io::Read;
    
    // Read and verify magic
    let mut magic = [0u8; 4];
    r.read_exact(&mut magic)?;
    if &magic != MAGIC {
        return Err(SerializationError::InvalidMagic);
    }
    
    // Read and verify version
    let mut version_bytes = [0u8; 2];
    r.read_exact(&mut version_bytes)?;
    let version = u16::from_le_bytes(version_bytes);
    if version != BC_VERSION {
        return Err(SerializationError::VersionMismatch);
    }
    
    // Read flags (unused for now)
    let mut flags_bytes = [0u8; 2];
    r.read_exact(&mut flags_bytes)?;
    let _flags = u16::from_le_bytes(flags_bytes);
    
    // Read name
    let mut name_len_bytes = [0u8; 2];
    r.read_exact(&mut name_len_bytes)?;
    let name_len = u16::from_le_bytes(name_len_bytes) as usize;
    
    let mut name_bytes = vec![0u8; name_len];
    r.read_exact(&mut name_bytes)?;
    let name = String::from_utf8(name_bytes)
        .map_err(|_| SerializationError::InvalidData)?;
    
    // Read constants
    let mut const_len_bytes = [0u8; 4];
    r.read_exact(&mut const_len_bytes)?;
    let const_len = u32::from_le_bytes(const_len_bytes) as usize;
    
    let mut constants = Vec::with_capacity(const_len);
    for _ in 0..const_len {
        constants.push(read_constant(&mut r)?);
    }
    
    // Read code
    let mut code_len_bytes = [0u8; 4];
    r.read_exact(&mut code_len_bytes)?;
    let code_len = u32::from_le_bytes(code_len_bytes) as usize;
    
    let code = read_opcodes(&mut r, code_len)?;
    
    // Read line numbers
    let mut line_len_bytes = [0u8; 4];
    r.read_exact(&mut line_len_bytes)?;
    let line_len = u32::from_le_bytes(line_len_bytes) as usize;
    
    let mut line_rle = vec![0u8; line_len];
    r.read_exact(&mut line_rle)?;
    let lines = rle_decode_lines(&line_rle)?;
    
    Ok((Chunk { code, constants, lines }, name))
}

fn write_constant(w: &mut impl std::io::Write, value: &Value) -> Result<(), SerializationError> {
    use std::io::Write;
    
    match value {
        Value::Number(n) => {
            w.write_all(&[0u8])?; // tag for Number
            w.write_all(&n.to_le_bytes())?;
        }
        Value::String(s) => {
            w.write_all(&[1u8])?; // tag for String
            w.write_all(&(s.len() as u32).to_le_bytes())?;
            w.write_all(s.as_bytes())?;
        }
        Value::Boolean(b) => {
            w.write_all(&[2u8])?; // tag for Boolean
            w.write_all(&[*b as u8])?;
        }
        Value::Null => {
            w.write_all(&[3u8])?; // tag for Null
        }
        Value::Array(arr) => {
            w.write_all(&[4u8])?; // tag for Array
            w.write_all(&(arr.len() as u32).to_le_bytes())?;
            for item in arr {
                write_constant(w, item)?;
            }
        }
        Value::Object(obj) => {
            w.write_all(&[5u8])?; // tag for Object
            w.write_all(&(obj.len() as u32).to_le_bytes())?;
            for (key, value) in obj {
                w.write_all(&(key.len() as u32).to_le_bytes())?;
                w.write_all(key.as_bytes())?;
                write_constant(w, value)?;
            }
        }
        Value::Function(func) => {
            w.write_all(&[6u8])?; // tag for Function
            w.write_all(&(func.name.len() as u32).to_le_bytes())?;
            w.write_all(func.name.as_bytes())?;
            w.write_all(&(func.arity as u32).to_le_bytes())?;
            write_chunk(w, &func.chunk, &func.name)?;
        }
        Value::Closure(closure) => {
            w.write_all(&[7u8])?; // tag for Closure
            w.write_all(&(closure.func.name.len() as u32).to_le_bytes())?;
            w.write_all(closure.func.name.as_bytes())?;
            w.write_all(&(closure.upvalues.len() as u32).to_le_bytes())?;
            for (name, value) in &closure.upvalues {
                w.write_all(&(name.len() as u32).to_le_bytes())?;
                w.write_all(name.as_bytes())?;
                write_constant(w, value)?;
            }
        }
    }
    
    Ok(())
}

fn read_constant(r: &mut impl std::io::Read) -> Result<Value, SerializationError> {
    use std::io::Read;
    
    let mut tag = [0u8; 1];
    r.read_exact(&mut tag)?;
    
    match tag[0] {
        0 => { // Number
            let mut bytes = [0u8; 8];
            r.read_exact(&mut bytes)?;
            Ok(Value::Number(f64::from_le_bytes(bytes)))
        }
        1 => { // String
            let mut len_bytes = [0u8; 4];
            r.read_exact(&mut len_bytes)?;
            let len = u32::from_le_bytes(len_bytes) as usize;
            
            let mut bytes = vec![0u8; len];
            r.read_exact(&mut bytes)?;
            let s = String::from_utf8(bytes)
                .map_err(|_| SerializationError::InvalidData)?;
            Ok(Value::String(s))
        }
        2 => { // Boolean
            let mut bytes = [0u8; 1];
            r.read_exact(&mut bytes)?;
            Ok(Value::Boolean(bytes[0] != 0))
        }
        3 => Ok(Value::Null), // Null
        4 => { // Array
            let mut len_bytes = [0u8; 4];
            r.read_exact(&mut len_bytes)?;
            let len = u32::from_le_bytes(len_bytes) as usize;
            
            let mut arr = Vec::with_capacity(len);
            for _ in 0..len {
                arr.push(read_constant(r)?);
            }
            Ok(Value::Array(arr))
        }
        5 => { // Object
            let mut len_bytes = [0u8; 4];
            r.read_exact(&mut len_bytes)?;
            let len = u32::from_le_bytes(len_bytes) as usize;
            
            let mut obj = std::collections::HashMap::new();
            for _ in 0..len {
                let mut key_len_bytes = [0u8; 4];
                r.read_exact(&mut key_len_bytes)?;
                let key_len = u32::from_le_bytes(key_len_bytes) as usize;
                
                let mut key_bytes = vec![0u8; key_len];
                r.read_exact(&mut key_bytes)?;
                let key = String::from_utf8(key_bytes)
                    .map_err(|_| SerializationError::InvalidData)?;
                
                let value = read_constant(r)?;
                obj.insert(key, value);
            }
            Ok(Value::Object(obj))
        }
        6 => { // Function
            let mut name_len_bytes = [0u8; 4];
            r.read_exact(&mut name_len_bytes)?;
            let name_len = u32::from_le_bytes(name_len_bytes) as usize;
            
            let mut name_bytes = vec![0u8; name_len];
            r.read_exact(&mut name_bytes)?;
            let name = String::from_utf8(name_bytes)
                .map_err(|_| SerializationError::InvalidData)?;
            
            let mut arity_bytes = [0u8; 4];
            r.read_exact(&mut arity_bytes)?;
            let arity = u32::from_le_bytes(arity_bytes) as usize;
            
            let (chunk, _) = read_chunk(r)?;
            let func = FunctionObj { name, arity, chunk };
            Ok(Value::Function(std::rc::Rc::new(func)))
        }
        7 => { // Closure
            let mut name_len_bytes = [0u8; 4];
            r.read_exact(&mut name_len_bytes)?;
            let name_len = u32::from_le_bytes(name_len_bytes) as usize;
            
            let mut name_bytes = vec![0u8; name_len];
            r.read_exact(&mut name_bytes)?;
            let name = String::from_utf8(name_bytes)
                .map_err(|_| SerializationError::InvalidData)?;
            
            let mut upvalue_len_bytes = [0u8; 4];
            r.read_exact(&mut upvalue_len_bytes)?;
            let upvalue_len = u32::from_le_bytes(upvalue_len_bytes) as usize;
            
            let mut upvalues = Vec::with_capacity(upvalue_len);
            for _ in 0..upvalue_len {
                let mut upvalue_name_len_bytes = [0u8; 4];
                r.read_exact(&mut upvalue_name_len_bytes)?;
                let upvalue_name_len = u32::from_le_bytes(upvalue_name_len_bytes) as usize;
                
                let mut upvalue_name_bytes = vec![0u8; upvalue_name_len];
                r.read_exact(&mut upvalue_name_bytes)?;
                let upvalue_name = String::from_utf8(upvalue_name_bytes)
                    .map_err(|_| SerializationError::InvalidData)?;
                
                let upvalue_value = read_constant(r)?;
                upvalues.push((upvalue_name, upvalue_value));
            }
            
            // For simplicity, we'll create a dummy function
            let func = FunctionObj {
                name: name.clone(),
                arity: 0,
                chunk: Chunk { code: vec![], constants: vec![], lines: vec![] },
            };
            let closure = ClosureObj {
                func: std::rc::Rc::new(func),
                upvalues,
            };
            Ok(Value::Closure(std::rc::Rc::new(closure)))
        }
        _ => Err(SerializationError::InvalidData),
    }
}

fn write_opcodes(w: &mut impl std::io::Write, code: &[Opcode]) -> Result<(), SerializationError> {
    use std::io::Write;
    
    for opcode in code {
        match opcode {
            Opcode::Push(value) => {
                w.write_all(&[0u8])?; // tag for Push
                write_constant(w, value)?;
            }
            Opcode::Pop => {
                w.write_all(&[1u8])?; // tag for Pop
            }
            Opcode::Dup => {
                w.write_all(&[2u8])?; // tag for Dup
            }
            Opcode::Swap => {
                w.write_all(&[3u8])?; // tag for Swap
            }
            Opcode::Add => {
                w.write_all(&[4u8])?; // tag for Add
            }
            Opcode::Sub => {
                w.write_all(&[5u8])?; // tag for Sub
            }
            Opcode::Mul => {
                w.write_all(&[6u8])?; // tag for Mul
            }
            Opcode::Div => {
                w.write_all(&[7u8])?; // tag for Div
            }
            Opcode::Halt => {
                w.write_all(&[8u8])?; // tag for Halt
            }
            // Add more opcodes as needed
            _ => {
                // For now, just write a placeholder
                w.write_all(&[255u8])?; // unknown opcode
            }
        }
    }
    
    Ok(())
}

fn read_opcodes(r: &mut impl std::io::Read, code_len: usize) -> Result<Vec<Opcode>, SerializationError> {
    use std::io::Read;
    
    let mut code = Vec::with_capacity(code_len);
    
    for _ in 0..code_len {
        let mut tag = [0u8; 1];
        r.read_exact(&mut tag)?;
        
        let opcode = match tag[0] {
            0 => { // Push
                let value = read_constant(r)?;
                Opcode::Push(value)
            }
            1 => Opcode::Pop,
            2 => Opcode::Dup,
            3 => Opcode::Swap,
            4 => Opcode::Add,
            5 => Opcode::Sub,
            6 => Opcode::Mul,
            7 => Opcode::Div,
            8 => Opcode::Halt,
            _ => {
                // For unknown opcodes, just skip for now
                continue;
            }
        };
        
        code.push(opcode);
    }
    
    Ok(code)
}

fn rle_encode_lines(lines: &[usize]) -> Vec<u8> {
    if lines.is_empty() {
        return vec![];
    }
    
    let mut encoded = Vec::new();
    let mut current_line = lines[0];
    let mut count: u32 = 1;
    
    for &line in &lines[1..] {
        if line == current_line {
            count += 1;
        } else {
            encoded.extend_from_slice(&(current_line as u32).to_le_bytes());
            encoded.extend_from_slice(&count.to_le_bytes());
            current_line = line;
            count = 1;
        }
    }
    
    // Write the last run
    encoded.extend_from_slice(&(current_line as u32).to_le_bytes());
    encoded.extend_from_slice(&count.to_le_bytes());
    
    encoded
}

fn rle_decode_lines(data: &[u8]) -> Result<Vec<usize>, SerializationError> {
    if data.is_empty() {
        return Ok(vec![]);
    }
    
    let mut lines = Vec::new();
    let mut i = 0;
    
    while i < data.len() {
        if i + 8 > data.len() {
            return Err(SerializationError::InvalidData);
        }
        
        let line = u32::from_le_bytes([data[i], data[i+1], data[i+2], data[i+3]]) as usize;
        let count = u32::from_le_bytes([data[i+4], data[i+5], data[i+6], data[i+7]]) as usize;
        
        for _ in 0..count {
            lines.push(line);
        }
        
        i += 8;
    }
    
    Ok(lines)
}

// ========================================
// ========== PEEPHOLE OPTIMIZATIONS ====
// ========================================

pub fn peephole_optimize(code: &mut Vec<Opcode>) {
    let mut i = 0;
    while i + 1 < code.len() {
        match (&code[i], &code[i + 1]) {
            // Identity eliminations
            (Opcode::Push(Value::Number(0.0)), Opcode::Add) => {
                // x + 0 == x
                code.remove(i);
                code.remove(i);
                continue;
            }
            (Opcode::Push(Value::Number(0.0)), Opcode::Sub) => {
                // x - 0 == x
                code.remove(i);
                code.remove(i);
                continue;
            }
            (Opcode::Push(Value::Number(1.0)), Opcode::Mul) => {
                // x * 1 == x
                code.remove(i);
                code.remove(i);
                continue;
            }
            (Opcode::Push(Value::Number(1.0)), Opcode::Div) => {
                // x / 1 == x
                code.remove(i);
                code.remove(i);
                continue;
            }
            
            // Double operations
            (Opcode::Pop, Opcode::Pop) => {
                // Remove redundant pops
                code.remove(i);
                code.remove(i);
                continue;
            }
            (Opcode::Neg, Opcode::Neg) => {
                // Double negation: -(-x) == x
                code.remove(i);
                code.remove(i);
                continue;
            }
            
            // Jump optimizations
            (Opcode::JumpIfFalse(target), _) if *target == i + 2 => {
                // Jump to next instruction is a no-op
                code.remove(i);
                continue;
            }
            (Opcode::JumpIfTrue(target), _) if *target == i + 2 => {
                // Jump to next instruction is a no-op
                code.remove(i);
                continue;
            }
            
            // Constant folding
            (Opcode::Push(Value::Number(a)), Opcode::Push(Value::Number(b))) => {
                if i + 2 < code.len() {
                    match &code[i + 2] {
                        Opcode::Add => {
                            // Fold: a + b
                            let result = a + b;
                            code[i] = Opcode::Push(Value::Number(result));
                            code.remove(i + 1);
                            code.remove(i + 1);
                            continue;
                        }
                        Opcode::Sub => {
                            // Fold: a - b
                            let result = a - b;
                            code[i] = Opcode::Push(Value::Number(result));
                            code.remove(i + 1);
                            code.remove(i + 1);
                            continue;
                        }
                        Opcode::Mul => {
                            // Fold: a * b
                            let result = a * b;
                            code[i] = Opcode::Push(Value::Number(result));
                            code.remove(i + 1);
                            code.remove(i + 1);
                            continue;
                        }
                        Opcode::Div => {
                            // Fold: a / b (if b != 0)
                            if *b != 0.0 {
                                let result = a / b;
                                code[i] = Opcode::Push(Value::Number(result));
                                code.remove(i + 1);
                                code.remove(i + 1);
                                continue;
                            }
                        }
                        _ => {}
                    }
                }
            }
            
            _ => {}
        }
        i += 1;
    }
}

pub fn optimize_chunk(chunk: &mut Chunk) -> Result<(), String> {
    // Apply peephole optimizations
    peephole_optimize(&mut chunk.code);
    
    // Verify the optimized code is still valid
    verify_chunk(&chunk.code, chunk.constants.len())
        .map_err(|e| format!("Optimization produced invalid bytecode: {}", e))?;
    
    Ok(())
}
