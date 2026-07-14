"""Deterministic gzip and bomb-safe gunzip helpers for tile bytes."""

from __future__ import annotations

import gzip
import json
import zlib

from .caps import MAX_TILE_COMPRESSED_BYTES, MAX_TILE_UNCOMPRESSED_BYTES


def gzip_tile(obj, max_compressed_bytes: int = MAX_TILE_COMPRESSED_BYTES) -> bytes:
    raw = json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    if len(raw) > MAX_TILE_UNCOMPRESSED_BYTES:
        raise ValueError("gzip tile exceeded MAX_TILE_UNCOMPRESSED_BYTES")
    encoded = gzip.compress(raw, mtime=0)
    if len(encoded) > max_compressed_bytes:
        raise ValueError("gzip tile exceeded max_compressed_bytes")
    return encoded


def safe_gunzip(
    data: bytes,
    max_bytes: int = MAX_TILE_UNCOMPRESSED_BYTES,
    max_compressed_bytes: int = MAX_TILE_COMPRESSED_BYTES,
) -> bytes:
    if len(data) > max_compressed_bytes:
        raise ValueError("gzip input exceeded max_compressed_bytes")
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
