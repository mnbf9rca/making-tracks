"""Offline re-scoring from dumped signal values."""

from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from dataclasses import replace
from typing import Any

from .golden import GoldenRow

ScoreFn = Callable[[Mapping[str, float | None], Any], float]


def _default_score(signals: Mapping[str, float | None], config: Any) -> float:
    try:
        from mt_pipeline.score.composite import score
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "BLOCKED-ON A4: mt_pipeline.score.composite.score is not available"
        ) from exc
    return score(signals, config)


def rescore(
    rows: Sequence[GoldenRow],
    config: Any,
    *,
    score_fn: ScoreFn | None = None,
    llm_on: bool = True,
) -> list[GoldenRow]:
    scorer = score_fn or _default_score
    rescored = []
    for row in rows:
        signals = dict(row.signals)
        if not llm_on:
            signals["llm_curiosity"] = None
        score = scorer(signals, config)
        rescored.append(replace(row, score=score, signals=signals))
    return sorted(rescored, key=lambda r: (-r.score, r.place_id))

