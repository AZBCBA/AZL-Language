# AZL Backend: Machine Code Generation (Pure AZL)

This backend provides pure-AZL encoders and binary writers:

- Assembler: `azl/backend/asm/assembler.azl`
  - Two-pass assembly with label resolution
  - Encoders: x86_64 (subset), AArch64 (subset)
  - Helpers to build exit(0) programs
- ELF64 Writer: `azl/backend/format/elf64_writer.azl`
  - Minimal Linux executable with one PT_LOAD segment
- PE64 Writer: `azl/backend/format/pe64_writer.azl`
  - Minimal PE32+ executable with a single .text section
- Mach-O 64 Writer: `azl/backend/format/macho64_writer.azl`
  - Minimal Mach-O (x86_64) with __TEXT,__text and LC_MAIN

Error policy: all public functions return `{ ok: true, ... }` or `{ ok: false, error }`. No placeholders.

## Public APIs

Assembler:
- `assemble_x86_64([program]) -> { ok, bytes, labels }`
- `assemble_arm64([program]) -> { ok, bytes, labels }`
- `program_exit_linux_x86_64([code]) -> program`
- `program_exit_linux_arm64([code]) -> program`

Writers:
- `elf64_writer.write_exec([entry_vaddr, text_bytes, base_vaddr?])`
- `pe64_writer.write_exec([entry_rva, text_bytes, image_base?])`
- `macho64_writer.write_exec([entry_file_offset, text_bytes])`

## Example: ELF64 Linux x86_64 exit(0)

1) Build program:
```
program = azl.backend.asm.assembler.program_exit_linux_x86_64([0])
res = azl.backend.asm.assembler.assemble_x86_64([program])
```
2) Write ELF64:
```
base = 0x400000
entry = base + 0x1000
elf = azl.backend.format.elf64_writer.write_exec([entry, res.bytes, base])
```

## Example: PE64 Windows x86_64 exit stub

- Entry RVA typically points inside .text (e.g., 0x1000). Provide bytes from assembler and call writer.
```
entry_rva = 0x1000
pe = azl.backend.format.pe64_writer.write_exec([entry_rva, res.bytes, 0x140000000])
```

## Example: Mach-O 64 (x86_64) exit stub

- LC_MAIN uses a file offset relative to __TEXT,__text. If code starts at offset 0 in the text payload, set entry_file_offset=0.
```
entry_file_offset = 0
macho = azl.backend.format.macho64_writer.write_exec([entry_file_offset, res.bytes])
```

## Notes
- Encoders currently support a safe subset sufficient for bootstrap binaries.
- Extend instruction support incrementally with tests.
- All integers are treated as unsigned where applicable; callers must ensure appropriate ranges.
- For non-Linux formats, adjust entry and base addresses appropriately; loaders differ by platform.
