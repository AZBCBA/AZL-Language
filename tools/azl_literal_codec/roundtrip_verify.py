#!/usr/bin/env python3
"""
Harness: AZL0 v1 identity + zlib round-trip + negative cases.

Exit codes: see docs/ERROR_SYSTEM.md § AZL literal codec round-trip harness.
"""

from __future__ import annotations

import os
import struct
import sys

# tools/ on path when invoked via -m from repo root with PYTHONPATH=tools
from azl_literal_codec.crc32c import crc32c
from azl_literal_codec.container_v1 import (
    KIND_CHECKPOINT_EXACT,
    KIND_RAW_BLOB,
    CodecError,
    decode_container_v1,
    encode_identity_v1,
    encode_zlib_v1,
)


def _fail(msg: str, code: int) -> None:
    print(f"ERROR[AZL_LITERAL_CODEC_ROUNDTRIP]: {msg}", file=sys.stderr)
    raise SystemExit(code)


def _assert_roundtrip(
    label: str,
    blob: bytes,
    *,
    kind: int = KIND_RAW_BLOB,
    zlib_compress: bool = False,
) -> None:
    try:
        if zlib_compress:
            enc = encode_zlib_v1(blob, kind=kind)
        else:
            enc = encode_identity_v1(blob, kind=kind)
    except CodecError as e:
        _fail(f"{label} encode: {e.semantic}", e.exit_code)
    try:
        dec = decode_container_v1(enc)
    except CodecError as e:
        _fail(f"{label} decode: {e.semantic}", e.exit_code)
    if dec.payload != blob:
        _fail(f"{label} payload mismatch", 262)
    if dec.kind != kind:
        _fail(f"{label} kind mismatch", 262)


def _assert_error(label: str, data: bytes, expect_semantic: str) -> None:
    try:
        decode_container_v1(data)
    except CodecError as e:
        if e.semantic != expect_semantic:
            _fail(f"{label} expected {expect_semantic} got {e.semantic}", 262)
        return
    _fail(f"{label} expected CodecError {expect_semantic}", 262)


def main() -> int:
    if not os.path.isfile("Makefile") or not os.path.isdir("azl"):
        _fail("must run from repository root", 260)

    _assert_roundtrip("empty", b"")
    _assert_roundtrip("ascii", b"hello-azl-literal-codec")
    _assert_roundtrip("binary", bytes(range(256)))
    _assert_roundtrip("repeat", b"a" * 4096)
    _assert_roundtrip("checkpoint_kind", b"weights-bytes-here", kind=KIND_CHECKPOINT_EXACT)

    _assert_roundtrip("zlib_empty", b"", zlib_compress=True)
    _assert_roundtrip("zlib_text", b"compress-me " * 500, zlib_compress=True)
    _assert_roundtrip("zlib_checkpoint", b"w" * 8000, kind=KIND_CHECKPOINT_EXACT, zlib_compress=True)

    zgood = encode_zlib_v1(b"payload", kind=KIND_RAW_BLOB)
    zb = bytearray(zgood)
    hl = 32
    plen = struct.unpack_from("<Q", zb, 24)[0]
    zb[hl + 1] ^= 0xFF
    body = bytes(zb[: hl + plen])
    zb[hl + plen : hl + plen + 4] = struct.pack("<I", crc32c(body))
    _assert_error("zlib_invalid_stream", bytes(zb), "CODEC_DECOMPRESS_FAILED")

    good = encode_identity_v1(b"x", kind=KIND_RAW_BLOB)
    bad_crc = bytearray(good)
    bad_crc[-1] ^= 0xFF
    _assert_error("crc_tamper", bytes(bad_crc), "CODEC_CRC_MISMATCH")

    _assert_error("bad_magic", b"XXXX" + good[4:], "CODEC_MAGIC_INVALID")
    _assert_error("truncated", good[:20], "CODEC_TRUNCATED")

    ver = encode_identity_v1(b"v", kind=KIND_RAW_BLOB)
    bver = bytearray(ver)
    struct.pack_into("<I", bver, 4, 999)
    _assert_error("bad_format_version", bytes(bver), "CODEC_VERSION_UNSUPPORTED")

    print("azl-literal-codec-roundtrip-ok")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as exc:
        print(f"ERROR[AZL_LITERAL_CODEC_ROUNDTRIP]: unexpected {exc!r}", file=sys.stderr)
        raise SystemExit(262) from exc
