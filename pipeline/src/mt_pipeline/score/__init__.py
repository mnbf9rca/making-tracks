"""Heuristic scoring primitives for Making Tracks places."""

from __future__ import annotations

ADDITIVE_SIGNAL_NAMES = (
    "article",
    "sitelinks",
    "heritage",
    "plaque",
    "image",
    "tag_rarity",
    "pageviews",
    "llm_curiosity",
)
SIGNAL_NAMES = (*ADDITIVE_SIGNAL_NAMES, "class_penalty")

__all__ = ("ADDITIVE_SIGNAL_NAMES", "SIGNAL_NAMES")
