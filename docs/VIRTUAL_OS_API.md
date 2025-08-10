# Virtual OS API (Pure AZL)

The Virtual OS lives in `azl/system/azl_system_interface.azl`. It offers deterministic, in-memory primitives for FS/HTTP/console/process via a single event surface.

## Unified syscall
- Emit: `syscall` with `{ type, args, request_id? }`
- Receive: `syscall.response` with `{ request_id, ...fields }`

Example:
```azl
emit syscall with { type: "write_file", args: { path: "/tmp/x.txt", content: "hello" } }
emit syscall with { type: "read_file", args: { path: "/tmp/x.txt" } }
listen for "syscall.response" then { say "content=" + ::event.data.content }
```

## Supported calls
- Files
  - `read_file { path }` → `{ content }`
  - `write_file { path, content }` → `{ success }`
  - `list_dir { path }` → `{ entries }`
  - `file_exists { path }` → `{ exists }`
  - `delete_file { path }` → `{ success }`
- Memory
  - `mmap { size }` → `{ address, size }`
  - `munmap { address, size }` → `{ success }`
- Network (virtual)
  - `http { url, method, headers?, body? }` → `{ status, headers, body }`
- Process
  - `exec { command, args? }` → `{ pid, exit_code }`
- Console
  - `console.write { text, stream? }` → `{ success }`

## Convenience listeners
- `fs.read { path }` → `fs.read.response { path, content }`
- `fs.write { path, content }` → `fs.write.response { path, success }`
- `fs.list { path }` → `fs.list.response { path, entries }`
- `net.http { url, method, headers?, body? }` → `net.http.response { status, headers, body }`
- `console.write { text, stream? }` → `console.write.response { success }`

## Deterministic stores
- Files: `::fs_store[path] = content` and `::fs_meta[path] = { size, modified }`
- HTTP: `::http_store[url] = body`
- Console: `::stdout`, `::stderr`

All behavior is deterministic and suitable for testing and self-hosted execution.
