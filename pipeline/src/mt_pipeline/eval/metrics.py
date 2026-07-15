"""Ranking metrics for golden-area evaluation."""

from __future__ import annotations

from collections.abc import Iterable, Sequence

from .golden import GoldenRow


def precision_at_k(
    ranked: Sequence[GoldenRow],
    k: int,
    *,
    positive: Iterable[str],
) -> float | None:
    labeled = [row for row in ranked if row.label is not None]
    denom = min(k, len(labeled))
    if denom <= 0:
        return None
    positives = set(positive)
    top = labeled[:denom]
    return sum(1 for row in top if row.label in positives) / denom

