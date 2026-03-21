"""
AZL0 container v1 — encode/decode (identity + zlib DEFLATE).

Raises CodecError with semantic codes matching docs/AZL_LITERAL_CODEC_CONTAINER_V0.md §6.
"""

from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass

from azl_literal_codec.crc32c import crc32c

MAGIC = b"AZL0"
FORMAT_VERSION_V1 = 1
HEADER_LEN_V1 = 32

# Kinds (spec §4)
KIND_RAW_BLOB = 0
KIND_TENSOR_SLICE = 1
KIND_CHECKPOINT_EXACT = 2

KNOWN_KINDS = frozenset({KIND_RAW_BLOB, KIND_TENSOR_SLICE, KIND_CHECKPOINT_EXACT})

# Codecs (spec §5)
CODEC_IDENTITY = 0
CODEC_ZLIB_DEFLATE = 1


@dataclass(frozen=True)
class CodecError(Exception):
    """Logical codec failure; do not use for I/O."""

    semantic: str
    exit_code: int

    def __str__(self) -> str:  # pragma: no cover
        return f"{self.semantic}"


@dataclass(frozen=True)
class DecodedV1:
    kind: int
    codec_id: int
    flags: int
    uncompressed_len: int
    payload: bytes


def _pack_header(
    flags: int,
    kind: int,
    codec_id: int,
    uncompressed_len: int,
    payload_len: int,
) -> bytes:
    header = struct.pack(
        "<4sIHHHHQQ",
        MAGIC,
        FORMAT_VERSION_V1,
        HEADER_LEN_V1,
        flags,
        kind,
        codec_id,
        uncompressed_len,
        payload_len,
    )
    if len(header) != HEADER_LEN_V1:
        raise RuntimeError("internal: header size mismatch")
    return header


def encode_identity_v1(
    payload: bytes,
    *,
    kind: int = KIND_RAW_BLOB,
) -> bytes:
    """
    Identity storage: flags bit0 = 0, codec_id = 0.
    uncompressed_len and payload_len both equal len(payload).
    """
    if kind not in KNOWN_KINDS:
        raise CodecError("CODEC_KIND_UNKNOWN", 268)
    flags = 0
    codec_id = CODEC_IDENTITY
    ulen = len(payload)
    plen = len(payload)
    header = _pack_header(flags, kind, codec_id, ulen, plen)
    body = header + payload
    return body + struct.pack("<I", crc32c(body))


def encode_zlib_v1(
    payload: bytes,
    *,
    kind: int = KIND_RAW_BLOB,
    level: int = 6,
) -> bytes:
    """
    zlib-wrapped DEFLATE (``zlib.compress``): flags bit0 = 1, codec_id = 1.
    ``uncompressed_len`` = original byte length; stored payload = compressed octets.
    """
    if kind not in KNOWN_KINDS:
        raise CodecError("CODEC_KIND_UNKNOWN", 268)
    flags = 1
    codec_id = CODEC_ZLIB_DEFLATE
    ulen = len(payload)
    compressed = zlib.compress(payload, level=level)
    plen = len(compressed)
    header = _pack_header(flags, kind, codec_id, ulen, plen)
    body = header + compressed
    return body + struct.pack("<I", crc32c(body))


def decode_container_v1(data: bytes) -> DecodedV1:
    if len(data) < HEADER_LEN_V1 + 4:
        raise CodecError("CODEC_TRUNCATED", 263)
    if data[:4] != MAGIC:
        raise CodecError("CODEC_MAGIC_INVALID", 264)
    (
        _magic,
        fmt_ver,
        header_len,
        flags,
        kind,
        codec_id,
        uncompressed_len,
        payload_len,
    ) = struct.unpack_from("<4sIHHHHQQ", data, 0)
    if fmt_ver != FORMAT_VERSION_V1:
        raise CodecError("CODEC_VERSION_UNSUPPORTED", 265)
    if header_len < HEADER_LEN_V1 or header_len > len(data):
        raise CodecError("CODEC_HEADER_INVALID", 266)
    need = header_len + payload_len + 4
    if need > len(data) or need < header_len:
        raise CodecError("CODEC_TRUNCATED", 263)
    protected = data[: header_len + payload_len]
    stored_crc = struct.unpack_from("<I", data, header_len + payload_len)[0]
    if crc32c(protected) != stored_crc:
        raise CodecError("CODEC_CRC_MISMATCH", 267)
    if kind not in KNOWN_KINDS:
        raise CodecError("CODEC_KIND_UNKNOWN", 268)

    raw_payload = data[header_len : header_len + payload_len]
    compressed = (flags & 1) != 0

    if compressed:
        if codec_id != CODEC_ZLIB_DEFLATE:
            raise CodecError("CODEC_CODEC_UNKNOWN", 269)
        try:
            plain = zlib.decompress(raw_payload)
        except zlib.error as e:
            raise CodecError("CODEC_DECOMPRESS_FAILED", 271) from e
        if uncompressed_len != 0 and len(plain) != uncompressed_len:
            raise CodecError("CODEC_LENGTH_MISMATCH", 270)
        return DecodedV1(
            kind=kind,
            codec_id=codec_id,
            flags=flags,
            uncompressed_len=uncompressed_len,
            payload=plain,
        )

    if codec_id != CODEC_IDENTITY:
        raise CodecError("CODEC_HEADER_INVALID", 266)
    if uncompressed_len != 0 and uncompressed_len != len(raw_payload):
        raise CodecError("CODEC_LENGTH_MISMATCH", 270)
    return DecodedV1(
        kind=kind,
        codec_id=codec_id,
        flags=flags,
        uncompressed_len=uncompressed_len,
        payload=raw_payload,
    )
