"""CRC-32C (Castagnoli) — same polynomial as spec §2 (verify vector: ``123456789`` → ``0xE3069283``)."""

from __future__ import annotations

_POLY = 0x82F63B78
_TABLE: list[int] = []
for _i in range(256):
    c = _i
    for _ in range(8):
        if c & 1:
            c = (c >> 1) ^ _POLY
        else:
            c >>= 1
    _TABLE.append(c & 0xFFFFFFFF)


def crc32c(data: bytes, seed: int = 0xFFFFFFFF) -> int:
    c = seed & 0xFFFFFFFF
    for b in data:
        c = _TABLE[(c ^ b) & 0xFF] ^ (c >> 8)
    return (~c) & 0xFFFFFFFF
