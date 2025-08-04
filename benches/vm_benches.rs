use criterion::{criterion_group, criterion_main, Criterion};
use azl_vm::{AzlVM, Opcode, Value, verify_chunk, peephole_optimize};

fn bench_arithmetic_operations(c: &mut Criterion) {
    let mut group = c.benchmark_group("arithmetic");
    
    // Benchmark addition
    group.bench_function("add_1000", |b| {
        b.iter(|| {
            let mut vm = AzlVM::new();
            let mut code = Vec::new();
            
            // Push 1000 numbers and add them
            for i in 0..1000 {
                code.push(Opcode::Push(Value::Number(i as f64)));
            }
            for _ in 1..1000 {
                code.push(Opcode::Add);
            }
            code.push(Opcode::Halt);
            
            vm.load_bytecode(code);
            vm.run().unwrap();
        });
    });
    
    // Benchmark multiplication
    group.bench_function("mul_100", |b| {
        b.iter(|| {
            let mut vm = AzlVM::new();
            let mut code = Vec::new();
            
            // Push 100 numbers and multiply them
            for i in 1..101 {
                code.push(Opcode::Push(Value::Number(i as f64)));
            }
            for _ in 1..100 {
                code.push(Opcode::Mul);
            }
            code.push(Opcode::Halt);
            
            vm.load_bytecode(code);
            vm.run().unwrap();
        });
    });
    
    group.finish();
}

fn bench_function_calls(c: &mut Criterion) {
    let mut group = c.benchmark_group("function_calls");
    
    group.bench_function("call_1000", |b| {
        b.iter(|| {
            let mut vm = AzlVM::new();
            let mut code = Vec::new();
            
            // Create a simple function and call it 1000 times
            for _ in 0..1000 {
                code.push(Opcode::Push(Value::Number(5.0)));
                code.push(Opcode::Push(Value::Number(3.0)));
                code.push(Opcode::Add);
                code.push(Opcode::Pop); // Pop result
            }
            code.push(Opcode::Halt);
            
            vm.load_bytecode(code);
            vm.run().unwrap();
        });
    });
    
    group.finish();
}

fn bench_stack_operations(c: &mut Criterion) {
    let mut group = c.benchmark_group("stack_operations");
    
    group.bench_function("dup_swap_1000", |b| {
        b.iter(|| {
            let mut vm = AzlVM::new();
            let mut code = Vec::new();
            
            // Push a value and do dup/swap operations
            code.push(Opcode::Push(Value::Number(42.0)));
            for _ in 0..1000 {
                code.push(Opcode::Dup);
                code.push(Opcode::Swap);
                code.push(Opcode::Pop);
            }
            code.push(Opcode::Halt);
            
            vm.load_bytecode(code);
            vm.run().unwrap();
        });
    });
    
    group.finish();
}

fn bench_bytecode_verification(c: &mut Criterion) {
    let mut group = c.benchmark_group("verification");
    
    group.bench_function("verify_large_chunk", |b| {
        b.iter(|| {
            let mut code = Vec::new();
            
            // Create a large valid bytecode chunk
            for i in 0..1000 {
                code.push(Opcode::Push(Value::Number(i as f64)));
            }
            for _ in 1..1000 {
                code.push(Opcode::Add);
            }
            code.push(Opcode::Halt);
            
            verify_chunk(&code, 0).unwrap();
        });
    });
    
    group.finish();
}

fn bench_peephole_optimization(c: &mut Criterion) {
    let mut group = c.benchmark_group("optimization");
    
    group.bench_function("optimize_identity_ops", |b| {
        b.iter(|| {
            let mut code = Vec::new();
            
            // Create code with many identity operations
            for i in 0..100 {
                code.push(Opcode::Push(Value::Number(i as f64)));
                code.push(Opcode::Push(Value::Number(0.0)));
                code.push(Opcode::Add); // x + 0
                code.push(Opcode::Push(Value::Number(1.0)));
                code.push(Opcode::Mul); // x * 1
            }
            code.push(Opcode::Halt);
            
            peephole_optimize(&mut code);
        });
    });
    
    group.finish();
}

fn bench_serialization(c: &mut Criterion) {
    let mut group = c.benchmark_group("serialization");
    
    group.bench_function("serialize_chunk", |b| {
        b.iter(|| {
            let chunk = azl_vm::Chunk {
                code: vec![
                    Opcode::Push(Value::Number(42.0)),
                    Opcode::Push(Value::Number(10.0)),
                    Opcode::Add,
                    Opcode::Halt,
                ],
                constants: vec![Value::Number(42.0), Value::Number(10.0)],
                lines: vec![1, 1, 1, 1],
            };
            
            let mut buffer = Vec::new();
            azl_vm::write_chunk(&mut buffer, &chunk, "test").unwrap();
        });
    });
    
    group.bench_function("deserialize_chunk", |b| {
        let chunk = azl_vm::Chunk {
            code: vec![
                Opcode::Push(Value::Number(42.0)),
                Opcode::Push(Value::Number(10.0)),
                Opcode::Add,
                Opcode::Halt,
            ],
            constants: vec![Value::Number(42.0), Value::Number(10.0)],
            lines: vec![1, 1, 1, 1],
        };
        
        let mut buffer = Vec::new();
        azl_vm::write_chunk(&mut buffer, &chunk, "test").unwrap();
        
        b.iter(|| {
            let mut reader = std::io::Cursor::new(&buffer);
            azl_vm::read_chunk(&mut reader).unwrap();
        });
    });
    
    group.finish();
}

criterion_group!(
    benches,
    bench_arithmetic_operations,
    bench_function_calls,
    bench_stack_operations,
    bench_bytecode_verification,
    bench_peephole_optimization,
    bench_serialization
);
criterion_main!(benches); 