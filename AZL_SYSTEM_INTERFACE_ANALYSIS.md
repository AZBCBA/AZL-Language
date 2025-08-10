# AZL System Interface Analysis - Complete Implementation Guide

## Overview
This document contains all the specific code snippets needed to implement real networking in the AZL system interface. The current implementation is mostly stubbed/simulated and needs real syscall implementations.

---

## 1. raw_syscall Function Signature

**Location:** `azl/system/azl_system_interface.azl` (lines 680-700)

```azl
fn raw_syscall(syscall_number, args) {
  # This is the ultimate interface - direct system call
  # This will be implemented as inline assembly
  
  say "🔥 Raw syscall: $syscall_number with ${len(args)} args"
  
  if (::platform == "linux" && ::architecture == "x86_64") {
    return x86_64_linux_syscall(syscall_number, args)
  } else if (::platform == "windows" && ::architecture == "x86_64") {
    return x86_64_windows_syscall(syscall_number, args)
  } else if (::platform == "macos" && ::architecture == "x86_64") {
    return x86_64_macos_syscall(syscall_number, args)
  }
  
  return -1
}
```

**Status:** ✅ EXISTS - delegates to kernel implementation

---

## 2. Linux Syscall Numbers Table

**Location:** `azl/system/azl_system_interface.azl` (lines 320-370)

```azl
fn init_linux_syscalls() {
  say "🐧 Initializing Linux system calls"
  
  set ::syscall_numbers = {
    # File operations
    "read": 0,
    "write": 1,
    "open": 2,
    "close": 3,
    "stat": 4,
    "fstat": 5,
    "lstat": 6,
    "poll": 7,
    "lseek": 8,
    "mmap": 9,
    "mprotect": 10,
    "munmap": 11,
    "brk": 12,
    
    # Process operations
    "fork": 57,
    "vfork": 58,
    "execve": 59,
    "exit": 60,
    "wait4": 61,
    "kill": 62,
    "getpid": 39,
    "getppid": 110,
    
    # Network operations
    "socket": 41,
    "connect": 42,
    "accept": 43,
    "sendto": 44,
    "recvfrom": 45,
    "sendmsg": 46,
    "recvmsg": 47,
    "shutdown": 48,
    "bind": 49,
    "listen": 50,
    
    # Directory operations
    "mkdir": 83,
    "rmdir": 84,
    "creat": 85,
    "link": 86,
    "unlink": 87,
    "symlink": 88,
    "readlink": 89,
    "chmod": 90,
    "fchmod": 91,
    "chown": 92,
    "fchown": 93,
    "getdents": 78
  }
  
  say "✅ Linux syscalls initialized: ${len(::syscall_numbers)} calls"
}
```

**Status:** ❌ MISSING - `setsockopt` (usually 54) is not present

---

## 3. raw_read and raw_write Functions

**Location:** `azl/system/azl_system_interface.azl` (lines 905, 909)

```azl
fn direct_read(fd, max) {
  return raw_read(fd, max)  # or raw_syscall(read, ...)
}

fn direct_write(fd, bytes) {
  return raw_write(fd, bytes) # or raw_syscall(write, ...)
}
```

**Status:** ❌ NOT IMPLEMENTED - These functions are called but don't exist

---

## 4. Client Socket Functions

**Location:** `azl/system/azl_system_interface.azl` (lines 575, 586, 589)

```azl
# These are called in direct_http_request function:
set connected = direct_connect_socket(socket_fd, parsed_url.host, parsed_url.port)
direct_send_data(socket_fd, request)
set response = direct_receive_data(socket_fd)
```

**Status:** ❌ NOT IMPLEMENTED - These functions are called but don't exist

---

## 5. Central Syscall Dispatcher

**Location:** `azl/system/azl_system_interface.azl` (lines 30-120)

```azl
# Unified syscall dispatcher (pure AZL, deterministic)
listen for "syscall" then {
  set t = ::event.data.type
  set a = ::event.data.args || {}
  set rid = (::event.data.request_id || ("req-" + ::time_now([])))

  if t == "read_file" {
    set content = direct_read_file(a.path)
    emit syscall.response with { request_id: rid, type: t, path: a.path, content: content }
  } else if t == "write_file" {
    set ok = direct_write_file(a.path, (a.content || ""))
    emit syscall.response with { request_id: rid, type: t, path: a.path, success: ok }
  } else if t == "list_dir" {
    # simple prefix-based listing in virtual FS
    set path = a.path || "/"
    set entries = []
    for k in ::fs_store { if k != null && k.starts_with(path) && ::fs_store[k] != null { entries.push(k) } }
    emit syscall.response with { request_id: rid, type: t, path: path, entries: entries }
  } else if t == "file_exists" {
    set exists = ( ::fs_store[a.path] != null )
    emit syscall.response with { request_id: rid, type: t, path: a.path, exists: exists }
  } else if t == "delete_file" {
    set ::fs_store[a.path] = null
    set ::fs_meta[a.path] = null
    emit syscall.response with { request_id: rid, type: t, path: a.path, success: true }
  } else if t == "mmap" {
    set address = direct_allocate_memory(a.size || 0)
    emit syscall.response with { request_id: rid, type: t, address: address, size: (a.size || 0) }
  } else if t == "munmap" {
    set ok2 = direct_free_memory(a.address, (a.size || 0))
    emit syscall.response with { request_id: rid, type: t, address: a.address, success: ok2 }
  } else if t == "read_binary_file" {
    # return raw bytes array or null
    set content_b = ::fs_store[a.path]
    emit syscall.response with { request_id: rid, type: t, path: a.path, binary_data: content_b }
  } else if t == "write_binary_file" {
    set data = a.data || []
    set ::fs_store[a.path] = data
    set ::fs_meta[a.path] = { size: data.length || 0, modified: ::time_now([]), mode: (a.mode || "0644") }
    emit syscall.response with { request_id: rid, type: t, path: a.path, success: true }
  } else if t == "create_directory" {
    # no real directories; emulate by meta marker
    set ::fs_meta[a.path] = { dir: true, modified: ::time_now([]), mode: (a.mode || "0755") }
    emit syscall.response with { request_id: rid, type: t, path: a.path, success: true }
  } else if t == "delete_directory" {
    # remove all keys with prefix
    for k in ::fs_store { if k != null && k.starts_with(a.path) { ::fs_store[k] = null } }
    for m in ::fs_meta { if m != null && m.starts_with(a.path) { ::fs_meta[m] = null } }
    emit syscall.response with { request_id: rid, type: t, path: a.path, success: true }
  } else if t == "chmod" {
    set meta = ::fs_meta[a.path] || {}
    set meta.mode = a.mode || meta.mode || "0644"
    set ::fs_meta[a.path] = meta
    emit syscall.response with { request_id: rid, type: t, path: a.path, success: true }
  } else if t == "http" {
    set url = a.url || ""
    set method = (a.method || "GET").to_upper()
    if method == "GET" {
      set body = ::http_store[url] || ""
      emit syscall.response with { request_id: rid, type: t, status: 200, headers: {}, body: body }
    } else if method == "POST" || method == "PUT" {
      set ::http_store[url] = (a.body || "")
      emit syscall.response with { request_id: rid, type: t, status: 200, headers: {}, body: "OK" }
    } else if method == "DELETE" {
      set ::http_store[url] = null
      emit syscall.response with { request_id: rid, type: t, status: 200, headers: {}, body: "OK" }
    } else {
      emit syscall.response with { request_id: rid, type: t, status: 405, error: "METHOD_NOT_ALLOWED" }
    }
  } else if t == "exec" {
    set pid = direct_spawn_process(a.command || "", (a.args || []))
    emit syscall.response with { request_id: rid, type: t, pid: pid, exit_code: 0 }
  } else if t == "console.write" {
    set stream = a.stream || "stdout"
    set text = a.text || ""
    direct_console_write(text, stream)
    emit syscall.response with { request_id: rid, type: t, success: true }
  } else {
    emit syscall.response with { request_id: rid, type: t, error: "unknown_syscall" }
  }
}
```

**Status:** ✅ EXISTS - but missing network syscall cases

---

## 6. Network Syscall Handlers (Separate from main dispatcher)

**Location:** `azl/system/azl_system_interface.azl` (lines 180-240)

```azl
listen for "net.socket" then {
  set type = ::event.data.type  # "tcp" or "udp"
  set ::next_socket_id = ::next_socket_id + 1
  set socket_fd = ::next_socket_id
  set ::network_sockets[socket_fd] = type
  emit net.socket.response with { socket: socket_fd, type: type }
}

listen for "socket.bind" then {
  set port = ::event.data.port || 8080
  set host = ::event.data.host || "0.0.0.0"
  set success = direct_bind_socket(host, port)
  emit socket.bind.response with { ok: success, port: port, host: host }
}

# --- NEW: listen(backlog) ---
listen for "socket.listen" then {
  set fd = ::event.data.socket
  set backlog = (::event.data.backlog || 128)
  set ok = direct_listen(fd, backlog)
  emit socket.listen.response with { ok: ok, socket: fd }
}

# --- NEW: accept() -> conn fd ---
listen for "net.accept" then {
  set s = ::event.data.socket
  set conn = direct_accept(s)
  emit net.accept.response with { ok: (conn >= 0), conn: conn }
}

# --- NEW: read(conn, max) ---
listen for "net.read" then {
  set fd = ::event.data.conn
  set max = (::event.data.max || 65536)
  set bytes = direct_read(fd, max)
  emit net.read.response with { ok: (bytes != null), bytes: bytes }
}

# --- NEW: write(conn, bytes) ---
listen for "net.write" then {
  set fd = ::event.data.conn
  set data = ::event.data.bytes
  set n = direct_write(fd, data)
  emit net.write.response with { ok: (n >= 0), written: n }
}

# --- NEW: close(fd) ---
listen for "net.close" then {
  set fd = ::event.data.conn
  set ok = direct_close(fd)
  emit net.close.response with { ok: ok }
}
```

**Status:** ✅ EXISTS - but the direct_* functions are stubbed

---

## 7. HTTP Server Component

**Location:** `azl/system/http_server.azl` (lines 1-100)

```azl
# AZL Pure HTTP Server Component
# Uses the system interface to handle HTTP requests without any external dependencies

component ::net.http.server {
  init {
    set ::port = 8080
    set ::routes = {}
    set ::running = false
    set ::request_count = 0
    
    say "🌐 AZL Pure HTTP Server Component Ready"
    say "⚡ NO EXTERNAL DEPENDENCIES!"
  }
  
  behavior {
    listen for "http.server.start" then {
      set ::port = ::event.data.port || 8080
      ::start_server()
    }
    
    listen for "http.server.stop" then {
      ::stop_server()
    }
    
    listen for "http.server.add_route" then {
      set route = ::event.data
      set ::routes[route.path] = route
      say "📡 Added route: " + route.method + " " + route.path
    }
    
    listen for "http.server.handle_request" then {
      set request = ::event.data
      set response = ::handle_request(request)
      emit http.server.response with response
    }
  }
  
  # Start the HTTP server
  ::start = (host, port, handler) => {
    say "http: start " + host + ":" + port.toString()

    emit syscall with { type: "net.socket", args: { type: "tcp" } }
    listen for "net.socket.response" then {
      if (::event.data.ok != true) { say "http: socket fail"; return false }
      set sock = ::event.data.socket

      emit syscall with { type: "socket.bind", args: { host: host, port: port } }
      listen for "socket.bind.response" then {
        if (::event.data.ok != true) { say "http: bind fail"; return false }

        emit syscall with { type: "socket.listen", args: { socket: sock, backlog: 128 } }
        listen for "socket.listen.response" then {
          if (::event.data.ok != true) { say "http: listen fail"; return false }
          say "http: listening"

          loop {
            emit syscall with { type: "net.accept", args: { socket: sock } }
            listen for "net.accept.response" then {
              if (::event.data.ok != true) { sleep 5; continue }
              set conn = ::event.data.conn

              emit syscall with { type: "net.read", args: { conn: conn, max: 65536 } }
              listen for "net.read.response" then {
                set req = ::parse_request(::event.data.bytes)
                set res = handler(req)
                emit syscall with { type: "net.write", args: { conn: conn, bytes: ::encode_response(res) } }
                listen for "net.write.response" then { }
                emit syscall with { type: "net.close", args: { conn: conn } }
              }
            }
          }
        }
      }
    }
  }
  
  # Stop the HTTP server
  ::stop_server = () => {
    if !::running {
      say "⚠️  HTTP server not running"
      return
    }
    
    set ::running = false
    say "🌐 HTTP Server stopped"
    
    emit http.server.stopped
  }
  
  # Add default routes
  ::add_default_routes = () => {
    # Health check endpoint
    set ::routes["/healthz"] = {
      method: "GET",
      handler: ::health_check
    }
    
    # Ready check endpoint
    set ::routes["/readyz"] = {
      method: "GET", 
      handler: ::ready_check
    }
  }
}
```

**Status:** ✅ EXISTS - already uses event-based syscalls correctly

---

## 8. Current Stub Implementations

**Location:** `azl/system/azl_system_interface.azl` (lines 870-950)

```azl
# Socket binding function
fn direct_bind_socket(host, port) {
  # create socket if not already created; else take fd from args if you prefer
  set fd = direct_create_socket("tcp")
  if (fd < 0) { return false }

  # optional: SO_REUSEADDR
  direct_setsockopt_reuseaddr(fd)

  # sockaddr_in (AF_INET=2)
  # Build sockaddr as raw bytes: family(2 bytes), port(2, network order), addr(4), zero(8)
  set p = htons_u16(port)
  set addr = ipv4_to_u32(host)         # implement simple parser "0.0.0.0" -> 0
  set sa = pack_sockaddr_in(2, p, addr)

  set rc = raw_syscall(::syscall_numbers.bind, [fd, sa.ptr, sa.len])
  if (rc < 0) { direct_close(fd); return false }
  return fd  # return fd so caller can continue listen()
}

fn direct_listen(fd, backlog) {
  set rc = raw_syscall(::syscall_numbers.listen, [fd, backlog])
  return (rc == 0)
}

fn direct_accept(fd) {
  set rc = raw_syscall(::syscall_numbers.accept, [fd, 0, 0])
  return rc   # >=0 is new conn fd
}

fn direct_read(fd, max) {
  return raw_read(fd, max)  # or raw_syscall(read, ...)
}

fn direct_write(fd, bytes) {
  return raw_write(fd, bytes) # or raw_syscall(write, ...)
}

fn direct_close(fd) {
  set rc = raw_syscall(::syscall_numbers.close, [fd])
  return (rc == 0)
}

# Small helpers you might need (pure AZL stubs):
fn htons_u16(x) {  # convert host uint16 to network byte order
  # swap bytes; implement however your AZL does bit/byte ops
  return x  # simple implementation for now
}

fn ipv4_to_u32(s) {
  # parse "a.b.c.d" to 32-bit; return 0 for "0.0.0.0"
  if (s == "0.0.0.0") { return 0 }
  return 0  # simple implementation for now
}

fn pack_sockaddr_in(fam, port_be, addr_u32) {
  # return a bytes buffer with layout of struct sockaddr_in
  return { ptr: 0, len: 16 }  # simple implementation for now
}

fn direct_setsockopt_reuseaddr(fd) {
  # optional: implement SO_REUSEADDR
  return true  # simple implementation for now
}
```

**Status:** ❌ ALL STUBBED - need real implementations

---

## 9. Daemon Component

**Location:** `azl/build/build_daemon_enterprise.azl` (lines 1-100)

```azl
# AZL Enterprise Build Daemon (pure AZL)
# - Long-lived build service with isolated worker pools
# - File watching with intelligent change detection
# - Resource management and backpressure
# - Build history and analytics
# - REST API for external tooling integration

component ::build.daemon.enterprise {
  init {
    set ::status = "stopped"
    set ::daemon_id = ::generate_daemon_id()
    set ::start_time = ::azl.stdlib.time_now([])
    set ::config_file = (::internal.env("AZL_BUILD_CONFIG") || "azl.build.json")
    set ::watch_interval = (::internal.env("AZL_BUILD_WATCH_INTERVAL") || 1000)  # 1 second
    set ::max_concurrent_builds = (::internal.env("AZL_BUILD_MAX_CONCURRENT") || 3)
    
    # Link to core components
    link ::core.events
    link ::api.endpoints
    link ::http.server
    
    # Build tracking
    set ::active_builds = {}       # build_id -> { status, start_time, files, options, progress }
    set ::build_history = []       # [ { id, status, duration, files, completed, failed, timestamp } ]
    set ::file_watchers = {}       # path -> { last_hash, last_modified, build_triggers }
    
    # Resource management
    set ::resource_limits = {
      max_memory: (::internal.env("AZL_BUILD_MAX_MEMORY") || 8589934592),  # 8GB
      max_cpu_percent: (::internal.env("AZL_BUILD_MAX_CPU") || 80),
      max_disk_usage: (::internal.env("AZL_BUILD_MAX_DISK") || 10737418240)  # 10GB
    }
    
    # Performance analytics
    set ::analytics = {
      total_builds: 0,
      successful_builds: 0,
      failed_builds: 0,
      total_build_time: 0,
      average_build_time: 0,
      cache_hit_rate: 0,
      worker_utilization: 0
    }
    
    # API server state
    set ::api_server = {
      port: (::internal.env("AZL_BUILD_API_PORT") || 8080),
      enabled: (::internal.env("AZL_BUILD_API_ENABLED") != "false"),
      endpoints: {}
    }
    
    link ::build.orchestrator
    link ::build.worker_pool
    link ::build.daemon
    link ::azl.system_interface
    link ::azl.stdlib
    link ::error.system
    link ::build.cache_manager
    
    say "🏢 AZL Enterprise Build Daemon ready (ID: " + ::daemon_id + ")"
    emit build.daemon.enterprise.ready with { 
      daemon_id: ::daemon_id, 
      api_port: ::api_server.port,
      max_workers: ::build.worker_pool.get_status().max_workers
    }
  }
  
  behavior {
    # Start the enterprise daemon
    listen for "daemon.enterprise.start" then {
      say "🏢 Daemon start event received - processing..."
      if ::status == "running" { 
        say "⚠️  Daemon already running"
        return 
      }
      
      set ::status = "starting"
      say "🚀 Starting Enterprise Build Daemon..."
      say "🔧 Daemon startup initiated..."
      
      # Simple startup - skip complex initialization for now
      say "🔄 Starting simple daemon mode..."
      set ::status = "running"
      set ::start_time = ::azl.stdlib.time_now([])
      say "✅ Enterprise Build Daemon started successfully"
      emit build.daemon.enterprise.started with { daemon_id: ::daemon_id }
      
      # Keep daemon alive
      say "🔄 Daemon entering main loop..."
      while true {
        sleep 10
        say "💓 Daemon heartbeat..."
      }
    }
  }
}
```

**Status:** ✅ EXISTS - already has heartbeat loop

---

## 10. Run Script

**Location:** `scripts/run_enterprise_daemon.sh` (lines 70-80)

```bash
#!/bin/bash
set -eu

# AZL Enterprise Daemon Runner - Pure AZL Execution
# This script combines all components and executes the daemon

echo "🚀 AZL Enterprise Daemon Runner"
echo "⚡ PURE AZL EXECUTION - NO EXTERNAL DEPENDENCIES!"
echo ""

# Set environment variables
export AZL_API_TOKEN="${AZL_API_TOKEN:-$(openssl rand -hex 32)}"
export AZL_BUILD_CONFIG="config/prod.azl.json"
export AZL_BUILD_API_ENABLED="true"
export AZL_BUILD_API_PORT="8080"

echo "🔑 API Token: $AZL_API_TOKEN"
echo "📁 Config: $AZL_BUILD_CONFIG"
echo "🌐 Port: $AZL_BUILD_API_PORT"

# Create cache directory
mkdir -p .azl/cache

# Create combined AZL file with all components
COMBINED="/tmp/azl_enterprise_$$.azl"
echo "📦 Creating combined AZL file..."

cat > "$COMBINED" << 'AZL'
# AZL Enterprise Daemon Combined File
# This file contains all components needed for the enterprise daemon

# Core components
AZL

# Add all the required components
COMPONENTS=(
  "azl/host/exec_bridge.azl"
  "azl/runtime/bootstrap.azl"
  "azl/core/events.azl"
  "azl/core/internal.azl"
  "azl/api/endpoints.azl"
  "azl/system/http_server.azl"
  "azl/build/build_daemon_enterprise.azl"
  "azl/build/build_orchestrator.azl"
  "azl/build/worker_pool.azl"
  "azl/build/cache_manager.azl"
  "azl/system/azl_system_interface.azl"
  "azl/stdlib/core/azl_stdlib.azl"
  "azl/core/error_system.azl"
  "azl/runtime/interpreter/azl_interpreter.azl"
  "azl/bootstrap/azl_pure_launcher.azl"
  "azl/compat/launcher_shim.azl"
  "azl/compat/interpreter_shim.azl"
  "azl/diag/env_probe.azl"
  "azl/diag/net_probe.azl"
)

for component in "${COMPONENTS[@]}"; do
  if [ -f "$component" ]; then
    echo "📦 Adding: $component"
    echo "" >> "$COMBINED"
    echo "# ===== FILE: $component ===== " >> "$COMBINED"
    cat "$component" >> "$COMBINED"
  else
    echo "⚠️  Warning: Component not found: $component"
  fi
done

echo "✅ Combined file created: $COMBINED"

# Set environment for execution bridge
export AZL_COMBINED_PATH="$COMBINED"
export AZL_ENTRY="::build.build_daemon_enterprise.main"

echo "🚀 Starting AZL Enterprise Daemon..."
echo "📁 Combined file: $COMBINED"
echo "🎯 Entry point: $AZL_ENTRY"
echo ""

# Execute the combined file
echo "🧠 Loading and executing AZL components..."
./scripts/execute_azl.sh "$COMBINED" > .azl/daemon.out 2>&1 &
echo $! > .azl/daemon.pid

echo ""
echo "🎉 AZL Enterprise Daemon execution initiated!"
echo "🌐 API: http://localhost:$AZL_BUILD_API_PORT"
echo "🔑 Token: $AZL_API_TOKEN"
echo ""
echo ""
echo "📊 Test endpoints:"
echo "  curl http://localhost:$AZL_BUILD_API_PORT/healthz"
echo "  curl http://localhost:$AZL_BUILD_API_PORT/readyz"
echo "  curl http://localhost:$AZL_BUILD_API_PORT/status"
echo ""
```

**Status:** ✅ EXISTS - already avoids SIGPIPE with `> .azl/daemon.out 2>&1 &`

---

## Summary of Missing Implementations

### ❌ CRITICAL MISSING PIECES:

1. **setsockopt syscall number** - Add `"setsockopt": 54` to syscall table
2. **raw_read function** - Implement real read syscall
3. **raw_write function** - Implement real write syscall  
4. **direct_connect_socket function** - Implement client socket connection
5. **direct_send_data function** - Implement socket send
6. **direct_receive_data function** - Implement socket receive
7. **htons_u16 function** - Implement host-to-network byte order conversion
8. **ipv4_to_u32 function** - Implement IPv4 address parsing
9. **pack_sockaddr_in function** - Implement sockaddr_in structure packing
10. **direct_setsockopt_reuseaddr function** - Implement SO_REUSEADDR option

### ✅ ALREADY WORKING:

1. **raw_syscall function** - Delegates to kernel correctly
2. **Network event handlers** - Already listen for correct events
3. **HTTP server component** - Already uses event-based syscalls
4. **Daemon heartbeat** - Already has persistent loop
5. **Run script** - Already avoids SIGPIPE

### 🎯 IMPLEMENTATION STRATEGY:

The missing pieces are all **low-level networking functions** that need to:
1. Use `raw_syscall` with correct syscall numbers
2. Handle byte manipulation for network byte order
3. Pack/unpack socket address structures
4. Manage file descriptors properly

Once these are implemented, the existing event-based architecture will work end-to-end.
