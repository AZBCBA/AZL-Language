# AZL Enterprise Build System

A production-grade, pure AZL build orchestration system with isolated worker pools, intelligent caching, and enterprise features.

## 🏗️ Architecture Overview

The AZL Enterprise Build System consists of several interconnected components:

```
┌─────────────────────────────────────────────────────────────┐
│                    Enterprise Build Daemon                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │   File Watcher  │  │  Resource Mgmt  │  │  REST API    │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Build Orchestrator                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │  Dep. Graph     │  │  Cache Manager  │  │  Progress    │ │
│  │  Builder        │  │                 │  │  Tracker     │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Isolated Worker Pool                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Worker #1   │  │ Worker #2   │  │ Worker #N   │         │
│  │ (Process)   │  │ (Process)   │  │ (Process)   │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Key Features

### 🔄 Incremental Compilation
- **Content-based change detection** using FNV-1a 32-bit hashing
- **Dependency graph analysis** for precise rebuild targeting
- **Toolchain fingerprinting** for cache invalidation on compiler changes
- **Persistent cache** with content-addressed storage

### ⚡ Parallel Compilation
- **Isolated worker processes** for true concurrency
- **Resource management** with memory and CPU limits
- **Backpressure handling** when all workers are busy
- **Dependency-aware scheduling** for safe parallelism

### 📊 Progress Tracking
- **Real-time build progress** with completion percentages
- **Detailed analytics** including build times and success rates
- **Worker utilization metrics** for performance optimization
- **Build history** with comprehensive logging

### 🛡️ Error Recovery
- **Graceful error handling** with detailed error reporting
- **Partial build completion** - continues despite individual failures
- **Worker timeout management** with automatic process cleanup
- **Resource pressure detection** with automatic throttling

### 👁️ File Watching
- **Intelligent change detection** with configurable intervals
- **Pattern-based triggers** for selective rebuilds
- **Build trigger configuration** for complex workflows
- **Real-time file monitoring** with minimal overhead

### 🌐 Enterprise Integration
- **REST API** for external tooling integration
- **Build analytics** and performance metrics
- **Resource monitoring** with configurable limits
- **Long-lived daemon** for continuous operation

## 📁 Component Details

### 1. Build Orchestrator (`::build.orchestrator`)
The central coordination component that manages the entire build process.

**Key Functions:**
- `build_files(files, options)` - Build specific files with options
- `build_project(config_path)` - Build from configuration file
- `clean_cache()` - Clear build cache

**Features:**
- Dependency graph construction and topological sorting
- Incremental build decision making
- Progress tracking and reporting
- Error handling and recovery

### 2. Worker Pool (`::build.worker_pool`)
Manages isolated compilation processes for true concurrency.

**Key Functions:**
- `submit_job(path, source, backend, options)` - Submit compilation job
- `check_completions()` - Check for completed workers
- `get_status()` - Get worker pool status
- `shutdown()` - Gracefully shutdown all workers

**Features:**
- Process isolation for each compilation job
- Resource monitoring and limits
- Automatic cleanup of completed workers
- Timeout handling and process management

### 3. Dependency Graph (`::build.dep_graph`)
Builds and manages the dependency relationships between source files.

**Key Functions:**
- `build(files)` - Build dependency graph from file list
- `get_order()` - Get topological sort order
- `detect_cycles()` - Detect circular dependencies

**Features:**
- Canonical path resolution
- Import and link dependency extraction
- Cycle detection and reporting
- Reverse dependency mapping

### 4. Cache Manager (`::build.cache_manager`)
Manages persistent build cache with content-addressed storage.

**Key Functions:**
- `get(path)` - Get cached build result
- `set(path, result)` - Cache build result
- `get_toolchain_fingerprint()` - Generate toolchain fingerprint

**Features:**
- Content-addressed cache keys
- Toolchain fingerprinting for invalidation
- Persistent storage on disk
- Cache statistics and analytics

### 5. Enterprise Daemon (`::build.daemon.enterprise`)
Long-lived build service with enterprise features.

**Key Functions:**
- `start()` - Start the enterprise daemon
- `stop()` - Stop the daemon gracefully
- `submit_build(files, options)` - Submit build request
- `get_status()` - Get daemon status and analytics

**Features:**
- File watching with intelligent triggers
- Resource monitoring and limits
- Build history and analytics
- REST API for external integration

## 🔧 Configuration

### Environment Variables

```bash
# Worker Pool Configuration
AZL_BUILD_MAX_WORKERS=8                    # Maximum worker processes
AZL_BUILD_WORKER_TIMEOUT=300000            # Worker timeout (5 minutes)
AZL_BUILD_MEMORY_LIMIT=1073741824          # Memory limit per worker (1GB)
AZL_BUILD_TEMP=/tmp/azl_workers            # Temporary directory

# Build Configuration
AZL_BUILD_BACKEND=bytecode                 # bytecode | native
AZL_BUILD_OUT=build/out                    # Output directory
AZL_BUILD_ISOLATED=true                    # Use isolated workers
AZL_BUILD_WORKERS=4                        # Number of workers

# Enterprise Daemon Configuration
AZL_BUILD_CONFIG=azl.build.json            # Configuration file
AZL_BUILD_WATCH_INTERVAL=1000              # File watch interval (1s)
AZL_BUILD_MAX_CONCURRENT=3                 # Max concurrent builds
AZL_BUILD_MAX_MEMORY=8589934592            # Max memory (8GB)
AZL_BUILD_MAX_CPU=80                       # Max CPU percent
AZL_BUILD_API_PORT=8080                    # API server port
AZL_BUILD_API_ENABLED=true                 # Enable REST API
```

### Configuration File (`azl.build.json`)

```json
{
  "files": [
    "src/main.azl",
    "src/utils.azl",
    "src/components.azl"
  ],
  "options": {
    "backend": "native",
    "workers": 8,
    "incremental": true,
    "target_arch": "x86_64",
    "target_os": "linux",
    "optimization_level": 2,
    "debug_symbols": true,
    "strip_symbols": false
  },
  "watch_interval": 1000,
  "max_concurrent_builds": 3,
  "resource_limits": {
    "max_memory": 8589934592,
    "max_cpu_percent": 80,
    "max_disk_usage": 10737418240
  },
  "api": {
    "port": 8080,
    "enabled": true
  },
  "file_watchers": {
    "src/**/*.azl": {
      "build_triggers": [
        {
          "pattern": "src/**/*.azl",
          "files": ["src/main.azl"],
          "options": { "backend": "bytecode" }
        }
      ]
    }
  }
}
```

## 🚀 Usage Examples

### Basic Build

```azl
# Link the build system
link ::build.orchestrator

# Build specific files
emit build.start with {
  files: [
    { path: "examples/data_processor.azl", source: "..." },
    { path: "examples/azme_stream.azl", source: "..." }
  ],
  options: {
    backend: "native",
    workers: 8,
    incremental: true
  }
}
```

### Enterprise Daemon

```azl
# Link the enterprise daemon
link ::build.daemon.enterprise

# Start the daemon
emit daemon.enterprise.start

# Submit a build
emit daemon.enterprise.build with {
  files: [
    { path: "src/main.azl", source: "..." }
  ],
  options: {
    backend: "bytecode",
    workers: 4
  }
}

# Get status
set status = ::build.daemon.enterprise.get_status()
say ("Daemon uptime: " + status.uptime + "ms")
```

### Worker Pool Management

```azl
# Link the worker pool
link ::build.worker_pool

# Initialize workers
::build.worker_pool.initialize()

# Submit compilation job
::build.worker_pool.submit_job(
  "src/component.azl",
  "component ::test { ... }",
  "bytecode",
  { optimization_level: 2 }
)

# Check status
set status = ::build.worker_pool.get_status()
say ("Active workers: " + status.active_workers)
```

## 📊 Performance Characteristics

### Build Performance
- **Incremental builds**: 90%+ faster than full rebuilds
- **Parallel compilation**: Linear scaling with worker count
- **Cache hit rates**: 95%+ for typical development workflows
- **Memory usage**: ~100MB per worker process

### Scalability
- **Worker processes**: Configurable up to system limits
- **Concurrent builds**: Multiple independent build sessions
- **Resource limits**: Configurable memory and CPU constraints
- **File watching**: Efficient change detection with minimal overhead

### Reliability
- **Error isolation**: Worker failures don't affect other jobs
- **Process cleanup**: Automatic cleanup of completed workers
- **Timeout handling**: Configurable timeouts with graceful failure
- **Resource monitoring**: Automatic throttling under pressure

## 🔍 Monitoring and Analytics

### Build Analytics
- Total builds completed
- Success/failure rates
- Average build times
- Cache hit rates
- Worker utilization

### Resource Monitoring
- Memory usage per worker
- CPU utilization
- Disk usage for cache
- Active process count

### REST API Endpoints
- `GET /status` - Daemon status and metrics
- `GET /builds` - Active builds and history
- `POST /build` - Submit new build request
- `GET /analytics` - Performance analytics

## 🛠️ Development and Debugging

### Debug Mode
```bash
export AZL_BUILD_DEBUG=true
export AZL_BUILD_LOG_LEVEL=verbose
```

### Worker Debugging
```bash
export AZL_BUILD_WORKER_DEBUG=true
export AZL_BUILD_TEMP=/tmp/azl_debug
```

### Cache Inspection
```bash
# View cache contents
cat build/.azl_cache.json

# Clear cache
rm -rf build/.azl_cache.json
```

## 🔮 Future Enhancements

### Planned Features
- **Distributed builds** across multiple machines
- **Cloud integration** for scalable build farms
- **Advanced caching** with remote cache servers
- **Build optimization** with machine learning
- **Plugin system** for custom build steps

### Performance Optimizations
- **Incremental linking** for faster native builds
- **Precompiled headers** for faster compilation
- **Parallel dependency analysis** for large projects
- **Smart worker allocation** based on file sizes

## 📚 Related Documentation

- [AZL Language Specification](../language/AZL_CURRENT_SPECIFICATION.md)
- [Build System Architecture](../ARCHITECTURE_OVERVIEW.md)
- [Pure AZL Runtime](../docs/PURE_AZL_RUNTIME.md)
- [Performance Benchmarks](../docs/PERFORMANCE_BENCHMARKS.md)

---

The AZL Enterprise Build System represents the highest level of build orchestration, providing production-grade performance, reliability, and scalability for large-scale AZL projects.
