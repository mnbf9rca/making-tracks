"""Deterministic gzip and bomb-safe gunzip helpers for tile bytes."""

from __future__ import annotations

import gzip
import json
import zlib

from .caps import MAX_TILE_UNCOMPRESSED_BYTES


def gzip_tile(obj) -> bytes:
    raw = json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return gzip.compress(raw, mtime=0)


def safe_gunzip(data: bytes, max_bytes: int = MAX_TILE_UNCOMPRESSED_BYTES) -> bytes:
    decoder = zlib.decompressobj(wbits=16 + zlib.MAX_WBITS)
    out = bytearray()

    for index in range(0, len(data), 65536):
        pending = data[index:index + 65536]
        while pending:
            chunk = decoder.decompress(pending, max_bytes - len(out) + 1)
            out += chunk
            if len(out) > max_bytes:
                raise ValueError("gunzip exceeded max_bytes")
            pending = decoder.unconsumed_tail

    tail = decoder.flush(max_bytes - len(out) + 1)
    out += tail
    if len(out) > max_bytes:
        raise ValueError("gunzip exceeded max_bytes")
    if not decoder.eof or decoder.unused_data:
        raise ValueError("invalid gzip stream")
    return bytes(out)
