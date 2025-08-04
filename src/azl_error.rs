use std::fmt;

#[derive(Debug, Clone)]
pub struct CallSite {
    pub function_name: String,
    pub line: usize,
    pub column: usize,
    pub instruction: String,
}

#[derive(Debug, Clone)]
pub enum ErrorKind {
    Runtime,
    Compilation,
    Type,
    DivisionByZero,
    StackUnderflow,
    VariableNotFound,
    FunctionNotFound,
    // Future metaphysical errors
    ConsciousnessError,
    SoulSignatureMismatch,
}

#[derive(Debug, Clone)]
pub struct AzlError {
    pub kind: ErrorKind,
    pub message: String,
    pub stack_trace: Vec<CallSite>,
    pub soul_signature: Option<u64>,
}

impl AzlError {
    pub fn new(kind: ErrorKind, message: String) -> Self {
        AzlError {
            kind,
            message,
            stack_trace: Vec::new(),
            soul_signature: None,
        }
    }

    pub fn with_stack_trace(mut self, stack_trace: Vec<CallSite>) -> Self {
        self.stack_trace = stack_trace;
        self
    }

    pub fn with_soul_signature(mut self, signature: u64) -> Self {
        self.soul_signature = Some(signature);
        self
    }

    pub fn is_catchable(&self) -> bool {
        matches!(self.kind, 
            ErrorKind::Runtime | 
            ErrorKind::DivisionByZero | 
            ErrorKind::StackUnderflow |
            ErrorKind::VariableNotFound |
            ErrorKind::FunctionNotFound
        )
    }
}

impl fmt::Display for AzlError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{:?}] {}", self.kind, self.message)?;
        
        if !self.stack_trace.is_empty() {
            write!(f, "\nStack trace:")?;
            for (i, site) in self.stack_trace.iter().enumerate() {
                write!(f, "\n  {}: {} at {}:{}:{}", 
                    i, site.function_name, site.line, site.column, site.instruction)?;
            }
        }
        
        if let Some(signature) = self.soul_signature {
            write!(f, "\nSoul signature: {:x}", signature)?;
        }
        
        Ok(())
    }
}

impl std::error::Error for AzlError {}

// Error context for try/catch blocks
#[derive(Debug, Clone)]
pub enum ErrorContext {
    TryCatch { 
        handler_addr: usize,
        try_start: usize,
        try_end: usize,
    },
    // Future: Async/Generics contexts
    Async { task_id: String },
    Generic { type_params: Vec<String> },
}

impl ErrorContext {
    pub fn try_catch(handler_addr: usize, try_start: usize, try_end: usize) -> Self {
        ErrorContext::TryCatch { 
            handler_addr, 
            try_start, 
            try_end 
        }
    }
} 