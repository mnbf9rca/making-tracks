"""Ranking metrics for golden-area evaluation."""

from __future__ import annotations

from collections.abc import Iterable, Sequence
import math

from .golden import GoldenRow, MAX_SAMPLE_WEIGHT


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


def weighted_auc(
    ranked: Sequence[GoldenRow],
    *,
    positive: Iterable[str],
) -> float | None:
    positives = set(positive)
    pos = [row for row in ranked if row.label in positives]
    neg = [row for row in ranked if row.label is not None and row.label not in positives]
    for row in [*pos, *neg]:
        if (
            not math.isfinite(row.sample_weight)
            or row.sample_weight <= 0
            or row.sample_weight > MAX_SAMPLE_WEIGHT
        ):
            raise ValueError(f"invalid sample_weight for {row.place_id}")

    total_weight = sum(p.sample_weight * n.sample_weight for p in pos for n in neg)
    if not math.isfinite(total_weight):
        raise ValueError("sample_weight pair total is non-finite")
    if total_weight <= 0:
        return None

    wins = 0.0
    for p in pos:
        for n in neg:
            pair_weight = p.sample_weight * n.sample_weight
            if not math.isfinite(pair_weight):
                raise ValueError("sample_weight pair product is non-finite")
            if p.score > n.score:
                wins += pair_weight
            elif p.score == n.score:
                wins += 0.5 * pair_weight
    auc = wins / total_weight
    if not math.isfinite(auc):
        raise ValueError("weighted AUC is non-finite")
    return auc
