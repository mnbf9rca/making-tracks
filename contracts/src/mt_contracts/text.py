"""Text-safety helpers shared by pipeline stages and schemas."""

from __future__ import annotations

import re

SAFE_TEXT_PATTERN = (
    r"^[^\u0000-\u001f\u007f-\u009f\u200b\u200c\u200d"
    r"\u2028\u2029\u202a-\u202e\u2060\u2066-\u2069\ufeff]*$"
)
SAFE_TEXT_RE = re.compile(SAFE_TEXT_PATTERN)


def _is_unsafe_text_char(ch: str) -> bool:
    codepoint = ord(ch)
    return (
        codepoint <= 0x001F
        or 0x007F <= codepoint <= 0x009F
        or codepoint in {0x200B, 0x200C, 0x200D, 0x2028, 0x2029, 0x2060, 0xFEFF}
        or 0x202A <= codepoint <= 0x202E
        or 0x2066 <= codepoint <= 0x2069
    )


def strip_unsafe_text(value: str) -> str:
    """Remove exactly the codepoints denied by SAFE_TEXT, preserving LRM/RLM."""
    return "".join(ch for ch in value if not _is_unsafe_text_char(ch))
