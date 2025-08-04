use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};
use std::fs;
use crate::azl_error::{AzlError, ErrorKind};
use crate::azl_v2_compiler::{Stmt, Value};

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ModulePath {
    pub path: String,
    pub origin: ModuleOrigin,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum ModuleOrigin {
    Filesystem(PathBuf),
    Network(String),
    Memory(Vec<u8>),
}

#[derive(Debug, Clone)]
pub struct ModuleSource {
    pub path: ModulePath,
    pub content: String,
    pub origin: ModuleOrigin,
    pub soul_signature: u64,
}

#[derive(Debug, Clone)]
pub struct ModuleAst {
    pub path: ModulePath,
    pub statements: Vec<Stmt>,
    pub exports: HashMap<String, Value>,
    pub soul_signature: u64,
    pub dependencies: Vec<ModulePath>,
}

pub trait ModuleLoader: Send + Sync {
    fn load(&self, path: &ModulePath) -> Result<ModuleSource, AzlError>;
}

pub struct SoulTracker {
    signatures: RwLock<HashMap<String, u64>>,
    karmic_balance: RwLock<HashMap<String, f64>>,
}

impl SoulTracker {
    pub fn new() -> Self {
        SoulTracker {
            signatures: RwLock::new(HashMap::new()),
            karmic_balance: RwLock::new(HashMap::new()),
        }
    }

    pub fn register_soul(&self, module_name: &str, signature: u64) {
        if let Ok(mut signatures) = self.signatures.write() {
            signatures.insert(module_name.to_string(), signature);
        }
    }

    pub fn get_soul(&self, module_name: &str) -> Option<u64> {
        if let Ok(signatures) = self.signatures.read() {
            signatures.get(module_name).copied()
        } else {
            None
        }
    }

    pub fn update_karma(&self, module_name: &str, karma_delta: f64) {
        if let Ok(mut balance) = self.karmic_balance.write() {
            let current = *balance.get(module_name).unwrap_or(&0.0);
            balance.insert(module_name.to_string(), current + karma_delta);
        }
    }
}

pub struct ModuleResolver {
    cache: RwLock<HashMap<ModulePath, ModuleAst>>,
    loaders: Vec<Box<dyn ModuleLoader>>,
    soul_tracker: SoulTracker,
    search_paths: Vec<PathBuf>,
}

impl ModuleResolver {
    pub fn new() -> Self {
        let mut resolver = ModuleResolver {
            cache: RwLock::new(HashMap::new()),
            loaders: Vec::new(),
            soul_tracker: SoulTracker::new(),
            search_paths: Vec::new(),
        };
        
        // Add default search paths
        resolver.search_paths.push(PathBuf::from("."));
        resolver.search_paths.push(PathBuf::from("./modules"));
        resolver.search_paths.push(PathBuf::from("./lib"));
        
        resolver
    }

    pub fn add_loader(&mut self, loader: Box<dyn ModuleLoader>) {
        self.loaders.push(loader);
    }

    pub fn add_search_path(&mut self, path: PathBuf) {
        self.search_paths.push(path);
    }

    pub fn resolve(&self, import_path: &str) -> Result<ModuleAst, AzlError> {
        // Check cache first
        if let Ok(cache) = self.cache.read() {
            let module_path = ModulePath {
                path: import_path.to_string(),
                origin: ModuleOrigin::Filesystem(PathBuf::new()), // Will be set by loader
            };
            if let Some(module) = cache.get(&module_path) {
                return Ok(module.clone());
            }
        }

        // Try to load from available loaders
        for loader in &self.loaders {
            let module_path = ModulePath {
                path: import_path.to_string(),
                origin: ModuleOrigin::Filesystem(PathBuf::new()),
            };
            
            match loader.load(&module_path) {
                Ok(source) => {
                    // Parse the module
                    let ast = self.parse_module(&source)?;
                    
                    // Cache the module
                    if let Ok(mut cache) = self.cache.write() {
                        cache.insert(module_path, ast.clone());
                    }
                    
                    // Register soul signature
                    self.soul_tracker.register_soul(import_path, source.soul_signature);
                    
                    return Ok(ast);
                }
                Err(_) => continue, // Try next loader
            }
        }

        Err(AzlError::new(
            ErrorKind::Runtime,
            format!("Module not found: {}", import_path)
        ))
    }

    fn parse_module(&self, source: &ModuleSource) -> Result<ModuleAst, AzlError> {
        // Use the real parser to parse module items
        let mut scanner = crate::azl_v2_compiler::Scanner::new(source.content.clone());
        let tokens = scanner.scan_tokens()
            .map_err(|e| AzlError::new(ErrorKind::Compilation, format!("Scanner error: {}", e)))?;
        
        let mut parser = crate::azl_v2_compiler::Parser::new(tokens);
        let statements = parser.parse_module_items()
            .map_err(|e| AzlError::new(ErrorKind::Compilation, format!("Parser error: {}", e)))?;
        
        // Extract exports from statements
        let exports = self.extract_exports_from_statements(&statements);
        
        // Extract dependencies from imports
        let dependencies = self.extract_dependencies_from_statements(&statements);
        
        let module = ModuleAst {
            path: source.path.clone(),
            statements,
            exports,
            soul_signature: source.soul_signature,
            dependencies,
        };

        Ok(module)
    }

    fn extract_exports_from_statements(&self, statements: &[crate::azl_v2_compiler::Stmt]) -> HashMap<String, crate::azl_v2_compiler::Value> {
        let mut exports = HashMap::new();
        
        for stmt in statements {
            match stmt {
                crate::azl_v2_compiler::Stmt::Export { name, value } => {
                    // For now, just store the export name
                    // TODO: Evaluate the value expression if present
                    exports.insert(name.clone(), crate::azl_v2_compiler::Value::String(name.clone()));
                }
                _ => {}
            }
        }
        
        exports
    }

    fn extract_dependencies_from_statements(&self, statements: &[crate::azl_v2_compiler::Stmt]) -> Vec<ModulePath> {
        let mut dependencies = Vec::new();
        
        for stmt in statements {
            match stmt {
                crate::azl_v2_compiler::Stmt::Import { path, .. } => {
                    dependencies.push(ModulePath {
                        path: path.clone(),
                        origin: ModuleOrigin::Filesystem(PathBuf::new()), // Will be resolved later
                    });
                }
                _ => {}
            }
        }
        
        dependencies
    }

    pub fn get_soul_signature(&self, module_name: &str) -> Option<u64> {
        self.soul_tracker.get_soul(module_name)
    }

    pub fn update_module_karma(&self, module_name: &str, karma_delta: f64) {
        self.soul_tracker.update_karma(module_name, karma_delta);
    }
} 