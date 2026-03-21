# AZL literal codec container (format v0 — specification)

**Purpose:** Define a **byte-exact**, **versioned** container for **lossless** (and future **serving**) payloads so **Exact** artifacts can be compressed, stored, and verified without silent corruption. Aligns with **[AZL_STRATEGIC_CONSENSUS_AND_EXECUTION_PLAN.md](AZL_STRATEGIC_CONSENSUS_AND_EXECUTION_PLAN.md)** Phase 1 and **[ERROR_SYSTEM.md](ERROR_SYSTEM.md)**.

**Status:** **Specification + reference implementation + harness.** Normative layout: this doc. **Identity codec (`codec_id=0`):** Python package **`tools/azl_literal_codec/`** (`encode_identity_v1`, `decode_container_v1`, CRC-32C). **CI:** **`scripts/verify_azl_literal_codec_container_doc_contract.sh`** (doc anchor) + **`scripts/verify_azl_literal_codec_roundtrip.sh`** (round-trip + negatives).

**Contract anchor (CI):** `AZL_LITERAL_CODEC_CONTAINER_CONTRACT_V1`

**Last updated:** 2026-03-20

---

## 1. Goals

- **Lossless path:** `decompress(compress(payload)) == payload` for registered **codec_id** values (proved in harness, not in language grammar).
- **Explicit failure:** bad magic, unknown version, truncated stream, CRC mismatch → **named errors** (no “successful” garbage).
- **Extensible:** new **codec_id** and **kind** without breaking **format_version == 1** readers that reject unknown IDs.

---

## 2. Wire format (v0 / format_version 1)

All multi-byte integers are **little-endian**. Offsets are from start of file/stream.

| Offset | Size | Field | Description |
|--------|------|--------|-------------|
| 0 | 4 | `magic` | ASCII **`AZL0`** (`0x41 0x5A 0x4C 0x30`). |
| 4 | 4 | `format_version` | **1** for this spec. Readers **must** reject other values with **`CODEC_VERSION_UNSUPPORTED`**. |
| 8 | 2 | `header_len` | Total header size in bytes **including** `magic` through `reserved` (see below). For v1 fixed header: **32**. |
| 10 | 2 | `flags` | Bit flags; **v1:** bit0 **`1`** = payload is compressed; bit0 **`0`** = payload stored raw (identity). Bits 1–15 reserved (**0** on write). |
| 12 | 2 | `kind` | **Artifact kind** (see §4). Unknown → **`CODEC_KIND_UNKNOWN`**. |
| 14 | 2 | `codec_id` | **0** = none / identity; **1** = reserved for future **DEFLATE**-class; **2+** = registered in §5. Unknown → **`CODEC_CODEC_UNKNOWN`**. |
| 16 | 8 | `uncompressed_len` | Original byte length before compression; **0** if unknown (discouraged for **Exact**). |
| 24 | 8 | `payload_len` | Length of **`payload`** in bytes. |
| 32 | `payload_len` | `payload` | Compressed or raw octets per **`flags`** + **`codec_id`**. |
| 32+`payload_len` | 4 | `crc32c` | CRC-32C (Castagnoli, polynomial 0x1EDC6F41) over bytes **`[0 .. header_len+payload_len)`** (entire header including `magic` through end of `payload`). |

**`header_len` for v1:** **32** (fixed). Future versions may grow the header if `header_len` > 32; v1 readers **must** verify `header_len >= 32` and use `header_len` to locate `payload`.

**Truncation:** If stream ends before `payload_len` + `crc32c` → **`CODEC_TRUNCATED`**.

---

## 3. Decoder algorithm (normative)

1. Require at least **36** bytes (minimum header + CRC after empty payload is **36** bytes: header 32 + crc 4). If fewer → **`CODEC_TRUNCATED`**.
2. Verify `magic == AZL0` → else **`CODEC_MAGIC_INVALID`**.
3. Read `format_version`; if not **1** → **`CODEC_VERSION_UNSUPPORTED`**.
4. Read `header_len`; if `< 32` or `> available` → **`CODEC_HEADER_INVALID`**.
5. Verify `32 + payload_len + 4 <= file_size` → else **`CODEC_TRUNCATED`**.
6. Recompute CRC-32C over `header_len + payload_len` bytes from start; compare to trailing **4** bytes → else **`CODEC_CRC_MISMATCH`**.
7. If `kind` unknown → **`CODEC_KIND_UNKNOWN`**.
8. If `codec_id` not registered for this build → **`CODEC_CODEC_UNKNOWN`**.
9. If `flags` bit0 == 0: plaintext is `payload` (**`codec_id`** must be **0**). If bit0 == 1: decompress with **`codec_id`** (**1** = zlib); length **must** match `uncompressed_len` when `uncompressed_len != 0` → else **`CODEC_LENGTH_MISMATCH`**; zlib failure → **`CODEC_DECOMPRESS_FAILED`**.

---

## 4. Artifact kinds (`kind` u16)

| `kind` | Name | Use |
|--------|------|-----|
| 0 | `RAW_BLOB` | Opaque bytes; semantics defined by caller. |
| 1 | `TENSOR_SLICE` | Future: typed tensor slab (dtype, shape in separate sidecar or extended header). **v1:** treat as opaque blob at container level. |
| 2 | `CHECKPOINT_EXACT` | Exact reproducibility tier (must be lossless + `uncompressed_len` set when compressed). |

Unknown `kind` → error (**do not** decode payload as truth for **Exact** workflows).

---

## 5. Codec registry (`codec_id` u16) — v1

| `codec_id` | Name | Notes |
|------------|------|--------|
| 0 | `IDENTITY` | No compression; `flags` bit0 **0**. |
| 1 | `ZLIB_DEFLATE` | **`zlib.compress` / `zlib.decompress`** (default zlib wrapper); `flags` bit0 **1**; **`uncompressed_len`** = original byte length; stored **`payload`** = compressed octets. **`CODEC_DECOMPRESS_FAILED`** if decompress raises. |

Adding **codec_id ≥ 2** requires: **round-trip harness**, **ERROR_SYSTEM** line for any new verifier exit, **CHANGELOG** entry.

---

## 6. Error identifiers (semantic)

Use in logs, `log_error`, and harness stderr (prefix optional):

- `CODEC_MAGIC_INVALID`
- `CODEC_VERSION_UNSUPPORTED`
- `CODEC_HEADER_INVALID`
- `CODEC_TRUNCATED`
- `CODEC_CRC_MISMATCH`
- `CODEC_KIND_UNKNOWN`
- `CODEC_CODEC_UNKNOWN`
- `CODEC_LENGTH_MISMATCH`
- `CODEC_DECOMPRESS_FAILED`

Map to process exit codes in **harness scripts** (not necessarily 1:1 with doc verifier **250–254**).

---

## 7. Relationship to LHA3

**LHA3** retention/compaction in **`azl/memory/`** and **`azl/quantum/memory/`** may remain **heuristic** per **[LHA3_COMPRESSION_HONESTY.md](LHA3_COMPRESSION_HONESTY.md)** until a path **writes** this container with **`kind=CHECKPOINT_EXACT`** and a **proven** codec. This spec does **not** rename LHA3 events; it adds a **parallel literal tier** for **Exact** claims.

---

## 8. Changelog (this spec)

| Date | Change |
|------|--------|
| 2026-03-20 | **v0** wire layout + **`AZL_LITERAL_CODEC_CONTAINER_CONTRACT_V1`**; codec_id **0–1**; reference **`tools/azl_literal_codec/`** (**identity** + **zlib** **`codec_id=1`**) + **`verify_azl_literal_codec_roundtrip.sh`**. |
