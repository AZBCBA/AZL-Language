use std::path::{Path, PathBuf};
use std::fs;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use crate::azl_error::{AzlError, ErrorKind};
use crate::module::resolver::{ModuleLoader, ModulePath, ModuleSource, ModuleOrigin};

pub struct FilesystemModuleLoader {
    search_paths: Vec<PathBuf>,
    file_extensions: Vec<String>,
}

impl FilesystemModuleLoader {
    pub fn new() -> Self {
        FilesystemModuleLoader {
            search_paths: vec![
                PathBuf::from("."),
                PathBuf::from("./modules"),
                PathBuf::from("./lib"),
            ],
            file_extensions: vec![
                "azl".to_string(),
                "azl".to_string(), // Allow both .azl and .azl
            ],
        }
    }

    pub fn add_search_path(&mut self, path: PathBuf) {
        self.search_paths.push(path);
    }

    pub fn add_file_extension(&mut self, ext: String) {
        self.file_extensions.push(ext);
    }

    fn resolve_path(&self, import_path: &str) -> Result<PathBuf, AzlError> {
        // Handle relative paths
        if import_path.starts_with("./") || import_path.starts_with("../") {
            for search_path in &self.search_paths {
                let mut path = search_path.clone();
                path.push(import_path);
                
                // Try with different extensions
                for ext in &self.file_extensions {
                    let mut file_path = path.clone();
                    file_path.set_extension(ext);
                    
                    if file_path.exists() {
                        return Ok(file_path);
                    }
                }
                
                // Try as directory with index.azl
                let mut index_path = path.clone();
                index_path.push("index.azl");
                
                if index_path.exists() {
                    return Ok(index_path);
                }
            }
        } else {
            // Handle module names (e.g., "math" -> "./modules/math.azl")
            for search_path in &self.search_paths {
                for ext in &self.file_extensions {
                    let mut path = search_path.clone();
                    path.push(format!("{}.{}", import_path, ext));
                    
                    if path.exists() {
                        return Ok(path);
                    }
                }
                
                // Try as directory with index
                let mut index_path = search_path.clone();
                index_path.push(import_path);
                index_path.push("index.azl");
                
                if index_path.exists() {
                    return Ok(index_path);
                }
            }
        }

        Err(AzlError::new(
            ErrorKind::Runtime,
            format!("Module file not found: {}", import_path)
        ))
    }

    fn calculate_soul_signature(&self, content: &str, path: &Path) -> u64 {
        let mut hasher = DefaultHasher::new();
        
        // Hash the content
        content.hash(&mut hasher);
        
        // Hash the path for uniqueness
        path.to_string_lossy().hash(&mut hasher);
        
        // Hash the file modification time if available
        if let Ok(metadata) = fs::metadata(path) {
            if let Ok(modified) = metadata.modified() {
                if let Ok(duration) = modified.duration_since(std::time::UNIX_EPOCH) {
                    duration.as_secs().hash(&mut hasher);
                }
            }
        }
        
        hasher.finish()
    }

    fn read_file_safely(&self, path: &Path) -> Result<String, AzlError> {
        // Check if file exists
        if !path.exists() {
            return Err(AzlError::new(
                ErrorKind::Runtime,
                format!("File does not exist: {}", path.display())
            ));
        }

        // Check if it's a file (not a directory)
        if !path.is_file() {
            return Err(AzlError::new(
                ErrorKind::Runtime,
                format!("Path is not a file: {}", path.display())
            ));
        }

        // Read the file
        fs::read_to_string(path).map_err(|e| {
            AzlError::new(
                ErrorKind::Runtime,
                format!("Failed to read file {}: {}", path.display(), e)
            )
        })
    }
}

impl ModuleLoader for FilesystemModuleLoader {
    fn load(&self, module_path: &ModulePath) -> Result<ModuleSource, AzlError> {
        // Resolve the actual file path
        let file_path = self.resolve_path(&module_path.path)?;
        
        // Read the file content
        let content = self.read_file_safely(&file_path)?;
        
        // Calculate soul signature
        let soul_signature = self.calculate_soul_signature(&content, &file_path);
        
        // Create module source
        let source = ModuleSource {
            path: ModulePath {
                path: module_path.path.clone(),
                origin: ModuleOrigin::Filesystem(file_path.clone()),
            },
            content,
            origin: ModuleOrigin::Filesystem(file_path),
            soul_signature,
        };

        Ok(source)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_filesystem_loader_creation() {
        let loader = FilesystemModuleLoader::new();
        assert!(!loader.search_paths.is_empty());
        assert!(!loader.file_extensions.is_empty());
    }

    #[test]
    fn test_soul_signature_calculation() {
        let loader = FilesystemModuleLoader::new();
        let content = "module test { pub const PI = 3.14; }";
        let path = PathBuf::from("test.azl");
        
        let signature1 = loader.calculate_soul_signature(content, &path);
        let signature2 = loader.calculate_soul_signature(content, &path);
        
        // Same content and path should produce same signature
        assert_eq!(signature1, signature2);
        
        // Different content should produce different signature
        let signature3 = loader.calculate_soul_signature("different content", &path);
        assert_ne!(signature1, signature3);
    }

    #[test]
    fn test_file_reading() {
        let temp_dir = tempdir().unwrap();
        let test_file = temp_dir.path().join("test.azl");
        let content = "module test { pub const PI = 3.14; }";
        
        fs::write(&test_file, content).unwrap();
        
        let loader = FilesystemModuleLoader::new();
        let result = loader.read_file_safely(&test_file);
        
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), content);
    }

    #[test]
    fn test_nonexistent_file() {
        let loader = FilesystemModuleLoader::new();
        let nonexistent_path = PathBuf::from("nonexistent.azl");
        
        let result = loader.read_file_safely(&nonexistent_path);
        assert!(result.is_err());
    }
} 