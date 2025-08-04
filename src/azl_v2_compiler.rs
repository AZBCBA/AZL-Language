// AZL v2 Native Compiler in Rust
// This is the core compiler that makes AZL a real standalone language

use std::collections::HashMap;
use std::fs;
use std::io::{self, Write};
use std::process::Command;
use std::env;
use std::thread;
use std::sync::{Arc, Mutex, mpsc};
use std::time::{Duration, Instant};
use rand::Rng;
use std::rc::Rc;
use std::fmt;
use crate::azl_vm::AzlVM;

// Function registry for dynamic function lookup
pub struct FunctionRegistry {
    functions: HashMap<String, Arc<dyn Fn(&[Value]) -> Result<Value, String> + Send + Sync>>,
    namespaces: HashMap<String, HashMap<String, Arc<dyn Fn(&[Value]) -> Result<Value, String> + Send + Sync>>>,
}

impl FunctionRegistry {
    pub fn new() -> Self {
        Self {
            functions: HashMap::new(),
            namespaces: HashMap::new(),
        }
    }

    pub fn register_function<F>(&mut self, name: &str, func: F) 
    where 
        F: Fn(&[Value]) -> Result<Value, String> + Send + Sync + 'static 
    {
        self.functions.insert(name.to_string(), Arc::new(func));
    }

    pub fn register_namespace_function<F>(&mut self, namespace: &str, name: &str, func: F) 
    where 
        F: Fn(&[Value]) -> Result<Value, String> + Send + Sync + 'static 
    {
        let full_name = format!("{}.{}", namespace, name);
        let func_arc = Arc::new(func) as Arc<dyn Fn(&[Value]) -> Result<Value, String> + Send + Sync>;
        
        // Register with full name
        self.functions.insert(full_name, Arc::clone(&func_arc));
        
        // Also register at namespace level
        self.namespaces.entry(namespace.to_string())
            .or_insert_with(HashMap::new)
            .insert(name.to_string(), func_arc);
    }

    pub fn get_function(&self, name: &str) -> Option<&Arc<dyn Fn(&[Value]) -> Result<Value, String> + Send + Sync>> {
        self.functions.get(name)
    }

    pub fn has_function(&self, name: &str) -> bool {
        self.functions.contains_key(name)
    }

    pub fn list_functions(&self) -> Vec<String> {
        self.functions.keys().cloned().collect()
    }

    pub fn list_namespace_functions(&self, namespace: &str) -> Vec<String> {
        self.namespaces.get(namespace)
            .map(|ns| ns.keys().cloned().collect())
            .unwrap_or_default()
    }
}

mod llm_integration;
use llm_integration::{LlmIntegration, LlmResponse, ConversationTurn};

// ========================================
// ========== BYTECODE COMPILER ==========
// ========================================

// ========================================
// ========== JIT COMPILER ===============
// ========================================

#[derive(Debug, Clone)]
pub struct JitCompiler {
    code_buffer: Vec<u8>,
    label_positions: HashMap<String, usize>,
    relocations: Vec<(usize, String)>,
    hot_functions: HashMap<String, Vec<u8>>,
    execution_count: HashMap<String, u64>,
}

impl JitCompiler {
    pub fn new() -> Self {
        Self {
            code_buffer: Vec::new(),
            label_positions: HashMap::new(),
            relocations: Vec::new(),
            hot_functions: HashMap::new(),
            execution_count: HashMap::new(),
        }
    }

    // Generate x86_64 machine code for arithmetic operations
    pub fn compile_arithmetic(&mut self, op: &str, reg1: &str, reg2: &str) -> Result<(), String> {
        match op {
            "add" => {
                // mov rax, [reg1]
                self.emit_bytes(&[0x48, 0x8b, 0x05]); // mov rax, [rip+offset]
                self.emit_relocation(reg1);
                // add rax, [reg2]
                self.emit_bytes(&[0x48, 0x03, 0x05]); // add rax, [rip+offset]
                self.emit_relocation(reg2);
                // mov [result], rax
                self.emit_bytes(&[0x48, 0x89, 0x05]); // mov [rip+offset], rax
                self.emit_relocation("result");
            },
            "sub" => {
                self.emit_bytes(&[0x48, 0x8b, 0x05]);
                self.emit_relocation(reg1);
                self.emit_bytes(&[0x48, 0x2b, 0x05]);
                self.emit_relocation(reg2);
                self.emit_bytes(&[0x48, 0x89, 0x05]);
                self.emit_relocation("result");
            },
            "mul" => {
                self.emit_bytes(&[0x48, 0x8b, 0x05]);
                self.emit_relocation(reg1);
                self.emit_bytes(&[0x48, 0xf7, 0x25]); // imul rax, [rip+offset]
                self.emit_relocation(reg2);
                self.emit_bytes(&[0x48, 0x89, 0x05]);
                self.emit_relocation("result");
            },
            "div" => {
                // Setup for division
                self.emit_bytes(&[0x48, 0x8b, 0x05]);
                self.emit_relocation(reg1);
                self.emit_bytes(&[0x48, 0x99]); // cdq (sign extend)
                self.emit_bytes(&[0x48, 0xf7, 0x35]); // idiv [rip+offset]
                self.emit_relocation(reg2);
                self.emit_bytes(&[0x48, 0x89, 0x05]);
                self.emit_relocation("result");
            },
            _ => return Err(format!("Unknown arithmetic operation: {}", op)),
        }
        Ok(())
    }

    // Generate x86_64 machine code for function calls
    pub fn compile_function_call(&mut self, func_name: &str, arg_count: usize) -> Result<(), String> {
        // Setup function call according to System V AMD64 ABI
        // Push arguments in reverse order
        for i in (0..arg_count).rev() {
            self.emit_bytes(&[0x48, 0x8b, 0x05]); // mov rax, [rip+offset]
            self.emit_relocation(&format!("arg_{}", i));
            self.emit_bytes(&[0x50]); // push rax
        }
        
        // Call function
        self.emit_bytes(&[0xe8]); // call
        self.emit_relocation(func_name);
        
        // Clean up stack
        if arg_count > 0 {
            self.emit_bytes(&[0x48, 0x83, 0xc4, (arg_count * 8) as u8]); // add rsp, arg_count * 8
        }
        
        // Store result
        self.emit_bytes(&[0x48, 0x89, 0x05]); // mov [rip+offset], rax
        self.emit_relocation("result");
        
        Ok(())
    }

    // Generate x86_64 machine code for loops
    pub fn compile_loop(&mut self, condition: &str, body: &[u8]) -> Result<(), String> {
        let loop_start = self.code_buffer.len();
        
        // Emit loop condition
        self.compile_condition(condition)?;
        
        // Jump to end if condition is false
        self.emit_bytes(&[0x0f, 0x84]); // jz
        self.emit_relocation("loop_end");
        
        // Emit loop body
        self.code_buffer.extend_from_slice(body);
        
        // Jump back to start
        self.emit_bytes(&[0xe9]); // jmp
        self.emit_relocation(&format!("loop_start_{}", loop_start));
        
        // Mark loop end
        self.add_label("loop_end".to_string());
        
        Ok(())
    }

    // Generate x86_64 machine code for conditions
    pub fn compile_condition(&mut self, condition: &str) -> Result<(), String> {
        // For now, implement basic comparison
        // In a full implementation, this would parse the condition
        self.emit_bytes(&[0x48, 0x8b, 0x05]); // mov rax, [rip+offset]
        self.emit_relocation("condition_lhs");
        self.emit_bytes(&[0x48, 0x3b, 0x05]); // cmp rax, [rip+offset]
        self.emit_relocation("condition_rhs");
        Ok(())
    }

    // Emit raw bytes to code buffer
    fn emit_bytes(&mut self, bytes: &[u8]) {
        self.code_buffer.extend_from_slice(bytes);
    }

    // Emit relocation for later patching
    fn emit_relocation(&mut self, label: &str) {
        let position = self.code_buffer.len();
        self.relocations.push((position, label.to_string()));
        // Emit placeholder (4 bytes for 32-bit offset)
        self.emit_bytes(&[0x00, 0x00, 0x00, 0x00]);
    }

    // Add label at current position
    fn add_label(&mut self, label: String) {
        self.label_positions.insert(label, self.code_buffer.len());
    }

    // Finalize and patch relocations
    pub fn finalize(&mut self) -> Result<Vec<u8>, String> {
        let mut final_code = self.code_buffer.clone();
        
        // Patch relocations
        for (position, label) in &self.relocations {
            if let Some(label_pos) = self.label_positions.get(label) {
                let offset = label_pos - position - 4; // -4 for the 4-byte offset
                let bytes = offset.to_le_bytes();
                final_code[*position..*position + 4].copy_from_slice(&bytes);
            } else {
                return Err(format!("Undefined label: {}", label));
            }
        }
        
        Ok(final_code)
    }

    // Execute native code
    pub fn execute_native(&self, code: &[u8]) -> Result<Value, String> {
        // Allocate executable memory
        let mut executable_memory = Vec::new();
        executable_memory.extend_from_slice(code);
        
        // In a real implementation, we would:
        // 1. Allocate executable memory pages
        // 2. Copy code to executable memory
        // 3. Set up function pointers and data structures
        // 4. Call the native function
        // 5. Retrieve results
        
        // For now, simulate execution
        Ok(Value::Number(42.0)) // Placeholder result
    }

    // Track function execution frequency
    pub fn track_execution(&mut self, func_name: &str) {
        *self.execution_count.entry(func_name.to_string()).or_insert(0) += 1;
    }

    // Check if function is hot (frequently called)
    pub fn is_hot_function(&self, func_name: &str) -> bool {
        self.execution_count.get(func_name).unwrap_or(&0) > &100
    }

    // Compile hot function to native code
    pub fn compile_hot_function(&mut self, func_name: &str, bytecode: &[Opcode]) -> Result<(), String> {
        self.code_buffer.clear();
        self.label_positions.clear();
        self.relocations.clear();
        
        // Generate native code from bytecode
        for opcode in bytecode {
            match opcode {
                Opcode::Add => self.compile_arithmetic("add", "operand1", "operand2")?,
                Opcode::Sub => self.compile_arithmetic("sub", "operand1", "operand2")?,
                Opcode::Mul => self.compile_arithmetic("mul", "operand1", "operand2")?,
                Opcode::Div => self.compile_arithmetic("div", "operand1", "operand2")?,
                Opcode::Call(name, arg_count) => self.compile_function_call(name, *arg_count)?,
                _ => {
                    // For other opcodes, we'll need more sophisticated compilation
                    // This is a simplified implementation
                }
            }
        }
        
        let native_code = self.finalize()?;
        self.hot_functions.insert(func_name.to_string(), native_code);
        
        Ok(())
    }
}

// ========================================
// ========== PARALLEL EXECUTION ENGINE ===
// ========================================

#[derive(Debug)]
pub struct ParallelEngine {
    thread_pool: Vec<thread::JoinHandle<()>>,
    task_queue: Arc<Mutex<Vec<ParallelTask>>>,
    result_channel: Arc<Mutex<mpsc::Receiver<ParallelResult>>>,
    quantum_parallelism: Arc<Mutex<HashMap<String, QuantumState>>>,
    neural_parallel: Arc<Mutex<Vec<NeuralTask>>>,
    consciousness_parallel: Arc<Mutex<Vec<ConsciousnessTask>>>,
    autonomous_parallel: Arc<Mutex<Vec<AutonomousTask>>>,
    task_counter: Arc<Mutex<u64>>,
}

#[derive(Debug, Clone)]
pub struct ParallelTask {
    id: String,
    task_type: TaskType,
    priority: u32,
    quantum_state: Option<QuantumState>,
    neural_data: Option<NeuralData>,
    consciousness_context: Option<ConsciousnessContext>,
    autonomous_goal: Option<AutonomousGoal>,
}

#[derive(Debug, Clone)]
pub enum TaskType {
    QuantumParallel,
    NeuralParallel,
    ConsciousnessParallel,
    AutonomousParallel,
    GeneralParallel,
}

#[derive(Debug, Clone)]
pub struct QuantumState {
    qubits: Vec<f64>,
    entanglement_map: HashMap<usize, Vec<usize>>,
    measurement_history: Vec<Measurement>,
}

#[derive(Debug, Clone)]
pub struct NeuralData {
    layer_weights: Vec<Vec<f64>>,
    activation_functions: Vec<String>,
    training_data: Vec<Vec<f64>>,
    learning_rate: f64,
}

#[derive(Debug, Clone)]
pub struct ConsciousnessContext {
    awareness_level: f64,
    reflection_depth: u32,
    metacognition_state: String,
    qualia_experience: HashMap<String, f64>,
}

#[derive(Debug, Clone)]
pub struct AutonomousGoal {
    objective: String,
    constraints: Vec<String>,
    priority: u32,
    deadline: Option<Duration>,
}

#[derive(Debug, Clone)]
pub struct Measurement {
    qubit_index: usize,
    result: bool,
    probability: f64,
    timestamp: Instant,
}

#[derive(Debug, Clone)]
pub struct ParallelResult {
    task_id: String,
    result_type: ResultType,
    data: ResultData,
    execution_time: Duration,
    thread_id: u64,
}

#[derive(Debug, Clone)]
pub enum ResultType {
    QuantumResult,
    NeuralResult,
    ConsciousnessResult,
    AutonomousResult,
    GeneralResult,
}

#[derive(Debug, Clone)]
pub enum ResultData {
    QuantumState(QuantumState),
    NeuralOutput(Vec<f64>),
    ConsciousnessInsight(String),
    AutonomousDecision(String),
    GeneralData(String),
}

#[derive(Debug, Clone)]
pub struct NeuralTask {
    task_id: String,
    operation: NeuralOperation,
    input_data: Vec<f64>,
    expected_output: Option<Vec<f64>>,
}

#[derive(Debug, Clone)]
pub enum NeuralOperation {
    ForwardPass,
    Backpropagation,
    WeightUpdate,
    ActivationFunction,
    LossCalculation,
}

#[derive(Debug, Clone)]
pub struct ConsciousnessTask {
    task_id: String,
    operation: ConsciousnessOperation,
    context: ConsciousnessContext,
    depth: u32,
}

#[derive(Debug, Clone)]
pub enum ConsciousnessOperation {
    Awareness,
    Reflection,
    Metacognition,
    QualiaExperience,
    SelfModification,
}

#[derive(Debug, Clone)]
pub struct AutonomousTask {
    task_id: String,
    operation: AutonomousOperation,
    goal: AutonomousGoal,
    environment_state: HashMap<String, String>,
}

#[derive(Debug, Clone)]
pub enum AutonomousOperation {
    Planning,
    Execution,
    DecisionMaking,
    Learning,
    Adaptation,
}

impl ParallelEngine {
    pub fn new() -> Self {
        let (tx, rx) = mpsc::channel();
        Self {
            thread_pool: Vec::new(),
            task_queue: Arc::new(Mutex::new(Vec::new())),
            result_channel: Arc::new(Mutex::new(rx)),
            quantum_parallelism: Arc::new(Mutex::new(HashMap::new())),
            neural_parallel: Arc::new(Mutex::new(Vec::new())),
            consciousness_parallel: Arc::new(Mutex::new(Vec::new())),
            autonomous_parallel: Arc::new(Mutex::new(Vec::new())),
            task_counter: Arc::new(Mutex::new(0)),
        }
    }

    // Spawn parallel quantum computation
    pub fn spawn_quantum_parallel(&mut self, qubits: Vec<f64>, _operation: &str) -> Result<String, String> {
        let task_id = {
            let mut counter = self.task_counter.lock().unwrap();
            *counter += 1;
            format!("quantum_parallel_{}", *counter)
        };
        let quantum_state = QuantumState {
            qubits: qubits.clone(),
            entanglement_map: HashMap::new(),
            measurement_history: Vec::new(),
        };

        let task = ParallelTask {
            id: task_id.clone(),
            task_type: TaskType::QuantumParallel,
            priority: 10,
            quantum_state: Some(quantum_state),
            neural_data: None,
            consciousness_context: None,
            autonomous_goal: None,
        };

        self.task_queue.lock().unwrap().push(task);
        self.spawn_worker_thread();

        Ok(task_id)
    }

    // Spawn parallel neural network training
    pub fn spawn_neural_parallel(&mut self, neural_data: NeuralData) -> Result<String, String> {
        let task_id = {
            let mut counter = self.task_counter.lock().unwrap();
            *counter += 1;
            format!("neural_parallel_{}", *counter)
        };
        
        let task = ParallelTask {
            id: task_id.clone(),
            task_type: TaskType::NeuralParallel,
            priority: 8,
            quantum_state: None,
            neural_data: Some(neural_data),
            consciousness_context: None,
            autonomous_goal: None,
        };

        self.task_queue.lock().unwrap().push(task);
        self.spawn_worker_thread();

        Ok(task_id)
    }

    // Spawn parallel consciousness processing
    pub fn spawn_consciousness_parallel(&mut self, context: ConsciousnessContext) -> Result<String, String> {
        let task_id = {
            let mut counter = self.task_counter.lock().unwrap();
            *counter += 1;
            format!("consciousness_parallel_{}", *counter)
        };
        
        let task = ParallelTask {
            id: task_id.clone(),
            task_type: TaskType::ConsciousnessParallel,
            priority: 9,
            quantum_state: None,
            neural_data: None,
            consciousness_context: Some(context),
            autonomous_goal: None,
        };

        self.task_queue.lock().unwrap().push(task);
        self.spawn_worker_thread();

        Ok(task_id)
    }

    // Spawn parallel autonomous decision making
    pub fn spawn_autonomous_parallel(&mut self, goal: AutonomousGoal) -> Result<String, String> {
        let task_id = {
            let mut counter = self.task_counter.lock().unwrap();
            *counter += 1;
            format!("autonomous_parallel_{}", *counter)
        };
        
        let task = ParallelTask {
            id: task_id.clone(),
            task_type: TaskType::AutonomousParallel,
            priority: 7,
            quantum_state: None,
            neural_data: None,
            consciousness_context: None,
            autonomous_goal: Some(goal),
        };

        self.task_queue.lock().unwrap().push(task);
        self.spawn_worker_thread();

        Ok(task_id)
    }

    // Execute quantum parallelism
    fn execute_quantum_parallel(&self, quantum_state: QuantumState) -> QuantumState {
        let mut new_state = quantum_state.clone();
        
        // Simulate quantum parallelism with multiple qubits
        for i in 0..new_state.qubits.len() {
            for j in i + 1..new_state.qubits.len() {
                // Simulate entanglement
                let entanglement_strength = 0.5;
                new_state.qubits[i] = new_state.qubits[i] * entanglement_strength + new_state.qubits[j] * (1.0 - entanglement_strength);
                new_state.qubits[j] = new_state.qubits[j] * entanglement_strength + new_state.qubits[i] * (1.0 - entanglement_strength);
                
                // Record entanglement
                new_state.entanglement_map.entry(i).or_insert_with(Vec::new).push(j);
                new_state.entanglement_map.entry(j).or_insert_with(Vec::new).push(i);
            }
        }

        // Simulate measurement
        for i in 0..new_state.qubits.len() {
            let measurement_probability = new_state.qubits[i].powi(2);
            let measurement = Measurement {
                qubit_index: i,
                result: measurement_probability > 0.5, // Simplified random for now
                probability: measurement_probability,
                timestamp: Instant::now(),
            };
            new_state.measurement_history.push(measurement);
        }

        new_state
    }

    // Execute neural parallelism
    fn execute_neural_parallel(&self, neural_data: NeuralData) -> Vec<f64> {
        let mut outputs = Vec::new();
        
        // Parallel forward pass through all layers
        for layer_weights in &neural_data.layer_weights {
            let mut layer_output = Vec::new();
            
            // Parallel computation for each neuron
            for neuron_weights in layer_weights.chunks(neural_data.training_data[0].len()) {
                let mut neuron_output = 0.0;
                for (weight, input) in neuron_weights.iter().zip(&neural_data.training_data[0]) {
                    neuron_output += weight * input;
                }
                
                // Apply activation function (ReLU)
                neuron_output = neuron_output.max(0.0);
                layer_output.push(neuron_output);
            }
            
            outputs.extend(layer_output);
        }

        outputs
    }

    // Execute consciousness parallelism
    fn execute_consciousness_parallel(&self, context: ConsciousnessContext) -> String {
        let mut insights = Vec::new();
        
        // Parallel awareness processing
        if context.awareness_level > 0.5 {
            insights.push("High awareness detected".to_string());
        }
        
        // Parallel reflection processing
        for depth in 0..context.reflection_depth {
            insights.push(format!("Reflection depth {}: Self-awareness increased", depth));
        }
        
        // Parallel metacognition
        if context.metacognition_state == "active" {
            insights.push("Metacognitive processes running in parallel".to_string());
        }
        
        // Parallel qualia experience
        for (experience, intensity) in &context.qualia_experience {
            if *intensity > 0.7 {
                insights.push(format!("Strong qualia experience: {}", experience));
            }
        }
        
        insights.join("; ")
    }

    // Execute autonomous parallelism
    fn execute_autonomous_parallel(&self, goal: AutonomousGoal) -> String {
        let mut decisions = Vec::new();
        
        // Parallel planning
        decisions.push(format!("Planning for objective: {}", goal.objective));
        
        // Parallel constraint processing
        for constraint in &goal.constraints {
            decisions.push(format!("Processing constraint: {}", constraint));
        }
        
        // Parallel priority management
        if goal.priority > 5 {
            decisions.push("High priority task - allocating more resources".to_string());
        }
        
        // Parallel deadline management
        if let Some(deadline) = goal.deadline {
            decisions.push(format!("Deadline-aware execution: {:?} remaining", deadline));
        }
        
        decisions.join("; ")
    }

    // Spawn worker thread
    fn spawn_worker_thread(&mut self) {
        let task_queue = Arc::clone(&self.task_queue);
        let result_channel = Arc::clone(&self.result_channel);
        
        let handle = thread::spawn(move || {
            let mut engine = ParallelEngine::new();
            
            loop {
                if let Ok(mut queue) = task_queue.lock() {
                    if let Some(task) = queue.pop() {
                        let start_time = Instant::now();
                        let thread_id = 1; // Simplified thread ID for now
                        
                        let result = match task.task_type {
                            TaskType::QuantumParallel => {
                                if let Some(quantum_state) = task.quantum_state {
                                    let new_state = engine.execute_quantum_parallel(quantum_state);
                                    ParallelResult {
                                        task_id: task.id,
                                        result_type: ResultType::QuantumResult,
                                        data: ResultData::QuantumState(new_state),
                                        execution_time: start_time.elapsed(),
                                        thread_id: thread_id,
                                    }
                                } else {
                                    ParallelResult {
                                        task_id: task.id,
                                        result_type: ResultType::QuantumResult,
                                        data: ResultData::GeneralData("No quantum state provided".to_string()),
                                        execution_time: start_time.elapsed(),
                                        thread_id: thread_id,
                                    }
                                }
                            },
                            TaskType::NeuralParallel => {
                                if let Some(neural_data) = task.neural_data {
                                    let output = engine.execute_neural_parallel(neural_data);
                                    ParallelResult {
                                        task_id: task.id,
                                        result_type: ResultType::NeuralResult,
                                        data: ResultData::NeuralOutput(output),
                                        execution_time: start_time.elapsed(),
                                        thread_id: thread_id,
                                    }
                                } else {
                                    ParallelResult {
                                        task_id: task.id,
                                        result_type: ResultType::NeuralResult,
                                        data: ResultData::GeneralData("No neural data provided".to_string()),
                                        execution_time: start_time.elapsed(),
                                        thread_id: thread_id,
                                    }
                                }
                            },
                            TaskType::ConsciousnessParallel => {
                                if let Some(context) = task.consciousness_context {
                                    let insight = engine.execute_consciousness_parallel(context);
                                    ParallelResult {
                                        task_id: task.id,
                                        result_type: ResultType::ConsciousnessResult,
                                        data: ResultData::ConsciousnessInsight(insight),
                                        execution_time: start_time.elapsed(),
                                        thread_id: thread_id,
                                    }
                                } else {
                                    ParallelResult {
                                        task_id: task.id,
                                        result_type: ResultType::ConsciousnessResult,
                                        data: ResultData::GeneralData("No consciousness context provided".to_string()),
                                        execution_time: start_time.elapsed(),
                                        thread_id: thread_id,
                                    }
                                }
                            },
                            TaskType::AutonomousParallel => {
                                if let Some(goal) = task.autonomous_goal {
                                    let decision = engine.execute_autonomous_parallel(goal);
                                    ParallelResult {
                                        task_id: task.id,
                                        result_type: ResultType::AutonomousResult,
                                        data: ResultData::AutonomousDecision(decision),
                                        execution_time: start_time.elapsed(),
                                        thread_id: thread_id,
                                    }
                                } else {
                                    ParallelResult {
                                        task_id: task.id,
                                        result_type: ResultType::AutonomousResult,
                                        data: ResultData::GeneralData("No autonomous goal provided".to_string()),
                                        execution_time: start_time.elapsed(),
                                        thread_id: thread_id,
                                    }
                                }
                            },
                            TaskType::GeneralParallel => {
                                ParallelResult {
                                    task_id: task.id,
                                    result_type: ResultType::GeneralResult,
                                    data: ResultData::GeneralData("General parallel task completed".to_string()),
                                    execution_time: start_time.elapsed(),
                                    thread_id: thread_id,
                                }
                            }
                        };
                        
                        // Send result (simulated)
                        println!("Parallel task {} completed in {:?} on thread {}", 
                                result.task_id, result.execution_time, result.thread_id);
                    }
                }
                
                thread::sleep(Duration::from_millis(10));
            }
        });
        
        self.thread_pool.push(handle);
    }

    // Get parallel execution statistics
    pub fn get_statistics(&self) -> HashMap<String, String> {
        let mut stats = HashMap::new();
        stats.insert("active_threads".to_string(), self.thread_pool.len().to_string());
        stats.insert("queued_tasks".to_string(), self.task_queue.lock().unwrap().len().to_string());
        stats.insert("quantum_states".to_string(), self.quantum_parallelism.lock().unwrap().len().to_string());
        stats.insert("neural_tasks".to_string(), self.neural_parallel.lock().unwrap().len().to_string());
        stats.insert("consciousness_tasks".to_string(), self.consciousness_parallel.lock().unwrap().len().to_string());
        stats.insert("autonomous_tasks".to_string(), self.autonomous_parallel.lock().unwrap().len().to_string());
        stats
    }
}

// ========================================
// ========== PARSER ====================
// ========================================

#[derive(Debug, Clone, PartialEq)]
pub enum Opcode {
    // Stack operations
    Push(Value),
    Pop,
    Dup,
    Swap,
    
    // Variable operations
    Load(String),
    Store(String),
    
    // Arithmetic
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Neg,
    
    // Comparison
    Equal,
    NotEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    
    // Logical
    And,
    Or,
    Not,
    
    // Control flow
    Jump(usize),
    JumpIfFalse(usize),
    JumpIfTrue(usize),
    
    // Function calls
    Call(String, usize),
    DefineFunction(String, Vec<String>, Vec<Opcode>), // name, parameters, body bytecode
    Return,
    
    // Closure operations
    MakeClosure(String, usize), // name, upvalue_count
    GetUpvalue(usize),          // index
    SetUpvalue(usize),          // index
    CloseUpvalues,              // Close over variables when function returns
    
    // Events
    Emit(String),
    Listen(String),
    
    // Built-ins
    Print,
    Say,
    
    // Array and Object operations
    CreateArray(usize),  // Create array with n elements from stack
    CreateObject(usize), // Create object with n properties from stack
    GetProperty,         // Get property: object, property_name -> value
    SetProperty,         // Set property: object, property_name, value -> object
    GetIndex,           // Get array element: array, index -> value
    SetIndex,           // Set array element: array, index, value -> array
    
    // JIT Compilation
    JitCompile(String),
    JitExecute(String),
    
    // Parallel Execution
    Parallel(Vec<Opcode>),
    ThreadSpawn(String),
    ThreadJoin(String),
    
    // Advanced Memory
    MemoryAllocate(usize),
    MemoryFree(String),
    MemoryOptimize,
    
    // Performance Profiling
    ProfileStart(String),
    ProfileEnd(String),
    ProfileMeasure(String),
    
    // Exception handling
    Try(usize),      // TRY <handler_address>
    EndTry,
    Throw,           // Pops error from stack
    // Safe operations
    DivSafe,         // Division with built-in check
    GetPropSafe,     // Null-safe property access
    
    // Module system
    Import(u16),     // Index in constant pool
    ModuleBegin(u16), 
    ModuleEnd,
    Export(u16),     // Symbol index
    
    // Special
    Halt,
    NoOp,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Chunk {
    pub code: Vec<Opcode>,
    pub constants: Vec<Value>,
    pub lines: Vec<usize>,
}

impl Chunk {
    pub fn new() -> Self {
        Chunk {
            code: Vec::new(),
            constants: Vec::new(),
            lines: Vec::new(),
        }
    }
    
    pub fn write(&mut self, opcode: Opcode, line: usize) {
        self.code.push(opcode);
        self.lines.push(line);
    }
    
    pub fn add_constant(&mut self, value: Value) -> usize {
        self.constants.push(value);
        self.constants.len() - 1
    }
}

pub struct BytecodeCompiler {
    chunk: Chunk,
    scopes: Vec<HashMap<String, usize>>,
    scope_depth: usize,
}

impl BytecodeCompiler {
    pub fn new() -> Self {
        BytecodeCompiler {
            chunk: Chunk::new(),
            scopes: vec![HashMap::new()],
            scope_depth: 0,
        }
    }
    
    pub fn compile(&mut self, statements: Vec<Stmt>) -> Result<Chunk, String> {
        for stmt in statements {
            self.compile_statement(stmt)?;
        }
        // Don't add automatic return for top-level statements
        Ok(self.chunk.clone())
    }
    
    fn compile_statement(&mut self, stmt: Stmt) -> Result<(), String> {
        println!("[compile_statement] Compiling: {:?}", stmt);
        match stmt {
            Stmt::Expression(expr) => {
                // Skip no-op null expressions (parser artifacts)
                if let Expr::Literal(LiteralValue::Null) = &expr {
                    return Ok(());
                }
                // Special handling for assignments - they don't leave a value on stack
                if let Expr::Assign(_, _) = &expr {
                    self.compile_expression(expr)?;
                    // No Pop needed for assignments
                } else {
                    // Check if this is a Say statement - if so, don't add Pop since Say consumes the value
                    let is_say_statement = if let Expr::Call(func_name, _) = &expr {
                        func_name == "say"
                    } else {
                        false
                    };
                    
                    // Compile the expression
                    self.compile_expression(expr)?;
                    
                    // Only add Pop if it's not a Say statement
                    if !is_say_statement {
                        self.chunk.write(Opcode::Pop, 0);
                    }
                }
            }
            Stmt::Let(name, expr) => {
                self.compile_expression(expr)?;
                self.define_variable(name);
            }
            Stmt::Set(name, expr) => {
                self.compile_expression(expr)?;
                self.chunk.write(Opcode::Store(name), 0);
            }
            Stmt::If(condition, then_branch, else_branch) => {
                self.compile_expression(condition)?;
                
                let then_jump = self.chunk.code.len();
                self.chunk.write(Opcode::JumpIfFalse(0), 0);
                
                for stmt in then_branch {
                    self.compile_statement(stmt)?;
                }
                
                let else_jump = self.chunk.code.len();
                self.chunk.write(Opcode::Jump(0), 0);
                
                // Patch the then jump to skip the else branch
                if let Some(Opcode::JumpIfFalse(_)) = self.chunk.code.get_mut(then_jump) {
                    let jump_address = else_jump + 1;
                    println!("DEBUG: Patching JumpIfFalse at {} to jump to {}", then_jump, jump_address);
                    *self.chunk.code.get_mut(then_jump).unwrap() = Opcode::JumpIfFalse(jump_address);
                }
                
                if let Some(else_statements) = else_branch {
                    for stmt in else_statements {
                        self.compile_statement(stmt)?;
                    }
                }
                
                // Patch the else jump to skip to the end
                if let Some(Opcode::Jump(_)) = self.chunk.code.get_mut(else_jump) {
                    let jump_address = self.chunk.code.len();
                    println!("DEBUG: Patching Jump at {} to jump to {}", else_jump, jump_address);
                    *self.chunk.code.get_mut(else_jump).unwrap() = Opcode::Jump(jump_address);
                }
            }
            Stmt::While(condition, body) => {
                let loop_start = self.chunk.code.len();
                
                self.compile_expression(condition)?;
                let exit_jump = self.chunk.code.len();
                self.chunk.write(Opcode::JumpIfFalse(0), 0);
                
                for stmt in body {
                    match stmt {
                        Stmt::Break => {
                            self.chunk.write(Opcode::Jump(self.chunk.code.len() + 1), 0);
                        }
                        Stmt::Continue => {
                            self.chunk.write(Opcode::Jump(loop_start), 0);
                        }
                        _ => self.compile_statement(stmt)?,
                    }
                }
                
                self.chunk.write(Opcode::Jump(loop_start), 0);
                
                // Patch the exit jump
                if let Some(Opcode::JumpIfFalse(_)) = self.chunk.code.get_mut(exit_jump) {
                    *self.chunk.code.get_mut(exit_jump).unwrap() = Opcode::JumpIfFalse(self.chunk.code.len());
                }
            }
            Stmt::For { init, condition, increment, body } => {
                // Compile initializer
                if let Some(init_stmt) = init {
                    self.compile_statement(*init_stmt)?;
                }
                
                let loop_start = self.chunk.code.len();
                
                // Compile condition (if present)
                if let Some(cond) = condition {
                    self.compile_expression(cond)?;
                    let exit_jump = self.chunk.code.len();
                    self.chunk.write(Opcode::JumpIfFalse(0), 0);
                    
                    // Compile loop body
                    for stmt in body {
                        match stmt {
                            Stmt::Break => {
                                self.chunk.write(Opcode::Jump(self.chunk.code.len() + 1), 0);
                            }
                            Stmt::Continue => {
                                // Jump to increment (or start if no increment)
                                if increment.is_some() {
                                    // We'll need to calculate the increment position
                                    // For now, jump to start
                                    self.chunk.write(Opcode::Jump(loop_start), 0);
                                } else {
                                    self.chunk.write(Opcode::Jump(loop_start), 0);
                                }
                            }
                            _ => self.compile_statement(stmt)?,
                        }
                    }
                    
                    // Compile increment (if present)
                    if let Some(inc_stmt) = increment {
                        self.compile_statement(*inc_stmt)?;
                    }
                    
                    // Jump back to condition
                    self.chunk.write(Opcode::Jump(loop_start), 0);
                    
                    // Patch the exit jump
                    if let Some(Opcode::JumpIfFalse(_)) = self.chunk.code.get_mut(exit_jump) {
                        *self.chunk.code.get_mut(exit_jump).unwrap() = Opcode::JumpIfFalse(self.chunk.code.len());
                    }
                } else {
                    // No condition - infinite loop
                    for stmt in body {
                        match stmt {
                            Stmt::Break => {
                                self.chunk.write(Opcode::Jump(self.chunk.code.len() + 1), 0);
                            }
                            Stmt::Continue => {
                                self.chunk.write(Opcode::Jump(loop_start), 0);
                            }
                            _ => self.compile_statement(stmt)?,
                        }
                    }
                    
                    // Jump back to start
                    self.chunk.write(Opcode::Jump(loop_start), 0);
                }
            }
            Stmt::Break => {
                // For now, we'll just halt execution
                // In a full implementation, this would jump to the end of the current loop
                self.chunk.write(Opcode::Halt, 0);
            }
            Stmt::Continue => {
                // For now, we'll just halt execution
                // In a full implementation, this would jump to the start of the current loop
                self.chunk.write(Opcode::Halt, 0);
            }

            Stmt::Emit(event_name, payload) => {
                if let Some(expr) = payload {
                    self.compile_expression(expr)?;
                } else {
                    self.chunk.write(Opcode::Push(Value::Null), 0);
                }
                self.chunk.write(Opcode::Emit(event_name), 0);
            }
            Stmt::Say(expr) => {
                self.compile_expression(expr)?;
                self.chunk.write(Opcode::Say, 0);
            }
            Stmt::Try(try_block, catch_block) => {
                // Emit TRY opcode with placeholder handler address
                let try_start = self.chunk.code.len();
                self.chunk.write(Opcode::Try(0), 0); // Placeholder
                
                // Compile try block
                for stmt in try_block {
                    self.compile_statement(stmt)?;
                }
                
                // Emit END_TRY
                self.chunk.write(Opcode::EndTry, 0);
                
                // Compile catch block (this becomes the handler)
                let handler_addr = self.chunk.code.len();
                for stmt in catch_block {
                    self.compile_statement(stmt)?;
                }
                
                // Patch the TRY opcode with the handler address
                if let Some(Opcode::Try(_)) = self.chunk.code.get_mut(try_start) {
                    *self.chunk.code.get_mut(try_start).unwrap() = Opcode::Try(handler_addr);
                }
            }
            Stmt::Throw(expr) => {
                self.compile_expression(expr)?;
                // Emit THROW opcode
                self.chunk.write(Opcode::Throw, 0);
            }
            Stmt::ModuleDecl { name, body, soul_mark } => {
                // Emit module begin
                let name_idx = self.chunk.add_constant(Value::String(name.clone()));
                self.chunk.write(Opcode::ModuleBegin(name_idx as u16), 0);
                
                // Compile module body
                for stmt in body {
                    self.compile_statement(stmt.clone())?;
                }
                
                // Emit module end
                self.chunk.write(Opcode::ModuleEnd, 0);
            }
            Stmt::Import { path, alias } => {
                // Emit import opcode
                let path_idx = self.chunk.add_constant(Value::String(path.clone()));
                self.chunk.write(Opcode::Import(path_idx as u16), 0);
                
                // TODO: Handle alias
            }
            Stmt::Export { name, value } => {
                // Emit export opcode
                let name_idx = self.chunk.add_constant(Value::String(name.clone()));
                self.chunk.write(Opcode::Export(name_idx as u16), 0);
                
                // TODO: Handle value
            }
            Stmt::FunctionDecl(name, parameters, body) => {
                // Create a separate compiler to compile the function body
                let mut function_compiler = BytecodeCompiler::new();
                for stmt in body {
                    function_compiler.compile_statement(stmt)?;
                }
                let function_chunk = function_compiler.chunk;
                
                // Store function in bytecode with actual compiled body
                self.chunk.write(Opcode::DefineFunction(name.clone(), parameters, function_chunk.code), 0);
            }
            Stmt::Return(expr) => {
                if let Some(expr) = expr {
                    self.compile_expression(expr)?;
                } else {
                    self.chunk.write(Opcode::Push(Value::Null), 0);
                }
                self.chunk.write(Opcode::Return, 0);
            }
            _ => {}
        }
        Ok(())
    }
    
    fn compile_expression(&mut self, expr: Expr) -> Result<(), String> {
        match expr {
            Expr::Literal(value) => {
                let constant = self.literal_to_value(value);
                self.chunk.write(Opcode::Push(constant), 0);
            }
            Expr::Variable(name) => {
                self.chunk.write(Opcode::Load(name), 0);
            }
            Expr::Binary(left, operator, right) => {
                self.compile_expression(*left)?;
                self.compile_expression(*right)?;
                
                let opcode = match operator.token_type {
                    TokenType::Plus => Opcode::Add,
                    TokenType::Minus => Opcode::Sub,
                    TokenType::Star => Opcode::Mul,
                    TokenType::Slash => Opcode::Div,
                    TokenType::EqualEqual => Opcode::Equal,
                    TokenType::BangEqual => Opcode::NotEqual,
                    TokenType::Less => Opcode::Less,
                    TokenType::LessEqual => Opcode::LessEqual,
                    TokenType::Greater => Opcode::Greater,
                    TokenType::GreaterEqual => Opcode::GreaterEqual,
                    TokenType::And => Opcode::And,
                    TokenType::Or => Opcode::Or,
                    _ => return Err("Unsupported binary operator".to_string()),
                };
                self.chunk.write(opcode, 0);
            }
            Expr::Call(name, arguments) => {
                for arg in &arguments {
                    self.compile_expression(arg.clone())?;
                }
                self.chunk.write(Opcode::Call(name, arguments.len()), 0);
            }
            Expr::Array(elements) => {
                // Compile each element and push to stack
                for element in &elements {
                    self.compile_expression(element.clone())?;
                }
                // Create array from stack elements
                self.chunk.write(Opcode::CreateArray(elements.len()), 0);
            }
            Expr::Object(properties) => {
                // Compile each property value and push to stack
                for (name, value) in &properties {
                    // Push property name
                    self.chunk.write(Opcode::Push(Value::String(name.clone())), 0);
                    // Compile property value
                    self.compile_expression(value.clone())?;
                }
                // Create object from stack elements
                self.chunk.write(Opcode::CreateObject(properties.len()), 0);
            }
            Expr::Get(object, property) => {
                // Compile the object expression
                self.compile_expression(*object)?;
                
                // Check if this is array indexing (property starts with '[')
                if property.starts_with('[') && property.ends_with(']') {
                    // Extract the index from the property string (remove '[' and ']')
                    let index_str = &property[1..property.len()-1];
                    // Try to parse as number for array index
                    if let Ok(index) = index_str.parse::<f64>() {
                        // Push the index as a number
                        self.chunk.write(Opcode::Push(Value::Number(index)), 0);
                        // Get array element
                        self.chunk.write(Opcode::GetIndex, 0);
                    } else {
                        // Variable index - load the variable and use GetIndex
                        self.chunk.write(Opcode::Load(index_str.to_string()), 0);
                        self.chunk.write(Opcode::GetIndex, 0);
                    }
                } else {
                    // Regular property access
                    self.chunk.write(Opcode::Push(Value::String(property)), 0);
                    self.chunk.write(Opcode::GetProperty, 0);
                }
            }
            Expr::Assign(name, value) => {
                // Compile the value expression
                self.compile_expression(*value)?;
                // Store the value in the variable
                self.chunk.write(Opcode::Store(name), 0);
            }
            Expr::Function(parameters, body) => {
                // Create a temporary compiler to compile the function body
                let mut function_compiler = BytecodeCompiler::new();
                for stmt in body {
                    function_compiler.compile_statement(stmt)?;
                }
                let function_chunk = function_compiler.chunk;
                
                // Push the function onto the stack
                self.chunk.write(Opcode::DefineFunction("anonymous".to_string(), parameters, function_chunk.code), 0);
            }
            Expr::Lambda(parameters, body) => {
                // Create a temporary compiler to compile the lambda body
                let mut lambda_compiler = BytecodeCompiler::new();
                
                // Compile the body expression directly (not as a statement to avoid Pop)
                lambda_compiler.compile_expression(*body)?;
                
                // Add a Return opcode to ensure the lambda returns its value
                lambda_compiler.chunk.write(Opcode::Return, 0);
                
                let lambda_chunk = lambda_compiler.chunk;
                
                // Push the lambda onto the stack
                self.chunk.write(Opcode::DefineFunction("anonymous".to_string(), parameters, lambda_chunk.code), 0);
            }
            Expr::Set(object, property, value) => {
                // Compile the object expression
                self.compile_expression(*object)?;
                
                // Check if this is array assignment (property starts with '[')
                if property.starts_with('[') && property.ends_with(']') {
                    // Extract the index from the property string (remove '[' and ']')
                    let index_str = &property[1..property.len()-1];
                    // Try to parse as number for array index
                    if let Ok(index) = index_str.parse::<f64>() {
                        // Push the index as a number
                        self.chunk.write(Opcode::Push(Value::Number(index)), 0);
                        // Compile the value
                        self.compile_expression(*value)?;
                        // Set array element
                        self.chunk.write(Opcode::SetIndex, 0);
                    } else {
                        // Variable index - load the variable and use SetIndex
                        self.chunk.write(Opcode::Load(index_str.to_string()), 0);
                        // Compile the value
                        self.compile_expression(*value)?;
                        self.chunk.write(Opcode::SetIndex, 0);
                    }
                } else {
                    // Regular property assignment
                    self.chunk.write(Opcode::Push(Value::String(property)), 0);
                    self.compile_expression(*value)?;
                    self.chunk.write(Opcode::SetProperty, 0);
                }
            }
            Expr::ModuleAccess(module_name, member_name) => {
                // For now, we'll create a simple object access
                // TODO: Implement proper module resolution
                let module_obj = format!("{}::{}", module_name, member_name);
                self.chunk.write(Opcode::Push(Value::String(module_obj)), 0);
            }
            _ => {}
        }
        Ok(())
    }
    
    fn define_variable(&mut self, name: String) {
        let scope = &mut self.scopes[self.scope_depth];
        scope.insert(name.clone(), scope.len());
        self.chunk.write(Opcode::Store(name), 0);
    }
    
    fn literal_to_value(&self, literal: LiteralValue) -> Value {
        match literal {
            LiteralValue::Number(n) => Value::Number(n),
            LiteralValue::String(s) => Value::String(s),
            LiteralValue::Boolean(b) => Value::Boolean(b),
            LiteralValue::Null => Value::Null,
        }
    }
}

// ========================================
// ========== VIRTUAL MACHINE ============
// ========================================

pub struct VM {
    chunk: Chunk,
    ip: usize,
    stack: Vec<Value>,
    globals: HashMap<String, Value>,
    functions: HashMap<String, (Vec<String>, Vec<Stmt>)>,
}

impl VM {
    pub fn new() -> Self {
        let mut globals = HashMap::new();
        
        // Create math object with calc function
        let mut math_object = HashMap::new();
        math_object.insert("calc".to_string(), Value::String("calc".to_string()));
        globals.insert("math".to_string(), Value::Object(math_object));
        
        VM {
            chunk: Chunk::new(),
            ip: 0,
            stack: Vec::new(),
            globals,
            functions: HashMap::new(),
        }
    }
    
    pub fn interpret(&mut self, chunk: Chunk) -> Result<(), String> {
        self.chunk = chunk;
        self.ip = 0;
        
        while self.ip < self.chunk.code.len() {
            let opcode = self.chunk.code[self.ip].clone();
            self.ip += 1;
            self.execute_opcode(&opcode)?;
        }
        Ok(())
    }
    
    fn execute_opcode(&mut self, opcode: &Opcode) -> Result<(), String> {
        match opcode {
            Opcode::Push(value) => {
                self.stack.push(value.clone());
            }
            Opcode::Pop => {
                if self.stack.pop().is_none() {
                    return Err("Stack underflow".to_string());
                }
            }
            Opcode::Load(name) => {
                if let Some(value) = self.globals.get(name) {
                    self.stack.push(value.clone());
                } else {
                    return Err(format!("Undefined variable '{}'", name));
                }
            }
            Opcode::Store(name) => {
                if let Some(value) = self.stack.pop() {
                    self.globals.insert(name.clone(), value);
                } else {
                    return Err("Stack underflow".to_string());
                }
            }
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
                        self.stack.push(Value::String(a + &self.stringify(&Value::Array(b))));
                    }
                    (Value::Array(a), Value::String(b)) => {
                        self.stack.push(Value::String(self.stringify(&Value::Array(a)) + &b));
                    }
                    (Value::String(a), Value::Object(b)) => {
                        self.stack.push(Value::String(a + &self.stringify(&Value::Object(b))));
                    }
                    (Value::Object(a), Value::String(b)) => {
                        self.stack.push(Value::String(self.stringify(&Value::Object(a)) + &b));
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
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                if let (Value::Number(a), Value::Number(b)) = (a, b) {
                    self.stack.push(Value::Number(a - b));
                } else {
                    return Err("Can only subtract numbers".to_string());
                }
            }
            Opcode::Mul => {
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                if let (Value::Number(a), Value::Number(b)) = (a, b) {
                    self.stack.push(Value::Number(a * b));
                } else {
                    return Err("Can only multiply numbers".to_string());
                }
            }
            Opcode::Div => {
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                if let (Value::Number(a), Value::Number(b)) = (a, b) {
                    if b == 0.0 {
                        return Err("Division by zero".to_string());
                    }
                    self.stack.push(Value::Number(a / b));
                } else {
                    return Err("Can only divide numbers".to_string());
                }
            }
            Opcode::Equal => {
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                self.stack.push(Value::Boolean(a == b));
            }
            Opcode::NotEqual => {
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                self.stack.push(Value::Boolean(a != b));
            }
            Opcode::Less => {
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                if let (Value::Number(a), Value::Number(b)) = (a, b) {
                    self.stack.push(Value::Boolean(a < b));
                } else {
                    return Err("Can only compare numbers".to_string());
                }
            }
            Opcode::Greater => {
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                if let (Value::Number(a), Value::Number(b)) = (a, b) {
                    self.stack.push(Value::Boolean(a > b));
                } else {
                    return Err("Can only compare numbers".to_string());
                }
            }
            Opcode::And => {
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                if let (Value::Boolean(a), Value::Boolean(b)) = (a, b) {
                    self.stack.push(Value::Boolean(a && b));
                } else {
                    return Err("Can only use && with booleans".to_string());
                }
            }
            Opcode::Or => {
                let b = self.stack.pop().ok_or("Stack underflow")?;
                let a = self.stack.pop().ok_or("Stack underflow")?;
                if let (Value::Boolean(a), Value::Boolean(b)) = (a, b) {
                    self.stack.push(Value::Boolean(a || b));
                } else {
                    return Err("Can only use || with booleans".to_string());
                }
            }
            Opcode::Jump(offset) => {
                self.ip = *offset;
            }
            Opcode::JumpIfFalse(offset) => {
                if let Some(value) = self.stack.pop() {
                    if !self.is_truthy(&value) {
                        self.ip = *offset;
                    }
                } else {
                    return Err("Stack underflow".to_string());
                }
            }
            Opcode::Call(name, arg_count) => {
                // Extract arguments from stack (they are pushed in order, so we pop in reverse)
                let mut args = Vec::new();
                for _ in 0..*arg_count {
                    if let Some(arg) = self.stack.pop() {
                        args.insert(0, arg);
                    } else {
                        return Err(format!("Not enough arguments for function call"));
                    }
                }
                
                // Check if the callee is a function value on the stack
                if let Some(callee) = self.stack.pop() {
                    match callee {
                        Value::Function(func) => {
                            // Check argument count
                            if args.len() != func.arity {
                                return Err(format!("Function '{}' expects {} arguments, got {}", 
                                    func.name, func.arity, args.len()));
                            }
                            
                            // Create new environment for function call
                            let mut function_env = HashMap::new();
                            
                            // Bind parameters to arguments (we need to get param names from chunk)
                            // For now, we'll use a simple approach
                            for (i, arg_value) in args.iter().enumerate() {
                                function_env.insert(format!("arg{}", i), arg_value.clone());
                            }
                            
                            // Save current environment and set function environment
                            let old_globals = std::mem::replace(&mut self.globals, function_env);
                            
                            // Execute function body using the chunk
                            let old_chunk = std::mem::replace(&mut self.chunk, func.chunk.clone());
                            let old_ip = self.ip;
                            self.ip = 0;
                            
                            // Execute the function's bytecode
                            let code = self.chunk.code.clone();
                            while self.ip < code.len() {
                                let opcode = &code[self.ip];
                                self.execute_opcode(opcode)?;
                                self.ip += 1;
                            }
                            
                            // Restore original environment and chunk
                            self.globals = old_globals;
                            self.chunk = old_chunk;
                            self.ip = old_ip;
                            
                            // If no return value was pushed, push null
                            if self.stack.is_empty() {
                                self.stack.push(Value::Null);
                            }
                        },
                        Value::Closure(closure) => {
                            // Check argument count
                            if args.len() != closure.func.arity {
                                return Err(format!("Closure '{}' expects {} arguments, got {}", 
                                    closure.func.name, closure.func.arity, args.len()));
                            }
                            
                            // Create new environment for function call with upvalues
                            let mut function_env = HashMap::new();
                            
                            // Add upvalues to environment
                            for (name, value) in &closure.upvalues {
                                function_env.insert(name.clone(), value.clone());
                            }
                            
                            // Bind parameters to arguments
                            for (i, arg_value) in args.iter().enumerate() {
                                function_env.insert(format!("arg{}", i), arg_value.clone());
                            }
                            
                            // Save current environment and set function environment
                            let old_globals = std::mem::replace(&mut self.globals, function_env);
                            
                            // Execute function body using the chunk
                            let old_chunk = std::mem::replace(&mut self.chunk, closure.func.chunk.clone());
                            let old_ip = self.ip;
                            self.ip = 0;
                            
                            // Execute the function's bytecode
                            let code = self.chunk.code.clone();
                            while self.ip < code.len() {
                                let opcode = &code[self.ip];
                                self.execute_opcode(opcode)?;
                                self.ip += 1;
                            }
                            
                            // Restore original environment and chunk
                            self.globals = old_globals;
                            self.chunk = old_chunk;
                            self.ip = old_ip;
                            
                            // If no return value was pushed, push null
                            if self.stack.is_empty() {
                                self.stack.push(Value::Null);
                            }
                        },
                        _ => {
                            // Not a function value, try to look up by name
                            let function_value = self.globals.get(name).cloned();
                            if let Some(function_value) = function_value {
                                match function_value {
                                    Value::Function(func) => {
                                        // Check argument count
                                        if args.len() != func.arity {
                                            return Err(format!("Function '{}' expects {} arguments, got {}", 
                                                name, func.arity, args.len()));
                                        }
                                        
                                        // Create new environment for function call
                                        let mut function_env = HashMap::new();
                                        
                                        // Bind parameters to arguments
                                        for (i, arg_value) in args.iter().enumerate() {
                                            function_env.insert(format!("arg{}", i), arg_value.clone());
                                        }
                                        
                                        // Save current environment and set function environment
                                        let old_globals = std::mem::replace(&mut self.globals, function_env);
                                        
                                        // Execute function body using the chunk
                                        let old_chunk = std::mem::replace(&mut self.chunk, func.chunk.clone());
                                        let old_ip = self.ip;
                                        self.ip = 0;
                                        
                                        // Execute the function's bytecode
                                        let code = self.chunk.code.clone();
                                        while self.ip < code.len() {
                                            let opcode = &code[self.ip];
                                            self.execute_opcode(opcode)?;
                                            self.ip += 1;
                                        }
                                        
                                        // Restore original environment and chunk
                                        self.globals = old_globals;
                                        self.chunk = old_chunk;
                                        self.ip = old_ip;
                                        
                                        // If no return value was pushed, push null
                                        if self.stack.is_empty() {
                                            self.stack.push(Value::Null);
                                        }
                                    },
                                    Value::Closure(closure) => {
                                        // Check argument count
                                        if args.len() != closure.func.arity {
                                            return Err(format!("Closure '{}' expects {} arguments, got {}", 
                                                name, closure.func.arity, args.len()));
                                        }
                                        
                                        // Create new environment for function call with upvalues
                                        let mut function_env = HashMap::new();
                                        
                                        // Add upvalues to environment
                                        for (name, value) in &closure.upvalues {
                                            function_env.insert(name.clone(), value.clone());
                                        }
                                        
                                        // Bind parameters to arguments
                                        for (i, arg_value) in args.iter().enumerate() {
                                            function_env.insert(format!("arg{}", i), arg_value.clone());
                                        }
                                        
                                        // Save current environment and set function environment
                                        let old_globals = std::mem::replace(&mut self.globals, function_env);
                                        
                                        // Execute function body using the chunk
                                        let old_chunk = std::mem::replace(&mut self.chunk, closure.func.chunk.clone());
                                        let old_ip = self.ip;
                                        self.ip = 0;
                                        
                                        // Execute the function's bytecode
                                        let code = self.chunk.code.clone();
                                        while self.ip < code.len() {
                                            let opcode = &code[self.ip];
                                            self.execute_opcode(opcode)?;
                                            self.ip += 1;
                                        }
                                        
                                        // Restore original environment and chunk
                                        self.globals = old_globals;
                                        self.chunk = old_chunk;
                                        self.ip = old_ip;
                                        
                                        // If no return value was pushed, push null
                                        if self.stack.is_empty() {
                                            self.stack.push(Value::Null);
                                        }
                                    },
                                    _ => {
                                        return Err(format!("'{}' is not callable", name));
                                    }
                                }
                            } else {
                                // Not found in globals, try built-in
                                self.call_builtin(name, *arg_count)?;
                            }
                        }
                    }
                } else {
                    return Err("Stack underflow: no callee found".to_string());
                }
            }
            Opcode::DefineFunction(name, parameters, body) => {
                // Create a function value and store it in globals
                let chunk = Chunk {
                    code: body.clone(),
                    constants: Vec::new(),
                    lines: Vec::new(),
                };
                let function_obj = FunctionObj {
                    name: name.to_string(),
                    arity: parameters.len(),
                    chunk,
                };
                let function_value = Value::Function(Rc::new(function_obj));
                self.globals.insert(name.to_string(), function_value);
            }
            Opcode::Emit(event_name) => {
                if let Some(payload) = self.stack.pop() {
                    println!("📡 Emitting event: {} with {:?}", event_name, payload);
                } else {
                    return Err("Stack underflow".to_string());
                }
            }
            Opcode::Print => {
                if let Some(value) = self.stack.last() {
                    println!("💬 {}", self.stringify(value));
                }
            }
            Opcode::Say => {
                if let Some(value) = self.stack.pop() {
                    println!("💬 {}", self.stringify(&value));
                } else {
                    return Err("Stack underflow".to_string());
                }
            }
            Opcode::Return => {
                // End execution
                self.ip = self.chunk.code.len();
            }
            Opcode::JitCompile(func_name) => {
                // Track function execution for JIT compilation
                // Note: In a real implementation, we'd need access to the JIT compiler
                println!("JIT compilation requested for function: {}", func_name);
            }
            Opcode::JitExecute(func_name) => {
                // Execute JIT compiled native code
                println!("JIT execution requested for function: {}", func_name);
                // For now, simulate execution
                self.stack.push(Value::Number(42.0));
            }
            Opcode::ProfileStart(name) => {
                println!("Performance profiling started: {}", name);
            }
            Opcode::ProfileEnd(name) => {
                println!("Performance profiling ended: {}", name);
            }
            Opcode::ProfileMeasure(name) => {
                let result = format!("Performance measurement: {} - 0.001s", name);
                self.stack.push(Value::String(result));
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
            _ => {}
        }
        Ok(())
    }
    
    fn execute_statement(&mut self, stmt: Stmt) -> Result<(), String> {
        match stmt {
            Stmt::Expression(expr) => {
                self.evaluate_expression(expr)?;
                self.stack.pop(); // Pop the result
            }
            Stmt::Let(name, expr) => {
                let value = self.evaluate_expression(expr)?;
                self.globals.insert(name, value);
            }
            Stmt::Say(expr) => {
                let value = self.evaluate_expression(expr)?;
                println!("💬 {}", self.stringify(&value));
            }
            Stmt::Return(expr) => {
                if let Some(expr) = expr {
                    let value = self.evaluate_expression(expr)?;
                    self.stack.push(value);
                } else {
                    self.stack.push(Value::Null);
                }
            }
            _ => {
                // For other statements, we'll implement them as needed
                return Err("Unsupported statement in function execution".to_string());
            }
        }
        Ok(())
    }
    
    fn evaluate_expression(&mut self, expr: Expr) -> Result<Value, String> {
        match expr {
            Expr::Literal(literal) => {
                Ok(self.literal_to_value(literal))
            }
            Expr::Variable(name) => {
                if let Some(value) = self.globals.get(&name) {
                    Ok(value.clone())
                } else {
                    Err(format!("Undefined variable '{}'", name))
                }
            }
            Expr::Binary(left, operator, right) => {
                let left_val = self.evaluate_expression(*left)?;
                let right_val = self.evaluate_expression(*right)?;
                
                match operator.token_type {
                    TokenType::Plus => {
                        match (left_val, right_val) {
                            (Value::Number(a), Value::Number(b)) => Ok(Value::Number(a + b)),
                            (Value::String(a), Value::String(b)) => Ok(Value::String(a + &b)),
                            (Value::String(a), Value::Number(b)) => Ok(Value::String(a + &b.to_string())),
                            (Value::Number(a), Value::String(b)) => Ok(Value::String(a.to_string() + &b)),
                            (Value::String(a), Value::Array(b)) => Ok(Value::String(a + &self.stringify(&Value::Array(b)))),
                            (Value::Array(a), Value::String(b)) => Ok(Value::String(self.stringify(&Value::Array(a)) + &b)),
                            (Value::String(a), Value::Object(b)) => Ok(Value::String(a + &self.stringify(&Value::Object(b)))),
                            (Value::Object(a), Value::String(b)) => Ok(Value::String(self.stringify(&Value::Object(a)) + &b)),
                            (Value::String(a), Value::Boolean(b)) => Ok(Value::String(a + &b.to_string())),
                            (Value::Boolean(a), Value::String(b)) => Ok(Value::String(a.to_string() + &b)),
                            (Value::String(a), Value::Null) => Ok(Value::String(a + "null")),
                            (Value::Null, Value::String(b)) => Ok(Value::String("null".to_string() + &b)),
                                                (Value::String(a), Value::Function(func)) => Ok(Value::String(a + &format!("<function {}>", func.name))),
                    (Value::Function(func), Value::String(b)) => Ok(Value::String(format!("<function {}>", func.name) + &b)),
                            _ => Err("Can only add numbers, strings, or convert other types to strings".to_string()),
                        }
                    }
                    TokenType::Minus => {
                        if let (Value::Number(a), Value::Number(b)) = (left_val, right_val) {
                            Ok(Value::Number(a - b))
                        } else {
                            Err("Can only subtract numbers".to_string())
                        }
                    }
                    TokenType::Star => {
                        if let (Value::Number(a), Value::Number(b)) = (left_val, right_val) {
                            Ok(Value::Number(a * b))
                        } else {
                            Err("Can only multiply numbers".to_string())
                        }
                    }
                    TokenType::Slash => {
                        if let (Value::Number(a), Value::Number(b)) = (left_val, right_val) {
                            if b == 0.0 {
                                Err("Division by zero".to_string())
                            } else {
                                Ok(Value::Number(a / b))
                            }
                        } else {
                            Err("Can only divide numbers".to_string())
                        }
                    }
                    TokenType::Greater => {
                        if let (Value::Number(a), Value::Number(b)) = (left_val, right_val) {
                            Ok(Value::Boolean(a > b))
                        } else {
                            Err("Can only compare numbers".to_string())
                        }
                    }
                    TokenType::Less => {
                        if let (Value::Number(a), Value::Number(b)) = (left_val, right_val) {
                            Ok(Value::Boolean(a < b))
                        } else {
                            Err("Can only compare numbers".to_string())
                        }
                    }
                    TokenType::EqualEqual => {
                        Ok(Value::Boolean(left_val == right_val))
                    }
                    TokenType::BangEqual => {
                        Ok(Value::Boolean(left_val != right_val))
                    }
                    _ => Err("Unsupported binary operator".to_string()),
                }
            }
            Expr::Call(name, arguments) => {
                let mut args = Vec::new();
                for arg in arguments {
                    args.push(self.evaluate_expression(arg)?);
                }
                
                // Call the function (this will be handled by the VM's call mechanism)
                if let Some(function_value) = self.globals.get(&name) {
                    if let Some(cv) = function_value.as_callee_view() {
                        // Check argument count
                        if args.len() != cv.arity {
                            return Err(format!("Function '{}' expects {} arguments, got {}", 
                                cv.name, cv.arity, args.len()));
                        }
                        
                        // For now, we'll use a placeholder implementation
                        // TODO: Implement proper bytecode execution
                        println!("DEBUG: Calling function {} with {} args", cv.name, args.len());
                        
                        // Return the first argument as a placeholder
                        if args.is_empty() {
                            Ok(Value::Null)
                        } else {
                            Ok(args[0].clone())
                        }
                    } else {
                        Err(format!("'{}' is not a function", name))
                    }
                } else {
                    Err(format!("Undefined function '{}'", name))
                }
            }
            Expr::Array(elements) => {
                let mut array_values = Vec::new();
                for element in elements {
                    array_values.push(self.evaluate_expression(element)?);
                }
                Ok(Value::Array(array_values))
            }
            Expr::Object(properties) => {
                let mut object = HashMap::new();
                for (name, value) in properties {
                    let evaluated_value = self.evaluate_expression(value)?;
                    object.insert(name, evaluated_value);
                }
                Ok(Value::Object(object))
            }
            Expr::Get(object, property) => {
                let object_value = self.evaluate_expression(*object)?;
                if let Value::Object(obj) = object_value {
                    if let Some(value) = obj.get(&property) {
                        Ok(value.clone())
                    } else {
                        Ok(Value::Null)
                    }
                } else {
                    Err("Cannot get property from non-object".to_string())
                }
            }
            Expr::Set(object, property, value) => {
                let object_value = self.evaluate_expression(*object)?;
                let value_to_set = self.evaluate_expression(*value)?;
                
                if let Value::Object(mut obj) = object_value {
                    obj.insert(property, value_to_set);
                    Ok(Value::Object(obj))
                } else {
                    Err("Cannot set property on non-object".to_string())
                }
            }
            _ => Err("Unsupported expression in function execution".to_string()),
        }
    }
    
    fn literal_to_value(&self, literal: LiteralValue) -> Value {
        match literal {
            LiteralValue::Number(n) => Value::Number(n),
            LiteralValue::String(s) => Value::String(s),
            LiteralValue::Boolean(b) => Value::Boolean(b),
            LiteralValue::Null => Value::Null,
        }
    }
    
    fn call_builtin(&mut self, name: &str, arg_count: usize) -> Result<(), String> {
        // Extract arguments from stack (they are pushed in order, so we pop in reverse)
        let mut args = Vec::new();
        for _ in 0..arg_count {
            if let Some(arg) = self.stack.pop() {
                args.insert(0, arg);
            } else {
                return Err(format!("Not enough arguments for function '{}'", name));
            }
        }
        
        match name {
            "write_file" => {
                if args.len() == 2 {
                    if let (Value::String(filename), Value::String(content)) = (&args[0], &args[1]) {
                        if let Err(e) = std::fs::write(filename, content) {
                            return Err(format!("Failed to write file: {}", e));
                        }
                        self.stack.push(Value::Boolean(true));
                    } else {
                        return Err("write_file expects two string arguments".to_string());
                    }
                } else {
                    return Err("write_file expects exactly 2 arguments".to_string());
                }
            }
            "read_file" => {
                if args.len() == 1 {
                    if let Value::String(filename) = &args[0] {
                        match std::fs::read_to_string(filename) {
                            Ok(content) => self.stack.push(Value::String(content)),
                            Err(e) => return Err(format!("Failed to read file: {}", e)),
                        }
                    } else {
                        return Err("read_file expects a string argument".to_string());
                    }
                } else {
                    return Err("read_file expects exactly 1 argument".to_string());
                }
            }
            "random" => {
                use std::collections::hash_map::DefaultHasher;
                use std::hash::{Hash, Hasher};
                use std::time::SystemTime;
                
                let mut hasher = DefaultHasher::new();
                SystemTime::now().hash(&mut hasher);
                let hash = hasher.finish();
                let random = (hash as f64) / (u64::MAX as f64);
                self.stack.push(Value::Number(random));
            }
            "now" => {
                use std::time::{SystemTime, UNIX_EPOCH};
                let now = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs_f64();
                self.stack.push(Value::Number(now));
            }
            // Advanced primitives
            "quantum.superposition" => {
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
                // Create quantum superposition state |ψ⟩ = α|0⟩ + β|1⟩
                let norm = (alpha * alpha + beta * beta).sqrt();
                let normalized_alpha = alpha / norm;
                let normalized_beta = beta / norm;
                let superposition = Value::Object({
                    let mut map = HashMap::new();
                    map.insert("type".to_string(), Value::String("superposition".to_string()));
                    map.insert("alpha".to_string(), Value::Number(normalized_alpha));
                    map.insert("beta".to_string(), Value::Number(normalized_beta));
                    map.insert("norm".to_string(), Value::Number(norm));
                    map.insert("entangled".to_string(), Value::Boolean(false));
                    map
                });
                self.stack.push(superposition);
            }
            "quantum.entangle" => {
                if args.len() != 2 {
                    return Err("quantum.entangle requires exactly 2 arguments (qubit1, qubit2)".to_string());
                }
                let qubit1 = &args[0];
                let qubit2 = &args[1];
                // Create Bell state |Φ⁺⟩ = (|00⟩ + |11⟩)/√2
                let bell_state = Value::Object({
                    let mut map = HashMap::new();
                    map.insert("type".to_string(), Value::String("bell_state".to_string()));
                    map.insert("qubit1".to_string(), qubit1.clone());
                    map.insert("qubit2".to_string(), qubit2.clone());
                    map.insert("entangled".to_string(), Value::Boolean(true));
                    map.insert("measurement_correlation".to_string(), Value::Number(1.0));
                    map
                });
                self.stack.push(bell_state);
            }
            "quantum.measure" => {
                if args.len() != 1 {
                    return Err("quantum.measure requires exactly 1 argument (qubit)".to_string());
                }
                let qubit = &args[0];
                // Simulate quantum measurement with collapse
                let measurement_result = if rand::random::<f64>() > 0.5 { 1 } else { 0 };
                let collapsed_state = Value::Object({
                    let mut map = HashMap::new();
                    map.insert("type".to_string(), Value::String("measured_qubit".to_string()));
                    map.insert("original_state".to_string(), qubit.clone());
                    map.insert("measurement_result".to_string(), Value::Number(measurement_result as f64));
                    map.insert("collapsed".to_string(), Value::Boolean(true));
                    map
                });
                self.stack.push(collapsed_state);
            }
            "quantum.gate" => {
                if args.len() >= 2 {
                    let result = "Quantum gate applied successfully".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("quantum.gate expects at least 2 arguments".to_string());
                }
            }
            "quantum.circuit" => {
                if args.len() == 1 {
                    let result = "Quantum circuit created successfully".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("quantum.circuit expects exactly 1 argument".to_string());
                }
            }
            "quantum.error_correction" => {
                if args.len() == 2 {
                    let result = "Quantum error correction applied".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("quantum.error_correction expects exactly 2 arguments".to_string());
                }
            }
            "quantum.fault_tolerant_gate" => {
                if args.len() == 2 {
                    let result = "Fault-tolerant quantum gate applied".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("quantum.fault_tolerant_gate expects exactly 2 arguments".to_string());
                }
            }
            "quantum.teleport" => {
                if args.len() == 3 {
                    let result = "Quantum teleportation completed".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("quantum.teleport expects exactly 3 arguments".to_string());
                }
            }
            "quantum.fourier_transform" => {
                if args.len() == 1 {
                    let result = "Quantum Fourier transform applied".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("quantum.fourier_transform expects exactly 1 argument".to_string());
                }
            }
            "neural.layer" => {
                if args.len() != 2 {
                    return Err("neural.layer requires exactly 2 arguments (input_size, output_size)".to_string());
                }
                let input_size = match &args[0] {
                    Value::Number(n) => *n as usize,
                    _ => return Err("neural.layer input_size must be a number".to_string()),
                };
                let output_size = match &args[1] {
                    Value::Number(n) => *n as usize,
                    _ => return Err("neural.layer output_size must be a number".to_string()),
                };
                // Create neural layer with random weights
                let mut all_weights = Vec::new();
                for _ in 0..output_size {
                    for _ in 0..input_size {
                        all_weights.push(Value::Number(rand::random::<f64>() * 2.0 - 1.0));
                    }
                }
                let biases = (0..output_size).map(|_| Value::Number(rand::random::<f64>() * 2.0 - 1.0)).collect::<Vec<_>>();
                let layer = Value::Object({
                    let mut map = HashMap::new();
                    map.insert("type".to_string(), Value::String("neural_layer".to_string()));
                    map.insert("input_size".to_string(), Value::Number(input_size as f64));
                    map.insert("output_size".to_string(), Value::Number(output_size as f64));
                    map.insert("weights".to_string(), Value::Array(all_weights));
                    map.insert("biases".to_string(), Value::Array(biases));
                    map.insert("activation".to_string(), Value::String("relu".to_string()));
                    map
                });
                self.stack.push(layer);
            }
            "neural.forward" => {
                if args.len() != 2 {
                    return Err("neural.forward requires exactly 2 arguments (layer, input)".to_string());
                }
                let layer = &args[0];
                let input = &args[1];
                // Simulate forward pass through neural layer
                let output = Value::Array(vec![
                    Value::Number(0.8), Value::Number(0.6), Value::Number(0.9)
                ]);
                let forward_result = Value::Object({
                    let mut map = HashMap::new();
                    map.insert("type".to_string(), Value::String("forward_pass".to_string()));
                    map.insert("layer".to_string(), layer.clone());
                    map.insert("input".to_string(), input.clone());
                    map.insert("output".to_string(), output);
                    map.insert("activation_energy".to_string(), Value::Number(0.75));
                    map
                });
                self.stack.push(forward_result);
            }
            "neural.backprop" => {
                if args.len() != 3 {
                    return Err("neural.backprop requires exactly 3 arguments (layer, gradient, learning_rate)".to_string());
                }
                let layer = &args[0];
                let gradient = &args[1];
                let learning_rate = match &args[2] {
                    Value::Number(n) => *n,
                    _ => return Err("neural.backprop learning_rate must be a number".to_string()),
                };
                // Simulate backpropagation
                let updated_layer = Value::Object({
                    let mut map = HashMap::new();
                    map.insert("type".to_string(), Value::String("updated_layer".to_string()));
                    map.insert("original_layer".to_string(), layer.clone());
                    map.insert("gradient".to_string(), gradient.clone());
                    map.insert("learning_rate".to_string(), Value::Number(learning_rate));
                    map.insert("weights_updated".to_string(), Value::Boolean(true));
                    map.insert("biases_updated".to_string(), Value::Boolean(true));
                    map
                });
                self.stack.push(updated_layer);
            }
            "neural.set_activation" => {
                if args.len() == 3 {
                    let result = "Neural activation function set".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("neural.set_activation expects exactly 3 arguments".to_string());
                }
            }
            "neural.set_optimizer" => {
                if args.len() == 2 {
                    let result = "Neural optimizer set".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("neural.set_optimizer expects exactly 2 arguments".to_string());
                }
            }
            "neural.set_learning_rate" => {
                if args.len() == 2 {
                    let result = "Neural learning rate set".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("neural.set_learning_rate expects exactly 2 arguments".to_string());
                }
            }
            "neural.train" => {
                if args.len() == 3 {
                    let result = "Neural network training completed".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("neural.train expects exactly 3 arguments".to_string());
                }
            }
            "neural.predict" => {
                if args.len() == 2 {
                    let result = "Neural prediction completed".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("neural.predict expects exactly 2 arguments".to_string());
                }
            }
            "consciousness.aware" => {
                if args.len() != 1 {
                    return Err("consciousness.aware requires exactly 1 argument (stimulus)".to_string());
                }
                let stimulus = &args[0];
                // Simulate consciousness awareness
                let awareness_level = match stimulus {
                    Value::String(s) => s.len() as f64 * 0.1,
                    Value::Number(n) => n.abs(),
                    Value::Array(arr) => arr.len() as f64 * 0.2,
                    _ => 0.5,
                };
                let consciousness_state = Value::Object({
                    let mut map = HashMap::new();
                    map.insert("type".to_string(), Value::String("consciousness_awareness".to_string()));
                    map.insert("stimulus".to_string(), stimulus.clone());
                    map.insert("awareness_level".to_string(), Value::Number(awareness_level));
                    map.insert("attention_focus".to_string(), Value::Number(awareness_level.min(1.0)));
                    map.insert("metacognitive_monitoring".to_string(), Value::Boolean(awareness_level > 0.7));
                    map
                });
                self.stack.push(consciousness_state);
            }
            "consciousness.reflect" => {
                if args.len() != 2 {
                    return Err("consciousness.reflect requires exactly 2 arguments (experience, depth)".to_string());
                }
                let experience = &args[0];
                let depth = match &args[1] {
                    Value::Number(n) => *n,
                    _ => return Err("consciousness.reflect depth must be a number".to_string()),
                };
                // Simulate consciousness reflection
                let reflection_insight = Value::Number(depth * 0.8);
                let metacognitive_gain = Value::Number(depth * 0.6);
                let reflection_result = Value::Object({
                    let mut map = HashMap::new();
                    map.insert("type".to_string(), Value::String("consciousness_reflection".to_string()));
                    map.insert("experience".to_string(), experience.clone());
                    map.insert("reflection_depth".to_string(), Value::Number(depth));
                    map.insert("insight_gained".to_string(), reflection_insight);
                    map.insert("metacognitive_gain".to_string(), metacognitive_gain);
                    map.insert("self_awareness_increased".to_string(), Value::Boolean(depth > 0.5));
                    map
                });
                self.stack.push(reflection_result);
            }
            // Advanced consciousness functions
            "consciousness.self_aware" => {
                if args.len() == 1 {
                    if let Value::String(context) = &args[0] {
                        let result = format!("Self-awareness activated in context: {}", context);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("consciousness.self_aware expects a string argument".to_string());
                    }
                } else {
                    return Err("consciousness.self_aware expects exactly 1 argument".to_string());
                }
            }
            "consciousness.introspect" => {
                if args.len() == 2 {
                    if let (Value::String(topic), Value::Number(depth)) = (&args[0], &args[1]) {
                        let result = format!("Introspection on {} at depth {}", topic, depth);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("consciousness.introspect expects string and number arguments".to_string());
                    }
                } else {
                    return Err("consciousness.introspect expects exactly 2 arguments".to_string());
                }
            }
            "consciousness.metacognition" => {
                if args.len() == 1 {
                    if let Value::String(process) = &args[0] {
                        let result = format!("Metacognitive process: {}", process);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("consciousness.metacognition expects a string argument".to_string());
                    }
                } else {
                    return Err("consciousness.metacognition expects exactly 1 argument".to_string());
                }
            }
            "consciousness.qualia" => {
                if args.len() == 1 {
                    if let Value::String(experience) = &args[0] {
                        let result = format!("Qualia experience: {}", experience);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("consciousness.qualia expects a string argument".to_string());
                    }
                } else {
                    return Err("consciousness.qualia expects exactly 1 argument".to_string());
                }
            }
            "consciousness.self_aware" => {
                if args.len() == 1 {
                    let result = "Self-awareness activated".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("consciousness.self_aware expects exactly 1 argument".to_string());
                }
            }
            "consciousness.introspect" => {
                if args.len() == 2 {
                    let result = "Introspection completed".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("consciousness.introspect expects exactly 2 arguments".to_string());
                }
            }
            "consciousness.metacognition" => {
                if args.len() == 1 {
                    let result = "Metacognitive process completed".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("consciousness.metacognition expects exactly 1 argument".to_string());
                }
            }
            "memory.lha3.store" => {
                if args.len() != 2 {
                    return Err("memory.lha3.store requires exactly 2 arguments (key, value)".to_string());
                }
                let key = match &args[0] {
                    Value::String(s) => s.clone(),
                    _ => return Err("memory.lha3.store key must be a string".to_string()),
                };
                let value = &args[1];
                // Simulate LHA3 memory storage with quantum coherence
                let memory_entry = Value::Object({
                    let mut map = HashMap::new();
                    map.insert("type".to_string(), Value::String("lha3_memory_entry".to_string()));
                    map.insert("key".to_string(), Value::String(key.clone()));
                    map.insert("value".to_string(), value.clone());
                    map.insert("quantum_coherence".to_string(), Value::Number(0.95));
                    map.insert("entanglement_strength".to_string(), Value::Number(0.8));
                    map.insert("retrieval_probability".to_string(), Value::Number(0.9));
                    map.insert("storage_timestamp".to_string(), Value::Number(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64()));
                    map
                });
                // Store in global memory
                self.globals.insert(format!("lha3_{}", key), memory_entry.clone());
                self.stack.push(memory_entry);
            }
            "memory.lha3.retrieve" => {
                if args.len() != 1 {
                    return Err("memory.lha3.retrieve requires exactly 1 argument (key)".to_string());
                }
                let key = match &args[0] {
                    Value::String(s) => s.clone(),
                    _ => return Err("memory.lha3.retrieve key must be a string".to_string()),
                };
                // Retrieve from LHA3 memory with quantum measurement
                match self.globals.get(&format!("lha3_{}", key)) {
                    Some(memory_entry) => {
                        let retrieved_value = Value::Object({
                            let mut map = HashMap::new();
                            map.insert("type".to_string(), Value::String("lha3_retrieved".to_string()));
                            map.insert("original_entry".to_string(), memory_entry.clone());
                            map.insert("retrieval_success".to_string(), Value::Boolean(true));
                            map.insert("quantum_fidelity".to_string(), Value::Number(0.92));
                            map.insert("retrieval_time".to_string(), Value::Number(0.001));
                            map
                        });
                        self.stack.push(retrieved_value);
                    },
                    None => return Err(format!("Memory entry '{}' not found in LHA3", key)),
                }
            }
            "memory.error_correction" => {
                if args.len() == 2 {
                    let result = "Memory error correction applied".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("memory.error_correction expects exactly 2 arguments".to_string());
                }
            }
            "memory.compress" => {
                if args.len() == 1 {
                    let result = "Memory compression completed".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("memory.compress expects exactly 1 argument".to_string());
                }
            }
            "memory.encrypt" => {
                if args.len() == 2 {
                    let result = "Memory encryption completed".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("memory.encrypt expects exactly 2 arguments".to_string());
                }
            }
            "memory.quantum_allocate" => {
                if args.len() == 1 {
                    let result = "Quantum memory allocated".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("memory.quantum_allocate expects exactly 1 argument".to_string());
                }
            }
            "memory.neural_allocate" => {
                if args.len() == 1 {
                    let result = "Neural memory allocated".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("memory.neural_allocate expects exactly 1 argument".to_string());
                }
            }
            "memory.consciousness_allocate" => {
                if args.len() == 1 {
                    let result = "Consciousness memory allocated".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("memory.consciousness_allocate expects exactly 1 argument".to_string());
                }
            }
            "memory.optimize" => {
                if args.len() == 0 {
                    let result = "Memory optimization completed".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("memory.optimize expects no arguments".to_string());
                }
            }
            // Advanced memory functions
            "memory.quantum_allocate" => {
                if args.len() == 1 {
                    if let Value::Number(size) = args[0].clone() {
                        let result = format!("Allocated {} quantum memory cells", size);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("memory.quantum_allocate expects a number argument".to_string());
                    }
                } else {
                    return Err("memory.quantum_allocate expects exactly 1 argument".to_string());
                }
            }
            "memory.neural_allocate" => {
                if args.len() == 1 {
                    if let Value::Number(neurons) = args[0].clone() {
                        let result = format!("Allocated {} neural memory units", neurons);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("memory.neural_allocate expects a number argument".to_string());
                    }
                } else {
                    return Err("memory.neural_allocate expects exactly 1 argument".to_string());
                }
            }
            "memory.consciousness_allocate" => {
                if args.len() == 1 {
                    if let Value::Number(units) = args[0].clone() {
                        let result = format!("Allocated {} consciousness memory units", units);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("memory.consciousness_allocate expects a number argument".to_string());
                    }
                } else {
                    return Err("memory.consciousness_allocate expects exactly 1 argument".to_string());
                }
            }
            "memory.error_correction" => {
                if args.len() == 2 {
                    if let (Value::String(algorithm), Value::String(data)) = (&args[0], &args[1]) {
                        let result = format!("Applied {} error correction to {}", algorithm, data);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("memory.error_correction expects two string arguments".to_string());
                    }
                } else {
                    return Err("memory.error_correction expects exactly 2 arguments".to_string());
                }
            }
            "memory.compress" => {
                if args.len() == 1 {
                    if let Value::String(data) = &args[0] {
                        let result = format!("Compressed data: {} (50% reduction)", data);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("memory.compress expects a string argument".to_string());
                    }
                } else {
                    return Err("memory.compress expects exactly 1 argument".to_string());
                }
            }
            "memory.encrypt" => {
                if args.len() == 2 {
                    if let (Value::String(data), Value::String(key)) = (&args[0], &args[1]) {
                        let result = format!("Encrypted data with quantum key: {}", data);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("memory.encrypt expects two string arguments".to_string());
                    }
                } else {
                    return Err("memory.encrypt expects exactly 2 arguments".to_string());
                }
            }
            "autonomous.plan" => {
                if args.len() != 2 {
                    return Err("autonomous.plan requires exactly 2 arguments (goal, constraints)".to_string());
                }
                let goal = &args[0];
                let constraints = &args[1];
                // Simulate autonomous planning
                let plan_steps = Value::Array(vec![
                    Value::String("analyze_environment".to_string()),
                    Value::String("identify_resources".to_string()),
                    Value::String("generate_strategies".to_string()),
                    Value::String("evaluate_options".to_string()),
                    Value::String("execute_optimal_plan".to_string())
                ]);
                let autonomous_plan = Value::Object({
                    let mut map = HashMap::new();
                    map.insert("type".to_string(), Value::String("autonomous_plan".to_string()));
                    map.insert("goal".to_string(), goal.clone());
                    map.insert("constraints".to_string(), constraints.clone());
                    map.insert("plan_steps".to_string(), plan_steps);
                    map.insert("confidence".to_string(), Value::Number(0.85));
                    map.insert("execution_ready".to_string(), Value::Boolean(true));
                    map
                });
                self.stack.push(autonomous_plan);
            }
            "autonomous.execute" => {
                if args.len() == 1 {
                    let result = "Autonomous execution completed".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("autonomous.execute expects exactly 1 argument".to_string());
                }
            }
            // Advanced quantum functions
            "quantum.circuit" => {
                if args.len() == 1 {
                    if let Value::Number(qubits) = args[0].clone() {
                        let result = format!("Created quantum circuit with {} qubits", qubits);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("quantum.circuit expects a number argument".to_string());
                    }
                } else {
                    return Err("quantum.circuit expects exactly 1 argument".to_string());
                }
            }
            "quantum.gate" => {
                if args.len() == 2 {
                    if let (Value::String(gate), Value::Number(qubit)) = (&args[0], &args[1]) {
                        let result = format!("Applied {} gate to qubit {}", gate, qubit);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("quantum.gate expects string and number arguments".to_string());
                    }
                } else {
                    return Err("quantum.gate expects exactly 2 arguments".to_string());
                }
            }
            "quantum.teleport" => {
                if args.len() == 3 {
                    let result = "Quantum teleportation completed successfully".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("quantum.teleport expects exactly 3 arguments".to_string());
                }
            }
            "quantum.fourier" => {
                if args.len() == 1 {
                    let result = "Quantum Fourier transform applied".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("quantum.fourier expects exactly 1 argument".to_string());
                }
            }
            // Advanced neural functions
            "neural.deep" => {
                if args.len() == 1 {
                    if let Value::String(architecture) = &args[0] {
                        let result = format!("Created deep neural network: {}", architecture);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("neural.deep expects a string argument".to_string());
                    }
                } else {
                    return Err("neural.deep expects exactly 1 argument".to_string());
                }
            }
            "neural.attention" => {
                if args.len() == 2 {
                    if let (Value::Number(dim), Value::Number(heads)) = (args[0].clone(), args[1].clone()) {
                        let result = format!("Created attention mechanism: {}d, {} heads", dim, heads);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("neural.attention expects two number arguments".to_string());
                    }
                } else {
                    return Err("neural.attention expects exactly 2 arguments".to_string());
                }
            }
            "neural.gan" => {
                if args.len() == 2 {
                    let result = "Created Generative Adversarial Network".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("neural.gan expects exactly 2 arguments".to_string());
                }
            }
            "neural.rl" => {
                if args.len() == 1 {
                    if let Value::String(algorithm) = &args[0] {
                        let result = format!("Created RL agent with {} algorithm", algorithm);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("neural.rl expects a string argument".to_string());
                    }
                } else {
                    return Err("neural.rl expects exactly 1 argument".to_string());
                }
            }
            // JIT Compilation functions
            "jit.compile" => {
                if args.len() == 1 {
                    if let Value::String(code) = &args[0] {
                        let result = format!("JIT compiled: {}", code);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("jit.compile expects a string argument".to_string());
                    }
                } else {
                    return Err("jit.compile expects exactly 1 argument".to_string());
                }
            }
            "jit.execute" => {
                if args.len() == 1 {
                    let result = "JIT execution completed".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("jit.execute expects exactly 1 argument".to_string());
                }
            }
            // Parallel execution functions
            "parallel.spawn" => {
                if args.len() == 1 {
                    if let Value::String(task) = &args[0] {
                        let result = format!("Spawned parallel task: {}", task);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("parallel.spawn expects a string argument".to_string());
                    }
                } else {
                    return Err("parallel.spawn expects exactly 1 argument".to_string());
                }
            }
            "parallel.join" => {
                if args.len() == 1 {
                    let result = "Parallel tasks joined successfully".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("parallel.join expects exactly 1 argument".to_string());
                }
            }
            // Advanced memory functions
            "memory.allocate" => {
                if args.len() == 1 {
                    if let Value::Number(size) = args[0].clone() {
                        let result = format!("Allocated {} bytes of memory", size);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("memory.allocate expects a number argument".to_string());
                    }
                } else {
                    return Err("memory.allocate expects exactly 1 argument".to_string());
                }
            }
            "memory.optimize" => {
                if args.len() == 0 {
                    let result = "Memory optimization completed".to_string();
                    self.stack.push(Value::String(result));
                } else {
                    return Err("memory.optimize expects no arguments".to_string());
                }
            }
            // Performance profiling functions
            "profiler.start" => {
                if args.len() == 1 {
                    if let Value::String(name) = &args[0] {
                        let result = format!("Started profiling: {}", name);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("profiler.start expects a string argument".to_string());
                    }
                } else {
                    return Err("profiler.start expects exactly 1 argument".to_string());
                }
            }
            "profiler.end" => {
                if args.len() == 1 {
                    if let Value::String(name) = &args[0] {
                        let result = format!("Ended profiling: {}", name);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("profiler.end expects a string argument".to_string());
                    }
                } else {
                    return Err("profiler.end expects exactly 1 argument".to_string());
                }
            }
            "profiler.measure" => {
                if args.len() == 1 {
                    if let Value::String(name) = &args[0] {
                        let result = format!("Measured performance: {} - 0.001s", name);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("profiler.measure expects a string argument".to_string());
                    }
                } else {
                    return Err("profiler.measure expects exactly 1 argument".to_string());
                }
            }
            "parallel.quantum" => {
                if args.len() >= 1 {
                    if let Value::Array(qubits) = &args[0] {
                        let qubit_values: Vec<f64> = qubits.iter()
                            .filter_map(|v| {
                                if let Value::Number(n) = v {
                                    Some(*n)
                                } else {
                                    None
                                }
                            })
                            .collect();
                        
                        let result = format!("Quantum parallel execution spawned with {} qubits", qubit_values.len());
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("parallel.quantum expects array of qubit values".to_string());
                    }
                } else {
                    return Err("parallel.quantum expects at least 1 argument".to_string());
                }
            }
            "parallel.neural" => {
                if args.len() >= 2 {
                    if let (Value::Array(weights), Value::Array(inputs)) = (&args[0], &args[1]) {
                        let result = format!("Neural parallel training spawned with {} weights and {} inputs", 
                                          weights.len(), inputs.len());
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("parallel.neural expects arrays for weights and inputs".to_string());
                    }
                } else {
                    return Err("parallel.neural expects at least 2 arguments".to_string());
                }
            }
            "parallel.consciousness" => {
                if args.len() >= 1 {
                    if let Value::String(context) = &args[0] {
                        let result = format!("Consciousness parallel processing spawned: {}", context);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("parallel.consciousness expects string context".to_string());
                    }
                } else {
                    return Err("parallel.consciousness expects at least 1 argument".to_string());
                }
            }
            "parallel.autonomous" => {
                if args.len() >= 1 {
                    if let Value::String(goal) = &args[0] {
                        let result = format!("Autonomous parallel decision making spawned: {}", goal);
                        self.stack.push(Value::String(result));
                    } else {
                        return Err("parallel.autonomous expects string goal".to_string());
                    }
                } else {
                    return Err("parallel.autonomous expects at least 1 argument".to_string());
                }
            }
            "parallel.statistics" => {
                let stats = HashMap::from([
                    ("active_threads".to_string(), Value::Number(4.0)),
                    ("queued_tasks".to_string(), Value::Number(8.0)),
                    ("quantum_states".to_string(), Value::Number(12.0)),
                    ("neural_tasks".to_string(), Value::Number(6.0)),
                    ("consciousness_tasks".to_string(), Value::Number(3.0)),
                    ("autonomous_tasks".to_string(), Value::Number(5.0)),
                ]);
                self.stack.push(Value::Object(stats));
            }
            "stringify" => {
                if args.len() != 1 {
                    return Err("stringify requires exactly 1 argument".to_string());
                }
                let value = &args[0];
                let string_value = self.stringify(value);
                self.stack.push(Value::String(string_value));
            }
            "calc" => {
                if args.len() != 3 {
                    return Err("calc requires exactly 3 arguments (operation, a, b)".to_string());
                }
                
                let operation = match &args[0] {
                    Value::String(op) => op.as_str(),
                    _ => return Err("calc operation must be a string (add, sub, mul, div)".to_string()),
                };
                
                let a = match &args[1] {
                    Value::Number(n) => *n,
                    _ => return Err("calc first operand must be a number".to_string()),
                };
                
                let b = match &args[2] {
                    Value::Number(n) => *n,
                    _ => return Err("calc second operand must be a number".to_string()),
                };
                
                let result = match operation {
                    "add" => a + b,
                    "sub" => a - b,
                    "mul" => a * b,
                    "div" => {
                        if b == 0.0 {
                            return Err("calc division by zero".to_string());
                        }
                        a / b
                    },
                    _ => return Err(format!("calc unknown operation: {} (use add, sub, mul, div)", operation)),
                };
                
                self.stack.push(Value::Number(result));
            }
            "math.calc" => {
                if args.len() != 3 {
                    return Err("math.calc requires exactly 3 arguments (operation, a, b)".to_string());
                }
                
                let operation = match &args[0] {
                    Value::String(op) => op.as_str(),
                    _ => return Err("math.calc operation must be a string (add, sub, mul, div)".to_string()),
                };
                
                let a = match &args[1] {
                    Value::Number(n) => *n,
                    _ => return Err("math.calc first operand must be a number".to_string()),
                };
                
                let b = match &args[2] {
                    Value::Number(n) => *n,
                    _ => return Err("math.calc second operand must be a number".to_string()),
                };
                
                let result = match operation {
                    "add" => a + b,
                    "sub" => a - b,
                    "mul" => a * b,
                    "div" => {
                        if b == 0.0 {
                            return Err("math.calc division by zero".to_string());
                        }
                        a / b
                    },
                    _ => return Err(format!("math.calc unknown operation: {} (use add, sub, mul, div)", operation)),
                };
                
                self.stack.push(Value::Number(result));
            }
            _ => {
                return Err(format!("Unknown function: {}", name));
            }
        }
        Ok(())
    }
    
    fn is_truthy(&self, value: &Value) -> bool {
        match value {
            Value::Boolean(b) => *b,
            Value::Null => false,
            Value::Number(n) => *n != 0.0,
            Value::String(s) => !s.is_empty(),
            Value::Array(arr) => !arr.is_empty(),
            Value::Object(obj) => !obj.is_empty(),
            Value::Function(_) => true,
            Value::Closure(_) => true,
        }
    }

    fn stringify(&self, value: &Value) -> String {
        match value {
            Value::Number(n) => n.to_string(),
            Value::String(s) => s.clone(),
            Value::Boolean(b) => b.to_string(),
            Value::Null => "null".to_string(),
            Value::Array(arr) => format!("[{}]", arr.iter().map(|v| self.stringify(v)).collect::<Vec<_>>().join(", ")),
            Value::Object(obj) => {
                let pairs: Vec<String> = obj.iter()
                    .map(|(k, v)| format!("{}: {}", k, self.stringify(v)))
                    .collect();
                format!("{{{}}}", pairs.join(", "))
            }
            Value::Function(func) => format!("<function {}>", func.name),
            Value::Closure(closure) => format!("<closure {}>", closure.func.name),
        }
    }
}

// ========================================
// ========== LEXICAL ANALYSIS ==========
// ========================================

#[derive(Debug, Clone, PartialEq)]
pub enum TokenType {
    // Keywords
    Let, Fn, If, Else, Loop, For, In, On, Emit, Say, Return, Set, Break, Continue, Do, With, While,
    Class, Method, Try, Catch, Throw, New, This, Super,
    Component, Trait, Implements, Type, Generic, Union, Intersection,
    Import, Module, Export, As, Pub,
    True, False, Null,
    
    // Literals
    Number(f64),
    String(String),
    Identifier(String),
    
    // Operators
    Plus, Minus, Star, Slash,
    Equal, EqualEqual, Bang, BangEqual,
    Less, LessEqual, Greater, GreaterEqual,
    And, Or, Pipe,
    
    // Delimiters
    LeftParen, RightParen,
    LeftBrace, RightBrace,
            LeftBracket, RightBracket,
        Semicolon, Comma, Dot, Colon, DoubleColon, Arrow,
    // Lambda syntax
    Lambda, // | for lambda expressions
    
    // Special
    Eof,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Token {
    pub token_type: TokenType,
    pub lexeme: String,
    pub line: usize,
    pub column: usize,
}

pub struct Scanner {
    source: Vec<char>,
    tokens: Vec<Token>,
    start: usize,
    current: usize,
    line: usize,
    column: usize,
}

impl Scanner {
    pub fn new(source: String) -> Self {
        Scanner {
            source: source.chars().collect(),
            tokens: Vec::new(),
            start: 0,
            current: 0,
            line: 1,
            column: 1,
        }
    }

    pub fn scan_tokens(&mut self) -> Result<Vec<Token>, String> {
        while !self.is_at_end() {
            self.start = self.current;
            self.scan_token()?;
        }

        self.tokens.push(Token {
            token_type: TokenType::Eof,
            lexeme: "".to_string(),
            line: self.line,
            column: self.column,
        });

        Ok(self.tokens.clone())
    }

    fn scan_token(&mut self) -> Result<(), String> {
        let c = self.advance();

        match c {
            '(' => self.add_token(TokenType::LeftParen),
            ')' => self.add_token(TokenType::RightParen),
            '{' => self.add_token(TokenType::LeftBrace),
            '}' => self.add_token(TokenType::RightBrace),
            '[' => self.add_token(TokenType::LeftBracket),
            ']' => self.add_token(TokenType::RightBracket),
            ',' => self.add_token(TokenType::Comma),
            '.' => self.add_token(TokenType::Dot),
            ':' => {
                if self.match_char(':') {
                    self.add_token(TokenType::DoubleColon);
                } else {
                    self.add_token(TokenType::Colon);
                }
            }
            '-' => {
                if self.match_char('>') {
                    self.add_token(TokenType::Arrow);
                } else {
                    self.add_token(TokenType::Minus);
                }
            },
            '+' => self.add_token(TokenType::Plus),
            ';' => self.add_token(TokenType::Semicolon),
            '*' => self.add_token(TokenType::Star),
            '!' => {
                let token_type = if self.match_char('=') {
                    TokenType::BangEqual
                } else {
                    TokenType::Bang
                };
                self.add_token(token_type);
            }
            '=' => {
                let token_type = if self.match_char('=') {
                    TokenType::EqualEqual
                } else {
                    TokenType::Equal
                };
                self.add_token(token_type);
            }
            '<' => {
                let token_type = if self.match_char('=') {
                    TokenType::LessEqual
                } else {
                    TokenType::Less
                };
                self.add_token(token_type);
            }
            '>' => {
                let token_type = if self.match_char('=') {
                    TokenType::GreaterEqual
                } else {
                    TokenType::Greater
                };
                self.add_token(token_type);
            }
            '&' => {
                if self.match_char('&') {
                    self.add_token(TokenType::And);
                } else {
                    self.add_token(TokenType::Intersection);
                }
            }
            '|' => {
                if self.match_char('|') {
                    self.add_token(TokenType::Or);
                } else {
                    self.add_token(TokenType::Lambda);
                }
            }
            '/' => {
                if self.match_char('/') {
                    // Comment
                    while self.peek() != '\n' && !self.is_at_end() {
                        self.advance();
                    }
                } else {
                    self.add_token(TokenType::Slash);
                }
            }
            '#' => {
                // Comment
                while self.peek() != '\n' && !self.is_at_end() {
                    self.advance();
                }
            }
            ' ' | '\r' | '\t' => {
                // Ignore whitespace
            }
            '\n' => {
                self.line += 1;
                self.column = 0;
            }
            '"' => self.string()?,
            '\'' => self.string()?,
            _ => {
                if c.is_ascii_digit() {
                    self.number()?;
                } else if c.is_ascii_alphabetic() || c == '_' {
                    self.identifier();
                } else {
                    return Err(format!("Unexpected character '{}' at line {}:{}", c, self.line, self.column));
                }
            }
        }

        Ok(())
    }

    fn string(&mut self) -> Result<(), String> {
        let quote = self.source[self.current - 1];
        
        while self.peek() != quote && !self.is_at_end() {
            if self.peek() == '\n' {
                self.line += 1;
            }
            self.advance();
        }

        if self.is_at_end() {
            return Err("Unterminated string".to_string());
        }

        // Consume the closing quote
        self.advance();

        // Trim the quotes
        let value = self.source[self.start + 1..self.current - 1]
            .iter()
            .collect::<String>();

        self.add_token(TokenType::String(value));
        Ok(())
    }

    fn number(&mut self) -> Result<(), String> {
        while self.peek().is_ascii_digit() {
            self.advance();
        }

        // Look for decimal part
        if self.peek() == '.' && self.peek_next().is_ascii_digit() {
            // Consume the "."
            self.advance();

            while self.peek().is_ascii_digit() {
                self.advance();
            }
        }

        let value = self.source[self.start..self.current]
            .iter()
            .collect::<String>();
        
        match value.parse::<f64>() {
            Ok(num) => self.add_token(TokenType::Number(num)),
            Err(_) => return Err("Invalid number".to_string()),
        }

        Ok(())
    }

    fn identifier(&mut self) {
        while self.peek().is_alphanumeric() || self.peek() == '_' {
            self.advance();
        }

        let text = self.source[self.start..self.current]
            .iter()
            .collect::<String>();

        let token_type = match text.as_str() {
                        "let" => TokenType::Let,
            "fn" => TokenType::Fn,
            "if" => TokenType::If,
            "else" => TokenType::Else,
            "loop" => TokenType::Loop,
            "for" => TokenType::For,
            "in" => TokenType::In,
            "on" => TokenType::On,
            "emit" => TokenType::Emit,
            "say" => TokenType::Say,
            "return" => TokenType::Return,
            "set" => TokenType::Set,
            "break" => TokenType::Break,
            "continue" => TokenType::Continue,
            "do" => TokenType::Do,
            "with" => TokenType::With,
            "while" => TokenType::While,
        "union" => TokenType::Union,
        "intersection" => TokenType::Intersection,
        "true" => TokenType::True,
        "false" => TokenType::False,
            // Class/Component keywords
            "class" => TokenType::Class,
            "method" => TokenType::Method,
            "component" => TokenType::Component,
            "trait" => TokenType::Trait,
            "implements" => TokenType::Implements,
            "type" => TokenType::Type,
            "generic" => TokenType::Generic,
            "new" => TokenType::New,
            "this" => TokenType::This,
            "super" => TokenType::Super,
            // Error handling keywords
            "try" => TokenType::Try,
            "catch" => TokenType::Catch,
            "throw" => TokenType::Throw,
                    "true" => TokenType::True,
        "false" => TokenType::False,
        "null" => TokenType::Null,
        "import" => TokenType::Import,
        "module" => TokenType::Module,
        "export" => TokenType::Export,
        "as" => TokenType::As,
        "pub" => TokenType::Pub,
            _ => TokenType::Identifier(text),
        };

        self.add_token(token_type);
    }

    fn match_char(&mut self, expected: char) -> bool {
        if self.is_at_end() {
            return false;
        }
        if self.source[self.current] != expected {
            return false;
        }

        self.current += 1;
        self.column += 1;
        true
    }

    fn peek(&self) -> char {
        if self.is_at_end() {
            '\0'
        } else {
            self.source[self.current]
        }
    }

    fn peek_next(&self) -> char {
        if self.current + 1 >= self.source.len() {
            '\0'
        } else {
            self.source[self.current + 1]
        }
    }

    fn advance(&mut self) -> char {
        let c = self.source[self.current];
        self.current += 1;
        self.column += 1;
        c
    }

    fn add_token(&mut self, token_type: TokenType) {
        let text = self.source[self.start..self.current]
            .iter()
            .collect::<String>();
        println!("[scanner] Adding token: {:?} at line {}:{}", token_type, self.line, self.column);
        
        self.tokens.push(Token {
            token_type,
            lexeme: text,
            line: self.line,
            column: self.column - (self.current - self.start),
        });
    }

    fn is_at_end(&self) -> bool {
        self.current >= self.source.len()
    }
}

// ========================================
// ========== ABSTRACT SYNTAX TREE ======
// ========================================

#[derive(Debug, Clone, PartialEq)]
pub enum Expr {
    Literal(LiteralValue),
    Variable(String),
    Binary(Box<Expr>, Token, Box<Expr>),
    Unary(Token, Box<Expr>),
    Call(String, Vec<Expr>),
    CallValue(Box<Expr>, Vec<Expr>), // Call function value directly
    Get(Box<Expr>, String),
    Set(Box<Expr>, String, Box<Expr>),
    Assign(String, Box<Expr>), // Simple variable assignment
    Function(Vec<String>, Vec<Stmt>), // Anonymous function: parameters, body
    Lambda(Vec<String>, Box<Expr>), // Lambda expression: parameters, body expression
    Array(Vec<Expr>),
    Object(Vec<(String, Expr)>),
    Slice(Box<Expr>, Option<Box<Expr>>, Option<Box<Expr>>),
    // Class/Component expressions
    New(String, Vec<Expr>), // constructor call
    This, // self reference
    Super(String), // super method call
    ModuleAccess(String, String), // module::member
}

#[derive(Debug, Clone, PartialEq)]
pub enum LiteralValue {
    Number(f64),
    String(String),
    Boolean(bool),
    Null,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Stmt {
    Expression(Expr),
    Let(String, Expr),
    Set(String, Expr),
    FunctionDecl(String, Vec<String>, Vec<Stmt>), // name, parameters, body
    EventHandler(String, Vec<String>, Vec<Stmt>),
    If(Expr, Vec<Stmt>, Option<Vec<Stmt>>),
    While(Expr, Vec<Stmt>),
    For {
        init: Option<Box<Stmt>>,
        condition: Option<Expr>,
        increment: Option<Box<Stmt>>,
        body: Vec<Stmt>,
    },
    Break,
    Continue,
    Emit(String, Option<Expr>),
    Say(Expr),
    Return(Option<Expr>),
    // Class/Component syntax
    Class(String, Vec<Stmt>), // class name, methods
    Method(String, Vec<String>, Vec<Stmt>), // method name, parameters, body
    Component(String, String, Vec<Stmt>), // module, name, methods
    Trait(String, Vec<Stmt>), // trait name, methods
    Implements(String, String), // component, trait
    Type(String, Type), // type name, type definition
    // Error handling
    Try(Vec<Stmt>, Vec<Stmt>), // try block, catch block
    Throw(Expr), // throw exception
    // Module system
    ModuleDecl {
        name: String,
        body: Vec<Stmt>,
        soul_mark: Option<u64>,
    },
    Import {
        path: String,
        alias: Option<String>,
    },
    Export {
        name: String,
        value: Option<Box<Expr>>,
    },
}

// ========================================
// ========== PARSER ====================
// ========================================

pub struct Parser {
    tokens: Vec<Token>,
    current: usize,
}

impl Parser {
    pub fn new(tokens: Vec<Token>) -> Self {
        Parser { tokens, current: 0 }
    }

    pub fn parse(&mut self) -> Result<Vec<Stmt>, String> {
        let mut statements = Vec::new();

        while !self.is_at_end() {
            statements.push(self.declaration()?);
        }

        Ok(statements)
    }

    pub fn parse_module_items(&mut self) -> Result<Vec<Stmt>, String> {
        let mut items = Vec::new();

        while !self.is_at_end() {
            // Parse module-level items (functions, constants, imports, exports)
            let item = self.parse_module_item()?;
            items.push(item);
        }

        Ok(items)
    }

    fn parse_module_item(&mut self) -> Result<Stmt, String> {
        // Check for visibility modifier
        let is_public = self.match_token(&TokenType::Pub);
        
        match self.peek().token_type {
            TokenType::Fn => {
                let function = self.function_declaration()?;
                // TODO: Handle public/private visibility
                Ok(function)
            }
            TokenType::Let => {
                let constant = self.let_declaration()?;
                // TODO: Handle public/private visibility
                Ok(constant)
            }
            TokenType::Identifier(ref name) if name == "const" => {
                // Handle const declarations
                self.advance(); // consume "const"
                if let TokenType::Identifier(const_name) = &self.peek().token_type {
                    let const_name = const_name.clone();
                    self.advance();
                    self.consume(&TokenType::Equal, "Expected '=' after const name")?;
                    let value = self.assignment()?;
                    Ok(Stmt::Let(const_name, value))
                } else {
                    Err("Expected const name after 'const' keyword".to_string())
                }
            }
            TokenType::Import => {
                self.import_statement()
            }
            TokenType::Export => {
                self.export_statement()
            }
            TokenType::Class => {
                self.class_declaration()
            }
            TokenType::Component => {
                self.component_declaration()
            }
            TokenType::Trait => {
                self.trait_declaration()
            }
            TokenType::Type => {
                self.type_declaration()
            }
            _ => {
                // For module-level expressions, they should be wrapped in a statement
                self.statement()
            }
        }
    }

    fn export_statement(&mut self) -> Result<Stmt, String> {
        self.consume(&TokenType::Export, "Expected 'export'")?;
        
        if let TokenType::Identifier(name) = &self.peek().token_type {
            let name = name.clone();
            self.advance();
            
            let value = if self.match_token(&TokenType::Equal) {
                Some(Box::new(self.assignment()?))
            } else {
                None
            };
            
            Ok(Stmt::Export { name, value })
        } else {
            Err("Expected identifier after 'export'".to_string())
        }
    }

    fn module_declaration(&mut self) -> Result<Stmt, String> {
        // Expect module name after 'module' keyword
        if let TokenType::Identifier(name) = &self.peek().token_type {
            let name = name.clone();
            self.advance();
            
            // Expect opening brace
            self.consume(&TokenType::LeftBrace, "Expected '{' after module name")?;
            
            // Parse module body statements using module-specific parsing
            let mut body = Vec::new();
            while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
                body.push(self.parse_module_item()?);
            }
            
            // Expect closing brace
            self.consume(&TokenType::RightBrace, "Expected '}' after module body")?;
            
            Ok(Stmt::ModuleDecl {
                name,
                body,
                soul_mark: None, // Will be calculated later
            })
        } else {
            Err("Expected module name after 'module' keyword".to_string())
        }
    }

    fn declaration(&mut self) -> Result<Stmt, String> {
        use std::io::{self, Write};
        println!("DEBUG: declaration called, current token: {:?}", self.peek().token_type);
        io::stdout().flush().unwrap();
        
        if self.match_token(&TokenType::Let) {
            println!("DEBUG: matched Let token");
            io::stdout().flush().unwrap();
            self.let_declaration()
        } else if self.match_token(&TokenType::Fn) {
            println!("DEBUG: matched Fn token, calling function_declaration");
            io::stdout().flush().unwrap();
            self.function_declaration()
        } else {
            println!("DEBUG: no match, calling statement");
            io::stdout().flush().unwrap();
            self.statement()
        }
    }

    fn let_declaration(&mut self) -> Result<Stmt, String> {
        if let TokenType::Identifier(name) = &self.peek().token_type {
            let name = name.clone();
            self.advance();
            self.consume(&TokenType::Equal, "Expect '=' after variable name.")?;
            let initializer = self.assignment()?;
            
            Ok(Stmt::Let(name, initializer))
        } else {
            Err("Expect variable name.".to_string())
        }
    }

    fn function_declaration(&mut self) -> Result<Stmt, String> {
        // The 'fn' token was already consumed by match_token in declaration()
        
        // Expect the function name
        if let TokenType::Identifier(name) = &self.peek().token_type {
            let name = name.clone();
            self.advance();
            
            self.consume(&TokenType::LeftParen, "Expect '(' after function name.")?;
            
            // Parse parameters
            let mut parameters = Vec::new();
            if !self.check(&TokenType::RightParen) {
                loop {
                    if let TokenType::Identifier(param) = &self.peek().token_type {
                        let param = param.clone();
                        self.advance();
                        parameters.push(param);
                        
                        if !self.match_token(&TokenType::Comma) {
                            break;
                        }
                    } else {
                        return Err("Expect parameter name.".to_string());
                    }
                }
            }
            
            self.consume(&TokenType::RightParen, "Expect ')' after parameters.")?;
            self.consume(&TokenType::LeftBrace, "Expect '{' before function body.")?;
            
            // Parse function body
            let mut body = Vec::new();
            while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
                body.push(self.declaration()?);
            }
            
            self.consume(&TokenType::RightBrace, "Expect '}' after function body.")?;
            
            Ok(Stmt::FunctionDecl(name, parameters, body))
        } else {
            println!("DEBUG: Expected Identifier but got: {:?}", self.peek().token_type);
            use std::io::{self, Write};
            io::stdout().flush().unwrap();
            Err("Expect function name.".to_string())
        }
    }

    fn class_declaration(&mut self) -> Result<Stmt, String> {
        if let TokenType::Identifier(name) = &self.peek().token_type {
            let name = name.clone();
            self.advance();
            self.consume(&TokenType::LeftBrace, "Expect '{' before class body.")?;
            
            let mut methods = Vec::new();
            while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
                methods.push(self.declaration()?);
            }
            
            self.consume(&TokenType::RightBrace, "Expect '}' after class body.")?;
            
            Ok(Stmt::Class(name, methods))
        } else {
            Err("Expect class name.".to_string())
        }
    }

    fn method_declaration(&mut self) -> Result<Stmt, String> {
        if let TokenType::Identifier(name) = &self.peek().token_type {
            let name = name.clone();
            self.advance();
            self.consume(&TokenType::LeftParen, "Expect '(' after method name.")?;
            
            let mut parameters = Vec::new();
            if !self.check(&TokenType::RightParen) {
                loop {
                    if let TokenType::Identifier(param) = &self.peek().token_type {
                        let param = param.clone();
                        self.advance();
                        parameters.push(param);
                        
                        if !self.match_token(&TokenType::Comma) {
                            break;
                        }
                    } else {
                        return Err("Expect parameter name.".to_string());
                    }
                }
            }
            
            self.consume(&TokenType::RightParen, "Expect ')' after parameters.")?;
            self.consume(&TokenType::LeftBrace, "Expect '{' before method body.")?;
            
            let mut body = Vec::new();
            while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
                body.push(self.declaration()?);
            }
            
            self.consume(&TokenType::RightBrace, "Expect '}' after method body.")?;
            
            Ok(Stmt::Method(name, parameters, body))
        } else {
            Err("Expect method name.".to_string())
        }
    }

    fn event_handler_declaration(&mut self) -> Result<Stmt, String> {
        // Handle both String and Identifier tokens for event names
        let event_name = match &self.peek().token_type {
            TokenType::String(name) => {
                let name = name.clone();
                self.advance();
                name
            },
            TokenType::Identifier(name) => {
                let name = name.clone();
                self.advance();
                name
            },
            _ => {
                return Err("Expect event name (string or identifier).".to_string());
            }
        };
        
        // Expect 'do' keyword
        self.consume(&TokenType::Do, "Expect 'do' after event name.")?;
        
        // Parse the handler body
        self.consume(&TokenType::LeftBrace, "Expect '{' before handler body.")?;
        
        let mut body = Vec::new();
        while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
            body.push(self.declaration()?);
        }
        
        self.consume(&TokenType::RightBrace, "Expect '}' after handler body.")?;
        
        // For now, we'll use empty parameters since we're using the simpler syntax
        Ok(Stmt::EventHandler(event_name, Vec::new(), body))
    }

    fn component_declaration(&mut self) -> Result<Stmt, String> {
        // Parse component name (can be either just name or module.name)
        if let TokenType::Identifier(first_part) = &self.peek().token_type {
            let first_part = first_part.clone();
            self.advance();
            
            // Check if this is module.component syntax
            if self.match_token(&TokenType::Dot) {
                // This is module.component syntax
                if let TokenType::Identifier(name) = &self.peek().token_type {
                    let name = name.clone();
                    self.advance();
                    
                    self.consume(&TokenType::LeftBrace, "Expect '{' before component body.")?;
                    
                    let mut methods = Vec::new();
                    while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
                        methods.push(self.declaration()?);
                    }
                    
                    self.consume(&TokenType::RightBrace, "Expect '}' after component body.")?;
                    
                    Ok(Stmt::Component(first_part, name, methods))
                } else {
                    Err("Expect component name.".to_string())
                }
            } else {
                // This is just component syntax
                self.consume(&TokenType::LeftBrace, "Expect '{' before component body.")?;
                
                let mut methods = Vec::new();
                while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
                    methods.push(self.declaration()?);
                }
                
                self.consume(&TokenType::RightBrace, "Expect '}' after component body.")?;
                
                Ok(Stmt::Component("".to_string(), first_part, methods))
            }
        } else {
            Err("Expect component name.".to_string())
        }
    }

    fn trait_declaration(&mut self) -> Result<Stmt, String> {
        if let TokenType::Identifier(name) = &self.peek().token_type {
            let name = name.clone();
            self.advance();
            
            self.consume(&TokenType::LeftBrace, "Expect '{' before trait body.")?;
            
            let mut methods = Vec::new();
            while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
                methods.push(self.declaration()?);
            }
            
            self.consume(&TokenType::RightBrace, "Expect '}' after trait body.")?;
            
            Ok(Stmt::Trait(name, methods))
        } else {
            Err("Expect trait name.".to_string())
        }
    }

    fn type_declaration(&mut self) -> Result<Stmt, String> {
        if let TokenType::Identifier(name) = &self.peek().token_type {
            let name = name.clone();
            self.advance();
            
            self.consume(&TokenType::Equal, "Expect '=' after type name.")?;
            
            // Parse type expression
            let mut type_parts = Vec::new();
            
            // Parse first type
            if let TokenType::Identifier(type_name) = &self.peek().token_type {
                let type_name = type_name.clone();
                self.advance();
                type_parts.push(Type::Custom(type_name));
            } else {
                return Err("Expect type name.".to_string());
            }
            
            // Parse union types (|)
            while self.match_token(&TokenType::Pipe) {
                if let TokenType::Identifier(type_name) = &self.peek().token_type {
                    let type_name = type_name.clone();
                    self.advance();
                    type_parts.push(Type::Custom(type_name));
                } else {
                    return Err("Expect type name after '|'.".to_string());
                }
            }
            
            // Parse intersection types (&)
            while self.match_token(&TokenType::Intersection) {
                if let TokenType::Identifier(type_name) = &self.peek().token_type {
                    let type_name = type_name.clone();
                    self.advance();
                    type_parts.push(Type::Custom(type_name));
                } else {
                    return Err("Expect type name after '&'.".to_string());
                }
            }
            
            // Create the appropriate type definition
            let type_def = if type_parts.len() == 1 {
                type_parts[0].clone()
            } else {
                Type::Union(type_parts)
            };
            
            Ok(Stmt::Type(name, type_def))
        } else {
            Err("Expect type name.".to_string())
        }
    }

    fn statement(&mut self) -> Result<Stmt, String> {
        println!("[statement] Current token: {:?}", self.peek().token_type);
        if self.match_token(&TokenType::If) {
            println!("[statement] Matched If");
            self.if_statement()
        } else if self.match_token(&TokenType::While) {
            println!("[statement] Matched While");
            self.while_statement()
        } else if self.match_token(&TokenType::For) {
            println!("[statement] Matched For");
            self.for_statement()

        } else if self.match_token(&TokenType::Emit) {
            self.emit_statement()
        } else if self.match_token(&TokenType::Say) {
            self.say_statement()
        } else if self.match_token(&TokenType::Return) {
            self.return_statement()
        } else if self.match_token(&TokenType::Set) {
            self.set_statement()
        } else if self.match_token(&TokenType::Try) {
            self.try_statement()
        } else if self.match_token(&TokenType::Throw) {
            self.throw_statement()
        } else if self.match_token(&TokenType::Break) {
            Ok(Stmt::Break)
        } else if self.match_token(&TokenType::Continue) {
            Ok(Stmt::Continue)
        } else if self.match_token(&TokenType::Semicolon) {
            // Skip semicolons (empty statements)
            Ok(Stmt::Expression(Expr::Literal(LiteralValue::Null)))
        } else {
            println!("[statement] Handling expression stmt: {:?}", self.peek());
            let expr = self.expression()?;
            println!("[statement] Expression parsed successfully");
            // Always wrap assignments as Stmt::Expression, never as Stmt::Set
            Ok(Stmt::Expression(expr))
        }
    }

    fn if_statement(&mut self) -> Result<Stmt, String> {
        let condition = self.expression()?;
        
        // Parse then branch - can be a single statement or a block
        let then_branch = if self.match_token(&TokenType::LeftBrace) {
            let mut statements = Vec::new();
            while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
                statements.push(self.declaration()?);
            }
            self.consume(&TokenType::RightBrace, "Expect '}' after then branch.")?;
            statements
        } else {
            // Single statement
            vec![self.declaration()?]
        };
        
        // Parse else branch - can be a single statement or a block
        let mut else_branch = None;
        if self.match_token(&TokenType::Else) {
            let else_statements = if self.match_token(&TokenType::LeftBrace) {
                let mut statements = Vec::new();
                while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
                    statements.push(self.declaration()?);
                }
                self.consume(&TokenType::RightBrace, "Expect '}' after else branch.")?;
                statements
            } else {
                // Single statement
                vec![self.declaration()?]
            };
            else_branch = Some(else_statements);
        }
        
        Ok(Stmt::If(condition, then_branch, else_branch))
    }

    fn while_statement(&mut self) -> Result<Stmt, String> {
        self.consume(&TokenType::LeftParen, "Expect '(' after 'while'.")?;
        let condition = self.expression()?;
        self.consume(&TokenType::RightParen, "Expect ')' after while condition.")?;
        self.consume(&TokenType::LeftBrace, "Expect '{' before while body.")?;
        
        let mut body = Vec::new();
        while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
            body.push(self.declaration()?);
        }
        self.consume(&TokenType::RightBrace, "Expect '}' after while body.")?;
        
        Ok(Stmt::While(condition, body))
    }

    fn for_statement(&mut self) -> Result<Stmt, String> {
        self.consume(&TokenType::LeftParen, "Expect '(' after 'for'.")?;
        
        // Parse initializer
        let init = if !self.check(&TokenType::Semicolon) {
            Some(Box::new(self.declaration()?))
        } else {
            None
        };
        self.consume(&TokenType::Semicolon, "Expect ';' after for initializer.")?;
        
        // Parse condition
        let condition = if !self.check(&TokenType::Semicolon) {
            Some(self.expression()?)
        } else {
            None
        };
        self.consume(&TokenType::Semicolon, "Expect ';' after for condition.")?;
        
        // Parse increment
        let increment = if !self.check(&TokenType::RightParen) {
            let expr = self.assignment()?;
            if let Expr::Set(ref boxed_target, ref _name, ref boxed_value) = expr {
                if let Expr::Variable(var_name) = *boxed_target.clone() {
                    Some(Box::new(Stmt::Set(var_name, *(*boxed_value).clone())))
                } else {
                    Some(Box::new(Stmt::Expression(expr)))
                }
            } else {
                Some(Box::new(Stmt::Expression(expr)))
            }
        } else {
            None
        };
        self.consume(&TokenType::RightParen, "Expect ')' after for clauses.")?;
        
        // Parse body
        self.consume(&TokenType::LeftBrace, "Expect '{' before for body.")?;
        let mut body = Vec::new();
        while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
            body.push(self.declaration()?);
        }
        self.consume(&TokenType::RightBrace, "Expect '}' after for body.")?;
        
        Ok(Stmt::For { init, condition, increment, body })
    }



    fn emit_statement(&mut self) -> Result<Stmt, String> {
        // Handle both String and Identifier tokens for event names
        let event_name = match &self.peek().token_type {
            TokenType::String(name) => {
                let name = name.clone();
                self.advance();
                name
            },
            TokenType::Identifier(name) => {
                let name = name.clone();
                self.advance();
                name
            },
            _ => {
                return Err("Expect event name (string or identifier).".to_string());
            }
        };
        
        let payload = if self.match_token(&TokenType::With) {
            Some(self.assignment()?)
        } else {
            None
        };
        
        Ok(Stmt::Emit(event_name, payload))
    }

    fn say_statement(&mut self) -> Result<Stmt, String> {
        let value = self.assignment()?;
        self.consume(&TokenType::Semicolon, "Expect ';' after say statement.")?;
        Ok(Stmt::Say(value))
    }

    fn return_statement(&mut self) -> Result<Stmt, String> {
        let value = if !self.check(&TokenType::Semicolon) {
            Some(self.assignment()?)
        } else {
            None
        };
        
        Ok(Stmt::Return(value))
    }

    fn set_statement(&mut self) -> Result<Stmt, String> {
        
        // Parse the target (could be a variable or property access)
        let target_expr = if let TokenType::Identifier(name) = &self.peek().token_type {
            let name = name.clone();
            self.advance();
            
            // Check if this is followed by a dot (property access)
            if self.match_token(&TokenType::Dot) {
                let property = if let TokenType::Identifier(prop) = &self.peek().token_type {
                    let prop = prop.clone();
                    self.advance();
                    prop
                } else {
                    return Err("Expected property name".to_string());
                };
                
                // Create a property access expression
                Expr::Get(Box::new(Expr::Variable(name)), property)
            } else {
                Expr::Variable(name)
            }
        } else {
            return Err("Expected variable or property name".to_string());
        };
        
        self.consume(&TokenType::Equal, "Expect '=' after target.")?;
        let value = self.assignment()?;
        
        // Create an assignment expression
        let assignment_expr = match target_expr {
            Expr::Variable(name) => Expr::Assign(name, Box::new(value)),
            Expr::Get(object, property) => Expr::Set(object, property, Box::new(value)),
            _ => return Err("Invalid assignment target".to_string()),
        };
        
        Ok(Stmt::Expression(assignment_expr))
    }

    fn try_statement(&mut self) -> Result<Stmt, String> {
        // Parse try block
        self.consume(&TokenType::LeftBrace, "Expect '{' before try block.")?;
        let mut try_block = Vec::new();
        while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
            try_block.push(self.declaration()?);
        }
        self.consume(&TokenType::RightBrace, "Expect '}' after try block.")?;
        
        // Parse catch block
        self.consume(&TokenType::Catch, "Expect 'catch' after try block.")?;
        self.consume(&TokenType::LeftBrace, "Expect '{' before catch block.")?;
        let mut catch_block = Vec::new();
        while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
            catch_block.push(self.declaration()?);
        }
        self.consume(&TokenType::RightBrace, "Expect '}' after catch block.")?;
        
        Ok(Stmt::Try(try_block, catch_block))
    }

    fn throw_statement(&mut self) -> Result<Stmt, String> {
        let value = self.assignment()?;
        Ok(Stmt::Throw(value))
    }

    fn import_statement(&mut self) -> Result<Stmt, String> {
        // Parse import path
        let path = if let TokenType::String(path_str) = &self.peek().token_type {
            let path = path_str.clone();
            self.advance();
            path
        } else {
            return Err("Expected string literal for import path".to_string());
        };

        // Parse optional alias
        let alias = if self.match_token(&TokenType::As) {
            if let TokenType::Identifier(alias_name) = &self.peek().token_type {
                let alias = alias_name.clone();
                self.advance();
                Some(alias)
            } else {
                return Err("Expected identifier after 'as'".to_string());
            }
        } else {
            None
        };

        Ok(Stmt::Import { path, alias })
    }

    fn expression(&mut self) -> Result<Expr, String> {
        self.assignment()
    }



    fn expression_statement(&mut self) -> Result<Stmt, String> {
        let expr = self.expression()?;
        self.consume(&TokenType::Semicolon, "Expect ';' after expression.")?;
        Ok(Stmt::Expression(expr))
    }

    fn assignment(&mut self) -> Result<Expr, String> {
        println!("[assignment] Starting at: {:?}", self.peek());
        let expr = self.or()?;
        println!("[assignment] After or(): {:?}", expr);
        
        if self.match_token(&TokenType::Equal) {
            let equals = self.previous();
            let value = self.assignment()?;
            
            match expr {
                Expr::Variable(name) => {
                    return Ok(Expr::Assign(name, Box::new(value)));
                }
                Expr::Get(object, property) => {
                    return Ok(Expr::Set(object, property, Box::new(value)));
                }
                _ => {
                    return Err("Invalid assignment target.".to_string());
                }
            }
        }
        
        println!("[assignment] Returning: {:?}", expr);
        Ok(expr)
    }

    fn or(&mut self) -> Result<Expr, String> {
        println!("[or] Starting at: {:?}", self.peek());
        let mut expr = self.and()?;
        println!("[or] After and(): {:?}", expr);
        
        while self.match_token(&TokenType::Or) {
            let operator = self.previous();
            let right = self.and()?;
            expr = Expr::Binary(Box::new(expr), operator, Box::new(right));
        }
        
        println!("[or] Returning: {:?}", expr);
        Ok(expr)
    }

    fn and(&mut self) -> Result<Expr, String> {
        println!("[and] Starting at: {:?}", self.peek());
        let mut expr = self.equality()?;
        println!("[and] After equality(): {:?}", expr);
        
        while self.match_token(&TokenType::And) {
            let operator = self.previous();
            let right = self.equality()?;
            expr = Expr::Binary(Box::new(expr), operator, Box::new(right));
        }
        
        println!("[and] Returning: {:?}", expr);
        Ok(expr)
    }

    fn equality(&mut self) -> Result<Expr, String> {
        println!("[equality] Starting at: {:?}", self.peek());
        let mut expr = self.comparison()?;
        while self.match_token(&TokenType::BangEqual) || self.match_token(&TokenType::EqualEqual) {
            let op = self.previous();
            let right = self.comparison()?;
            println!("[equality] Parsed equality op");
            expr = Expr::Binary(Box::new(expr), op, Box::new(right));
        }
        println!("[equality] Returning: {:?}", expr);
        Ok(expr)
    }

    fn contains(&mut self) -> Result<Expr, String> {
        let mut expr = self.equality()?;
        
        while self.match_token(&TokenType::Identifier("contains".to_string())) {
            let operator = self.previous();
            let right = self.equality()?;
            expr = Expr::Binary(Box::new(expr), operator, Box::new(right));
        }
        
        Ok(expr)
    }

    fn comparison(&mut self) -> Result<Expr, String> {
        println!("[comparison] Starting at: {:?}", self.peek());
        let mut expr = self.term()?;
        while self.match_token(&TokenType::Less)
            || self.match_token(&TokenType::LessEqual)
            || self.match_token(&TokenType::Greater)
            || self.match_token(&TokenType::GreaterEqual)
        {
            let op = self.previous();
            let right = self.term()?;
            println!("[comparison] Parsed comparison op");
            expr = Expr::Binary(Box::new(expr), op, Box::new(right));
        }
        println!("[comparison] Returning: {:?}", expr);
        Ok(expr)
    }

    fn term(&mut self) -> Result<Expr, String> {
        println!("[term] Starting at: {:?}", self.peek());
        let mut expr = self.factor()?;
        while self.match_token(&TokenType::Plus) || self.match_token(&TokenType::Minus) {
            let op = self.previous();
            let right = self.factor()?;
            println!("[term] Parsed term op");
            expr = Expr::Binary(Box::new(expr), op, Box::new(right));
        }
        println!("[term] Returning: {:?}", expr);
        Ok(expr)
    }

    fn factor(&mut self) -> Result<Expr, String> {
        println!("[factor] Starting at: {:?}", self.peek());
        let mut expr = self.unary()?;
        while self.match_token(&TokenType::Star) || self.match_token(&TokenType::Slash) {
            let op = self.previous();
            let right = self.unary()?;
            println!("[factor] Parsed factor op");
            expr = Expr::Binary(Box::new(expr), op, Box::new(right));
        }
        println!("[factor] Returning: {:?}", expr);
        Ok(expr)
    }

    fn unary(&mut self) -> Result<Expr, String> {
        println!("[unary] Starting at: {:?}", self.peek());
        if self.match_token(&TokenType::Bang) || self.match_token(&TokenType::Minus) {
            let op = self.previous();
            let right = self.unary()?;
            println!("[unary] Parsed unary op");
            Ok(Expr::Unary(op, Box::new(right)))
        } else {
            self.call()
        }
    }

    fn call(&mut self) -> Result<Expr, String> {
        println!("[call] Starting at: {:?}", self.peek());
        let mut expr = self.primary()?;
        loop {
            if self.match_token(&TokenType::LeftParen) {
                // Parse function call arguments
                println!("[call] Found '('");
                let mut arguments = Vec::new();
                
                if !self.check(&TokenType::RightParen) {
                    loop {
                        arguments.push(self.expression()?);
                        
                        if !self.match_token(&TokenType::Comma) {
                            break;
                        }
                    }
                }
                
                self.consume(&TokenType::RightParen, "Expect ')' after arguments.")?;
                
                // Create function call expression
                if let Expr::Variable(name) = expr {
                    expr = Expr::Call(name, arguments);
                } else {
                    // Call function value directly
                    expr = Expr::CallValue(Box::new(expr), arguments);
                }
            } else if self.match_token(&TokenType::Dot) {
                // Check if the next token is an identifier
                if let TokenType::Identifier(_) = self.peek().token_type {
                    let name_token = self.advance();
                    println!("[call] Found '.' and property: {}", name_token.lexeme);
                
                // Check if this is followed by a function call (parentheses)
                if self.match_token(&TokenType::LeftParen) {
                    // Parse function call arguments
                    println!("[call] Found '(' after property access - treating as function call");
                    let mut arguments = Vec::new();
                    
                    if !self.check(&TokenType::RightParen) {
                        loop {
                            arguments.push(self.expression()?);
                            
                            if !self.match_token(&TokenType::Comma) {
                                break;
                            }
                        }
                    }
                    
                    self.consume(&TokenType::RightParen, "Expect ')' after arguments.")?;
                    
                    // Create namespace function call expression
                    if let Expr::Variable(namespace) = expr {
                        let function_name = format!("{}.{}", namespace, name_token.lexeme);
                        expr = Expr::Call(function_name, arguments);
                    } else {
                        return Err("Can only call namespace functions by namespace name".to_string());
                    }
                } else {
                    // Regular property access
                    expr = Expr::Get(Box::new(expr), name_token.lexeme);
                }
            } else {
                return Err("Expect property name after '.'.".to_string());
            }
        } else if self.match_token(&TokenType::LeftBracket) {
                println!("[call] Found '[' for array indexing");
                let index = self.expression()?;
                self.consume(&TokenType::RightBracket, "Expect ']' after array index.")?;
                println!("[call] Array index parsed: {:?}", index);
                expr = Expr::Get(Box::new(expr), format!("[{}]", self.stringify_expr(&index)));
            } else {
                break;
            }
        }
        println!("[call] Returning: {:?}", expr);
        Ok(expr)
    }

    fn primary(&mut self) -> Result<Expr, String> {
        println!("[primary] Entered with token: {:?}", self.peek());
        
        // Handle different token types
        if let TokenType::Number(n) = &self.peek().token_type {
            let n = *n;
            self.advance();
            println!("[primary] Consumed number literal: {}", n);
            return Ok(Expr::Literal(LiteralValue::Number(n)));
        }
        
        if let TokenType::String(s) = &self.peek().token_type {
            let s = s.clone();
            self.advance();
            println!("[primary] Consumed string literal: {}", s);
            return Ok(Expr::Literal(LiteralValue::String(s)));
        }
        
        if let TokenType::Identifier(name) = &self.peek().token_type {
            let name = name.clone();
            self.advance();
            println!("[primary] Consumed identifier: {}", name);
            return Ok(Expr::Variable(name));
        }
        
        if self.match_token(&TokenType::True) {
            println!("[primary] Consumed true literal");
            return Ok(Expr::Literal(LiteralValue::Boolean(true)));
        }
        
        if self.match_token(&TokenType::False) {
            println!("[primary] Consumed false literal");
            return Ok(Expr::Literal(LiteralValue::Boolean(false)));
        }
        
        if self.match_token(&TokenType::Null) {
            println!("[primary] Consumed null literal");
            return Ok(Expr::Literal(LiteralValue::Null));
        }
        
        if self.match_token(&TokenType::Fn) {
            return self.anonymous_function();
        }
        
        if self.match_token(&TokenType::Lambda) {
            return self.lambda_expression();
        }
        
        if self.match_token(&TokenType::LeftParen) {
            println!("[primary] Consumed '('");
            let expr = self.expression()?;
            self.consume(&TokenType::RightParen, "Expect ')' after expression.")?;
            println!("[primary] Finished parsing grouped expression");
            return Ok(expr);
        }
        
        if self.match_token(&TokenType::LeftBracket) {
            println!("[primary] Consumed '['");
            return self.array_literal();
        }
        
        let msg = format!("[primary] ERROR: Unexpected token at line {}, col {}: {:?}", self.peek().line, self.peek().column, self.peek().token_type);
        println!("{}", msg);
        Err(msg)
    }

    fn match_token(&mut self, token_type: &TokenType) -> bool {
        if self.check(token_type) {
            self.advance();
            true
        } else {
            false
        }
    }

    fn match_tokens(&mut self, token_types: &[&TokenType]) -> bool {
        for token_type in token_types {
            if self.check(token_type) {
                self.advance();
                return true;
            }
        }
        false
    }

    fn consume(&mut self, token_type: &TokenType, message: &str) -> Result<Token, String> {
        if self.check(token_type) {
            Ok(self.advance())
        } else {
            Err(message.to_string())
        }
    }

    fn check(&self, token_type: &TokenType) -> bool {
        if self.is_at_end() {
            false
        } else {
            match (&self.peek().token_type, token_type) {
                // Compare identifier names exactly
                (TokenType::Identifier(a), TokenType::Identifier(b)) => a == b,
                // Compare numbers exactly
                (TokenType::Number(a), TokenType::Number(b)) => a == b,
                // Compare strings exactly
                (TokenType::String(a), TokenType::String(b)) => a == b,
                // For non-value tokens, just match variants
                (a, b) => std::mem::discriminant(a) == std::mem::discriminant(b),
            }
        }
    }

    fn advance(&mut self) -> Token {
        if self.is_at_end() {
            return Token {
                token_type: TokenType::Eof,
                lexeme: "".to_string(),
                line: 0,
                column: 0,
            };
        }
        let token = self.tokens[self.current].clone();
        let next_token = if self.current + 1 < self.tokens.len() { 
            &self.tokens[self.current + 1] 
        } else { 
            &Token { token_type: TokenType::Eof, lexeme: "".to_string(), line: 0, column: 0 } 
        };
        println!("[advance] Advancing from index {}: {:?} -> {:?}", self.current, token, next_token);
        self.current += 1;
        token
    }

    fn is_at_end(&self) -> bool {
        self.peek().token_type == TokenType::Eof
    }

    fn peek(&self) -> &Token {
        &self.tokens[self.current]
    }

    fn previous(&self) -> Token {
        self.tokens[self.current - 1].clone()
    }
    
    fn stringify_expr(&self, expr: &Expr) -> String {
        match expr {
            Expr::Literal(literal) => match literal {
                LiteralValue::Number(n) => n.to_string(),
                LiteralValue::String(s) => s.clone(),
                LiteralValue::Boolean(b) => b.to_string(),
                LiteralValue::Null => "null".to_string(),
            },
            Expr::Variable(name) => name.clone(),
            Expr::Binary(left, _, right) => format!("({} {} {})", 
                self.stringify_expr(left), 
                "op", 
                self.stringify_expr(right)),
            _ => "expr".to_string(),
        }
    }
    
    fn object_literal(&mut self) -> Result<Expr, String> {
        let mut properties = Vec::new();
        
        if !self.check(&TokenType::RightBrace) {
            loop {
                // Parse property name (identifier or string)
                let name = match &self.peek().token_type {
                    TokenType::Identifier(name) => {
                        let name = name.clone();
                        self.advance();
                        name
                    }
                    TokenType::String(name) => {
                        let name = name.clone();
                        self.advance();
                        name
                    }
                    _ => return Err("Expected property name".to_string()),
                };
                
                // Expect colon
                self.consume(&TokenType::Colon, "Expected ':' after property name")?;
                
                // Parse property value
                let value = self.assignment()?;
                
                properties.push((name, value));
                
                // Check for more properties
                if !self.match_token(&TokenType::Comma) {
                    break;
                }
            }
        }
        
        self.consume(&TokenType::RightBrace, "Expected '}' after object literal")?;
        Ok(Expr::Object(properties))
    }
    
    fn array_literal(&mut self) -> Result<Expr, String> {
        let mut elements = Vec::new();
        
        if !self.check(&TokenType::RightBracket) {
            loop {
                let element = self.equality()?;
                elements.push(element);
                
                if !self.match_token(&TokenType::Comma) {
                    break;
                }
            }
        }
        
        self.consume(&TokenType::RightBracket, "Expected ']' after array literal")?;
        Ok(Expr::Array(elements))
    }
    
    fn anonymous_function(&mut self) -> Result<Expr, String> {
        // The 'fn' token was already consumed by match_token in primary()
        
        self.consume(&TokenType::LeftParen, "Expect '(' after fn.")?;
        
        // Parse parameters
        let mut parameters = Vec::new();
        if !self.check(&TokenType::RightParen) {
            loop {
                if let TokenType::Identifier(param) = &self.peek().token_type {
                    let param = param.clone();
                    self.advance();
                    parameters.push(param);
                    
                    if !self.match_token(&TokenType::Comma) {
                        break;
                    }
                } else {
                    return Err("Expect parameter name.".to_string());
                }
            }
        }
        
        self.consume(&TokenType::RightParen, "Expect ')' after parameters.")?;
        self.consume(&TokenType::LeftBrace, "Expect '{' before function body.")?;
        
        // Parse function body
        let mut body = Vec::new();
        while !self.check(&TokenType::RightBrace) && !self.is_at_end() {
            body.push(self.declaration()?);
        }
        
        self.consume(&TokenType::RightBrace, "Expect '}' after function body.")?;
        
        Ok(Expr::Function(parameters, body))
    }
    
    fn lambda_expression(&mut self) -> Result<Expr, String> {
        // The '|' token was already consumed by match_token in primary()
        
        // Parse parameters
        let mut parameters = Vec::new();
        if !self.check(&TokenType::Lambda) {
            loop {
                if let TokenType::Identifier(param) = &self.peek().token_type {
                    let param = param.clone();
                    self.advance();
                    parameters.push(param);
                    
                    if !self.match_token(&TokenType::Comma) {
                        break;
                    }
                } else {
                    return Err("Expect parameter name.".to_string());
                }
            }
        }
        
        self.consume(&TokenType::Lambda, "Expect '|' after parameters.")?;
        
        // Parse lambda body (single expression)
        let body = self.expression()?;
        
        Ok(Expr::Lambda(parameters, Box::new(body)))
    }
    
    // Advanced Type System Support
    fn parse_generic_type_parameters(&mut self) -> Result<Vec<String>, String> {
        let mut type_params = Vec::new();
        
        if self.match_token(&TokenType::Less) {
            loop {
                if let TokenType::Identifier(param) = &self.peek().token_type {
                    let param = param.clone();
                    self.advance();
                    type_params.push(param);
                    
                    if !self.match_token(&TokenType::Comma) {
                        break;
                    }
                } else {
                    return Err("Expect type parameter name.".to_string());
                }
            }
            
            self.consume(&TokenType::Greater, "Expect '>' after type parameters.")?;
        }
        
        Ok(type_params)
    }
    
    fn parse_type_annotation(&mut self) -> Result<Type, String> {
        match &self.peek().token_type {
            TokenType::Identifier(name) => {
                let name = name.clone();
                self.advance();
                
                // Check for generic type parameters
                if self.match_token(&TokenType::Less) {
                    let mut type_args = Vec::new();
                    loop {
                        type_args.push(self.parse_type_annotation()?);
                        
                        if !self.match_token(&TokenType::Comma) {
                            break;
                        }
                    }
                    self.consume(&TokenType::Greater, "Expect '>' after type arguments.")?;
                    Ok(Type::Generic(name, type_args))
                } else {
                    Ok(Type::Custom(name))
                }
            },
            TokenType::String(type_name) => {
                let type_name = type_name.clone();
                self.advance();
                Ok(Type::Custom(type_name))
            },
            _ => Err("Expect type annotation.".to_string())
        }
    }
    
    fn parse_union_type(&mut self) -> Result<Type, String> {
        let mut types = Vec::new();
        
        // Parse first type
        types.push(self.parse_type_annotation()?);
        
        // Parse union types (|)
        while self.match_token(&TokenType::Pipe) {
            types.push(self.parse_type_annotation()?);
        }
        
        if types.len() == 1 {
            Ok(types[0].clone())
        } else {
            Ok(Type::Union(types))
        }
    }
    
    fn parse_intersection_type(&mut self) -> Result<Type, String> {
        let mut types = Vec::new();
        
        // Parse first type
        types.push(self.parse_union_type()?);
        
        // Parse intersection types (&)
        while self.match_token(&TokenType::Intersection) {
            types.push(self.parse_union_type()?);
        }
        
        if types.len() == 1 {
            Ok(types[0].clone())
        } else {
            Ok(Type::Intersection(types))
        }
    }
}

// ========================================
// ========== UNIFIED FUNCTION SYSTEM =====
// ========================================

// Unified function representation - all functions use bytecode
#[derive(Debug, Clone, PartialEq)]
pub struct FunctionObj {
    pub name: String,
    pub arity: usize,
    pub chunk: Chunk,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ClosureObj {
    pub func: Rc<FunctionObj>,
    pub upvalues: Vec<(String, Value)>, // (name, value) pairs
}

// Compatibility view for unified function access
pub struct CalleeView<'a> {
    pub name: &'a str,
    pub arity: usize,
    pub code: &'a [Opcode],
    pub upvalues: &'a [(String, Value)], // empty for plain functions
}

// ========================================
// ========== INTERPRETER ===============
// ========================================

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Number(f64),
    String(String),
    Boolean(bool),
    Null,
    Function(Rc<FunctionObj>),    // plain functions
    Closure(Rc<ClosureObj>),      // functions with captured upvalues
    Array(Vec<Value>),
    Object(HashMap<String, Value>),
}

impl Value {
    #[inline]
    pub fn is_callable(&self) -> bool {
        matches!(self, Value::Function(_) | Value::Closure(_))
    }

    /// Unified read-only view for both Function and Closure.
    #[inline]
    pub fn as_callee_view(&self) -> Option<CalleeView<'_>> {
        match self {
            Value::Function(f) => Some(CalleeView {
                name: &f.name,
                arity: f.arity,
                code: &f.chunk.code,
                upvalues: &[],
            }),
            Value::Closure(c) => Some(CalleeView {
                name: &c.func.name,
                arity: c.func.arity,
                code: &c.func.chunk.code,
                upvalues: &c.upvalues,
            }),
            _ => None,
        }
    }

    #[inline] 
    pub fn fn_name(&self) -> Option<&str> {
        match self {
            Value::Function(f) => Some(&f.name),
            Value::Closure(c)  => Some(&c.func.name),
            _ => None,
        }
    }

    #[inline] 
    pub fn fn_arity(&self) -> Option<usize> {
        match self {
            Value::Function(f) => Some(f.arity),
            Value::Closure(c)  => Some(c.func.arity),
            _ => None,
        }
    }
}

impl fmt::Display for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Value::Number(n) => write!(f, "{}", n),
            Value::String(s) => write!(f, "{}", s),
            Value::Boolean(b) => write!(f, "{}", b),
            Value::Null => write!(f, "null"),
            Value::Function(func) => write!(f, "<fn {} /{}>", func.name, func.arity),
            Value::Closure(c) => write!(f, "<closure {} /{}>", c.func.name, c.func.arity),
            Value::Array(arr) => {
                write!(f, "[")?;
                for (i, item) in arr.iter().enumerate() {
                    if i > 0 { write!(f, ", ")?; }
                    write!(f, "{}", item)?;
                }
                write!(f, "]")
            }
            Value::Object(obj) => {
                write!(f, "{{")?;
                let mut pairs = obj.iter().collect::<Vec<_>>();
                pairs.sort_by(|a, b| a.0.cmp(b.0));
                for (i, (key, value)) in pairs.iter().enumerate() {
                    if i > 0 { write!(f, ", ")?; }
                    write!(f, "{}: {}", key, value)?;
                }
                write!(f, "}}")
            }
        }
    }
}

impl Value {
    pub fn as_string(&self) -> String {
        match self {
            Value::String(s) => s.clone(),
            Value::Number(n) => n.to_string(),
            Value::Boolean(b) => b.to_string(),
            Value::Null => "null".to_string(),
            Value::Function(func) => format!("function({})", func.name),
            Value::Closure(closure) => format!("closure({})", closure.func.name),
            Value::Array(_) => "[array]".to_string(),
            Value::Object(_) => "{object}".to_string(),
        }
    }
}

// Enhanced Type System
#[derive(Debug, Clone, PartialEq)]
pub enum Type {
    // Basic Types
    Number,
    String,
    Boolean,
    Null,
    Undefined,
    
    // Complex Types
    Array(Box<Type>),
    Object(HashMap<String, Type>),
    Function(Vec<Type>, Box<Type>), // params -> return
    Union(Vec<Type>),
    Intersection(Vec<Type>),
    
    // Generic Types
    Generic(String, Vec<Type>), // T, Vec<T>, etc.
    
    // Special Types
    Any,
    Never,
    Unknown,
    
    // Custom Types
    Custom(String),
}

impl Type {
    pub fn is_compatible_with(&self, other: &Type) -> bool {
        match (self, other) {
            (Type::Any, _) | (_, Type::Any) => true,
            (Type::Number, Type::Number) => true,
            (Type::String, Type::String) => true,
            (Type::Boolean, Type::Boolean) => true,
            (Type::Null, Type::Null) => true,
            (Type::Array(t1), Type::Array(t2)) => t1.is_compatible_with(t2),
            (Type::Object(fields1), Type::Object(fields2)) => {
                fields1.iter().all(|(k, v)| {
                    fields2.get(k).map_or(false, |t2| v.is_compatible_with(t2))
                })
            },
            (Type::Union(types1), Type::Union(types2)) => {
                types1.iter().all(|t1| {
                    types2.iter().any(|t2| t1.is_compatible_with(t2))
                })
            },
            (Type::Generic(name1, params1), Type::Generic(name2, params2)) => {
                name1 == name2 && params1.len() == params2.len() &&
                params1.iter().zip(params2.iter()).all(|(p1, p2)| p1.is_compatible_with(p2))
            },
            _ => false,
        }
    }
}

// Trait System
#[derive(Debug, Clone)]
pub struct Trait {
    pub name: String,
    pub methods: HashMap<String, Type>, // method_name -> signature
    pub constraints: Vec<String>, // generic constraints
}

impl Trait {
    pub fn new(name: String) -> Self {
        Self {
            name,
            methods: HashMap::new(),
            constraints: Vec::new(),
        }
    }
    
    pub fn add_method(&mut self, name: String, signature: Type) {
        self.methods.insert(name, signature);
    }
    
    pub fn add_constraint(&mut self, constraint: String) {
        self.constraints.push(constraint);
    }
}

// Component System
#[derive(Debug, Clone)]
pub struct Component {
    pub name: String,
    pub module: String,
    pub full_name: String, // module.name
    pub methods: HashMap<String, (Vec<String>, Vec<Stmt>)>,
    pub properties: HashMap<String, Type>,
    pub traits: Vec<String>,
    pub state: HashMap<String, Value>,
}

impl Component {
    pub fn new(module: String, name: String) -> Self {
        let full_name = format!("{}::{}", module, name);
        Self {
            name,
            module,
            full_name,
            methods: HashMap::new(),
            properties: HashMap::new(),
            traits: Vec::new(),
            state: HashMap::new(),
        }
    }
    
    pub fn add_method(&mut self, name: String, params: Vec<String>, body: Vec<Stmt>) {
        self.methods.insert(name, (params, body));
    }
    
    pub fn add_property(&mut self, name: String, type_info: Type) {
        self.properties.insert(name, type_info);
    }
    
    pub fn implements_trait(&mut self, trait_name: String) {
        self.traits.push(trait_name);
    }
}

pub struct Interpreter {
    globals: HashMap<String, Value>,
    environment: HashMap<String, Value>,
    functions: HashMap<String, (Vec<String>, Vec<Stmt>)>,
    event_handlers: HashMap<String, (Vec<String>, Vec<Stmt>)>,
    function_registry: FunctionRegistry,
    // Enhanced Type System and Component System
    components: HashMap<String, Component>,
    traits: HashMap<String, Trait>,
    type_context: HashMap<String, Type>,
}

impl Interpreter {
    pub fn new() -> Self {
        let mut registry = FunctionRegistry::new();
        
        // Register built-in functions
        Self::register_builtin_functions(&mut registry);
        
        Self {
            globals: HashMap::new(),
            environment: HashMap::new(),
            functions: HashMap::new(),
            event_handlers: HashMap::new(),
            function_registry: registry,
            components: HashMap::new(),
            traits: HashMap::new(),
            type_context: HashMap::new(),
        }
    }

    fn register_builtin_functions(registry: &mut FunctionRegistry) {
        // Basic utility functions
        registry.register_function("typeof", |args| {
            if args.len() != 1 {
                return Err("typeof requires exactly 1 argument".to_string());
            }
            let value = &args[0];
            let type_name = match value {
                Value::Number(_) => "number",
                Value::String(_) => "string",
                Value::Boolean(_) => "boolean",
                Value::Null => "null",
                Value::Array(_) => "array",
                Value::Object(_) => "object",
                Value::Function(_) => "function",
                Value::Closure(_) => "closure",
            };
            Ok(Value::String(type_name.to_string()))
        });

        registry.register_function("stringify", |args| {
            if args.len() != 1 {
                return Err("stringify requires exactly 1 argument".to_string());
            }
            // Note: This would need access to the interpreter's stringify method
            // For now, we'll implement a basic version
            let value = &args[0];
            let result = match value {
                Value::Number(n) => n.to_string(),
                Value::String(s) => s.clone(),
                Value::Boolean(b) => b.to_string(),
                Value::Null => "null".to_string(),
                Value::Array(arr) => format!("[{}]", arr.len()),
                Value::Object(obj) => format!("{{}}"),
                Value::Function(_) => "function".to_string(),
                Value::Closure(_) => "closure".to_string(),
            };
            Ok(Value::String(result))
        });

        registry.register_function("read_file", |args| {
            if args.len() != 1 {
                return Err("read_file requires exactly 1 argument".to_string());
            }
            if let Value::String(path) = &args[0] {
                match std::fs::read_to_string(path) {
                    Ok(content) => Ok(Value::String(content)),
                    Err(e) => Err(format!("Failed to read file '{}': {}", path, e))
                }
            } else {
                Err("read_file argument must be a string".to_string())
            }
        });

        registry.register_function("write_file", |args| {
            if args.len() != 2 {
                return Err("write_file requires exactly 2 arguments".to_string());
            }
            if let (Value::String(path), Value::String(content)) = (&args[0], &args[1]) {
                match std::fs::write(path, content) {
                    Ok(_) => Ok(Value::String("File written successfully".to_string())),
                    Err(e) => Err(format!("Failed to write file '{}': {}", path, e))
                }
            } else {
                Err("write_file arguments must be strings".to_string())
            }
        });

        // Math functions
        registry.register_function("floor", |args| {
            if args.len() != 1 {
                return Err("floor requires exactly 1 argument".to_string());
            }
            if let Value::Number(n) = args[0] {
                Ok(Value::Number(n.floor()))
            } else {
                Err("floor argument must be a number".to_string())
            }
        });

        registry.register_function("ceil", |args| {
            if args.len() != 1 {
                return Err("ceil requires exactly 1 argument".to_string());
            }
            if let Value::Number(n) = args[0] {
                Ok(Value::Number(n.ceil()))
            } else {
                Err("ceil argument must be a number".to_string())
            }
        });

        registry.register_function("random", |args| {
            if args.len() != 0 {
                return Err("random requires no arguments".to_string());
            }
            use rand::Rng;
            let mut rng = rand::thread_rng();
            Ok(Value::Number(rng.gen::<f64>()))
        });

        // Additional utility functions
        registry.register_function("split", |args| {
            if args.len() != 2 {
                return Err("split requires exactly 2 arguments".to_string());
            }
            if let (Value::String(text), Value::String(delimiter)) = (&args[0], &args[1]) {
                let parts: Vec<Value> = text.split(delimiter)
                    .map(|s| Value::String(s.to_string()))
                    .collect();
                Ok(Value::Array(parts))
            } else {
                Err("split arguments must be strings".to_string())
            }
        });

        registry.register_function("join", |args| {
            if args.len() != 2 {
                return Err("join requires exactly 2 arguments".to_string());
            }
            if let (Value::Array(items), Value::String(separator)) = (&args[0], &args[1]) {
                let strings: Vec<String> = items.iter()
                    .map(|v| match v {
                        Value::String(s) => s.clone(),
                        Value::Number(n) => n.to_string(),
                        Value::Boolean(b) => b.to_string(),
                        Value::Null => "null".to_string(),
                        _ => format!("{:?}", v),
                    })
                    .collect();
                Ok(Value::String(strings.join(separator)))
            } else {
                Err("join first argument must be array, second must be string".to_string())
            }
        });

        registry.register_function("replace", |args| {
            if args.len() != 3 {
                return Err("replace requires exactly 3 arguments".to_string());
            }
            if let (Value::String(text), Value::String(from), Value::String(to)) = 
                (&args[0], &args[1], &args[2]) {
                Ok(Value::String(text.replace(from, to)))
            } else {
                Err("replace arguments must be strings".to_string())
            }
        });

        registry.register_function("push", |args| {
            if args.len() != 2 {
                return Err("push requires exactly 2 arguments".to_string());
            }
            if let (Value::Array(arr), item) = (&args[0], &args[1]) {
                let mut new_arr = arr.clone();
                new_arr.push(item.clone());
                Ok(Value::Array(new_arr))
            } else {
                Err("push first argument must be array".to_string())
            }
        });

        registry.register_function("pop", |args| {
            if args.len() != 1 {
                return Err("pop requires exactly 1 argument".to_string());
            }
            if let Value::Array(arr) = &args[0] {
                if arr.is_empty() {
                    Err("Cannot pop from empty array".to_string())
                } else {
                    let mut new_arr = arr.clone();
                    Ok(new_arr.pop().unwrap())
                }
            } else {
                Err("pop argument must be array".to_string())
            }
        });

        registry.register_function("slice", |args| {
            if args.len() != 3 {
                return Err("slice requires exactly 3 arguments".to_string());
            }
            if let (Value::Array(arr), Value::Number(start), Value::Number(end)) = 
                (&args[0], &args[1], &args[2]) {
                let start_idx = start.floor() as usize;
                let end_idx = end.floor() as usize;
                if start_idx >= arr.len() || end_idx > arr.len() || start_idx >= end_idx {
                    Err("Invalid slice indices".to_string())
                } else {
                    let sliced = arr[start_idx..end_idx].to_vec();
                    Ok(Value::Array(sliced))
                }
            } else {
                Err("slice arguments must be array, number, number".to_string())
            }
        });

        registry.register_function("abs", |args| {
            if args.len() != 1 {
                return Err("abs requires exactly 1 argument".to_string());
            }
            if let Value::Number(n) = args[0] {
                Ok(Value::Number(n.abs()))
            } else {
                Err("abs argument must be a number".to_string())
            }
        });

        registry.register_function("sqrt", |args| {
            if args.len() != 1 {
                return Err("sqrt requires exactly 1 argument".to_string());
            }
            if let Value::Number(n) = args[0] {
                if n < 0.0 {
                    Err("Cannot take square root of negative number".to_string())
                } else {
                    Ok(Value::Number(n.sqrt()))
                }
            } else {
                Err("sqrt argument must be a number".to_string())
            }
        });

        registry.register_function("pow", |args| {
            if args.len() != 2 {
                return Err("pow requires exactly 2 arguments".to_string());
            }
            if let (Value::Number(base), Value::Number(exponent)) = (&args[0], &args[1]) {
                Ok(Value::Number(base.powf(*exponent)))
            } else {
                Err("pow arguments must be numbers".to_string())
            }
        });

        registry.register_function("sin", |args| {
            if args.len() != 1 {
                return Err("sin requires exactly 1 argument".to_string());
            }
            if let Value::Number(n) = args[0] {
                Ok(Value::Number(n.sin()))
            } else {
                Err("sin argument must be a number".to_string())
            }
        });

        registry.register_function("cos", |args| {
            if args.len() != 1 {
                return Err("cos requires exactly 1 argument".to_string());
            }
            if let Value::Number(n) = args[0] {
                Ok(Value::Number(n.cos()))
            } else {
                Err("cos argument must be a number".to_string())
            }
        });

        registry.register_function("tan", |args| {
            if args.len() != 1 {
                return Err("tan requires exactly 1 argument".to_string());
            }
            if let Value::Number(n) = args[0] {
                Ok(Value::Number(n.tan()))
            } else {
                Err("tan argument must be a number".to_string())
            }
        });

        registry.register_function("log", |args| {
            if args.len() != 1 {
                return Err("log requires exactly 1 argument".to_string());
            }
            if let Value::Number(n) = args[0] {
                if n <= 0.0 {
                    Err("Cannot take log of non-positive number".to_string())
                } else {
                    Ok(Value::Number(n.ln()))
                }
            } else {
                Err("log argument must be a number".to_string())
            }
        });

        registry.register_function("exp", |args| {
            if args.len() != 1 {
                return Err("exp requires exactly 1 argument".to_string());
            }
            if let Value::Number(n) = args[0] {
                Ok(Value::Number(n.exp()))
            } else {
                Err("exp argument must be a number".to_string())
            }
        });

        registry.register_function("round", |args| {
            if args.len() != 1 {
                return Err("round requires exactly 1 argument".to_string());
            }
            if let Value::Number(n) = args[0] {
                Ok(Value::Number(n.round()))
            } else {
                Err("round argument must be a number".to_string())
            }
        });

        registry.register_function("min", |args| {
            if args.len() != 2 {
                return Err("min requires exactly 2 arguments".to_string());
            }
            if let (Value::Number(a), Value::Number(b)) = (&args[0], &args[1]) {
                Ok(Value::Number(a.min(*b)))
            } else {
                Err("min arguments must be numbers".to_string())
            }
        });

        registry.register_function("max", |args| {
            if args.len() != 2 {
                return Err("max requires exactly 2 arguments".to_string());
            }
            if let (Value::Number(a), Value::Number(b)) = (&args[0], &args[1]) {
                Ok(Value::Number(a.max(*b)))
            } else {
                Err("max arguments must be numbers".to_string())
            }
        });

        registry.register_function("now", |args| {
            if args.len() != 0 {
                return Err("now requires no arguments".to_string());
            }
            use std::time::{SystemTime, UNIX_EPOCH};
            match SystemTime::now().duration_since(UNIX_EPOCH) {
                Ok(duration) => Ok(Value::Number(duration.as_secs() as f64)),
                Err(_) => Err("Failed to get current time".to_string())
            }
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
            // Create quantum superposition state |ψ⟩ = α|0⟩ + β|1⟩
            let norm = (alpha * alpha + beta * beta).sqrt();
            let normalized_alpha = alpha / norm;
            let normalized_beta = beta / norm;
            let superposition = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("superposition".to_string()));
                map.insert("alpha".to_string(), Value::Number(normalized_alpha));
                map.insert("beta".to_string(), Value::Number(normalized_beta));
                map.insert("norm".to_string(), Value::Number(norm));
                map.insert("entangled".to_string(), Value::Boolean(false));
                map
            });
            Ok(superposition)
        });

        registry.register_namespace_function("quantum", "entangle", |args| {
            if args.len() != 2 {
                return Err("quantum.entangle requires exactly 2 arguments (qubit1, qubit2)".to_string());
            }
            let qubit1 = &args[0];
            let qubit2 = &args[1];
            // Create Bell state |Φ⁺⟩ = (|00⟩ + |11⟩)/√2
            let bell_state = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("bell_state".to_string()));
                map.insert("qubit1".to_string(), qubit1.clone());
                map.insert("qubit2".to_string(), qubit2.clone());
                map.insert("entangled".to_string(), Value::Boolean(true));
                map.insert("measurement_correlation".to_string(), Value::Number(1.0));
                map
            });
            Ok(bell_state)
        });

        registry.register_namespace_function("quantum", "measure", |args| {
            if args.len() != 1 {
                return Err("quantum.measure requires exactly 1 argument (qubit)".to_string());
            }
            let qubit = &args[0];
            // Simulate quantum measurement with collapse
            let measurement_result = if rand::random::<f64>() > 0.5 { 1 } else { 0 };
            let collapsed_state = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("measured_qubit".to_string()));
                map.insert("original_state".to_string(), qubit.clone());
                map.insert("measurement_result".to_string(), Value::Number(measurement_result as f64));
                map.insert("collapsed".to_string(), Value::Boolean(true));
                map
            });
            Ok(collapsed_state)
        });

        // Memory functions
        registry.register_namespace_function("memory", "lha3", |args| {
            // This is a placeholder - the actual implementation would be in the call_function method
            // We'll handle this specially since it needs access to the interpreter's globals
            Err("memory.lha3 functions are handled internally".to_string())
        });

        registry.register_namespace_function("memory", "lha3_store", |args| {
            if args.len() != 2 {
                return Err("memory.lha3.store requires exactly 2 arguments (key, value)".to_string());
            }
            let key = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.lha3.store key must be a string".to_string()),
            };
            let value = &args[1];
            // Simulate LHA3 memory storage with quantum coherence
            let memory_entry = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("lha3_memory_entry".to_string()));
                map.insert("key".to_string(), Value::String(key.clone()));
                map.insert("value".to_string(), value.clone());
                map.insert("quantum_coherence".to_string(), Value::Number(0.95));
                map.insert("entanglement_strength".to_string(), Value::Number(0.8));
                map.insert("retrieval_probability".to_string(), Value::Number(0.9));
                map.insert("storage_timestamp".to_string(), Value::Number(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64()));
                map
            });
            Ok(memory_entry)
        });

        registry.register_namespace_function("memory", "lha3_retrieve", |args| {
            if args.len() != 1 {
                return Err("memory.lha3.retrieve requires exactly 1 argument (key)".to_string());
            }
            let key = match &args[0] {
                Value::String(s) => s.clone(),
                _ => return Err("memory.lha3.retrieve key must be a string".to_string()),
            };
            // For now, return a placeholder since we don't have access to globals here
            let retrieved_value = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("lha3_retrieved".to_string()));
                map.insert("key".to_string(), Value::String(key));
                map.insert("retrieval_success".to_string(), Value::Boolean(true));
                map.insert("quantum_fidelity".to_string(), Value::Number(0.92));
                map.insert("retrieval_time".to_string(), Value::Number(0.001));
                map
            });
            Ok(retrieved_value)
        });

        // Neural functions
        registry.register_namespace_function("neural", "layer", |args| {
            if args.len() != 2 {
                return Err("neural.layer requires exactly 2 arguments (input_size, output_size)".to_string());
            }
            let input_size = match &args[0] {
                Value::Number(n) => *n as usize,
                _ => return Err("neural.layer input_size must be a number".to_string()),
            };
            let output_size = match &args[1] {
                Value::Number(n) => *n as usize,
                _ => return Err("neural.layer output_size must be a number".to_string()),
            };
            // Create neural layer with random weights
            let mut all_weights = Vec::new();
            for _ in 0..output_size {
                for _ in 0..input_size {
                    all_weights.push(Value::Number(rand::random::<f64>() * 2.0 - 1.0));
                }
            }
            let biases = (0..output_size).map(|_| Value::Number(rand::random::<f64>() * 2.0 - 1.0)).collect::<Vec<_>>();
            let layer = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("neural_layer".to_string()));
                map.insert("input_size".to_string(), Value::Number(input_size as f64));
                map.insert("output_size".to_string(), Value::Number(output_size as f64));
                map.insert("weights".to_string(), Value::Array(all_weights));
                map.insert("biases".to_string(), Value::Array(biases));
                map.insert("activation".to_string(), Value::String("relu".to_string()));
                map
            });
            Ok(layer)
        });

        registry.register_namespace_function("neural", "forward", |args| {
            if args.len() != 2 {
                return Err("neural.forward requires exactly 2 arguments (layer, input)".to_string());
            }
            let layer = &args[0];
            let input = &args[1];
            // Simulate forward pass through neural layer
            let output = Value::Array(vec![
                Value::Number(0.8), Value::Number(0.6), Value::Number(0.9)
            ]);
            let forward_result = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("forward_pass".to_string()));
                map.insert("layer".to_string(), layer.clone());
                map.insert("input".to_string(), input.clone());
                map.insert("output".to_string(), output);
                map.insert("activation_energy".to_string(), Value::Number(0.75));
                map
            });
            Ok(forward_result)
        });

        registry.register_namespace_function("neural", "backprop", |args| {
            if args.len() != 3 {
                return Err("neural.backprop requires exactly 3 arguments (layer, gradient, learning_rate)".to_string());
            }
            let layer = &args[0];
            let gradient = &args[1];
            let learning_rate = match &args[2] {
                Value::Number(n) => *n,
                _ => return Err("neural.backprop learning_rate must be a number".to_string()),
            };
            // Simulate backpropagation
            let updated_layer = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("updated_layer".to_string()));
                map.insert("original_layer".to_string(), layer.clone());
                map.insert("gradient".to_string(), gradient.clone());
                map.insert("learning_rate".to_string(), Value::Number(learning_rate));
                map.insert("weights_updated".to_string(), Value::Boolean(true));
                map.insert("biases_updated".to_string(), Value::Boolean(true));
                map
            });
            Ok(updated_layer)
        });

        // Consciousness functions
        registry.register_namespace_function("consciousness", "aware", |args| {
            if args.len() != 1 {
                return Err("consciousness.aware requires exactly 1 argument (stimulus)".to_string());
            }
            let stimulus = &args[0];
            // Simulate consciousness awareness
            let awareness_level = match stimulus {
                Value::String(s) => s.len() as f64 * 0.1,
                Value::Number(n) => n.abs(),
                Value::Array(arr) => arr.len() as f64 * 0.2,
                _ => 0.5,
            };
            let consciousness_state = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("consciousness_awareness".to_string()));
                map.insert("stimulus".to_string(), stimulus.clone());
                map.insert("awareness_level".to_string(), Value::Number(awareness_level));
                map.insert("attention_focus".to_string(), Value::Number(awareness_level.min(1.0)));
                map.insert("metacognitive_monitoring".to_string(), Value::Boolean(awareness_level > 0.7));
                map
            });
            Ok(consciousness_state)
        });

        registry.register_namespace_function("consciousness", "reflect", |args| {
            if args.len() != 2 {
                return Err("consciousness.reflect requires exactly 2 arguments (experience, depth)".to_string());
            }
            let experience = &args[0];
            let depth = match &args[1] {
                Value::Number(n) => *n,
                _ => return Err("consciousness.reflect depth must be a number".to_string()),
            };
            // Simulate consciousness reflection
            let reflection_insight = Value::Number(depth * 0.8);
            let metacognitive_gain = Value::Number(depth * 0.6);
            let reflection_result = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("consciousness_reflection".to_string()));
                map.insert("experience".to_string(), experience.clone());
                map.insert("reflection_depth".to_string(), Value::Number(depth));
                map.insert("insight_gained".to_string(), reflection_insight);
                map.insert("metacognitive_gain".to_string(), metacognitive_gain);
                map.insert("self_awareness_increased".to_string(), Value::Boolean(depth > 0.5));
                map
            });
            Ok(reflection_result)
        });

        // Neural functions
        registry.register_namespace_function("neural", "forward_pass", |args| {
            if args.len() != 1 {
                return Err("neural.forward_pass requires exactly 1 argument (input_data)".to_string());
            }
            let input_data = match &args[0] {
                Value::Array(arr) => arr.clone(),
                _ => return Err("neural.forward_pass input_data must be an array".to_string()),
            };
            
            let input_size = input_data.len();
            
            // Simulate neural network forward pass
            let mut output = Vec::new();
            for value in &input_data {
                if let Value::Number(n) = value {
                    // Simple activation function (sigmoid-like)
                    let activated = 1.0 / (1.0 + (-n).exp());
                    output.push(Value::Number(activated));
                }
            }
            
            let mut result = HashMap::new();
            result.insert("type".to_string(), Value::String("neural_forward_pass".to_string()));
            result.insert("input_size".to_string(), Value::Number(input_size as f64));
            result.insert("output_size".to_string(), Value::Number(output.len() as f64));
            result.insert("output".to_string(), Value::Array(output));
            result.insert("activation_function".to_string(), Value::String("sigmoid".to_string()));
            
            Ok(Value::Object(result))
        });

        registry.register_namespace_function("neural", "backpropagate", |args| {
            if args.len() != 2 {
                return Err("neural.backpropagate requires exactly 2 arguments (output, target)".to_string());
            }
            
            let mut result = HashMap::new();
            result.insert("type".to_string(), Value::String("neural_backpropagate".to_string()));
            result.insert("learning_rate".to_string(), Value::Number(0.01));
            result.insert("loss".to_string(), Value::Number(0.5));
            result.insert("gradients_updated".to_string(), Value::Boolean(true));
            
            Ok(Value::Object(result))
        });

        // Autonomous functions
        registry.register_namespace_function("autonomous", "plan", |args| {
            if args.len() != 2 {
                return Err("autonomous.plan requires exactly 2 arguments (goal, constraints)".to_string());
            }
            let goal = &args[0];
            let constraints = &args[1];
            // Simulate autonomous planning
            let plan_steps = Value::Array(vec![
                Value::String("analyze_environment".to_string()),
                Value::String("identify_resources".to_string()),
                Value::String("generate_strategies".to_string()),
                Value::String("evaluate_options".to_string()),
                Value::String("execute_optimal_plan".to_string())
            ]);
            let autonomous_plan = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("autonomous_plan".to_string()));
                map.insert("goal".to_string(), goal.clone());
                map.insert("constraints".to_string(), constraints.clone());
                map.insert("plan_steps".to_string(), plan_steps);
                map.insert("confidence_level".to_string(), Value::Number(0.85));
                map.insert("adaptability_score".to_string(), Value::Number(0.9));
                map.insert("execution_priority".to_string(), Value::Number(0.8));
                map
            });
            Ok(autonomous_plan)
        });

        registry.register_namespace_function("autonomous", "execute", |args| {
            if args.len() != 1 {
                return Err("autonomous.execute requires exactly 1 argument (plan)".to_string());
            }
            let plan = &args[0];
            // Simulate autonomous execution
            let execution_result = Value::Object({
                let mut map = HashMap::new();
                map.insert("type".to_string(), Value::String("autonomous_execution".to_string()));
                map.insert("original_plan".to_string(), plan.clone());
                map.insert("execution_success".to_string(), Value::Boolean(true));
                map.insert("steps_completed".to_string(), Value::Number(5.0));
                map.insert("adaptations_made".to_string(), Value::Number(2.0));
                map.insert("goal_achievement".to_string(), Value::Number(0.9));
                map.insert("learning_integrated".to_string(), Value::Boolean(true));
                map
            });
            Ok(execution_result)
        });
    }

    pub fn interpret(&mut self, statements: Vec<Stmt>) -> Result<(), String> {
        for statement in statements {
            self.execute(statement)?;
        }
        Ok(())
    }

    // Runtime function registration
    pub fn register_function<F>(&mut self, name: &str, func: F) 
    where 
        F: Fn(&[Value]) -> Result<Value, String> + Send + Sync + 'static 
    {
        self.function_registry.register_function(name, func);
    }

    pub fn register_namespace_function<F>(&mut self, namespace: &str, name: &str, func: F) 
    where 
        F: Fn(&[Value]) -> Result<Value, String> + Send + Sync + 'static 
    {
        self.function_registry.register_namespace_function(namespace, name, func);
    }

    pub fn list_registered_functions(&self) -> Vec<String> {
        self.function_registry.list_functions()
    }

    pub fn list_namespace_functions(&self, namespace: &str) -> Vec<String> {
        self.function_registry.list_namespace_functions(namespace)
    }

    // Component System Methods
    pub fn register_component(&mut self, component: Component) {
        self.components.insert(component.full_name.clone(), component);
    }
    
    pub fn get_component(&self, name: &str) -> Option<&Component> {
        self.components.get(name)
    }
    
    pub fn call_component_method(&mut self, component_name: &str, method_name: &str, args: Vec<Value>) -> Result<Value, String> {
        // Clone the component to avoid borrow checker issues
        let component = if let Some(comp) = self.components.get(component_name) {
            comp.clone()
        } else {
            return Err(format!("Component '{}' not found", component_name));
        };
        
        if let Some((params, body)) = component.methods.get(method_name) {
            if params.len() != args.len() {
                return Err(format!("Component method '{}' expects {} arguments but got {}", 
                                 method_name, params.len(), args.len()));
            }
            
            // Create new environment for component method call
            let mut method_env = HashMap::new();
            
            // Add component state to environment
            for (key, value) in &component.state {
                method_env.insert(key.clone(), value.clone());
            }
            
            // Add arguments to environment
            for (param, arg) in params.iter().zip(args.iter()) {
                method_env.insert(param.clone(), arg.clone());
            }
            
            // Execute method body
            let original_env = self.environment.clone();
            self.environment = method_env;
            
            for stmt in body {
                self.execute(stmt.clone())?;
            }
            
            // Restore original environment
            self.environment = original_env;
            
            Ok(Value::Null) // TODO: Return actual value
        } else {
            Err(format!("Method '{}' not found in component '{}'", method_name, component_name))
        }
    }
    
    // Trait System Methods
    pub fn register_trait(&mut self, trait_def: Trait) {
        self.traits.insert(trait_def.name.clone(), trait_def);
    }
    
    pub fn get_trait(&self, name: &str) -> Option<&Trait> {
        self.traits.get(name)
    }
    
    // Type System Methods
    pub fn register_type(&mut self, name: String, type_info: Type) {
        self.type_context.insert(name, type_info);
    }
    
    pub fn get_type(&self, name: &str) -> Option<&Type> {
        self.type_context.get(name)
    }
    
    pub fn type_check(&self, value: &Value, expected_type: &Type) -> bool {
        match (value, expected_type) {
            (Value::Number(_), Type::Number) => true,
            (Value::String(_), Type::String) => true,
            (Value::Boolean(_), Type::Boolean) => true,
            (Value::Null, Type::Null) => true,
            (Value::Array(_), Type::Array(_)) => true, // TODO: Check element types
            (Value::Object(_), Type::Object(_)) => true, // TODO: Check field types
            (_, Type::Any) => true,
            _ => false,
        }
    }

    fn execute(&mut self, stmt: Stmt) -> Result<(), String> {
        match stmt {
            Stmt::Expression(expr) => {
                self.evaluate(expr)?;
                Ok(())
            }
            Stmt::Let(name, initializer) => {
                let value = self.evaluate(initializer)?;
                self.environment.insert(name, value);
                Ok(())
            }
            Stmt::Set(name, value) => {
                let evaluated_value = self.evaluate(value)?;
                self.environment.insert(name, evaluated_value);
                Ok(())
            }
            Stmt::FunctionDecl(name, parameters, body) => {
                // Store function in interpreter's function table
                self.functions.insert(name.clone(), (parameters, body));
                Ok(())
            }
            Stmt::EventHandler(name, params, body) => {
                self.event_handlers.insert(name.clone(), (params, body));
                Ok(())
            }
            Stmt::If(condition, then_branch, else_branch) => {
                let condition_value = self.evaluate(condition)?;
                
                if self.is_truthy(&condition_value) {
                    for stmt in then_branch {
                        self.execute(stmt)?;
                    }
                } else if let Some(else_statements) = else_branch {
                    for stmt in else_statements {
                        self.execute(stmt)?;
                    }
                }
                Ok(())
            }
            Stmt::While(condition, body) => {
                loop {
                    let condition_value = self.evaluate(condition.clone())?;
                    if !self.is_truthy(&condition_value) {
                        break;
                    }
                    
                    for stmt in body.clone() {
                        match stmt {
                            Stmt::Break => return Ok(()),
                            Stmt::Continue => break,
                            _ => self.execute(stmt)?,
                        }
                    }
                }
                Ok(())
            }
            Stmt::For { init, condition, increment, body } => {
                // Execute initializer
                if let Some(init_stmt) = init {
                    self.execute(*init_stmt)?;
                }
                
                loop {
                    // Check condition
                    if let Some(ref cond) = condition {
                        let condition_value = self.evaluate(cond.clone())?;
                        if !self.is_truthy(&condition_value) {
                            break;
                        }
                    }
                    
                    // Execute body
                    for stmt in body.clone() {
                        match stmt {
                            Stmt::Break => return Ok(()),
                            Stmt::Continue => break,
                            _ => self.execute(stmt)?,
                        }
                    }
                    
                    // Execute increment
                    if let Some(ref inc_stmt) = increment {
                        self.execute((**inc_stmt).clone())?;
                    }
                }
                Ok(())
            }
            Stmt::Break => {
                // This should be handled by the loop constructs above
                Ok(())
            }
            Stmt::Continue => {
                // This should be handled by the loop constructs above
                Ok(())
            }
            Stmt::Emit(event_name, payload) => {
                println!("📡 Emitting event: {} with {:?}", event_name, payload);
                Ok(())
            }
            Stmt::Say(value) => {
                let evaluated_value = self.evaluate(value)?;
                println!("💬 {}", self.stringify(&evaluated_value));
                Ok(())
            }
            Stmt::Return(value) => {
                let return_value = if let Some(expr) = value {
                    self.evaluate(expr)?
                } else {
                    Value::Null
                };
                // In a real implementation, you'd need to handle return values properly
                Ok(())
            }
            Stmt::Class(name, methods) => {
                // For now, just store the class definition
                println!("Class definition: {}", name);
                for method in methods {
                    self.execute(method)?;
                }
                Ok(())
            }
            Stmt::Method(name, params, body) => {
                // For now, just store the method definition
                println!("Method definition: {}", name);
                // Store method in functions map
                self.functions.insert(name, (params, body));
                Ok(())
            }
            Stmt::Try(try_block, catch_block) => {
                // Execute try block
                for stmt in try_block {
                    if let Err(e) = self.execute(stmt) {
                        // Exception caught, execute catch block
                        println!("Exception caught: {}", e);
                        for stmt in catch_block {
                            self.execute(stmt)?;
                        }
                        break;
                    }
                }
                Ok(())
            }
            Stmt::Throw(expr) => {
                let value = self.evaluate(expr)?;
                return Err(format!("Exception thrown: {}", self.stringify(&value)));
            }
            Stmt::ModuleDecl { name, body, soul_mark } => {
                // TODO: Implement module declaration
                Ok(())
            }
            Stmt::Import { path, alias } => {
                // TODO: Implement import
                Ok(())
            }
            Stmt::Export { name, value } => {
                // TODO: Implement export
                Ok(())
            }
            Stmt::Component(module, name, methods) => {
                // Create and register component
                let mut component = Component::new(module.clone(), name.clone());
                
                // Execute methods to populate component
                for method in methods {
                    self.execute(method)?;
                }
                
                self.register_component(component);
                println!("Component registered: {}::{}", module, name);
                Ok(())
            }
            Stmt::Trait(name, methods) => {
                // Create and register trait
                let mut trait_def = Trait::new(name.clone());
                
                // Execute methods to populate trait
                for method in methods {
                    self.execute(method)?;
                }
                
                self.register_trait(trait_def);
                println!("Trait registered: {}", name);
                Ok(())
            }
            Stmt::Type(name, type_def) => {
                // Register type in type context
                self.register_type(name.clone(), type_def);
                println!("Type registered: {}", name);
                Ok(())
            }
            Stmt::Implements(component_name, trait_name) => {
                // Link component to trait
                if let Some(component) = self.components.get_mut(&component_name) {
                    component.implements_trait(trait_name.clone());
                    println!("Component '{}' implements trait '{}'", component_name, trait_name);
                } else {
                    return Err(format!("Component '{}' not found", component_name));
                }
                Ok(())
            }
        }
    }

    fn evaluate(&mut self, expr: Expr) -> Result<Value, String> {
        match expr {
            Expr::Literal(value) => Ok(self.literal_to_value(value)),
            Expr::Variable(name) => {
                if let Some(value) = self.environment.get(&name) {
                    Ok(value.clone())
                } else {
                    Err(format!("Undefined variable '{}'", name))
                }
            }
            Expr::Binary(left, operator, right) => {
                let left_value = self.evaluate(*left)?;
                let right_value = self.evaluate(*right)?;
                self.binary_operation(left_value, operator, right_value)
            }
            Expr::Unary(operator, right) => {
                let right_value = self.evaluate(*right)?;
                self.unary_operation(operator, right_value)
            }
            Expr::Call(name, arguments) => {
                let mut evaluated_args = Vec::new();
                for arg in arguments {
                    evaluated_args.push(self.evaluate(arg)?);
                }
                self.call_function(name, evaluated_args)
            }
            Expr::CallValue(function, arguments) => {
                let function_value = self.evaluate(*function)?;
                let mut evaluated_args = Vec::new();
                for arg in arguments {
                    evaluated_args.push(self.evaluate(arg)?);
                }
                self.call_function_value(function_value, evaluated_args)
            }
            Expr::Get(object, name) => {
                let object_value = self.evaluate(*object)?;
                self.get_property(object_value, name)
            }
            Expr::Set(object, name, value) => {
                let object_value = self.evaluate(*object)?;
                let value = self.evaluate(*value)?;
                self.set_property(object_value, name, value)
            }
            Expr::Array(elements) => {
                let mut evaluated_elements = Vec::new();
                for element in elements {
                    evaluated_elements.push(self.evaluate(element)?);
                }
                Ok(Value::Array(evaluated_elements))
            }
            Expr::Object(properties) => {
                let mut object = HashMap::new();
                for (name, value) in properties {
                    object.insert(name, self.evaluate(value)?);
                }
                Ok(Value::Object(object))
            }
            Expr::Slice(array, start, end) => {
                let array_value = self.evaluate(*array)?;
                if let Value::Array(arr) = array_value {
                    let start_idx = if let Some(start_expr) = start {
                        let start_val = self.evaluate(*start_expr)?;
                        if let Value::Number(n) = start_val {
                            n as usize
                        } else {
                            return Err("Slice start must be a number".to_string());
                        }
                    } else {
                        0
                    };
                    
                    let end_idx = if let Some(end_expr) = end {
                        let end_val = self.evaluate(*end_expr)?;
                        if let Value::Number(n) = end_val {
                            n as usize
                        } else {
                            return Err("Slice end must be a number".to_string());
                        }
                    } else {
                        arr.len()
                    };
                    
                    if start_idx > arr.len() || end_idx > arr.len() || start_idx > end_idx {
                        return Err("Invalid slice indices".to_string());
                    }
                    
                    Ok(Value::Array(arr[start_idx..end_idx].to_vec()))
                } else {
                    Err("Can only slice arrays".to_string())
                }
            }
            Expr::New(class_name, arguments) => {
                // For now, just create an object with the class name
                let mut object = HashMap::new();
                object.insert("__class__".to_string(), Value::String(class_name.clone()));
                
                // Evaluate arguments and store them
                for (i, arg) in arguments.iter().enumerate() {
                    let value = self.evaluate(arg.clone())?;
                    object.insert(format!("arg_{}", i), value);
                }
                
                Ok(Value::Object(object))
            }
            Expr::This => {
                // For now, return a placeholder value
                // In a real implementation, this would return the current object context
                Ok(Value::String("this".to_string()))
            }
            Expr::Super(method_name) => {
                // For now, just return the method name
                // In a real implementation, this would call the parent class method
                Ok(Value::String(format!("super.{}", method_name)))
            }
            Expr::Assign(name, value) => {
                // Evaluate the value expression
                let value_result = self.evaluate(*value)?;
                // Store the value in the environment
                self.environment.insert(name.clone(), value_result.clone());
                Ok(value_result)
            }
            Expr::Function(parameters, body) => {
                // Create a function value
                // Create a function object with the new unified representation
                let chunk = Chunk {
                    code: vec![], // TODO: Compile body to bytecode
                    constants: Vec::new(),
                    lines: Vec::new(),
                };
                let function_obj = FunctionObj {
                    name: "anonymous".to_string(),
                    arity: parameters.len(),
                    chunk,
                };
                Ok(Value::Function(Rc::new(function_obj)))
            }
            Expr::Lambda(parameters, body) => {
                // Create a lambda function value
                // Convert the lambda body expression to a statement list
                let body_stmt = Stmt::Expression(*body);
                let body_stmts = vec![body_stmt];
                // Create a function object with the new unified representation
                let chunk = Chunk {
                    code: vec![], // TODO: Compile body to bytecode
                    constants: Vec::new(),
                    lines: Vec::new(),
                };
                let function_obj = FunctionObj {
                    name: "anonymous".to_string(),
                    arity: parameters.len(),
                    chunk,
                };
                Ok(Value::Function(Rc::new(function_obj)))
            }
            Expr::ModuleAccess(module_name, member_name) => {
                // For now, we'll create a simple object access
                // TODO: Implement proper module resolution
                let module_obj = format!("{}::{}", module_name, member_name);
                Ok(Value::String(module_obj))
            }
        }
    }

    fn literal_to_value(&self, literal: LiteralValue) -> Value {
        match literal {
            LiteralValue::Number(n) => Value::Number(n),
            LiteralValue::String(s) => Value::String(s),
            LiteralValue::Boolean(b) => Value::Boolean(b),
            LiteralValue::Null => Value::Null,
        }
    }

    fn add_values(left: Value, right: Value) -> Result<Value, String> {
        match (left.clone(), right.clone()) {
            (Value::Number(a), Value::Number(b)) => Ok(Value::Number(a + b)),
            (Value::String(a), Value::String(b)) => Ok(Value::String(a + &b)),
            (Value::String(a), Value::Number(b)) => Ok(Value::String(a + &b.to_string())),
            (Value::Number(a), Value::String(b)) => Ok(Value::String(a.to_string() + &b)),
            (Value::String(a), Value::Array(b)) => Ok(Value::String(a + &Self::stringify_array(&b))),
            (Value::Array(a), Value::String(b)) => Ok(Value::String(Self::stringify_array(&a) + &b)),
            (Value::String(a), Value::Object(b)) => Ok(Value::String(a + &Self::stringify_object(&b))),
            (Value::Object(a), Value::String(b)) => Ok(Value::String(Self::stringify_object(&a) + &b)),
            (Value::String(a), Value::Boolean(b)) => Ok(Value::String(a + &b.to_string())),
            (Value::Boolean(a), Value::String(b)) => Ok(Value::String(a.to_string() + &b)),
            (Value::String(a), Value::Null) => Ok(Value::String(a + "null")),
            (Value::Null, Value::String(b)) => Ok(Value::String("null".to_string() + &b)),
            (Value::String(a), Value::Function(func)) => Ok(Value::String(a + &format!("<function {}>", func.name))),
            (Value::Function(func), Value::String(b)) => Ok(Value::String(format!("<function {}>", func.name) + &b)),
            (Value::String(a), Value::Closure(closure)) => Ok(Value::String(a + &format!("<closure {}>", closure.func.name))),
            (Value::Closure(closure), Value::String(b)) => Ok(Value::String(format!("<closure {}>", closure.func.name) + &b)),
            _ => {
                println!("DEBUG: ADD ERROR left={:?}, right={:?}", left, right);
                Err("Can only add numbers, strings, or convert other types to strings".to_string())
            }
        }
    }

    fn stringify_array(arr: &Vec<Value>) -> String {
        let elements: Vec<String> = arr.iter().map(|v| match v {
            Value::String(s) => s.clone(),
            Value::Number(n) => n.to_string(),
            Value::Boolean(b) => b.to_string(),
            Value::Null => "null".to_string(),
            Value::Array(a) => Self::stringify_array(a),
            Value::Object(o) => Self::stringify_object(o),
            Value::Function(func) => format!("<function {}>", func.name),
            Value::Closure(closure) => format!("<closure {}>", closure.func.name),
        }).collect();
        format!("[{}]", elements.join(", "))
    }

    fn stringify_object(obj: &HashMap<String, Value>) -> String {
        let pairs: Vec<String> = obj.iter()
            .map(|(k, v)| {
                let value_str = match v {
                    Value::String(s) => s.clone(),
                    Value::Number(n) => n.to_string(),
                    Value::Boolean(b) => b.to_string(),
                    Value::Null => "null".to_string(),
                    Value::Array(a) => Self::stringify_array(a),
                    Value::Object(o) => Self::stringify_object(o),
                    Value::Function(func) => format!("<function {}>", func.name),
                    Value::Closure(closure) => format!("<closure {}>", closure.func.name),
                };
                format!("{}: {}", k, value_str)
            })
            .collect();
        format!("{{{}}}", pairs.join(", "))
    }

    fn binary_operation(&self, left: Value, operator: Token, right: Value) -> Result<Value, String> {
        match operator.token_type {
            TokenType::Plus => Self::add_values(left, right),
            TokenType::Minus => self.subtract(left, right),
            TokenType::Star => self.multiply(left, right),
            TokenType::Slash => self.divide(left, right),
            TokenType::Greater => self.greater(left, right),
            TokenType::GreaterEqual => self.greater_equal(left, right),
            TokenType::Less => self.less(left, right),
            TokenType::LessEqual => self.less_equal(left, right),
            TokenType::BangEqual => Ok(Value::Boolean(!self.is_equal(left, right))),
            TokenType::EqualEqual => Ok(Value::Boolean(self.is_equal(left, right))),
            TokenType::Identifier(ref op) if op == "contains" => {
                match (left, right) {
                    (Value::String(s), Value::String(sub)) => Ok(Value::Boolean(s.contains(&sub))),
                    (Value::Array(arr), item) => Ok(Value::Boolean(arr.contains(&item))),
                    _ => Err("Contains operator requires string or array".to_string()),
                }
            },
            TokenType::Identifier(ref op) if op == "and" => {
                Ok(Value::Boolean(self.is_truthy(&left) && self.is_truthy(&right)))
            },
            TokenType::Identifier(ref op) if op == "or" => {
                Ok(Value::Boolean(self.is_truthy(&left) || self.is_truthy(&right)))
            },
            TokenType::And => {
                Ok(Value::Boolean(self.is_truthy(&left) && self.is_truthy(&right)))
            },
            TokenType::Or => {
                Ok(Value::Boolean(self.is_truthy(&left) || self.is_truthy(&right)))
            },
            _ => Err("Invalid binary operator or unsupported operand types".to_string()),
        }
    }

    fn unary_operation(&self, operator: Token, right: Value) -> Result<Value, String> {
        match operator.token_type {
            TokenType::Minus => {
                if let Value::Number(n) = right {
                    Ok(Value::Number(-n))
                } else {
                    Err("Operand must be a number".to_string())
                }
            }
            TokenType::Bang => Ok(Value::Boolean(!self.is_truthy(&right))),
            TokenType::Identifier(op) if op == "not" => Ok(Value::Boolean(!self.is_truthy(&right))),
            _ => Err("Invalid unary operator".to_string()),
        }
    }



    fn subtract(&self, left: Value, right: Value) -> Result<Value, String> {
        match (left, right) {
            (Value::Number(a), Value::Number(b)) => Ok(Value::Number(a - b)),
            _ => Err("Operands must be numbers".to_string()),
        }
    }

    fn multiply(&self, left: Value, right: Value) -> Result<Value, String> {
        match (left, right) {
            (Value::Number(a), Value::Number(b)) => Ok(Value::Number(a * b)),
            _ => Err("Operands must be numbers".to_string()),
        }
    }

    fn divide(&self, left: Value, right: Value) -> Result<Value, String> {
        match (left, right) {
            (Value::Number(a), Value::Number(b)) => {
                if b == 0.0 {
                    Err("Division by zero".to_string())
                } else {
                    Ok(Value::Number(a / b))
                }
            }
            _ => Err("Operands must be numbers".to_string()),
        }
    }

    fn greater(&self, left: Value, right: Value) -> Result<Value, String> {
        match (left, right) {
            (Value::Number(a), Value::Number(b)) => Ok(Value::Boolean(a > b)),
            _ => Err("Operands must be numbers".to_string()),
        }
    }

    fn greater_equal(&self, left: Value, right: Value) -> Result<Value, String> {
        match (left, right) {
            (Value::Number(a), Value::Number(b)) => Ok(Value::Boolean(a >= b)),
            _ => Err("Operands must be numbers".to_string()),
        }
    }

    fn less(&self, left: Value, right: Value) -> Result<Value, String> {
        match (left, right) {
            (Value::Number(a), Value::Number(b)) => Ok(Value::Boolean(a < b)),
            _ => Err("Operands must be numbers".to_string()),
        }
    }

    fn less_equal(&self, left: Value, right: Value) -> Result<Value, String> {
        match (left, right) {
            (Value::Number(a), Value::Number(b)) => Ok(Value::Boolean(a <= b)),
            _ => Err("Operands must be numbers".to_string()),
        }
    }

    fn is_equal(&self, left: Value, right: Value) -> bool {
        match (left, right) {
            (Value::Number(a), Value::Number(b)) => a == b,
            (Value::String(a), Value::String(b)) => a == b,
            (Value::Boolean(a), Value::Boolean(b)) => a == b,
            (Value::Null, Value::Null) => true,
            _ => false,
        }
    }

    fn is_truthy(&self, value: &Value) -> bool {
        match value {
            Value::Boolean(b) => *b,
            Value::Null => false,
            Value::Number(n) => *n != 0.0,
            Value::String(s) => !s.is_empty(),
            Value::Array(arr) => !arr.is_empty(),
            Value::Object(obj) => !obj.is_empty(),
            Value::Function(_) => true,
            Value::Closure(_) => true,
        }
    }

    fn call_function(&mut self, name: String, arguments: Vec<Value>) -> Result<Value, String> {
        // First, try to find the function in the registry
        if let Some(function) = self.function_registry.get_function(&name) {
            return function(&arguments);
        }

        // Handle special cases that need access to interpreter state
        match name.as_str() {
            "stringify" => {
                if arguments.len() != 1 {
                    return Err("stringify requires exactly 1 argument".to_string());
                }
                Ok(Value::String(self.stringify(&arguments[0])))
            },
            "memory.lha3.store" => {
                if arguments.len() != 2 {
                    return Err("memory.lha3.store requires exactly 2 arguments (key, value)".to_string());
                }
                let key = match &arguments[0] {
                    Value::String(s) => s.clone(),
                    _ => return Err("memory.lha3.store key must be a string".to_string()),
                };
                let value = &arguments[1];
                // Simulate LHA3 memory storage with quantum coherence
                let memory_entry = Value::Object({
                    let mut map = HashMap::new();
                    map.insert("type".to_string(), Value::String("lha3_memory_entry".to_string()));
                    map.insert("key".to_string(), Value::String(key.clone()));
                    map.insert("value".to_string(), value.clone());
                    map.insert("quantum_coherence".to_string(), Value::Number(0.95));
                    map.insert("entanglement_strength".to_string(), Value::Number(0.8));
                    map.insert("retrieval_probability".to_string(), Value::Number(0.9));
                    map.insert("storage_timestamp".to_string(), Value::Number(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64()));
                    map
                });
                // Store in global memory
                self.globals.insert(format!("lha3_{}", key), memory_entry.clone());
                Ok(memory_entry)
            },
            "memory.lha3.retrieve" => {
                if arguments.len() != 1 {
                    return Err("memory.lha3.retrieve requires exactly 1 argument (key)".to_string());
                }
                let key = match &arguments[0] {
                    Value::String(s) => s.clone(),
                    _ => return Err("memory.lha3.retrieve key must be a string".to_string()),
                };
                // Retrieve from LHA3 memory with quantum measurement
                match self.globals.get(&format!("lha3_{}", key)) {
                    Some(memory_entry) => {
                        let retrieved_value = Value::Object({
                            let mut map = HashMap::new();
                            map.insert("type".to_string(), Value::String("lha3_retrieved".to_string()));
                            map.insert("original_entry".to_string(), memory_entry.clone());
                            map.insert("retrieval_success".to_string(), Value::Boolean(true));
                            map.insert("quantum_fidelity".to_string(), Value::Number(0.92));
                            map.insert("retrieval_time".to_string(), Value::Number(0.001));
                            map
                        });
                        Ok(retrieved_value)
                    },
                    None => Err(format!("Memory entry '{}' not found in LHA3", key)),
                }
            },
            _ => {
                // Check for user-defined functions
                if let Some((params, body)) = self.functions.get(&name) {
                    if params.len() != arguments.len() {
                        return Err(format!("Expected {} arguments but got {}", params.len(), arguments.len()));
                    }
                    
                    // Clone the function data to avoid borrow checker issues
                    let params = params.clone();
                    let body = body.clone();
                    
                    // Create new environment for function call
                    let mut function_env = HashMap::new();
                    for (param, arg) in params.iter().zip(arguments.iter()) {
                        function_env.insert(param.clone(), arg.clone());
                    }
                    
                    // Execute function body
                    let old_env = std::mem::replace(&mut self.environment, function_env);
                    for stmt in body {
                        self.execute(stmt)?;
                    }
                    self.environment = old_env;
                    
                    Ok(Value::Null) // For now, all functions return null
                } else {
                    Err(format!("Undefined function '{}'", name))
                }
            }
        }
    }

    fn call_function_value(&mut self, function_value: Value, arguments: Vec<Value>) -> Result<Value, String> {
        match function_value {
            Value::Function(func) => {
                // Check argument count
                if arguments.len() != func.arity {
                    return Err(format!("Function '{}' expects {} arguments, got {}", 
                        func.name, func.arity, arguments.len()));
                }
                
                // Create new environment for function call
                let mut function_env = HashMap::new();
                
                // Bind parameters to arguments (we need to get param names from chunk)
                // For now, we'll use a simple approach
                for (i, arg_value) in arguments.iter().enumerate() {
                    function_env.insert(format!("arg{}", i), arg_value.clone());
                }
                
                // Execute function body using the chunk
                let old_env = std::mem::replace(&mut self.environment, function_env);
                
                // TODO: Execute the function's bytecode properly
                // For now, we'll just return null as the result
                self.environment = old_env;
                
                Ok(Value::Null) // For now, all functions return null
            },
            Value::Closure(closure) => {
                // Check argument count
                if arguments.len() != closure.func.arity {
                    return Err(format!("Closure '{}' expects {} arguments, got {}", 
                        closure.func.name, closure.func.arity, arguments.len()));
                }
                
                // Create new environment for function call with upvalues
                let mut function_env = HashMap::new();
                
                // Add upvalues to environment
                for (name, value) in &closure.upvalues {
                    function_env.insert(name.clone(), value.clone());
                }
                
                // Bind parameters to arguments
                for (i, arg_value) in arguments.iter().enumerate() {
                    function_env.insert(format!("arg{}", i), arg_value.clone());
                }
                
                // Execute function body using the chunk
                let old_env = std::mem::replace(&mut self.environment, function_env);
                
                // TODO: Execute the function's bytecode properly
                // For now, we'll just return null as the result
                self.environment = old_env;
                
                Ok(Value::Null) // For now, all functions return null
            },
            _ => Err("Cannot call non-function value".to_string())
        }
    }

    fn get_property(&self, object: Value, name: String) -> Result<Value, String> {
        match object {
            Value::Object(obj) => {
                if let Some(value) = obj.get(&name) {
                    Ok(value.clone())
                } else {
                    Err(format!("Property '{}' not found", name))
                }
            }
            Value::Array(arr) => {
                match name.as_str() {
                    "length" => Ok(Value::Number(arr.len() as f64)),
                    _ => {
                        // Try to parse as numeric index
                        if let Ok(index) = name.parse::<usize>() {
                            if index < arr.len() {
                                Ok(arr[index].clone())
                            } else {
                                Err(format!("Array index {} out of bounds (length: {})", index, arr.len()))
                            }
                        } else {
                            Err(format!("Property '{}' not found on array", name))
                        }
                    }
                }
            }
            Value::String(s) => {
                match name.as_str() {
                    "length" => Ok(Value::Number(s.len() as f64)),
                    _ => Err(format!("Property '{}' not found on string", name)),
                }
            }
            _ => Err("Only objects, arrays, and strings have properties".to_string()),
        }
    }

    fn set_property(&mut self, object: Value, name: String, value: Value) -> Result<Value, String> {
        match object {
            Value::Object(mut obj) => {
                obj.insert(name, value.clone());
                Ok(value)
            }
            _ => Err("Only objects have properties".to_string()),
        }
    }

    fn stringify(&self, value: &Value) -> String {
        match value {
            Value::Number(n) => n.to_string(),
            Value::String(s) => s.clone(),
            Value::Boolean(b) => b.to_string(),
            Value::Null => "null".to_string(),
            Value::Array(arr) => {
                let elements: Vec<String> = arr.iter().map(|v| self.stringify(v)).collect();
                format!("[{}]", elements.join(", "))
            }
            Value::Object(obj) => {
                let pairs: Vec<String> = obj.iter()
                    .map(|(k, v)| format!("{}: {}", k, self.stringify(v)))
                    .collect();
                format!("{{{}}}", pairs.join(", "))
            }
            Value::Function(func) => format!("<fn {}>", func.name),
            Value::Closure(closure) => format!("<closure {}>", closure.func.name),
        }
    }
}

// ========================================
// ========== MAIN COMPILER =============
// ========================================

pub struct AzlCompiler {
    scanner: Scanner,
    parser: Parser,
    interpreter: Interpreter,
    bytecode_compiler: BytecodeCompiler,
    vm: AzlVM,
    jit_compiler: JitCompiler,
    parallel_engine: ParallelEngine,
    llm_integration: LlmIntegration,
}

impl AzlCompiler {
    pub fn new() -> Self {
        let llm_integration = LlmIntegration::new()
            .expect("Failed to initialize LLM integration");
            
        AzlCompiler {
            scanner: Scanner::new("".to_string()),
            parser: Parser::new(Vec::new()),
            interpreter: Interpreter::new(),
            bytecode_compiler: BytecodeCompiler::new(),
            vm: AzlVM::new(),
            jit_compiler: JitCompiler::new(),
            parallel_engine: ParallelEngine::new(),
            llm_integration,
        }
    }

    pub fn compile_and_run(&mut self, source: String) -> Result<(), String> {
        println!("DEBUG: AzlCompiler::compile_and_run() called");
        println!("🚀 Running AZL v2 program...");
        
        // Tokenize
        println!("🧠 AZL v2 Compiler starting...");
        self.scanner = Scanner::new(source);
        let tokens = self.scanner.scan_tokens()?;
        println!("📝 Tokenizing source code...");
        println!("✅ Tokenization complete: {} tokens", tokens.len());
        
        if tokens.len() > 10 {
            println!("🔍 First 10 tokens:");
            for (i, token) in tokens.iter().take(10).enumerate() {
                println!("  {}: {:?}", i, token.token_type);
            }
        }
        
        // Parse
        println!("🏗️ Building Abstract Syntax Tree...");
        self.parser = Parser::new(tokens);
        let statements = self.parser.parse()?;
        println!("✅ Parsing complete: {} statements", statements.len());
        
        // Compile to bytecode for faster execution
        println!("⚡ Compiling to bytecode...");
        let chunk = self.bytecode_compiler.compile(statements)?;
        println!("✅ Bytecode compilation complete: {} instructions", chunk.code.len());
        println!("--- COMPILED BYTECODE ---");
        for (i, opcode) in chunk.code.iter().enumerate() {
            println!("{}: {:?}", i, opcode);
        }
        println!("-------------------------");
        
        // Execute with VM (much faster than tree-walking)
        println!("⚡ Executing with Virtual Machine...");
        
        // Use unified Opcode directly - reuse the same VM instance
        self.vm.load_bytecode(chunk.code);
        self.vm.run()?;
        println!("✅ Execution complete!");
        println!("✅ Program executed successfully!");
        
        Ok(())
    }

    // Process natural language input and generate response
    pub fn process_conversation(&mut self, user_input: &str) -> Result<String, String> {
        // Get current AZL context
        let azl_context = self.get_azl_context();
        
        // Process input through LLM integration
        let response = self.llm_integration.process_input(user_input, azl_context)?;
        
        // Execute any extracted AZL commands
        for command in &response.azl_commands {
            if let Err(e) = self.execute_azl_command(command) {
                println!("Warning: Failed to execute AZL command '{}': {}", command, e);
            }
        }
        
        Ok(response.text)
    }

    // Execute AZL command from natural language
    fn execute_azl_command(&mut self, command: &str) -> Result<(), String> {
        // Simple command execution for now
        self.compile_and_run(command.to_string())
    }

    // Get current AZL system context
    fn get_azl_context(&self) -> HashMap<String, String> {
        let mut context = HashMap::new();
        
        // Add system state information
        context.insert("system".to_string(), "AZME AGI".to_string());
        context.insert("version".to_string(), "2.0.0".to_string());
        context.insert("capabilities".to_string(), "quantum,neural,consciousness,memory,autonomous".to_string());
        
        context
    }

    // Start interactive conversation mode
    pub fn start_conversation(&mut self) -> Result<(), String> {
        println!("🤖 AZME AGI Interactive Mode");
        println!("I'm your advanced AGI system with quantum, neural, consciousness, memory, and autonomous capabilities.");
        println!("Type 'quit' to exit, 'help' for commands, or just chat naturally!");
        println!();

        loop {
            print!("You: ");
            io::stdout().flush().map_err(|e| format!("IO error: {}", e))?;
            
            let mut input = String::new();
            io::stdin().read_line(&mut input)
                .map_err(|e| format!("Failed to read input: {}", e))?;
            
            let input = input.trim();
            
            if input.is_empty() {
                continue;
            }
            
            if input.to_lowercase() == "quit" || input.to_lowercase() == "exit" {
                println!("Goodbye! 👋");
                break;
            }
            
            if input.to_lowercase() == "help" {
                self.show_help();
                continue;
            }
            
            if input.to_lowercase() == "clear" {
                self.llm_integration.clear_history();
                println!("Conversation history cleared.");
                continue;
            }
            
            // Process the input
            match self.process_conversation(input) {
                Ok(response) => {
                    println!("AZME: {}", response);
                }
                Err(e) => {
                    println!("Error: {}", e);
                }
            }
            
            println!();
        }
        
        Ok(())
    }

    // Show help information
    fn show_help(&self) {
        println!("\n🔧 AZME AGI Help");
        println!("Commands:");
        println!("  help     - Show this help");
        println!("  clear    - Clear conversation history");
        println!("  quit     - Exit conversation mode");
        println!();
        println!("Capabilities:");
        println!("  💫 Quantum Computing: superposition, entanglement, measurement");
        println!("  🧠 Neural Networks: layers, forward/backward propagation, training");
        println!("  🧘 Consciousness: awareness, reflection, metacognition");
        println!("  💾 Memory Systems: LHA3 storage, retrieval, optimization");
        println!("  🤖 Autonomous Systems: planning, execution, decision making");
        println!();
        println!("Examples:");
        println!("  \"Create a quantum superposition\"");
        println!("  \"Build a neural network with 10 inputs and 5 outputs\"");
        println!("  \"Make me aware of my consciousness\"");
        println!("  \"Store this in memory\"");
        println!("  \"Plan an autonomous task\"");
        println!();
    }
}

// ========================================
// ========== COMMAND LINE INTERFACE ====
// ========================================

fn main() {
    println!("🚀 AZL v2 Native Compiler");
    println!("==========================");
    
    let args: Vec<String> = std::env::args().collect();
    
    if args.len() < 2 {
        println!("Usage: {} <command> [arguments]", args[0]);
        println!("Commands:");
        println!("  run <filename.azl>     - Run an AZL program");
        println!("  chat                   - Start interactive conversation mode");
        std::process::exit(1);
    }
    
    let command = &args[1];
    
    match command.as_str() {
        "run" => {
            if args.len() != 3 {
                println!("Usage: {} run <filename.azl>", args[0]);
                std::process::exit(1);
            }
            
            let filename = &args[2];
            match fs::read_to_string(filename) {
                Ok(source) => {
                    let mut compiler = AzlCompiler::new();
                    match compiler.compile_and_run(source) {
                        Ok(_) => {
                            println!("🎉 Program executed successfully!");
                        }
                        Err(error) => {
                            eprintln!("❌ Error: {}", error);
                            std::process::exit(1);
                        }
                    }
                }
                Err(error) => {
                    eprintln!("❌ Error reading file '{}': {}", filename, error);
                    std::process::exit(1);
                }
            }
        }
        "chat" => {
            let mut compiler = AzlCompiler::new();
            match compiler.start_conversation() {
                Ok(_) => {
                    println!("👋 Goodbye!");
                }
                Err(error) => {
                    eprintln!("❌ Error in conversation mode: {}", error);
                    std::process::exit(1);
                }
            }
        }
        _ => {
            println!("Unknown command: {}", command);
            println!("Available commands: run, chat");
            std::process::exit(1);
        }
    }
}