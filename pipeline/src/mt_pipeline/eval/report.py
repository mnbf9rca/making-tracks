"""Eval report and ranking regression gate."""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from .golden import GoldenRow
from .metrics import precision_at_k
from .rescore import ScoreFn, rescore

STRICT_POSITIVE = frozenset({"yes"})
LENIENT_POSITIVE = frozenset({"yes", "meh"})
DEFAULT_KS = (5, 10, 20)
LLM_OFF_FLOOR = 1.0


@dataclass(frozen=True)
class EvalReport:
    metrics: dict[str, float | None]


def _area_key(row: GoldenRow) -> str:
    return row.area or "all"


def eval_report(
    labeled_rows: Sequence[GoldenRow],
    config: Any,
    *,
    score_fn: ScoreFn | None = None,
    ks: Sequence[int] = DEFAULT_KS,
) -> EvalReport:
    grouped: dict[str, list[GoldenRow]] = defaultdict(list)
    for row in labeled_rows:
        grouped[_area_key(row)].append(row)

    metrics: dict[str, float | None] = {}
    for area in sorted(grouped):
        rows = grouped[area]
        for variant, llm_on in (("llm_on", True), ("llm_off", False)):
            ranked = rescore(rows, config, score_fn=score_fn, llm_on=llm_on)
            for k in ks:
                metrics[f"{area}.{variant}.strict@{k}"] = precision_at_k(
                    ranked, k, positive=STRICT_POSITIVE
                )
                metrics[f"{area}.{variant}.lenient@{k}"] = precision_at_k(
                    ranked, k, positive=LENIENT_POSITIVE
                )
    return EvalReport(metrics=metrics)


def assert_no_regression(
    labeled_rows: Sequence[GoldenRow],
    config: Any,
    baseline: Mapping[str, float],
    *,
    score_fn: ScoreFn | None = None,
) -> None:
    result = eval_report(labeled_rows, config, score_fn=score_fn)
    failures = []
    for key, expected in sorted(baseline.items()):
        actual = result.metrics.get(key)
        if actual is None or actual < expected:
            failures.append(f"{key}: actual={actual!r} baseline={expected!r}")
    if failures:
        raise AssertionError("ranking regression: " + "; ".join(failures))

