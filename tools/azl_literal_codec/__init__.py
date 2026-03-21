"""
AZL literal container (format v1) — reference encoder/decoder.

Normative spec: docs/AZL_LITERAL_CODEC_CONTAINER_V0.md
"""

from azl_literal_codec.container_v1 import (
    CodecError,
    decode_container_v1,
    encode_identity_v1,
    encode_zlib_v1,
)

__all__ = [
    "CodecError",
    "decode_container_v1",
    "encode_identity_v1",
    "encode_zlib_v1",
]
