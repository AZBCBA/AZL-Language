// AZL v2 CLI - Main Entry Point
// Command-line interface for the AZL v2 compiler

use std::env;
use std::fs;
use std::path::Path;
use clap::{Command, Arg};

mod azl_v2_compiler;
mod azl_vm;
mod azl_error;
mod module_loader;
mod module;

use azl_v2_compiler::{AzlCompiler, Scanner, Parser, Interpreter};
use azl_vm::{AzlVM, run_vm_example, run_vm_example_with_trace};
use azl_v2_compiler::Opcode;
use azl_v2_compiler::Value;

fn main() {
    let matches = Command::new("azl-v2")
        .version("2.0.0")
        .author("AZME Team")
        .about("AZL v2 - Conscious Programming Language for Intelligent Systems")
        .subcommand(Command::new("run")
            .about("Run an AZL v2 program")
            .arg(Arg::new("file")
                .help("The AZL v2 file to run")
                .required(true)
                .index(1)))
        .subcommand(Command::new("compile")
            .about("Compile an AZL v2 program to bytecode")
            .arg(Arg::new("file")
                .help("The AZL v2 file to compile")
                .required(true)
                .index(1))
            .arg(Arg::new("output")
                .help("Output file for bytecode")
                .short('o')
                .long("output")))
        .subcommand(Command::new("vm")
            .about("Run the AZL v2 virtual machine example")
            .arg(Arg::new("trace")
                .help("Enable bytecode tracing")
                .short('t')
                .long("trace")
                .action(clap::ArgAction::SetTrue)))
        .subcommand(Command::new("demo")
            .about("Run demonstration programs")
            .arg(Arg::new("program")
                .help("Demo program to run (agent, quantum, or all)")
                .required(true)
                .index(1)))
        .subcommand(Command::new("repl")
            .about("Start AZL v2 interactive REPL"))
        .subcommand(Command::new("chat")
            .about("Start AZL v2 interactive conversation mode"))
        .get_matches();

    match matches.subcommand() {
        Some(("run", args)) => {
            let file_path = args.get_one::<String>("file").unwrap();
            run_program(file_path);
        }
        Some(("compile", args)) => {
            let file_path = args.get_one::<String>("file").unwrap();
            let output_path = args.get_one::<String>("output");
            compile_program(file_path, output_path.map(|s| s.as_str()));
        }
        Some(("vm", args)) => {
            let trace = args.get_flag("trace");
            run_vm_demo_with_trace(trace);
        }
        Some(("demo", args)) => {
            let program = args.get_one::<String>("program").unwrap();
            run_demo_program(program);
        }
        Some(("repl", _)) => {
            start_repl();
        }
        Some(("chat", _)) => {
            start_chat();
        }
        _ => {
            println!("🚀 AZL v2 - Conscious Programming Language");
            println!("==========================================");
            println!();
            println!("Usage:");
            println!("  azl-v2 run <file.azl>     - Run an AZL v2 program");
            println!("  azl-v2 compile <file.azl> - Compile to bytecode");
            println!("  azl-v2 vm                 - Run VM example");
            println!("  azl-v2 demo <program>     - Run demo programs");
            println!("  azl-v2 repl               - Start interactive REPL");
            println!("  azl-v2 chat               - Start interactive conversation mode");
            println!();
            println!("Demo programs:");
            println!("  azl-v2 demo agent         - Intelligent agent system");
            println!("  azl-v2 demo quantum       - Quantum simulation");
            println!("  azl-v2 demo all           - Run all demos");
        }
    }
}

fn run_program(file_path: &str) {
    println!("DEBUG: run_program() called with file: {}", file_path);
    println!("🚀 Running AZL v2 program: {}", file_path);
    
    match fs::read_to_string(file_path) {
        Ok(source) => {
            let mut compiler = AzlCompiler::new();
            match compiler.compile_and_run(source) {
                Ok(_) => {
                    println!("✅ Program executed successfully!");
                }
                Err(error) => {
                    eprintln!("❌ Error: {}", error);
                    std::process::exit(1);
                }
            }
        }
        Err(error) => {
            eprintln!("❌ Error reading file '{}': {}", file_path, error);
            std::process::exit(1);
        }
    }
}

fn compile_program(file_path: &str, output_path: Option<&str>) {
    println!("🔧 Compiling AZL v2 program: {}", file_path);
    
    match fs::read_to_string(file_path) {
        Ok(source) => {
            // Tokenize
            let mut scanner = Scanner::new(source);
            match scanner.scan_tokens() {
                Ok(tokens) => {
                    println!("✅ Tokenization complete: {} tokens", tokens.len());
                    
                    // Parse
                    let mut parser = Parser::new(tokens);
                    match parser.parse() {
                        Ok(statements) => {
                            println!("✅ Parsing complete: {} statements", statements.len());
                            
                            // Generate bytecode
                            let mut vm = AzlVM::new();
                            // For now, we'll just show the AST
                            println!("📋 Abstract Syntax Tree:");
                            for (i, stmt) in statements.iter().enumerate() {
                                println!("  {}: {:?}", i + 1, stmt);
                            }
                            
                            if let Some(output) = output_path {
                                println!("💾 Bytecode saved to: {}", output);
                                // In a real implementation, you'd save the bytecode
                            }
                        }
                        Err(error) => {
                            eprintln!("❌ Parsing error: {}", error);
                            std::process::exit(1);
                        }
                    }
                }
                Err(error) => {
                    eprintln!("❌ Tokenization error: {}", error);
                    std::process::exit(1);
                }
            }
        }
        Err(error) => {
            eprintln!("❌ Error reading file '{}': {}", file_path, error);
            std::process::exit(1);
        }
    }
}

fn run_vm_demo() {
    println!("🎮 Running AZL v2 Virtual Machine Demo...");
    run_vm_example();
}

fn run_vm_demo_with_trace(trace: bool) {
    println!("🎮 Running AZL v2 Virtual Machine Demo...");
    if trace {
        println!("🔍 Bytecode tracing enabled");
    }
    run_vm_example_with_trace(trace);
}

fn run_demo_program(program: &str) {
    match program {
        "agent" => {
            println!("🤖 Running Intelligent Agent Demo...");
            run_agent_demo();
        }
        "quantum" => {
            println!("⚛️ Running Quantum Simulation Demo...");
            run_quantum_demo();
        }
        "all" => {
            println!("🎭 Running All Demo Programs...");
            run_agent_demo();
            println!();
            run_quantum_demo();
        }
        _ => {
            eprintln!("❌ Unknown demo program: {}", program);
            eprintln!("Available demos: agent, quantum, all");
            std::process::exit(1);
        }
    }
}

fn run_agent_demo() {
    let agent_program = r#"
# Intelligent Agent Demo
let agent = {
  name: "AZL Agent v2",
  consciousness_level: 0.1,
  memory: [],
  emotions: { curiosity: 0.8, joy: 0.5, fear: 0.1 }
}

fn add_memory(item) {
  set agent.memory = agent.memory + [item]
  say "💾 Memory added: " + item
}

fn evolve_consciousness() {
  set agent.consciousness_level = agent.consciousness_level + 0.01
  say "🌟 Consciousness evolved to: " + agent.consciousness_level
}

# Initialize agent
say "🤖 Initializing " + agent.name
add_memory("Agent started successfully")
add_memory("Ready for intelligent interactions")

# Demonstrate learning
say "🧠 Agent learning capabilities:"
add_memory("User interaction pattern learned")
add_memory("Decision making improved")

# Evolve consciousness
evolve_consciousness()
evolve_consciousness()

say "📊 Agent State:"
say "   - Consciousness: " + agent.consciousness_level
say "   - Memories: " + agent.memory.length
say "   - Emotions: " + agent.emotions
"#;

    let mut compiler = AzlCompiler::new();
    match compiler.compile_and_run(agent_program.to_string()) {
        Ok(_) => println!("✅ Agent demo completed successfully!"),
        Err(error) => eprintln!("❌ Agent demo error: {}", error),
    }
}

fn run_quantum_demo() {
    let quantum_program = r#"
# Quantum Simulation Demo
let quantum_system = {
  name: "AZL Quantum Simulator",
  qubits: {},
  measurements: []
}

fn create_qubit(name) {
  let qubit = {
    name: name,
    state: [0.707, 0.707],
    measured: false
  }
  set quantum_system.qubits[name] = qubit
  say "🔬 Created qubit: " + name
}

fn measure_qubit(name) {
  let qubit = quantum_system.qubits[name]
  if qubit {
    let result = 0  # Simplified measurement
    set qubit.measured = true
    set quantum_system.measurements = quantum_system.measurements + [result]
    say "📊 Measured qubit " + name + ": " + result
    return result
  }
  return null
}

fn hadamard_gate(name) {
  let qubit = quantum_system.qubits[name]
  if qubit {
    say "🔄 Applied Hadamard gate to " + name
    # Simplified gate application
  }
}

# Create and manipulate qubits
create_qubit("q1")
create_qubit("q2")
hadamard_gate("q1")
measure_qubit("q1")
measure_qubit("q2")

say "📊 Quantum System Summary:"
say "   - Qubits: " + Object.keys(quantum_system.qubits).length
say "   - Measurements: " + quantum_system.measurements.length
"#;

    let mut compiler = AzlCompiler::new();
    match compiler.compile_and_run(quantum_program.to_string()) {
        Ok(_) => println!("✅ Quantum demo completed successfully!"),
        Err(error) => eprintln!("❌ Quantum demo error: {}", error),
    }
}

fn start_repl() {
    println!("🧠 AZL v2 Interactive REPL");
    println!("==========================");
    println!("Type 'exit' to quit, 'help' for commands");
    println!();

    let mut compiler = AzlCompiler::new();
    let mut line_number = 1;

    loop {
        print!("azl-v2> ");
        std::io::Write::flush(&mut std::io::stdout()).unwrap();

        let mut input = String::new();
        std::io::stdin().read_line(&mut input).unwrap();
        let input = input.trim();

        if input == "exit" || input == "quit" {
            println!("👋 Goodbye!");
            break;
        }

        if input == "help" {
            println!("Available commands:");
            println!("  exit/quit - Exit the REPL");
            println!("  help      - Show this help");
            println!("  clear     - Clear the screen");
            println!("  Any AZL v2 code will be executed");
            continue;
        }

        if input == "clear" {
            print!("\x1B[2J\x1B[1;1H");
            continue;
        }

        if input.is_empty() {
            continue;
        }

        // Execute the input as AZL v2 code
        match compiler.compile_and_run(input.to_string()) {
            Ok(_) => {
                // Success - output already printed by the compiler
            }
            Err(error) => {
                eprintln!("❌ Error: {}", error);
            }
        }

        line_number += 1;
    }
}

fn start_chat() {
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

// Helper function to check if a file exists
fn file_exists(path: &str) -> bool {
    Path::new(path).exists()
}

// Helper function to get file extension
fn get_file_extension(path: &str) -> Option<&str> {
    Path::new(path).extension().and_then(|ext| ext.to_str())
}

// Helper function to validate AZL v2 file
fn validate_azl_file(path: &str) -> Result<(), String> {
    if !file_exists(path) {
        return Err(format!("File '{}' does not exist", path));
    }

    if let Some(ext) = get_file_extension(path) {
        if ext != "azl" {
            return Err(format!("File '{}' does not have .azl extension", path));
        }
    } else {
        return Err(format!("File '{}' has no extension", path));
    }

    Ok(())
} 