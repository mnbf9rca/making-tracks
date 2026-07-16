"""Ranking metrics for golden-area evaluation."""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass
import math
import random

from .golden import GoldenRow, MAX_SAMPLE_WEIGHT


@dataclass(frozen=True)
class DeLongResult:
    baseline_auc: float
    candidate_auc: float
    delta: float
    z: float
    p_value: float


@dataclass(frozen=True)
class BootstrapCI:
    point: float
    lower: float
    upper: float


def precision_at_k(
    ranked: Sequence[GoldenRow],
    k: int,
    *,
    positive: Iterable[str],
) -> float | None:
    if k <= 0:
        return None
    # p@k is descriptive only: unlabeled rows are filtered before k, so this
    # metric ignores sample_weight; London promotion must use IPW AUC instead.
    labeled = [row for row in ranked if row.label is not None]
    if len(labeled) < k:
        return None
    positives = set(positive)
    top = labeled[:k]
    return sum(1 for row in top if row.label in positives) / k


def weighted_auc(
    ranked: Sequence[GoldenRow],
    *,
    positive: Iterable[str],
) -> float | None:
    positives = set(positive)
    pos = [row for row in ranked if row.label in positives]
    neg = [row for row in ranked if row.label is not None and row.label not in positives]
    for row in [*pos, *neg]:
        _validate_score(row.score, field=f"score for {row.place_id}")
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
            if p.score > n.score:
                wins += pair_weight
            elif p.score == n.score:
                wins += 0.5 * pair_weight
    auc = wins / total_weight
    if not math.isfinite(auc):
        raise ValueError("weighted AUC is non-finite")
    return auc


def somers_d(
    ranked: Sequence[GoldenRow],
    *,
    label_order: Sequence[str],
) -> float | None:
    label_rank = {label: index for index, label in enumerate(label_order)}
    rows = [row for row in ranked if row.label in label_rank]
    denominator = 0
    numerator = 0.0
    for left_index, left in enumerate(rows):
        for right in rows[left_index + 1 :]:
            label_delta = _sign(label_rank[left.label] - label_rank[right.label])
            if label_delta == 0:
                continue
            denominator += 1
            score_delta = _sign(left.score - right.score)
            numerator += label_delta * score_delta
    if denominator == 0:
        return None
    return numerator / denominator


def paired_delong_test(
    baseline: Sequence[GoldenRow],
    candidate_scores: dict[str, float],
    *,
    positive: Iterable[str],
) -> DeLongResult | None:
    positives = set(positive)
    rows = [row for row in baseline if row.label is not None]
    missing = sorted(row.place_id for row in rows if row.place_id not in candidate_scores)
    if missing:
        raise ValueError(f"missing candidate scores for {len(missing)} labeled rows")
    for row in rows:
        if row.sample_weight != 1.0:
            raise ValueError("paired DeLong requires unit sample_weight")
    pos = [row for row in rows if row.label in positives]
    neg = [row for row in rows if row.label not in positives]
    if not pos or not neg:
        return None

    baseline_pos = [
        _validate_score(row.score, field=f"score for {row.place_id}") for row in pos
    ]
    baseline_neg = [
        _validate_score(row.score, field=f"score for {row.place_id}") for row in neg
    ]
    candidate_pos = [
        _validate_score(
            candidate_scores[row.place_id],
            field=f"candidate score for {row.place_id}",
        )
        for row in pos
    ]
    candidate_neg = [
        _validate_score(
            candidate_scores[row.place_id],
            field=f"candidate score for {row.place_id}",
        )
        for row in neg
    ]
    baseline_auc, baseline_v10, baseline_v01 = _delong_vectors(
        baseline_pos, baseline_neg
    )
    candidate_auc, candidate_v10, candidate_v01 = _delong_vectors(
        candidate_pos, candidate_neg
    )

    var_baseline = _sample_variance(baseline_v10) / len(pos) + _sample_variance(
        baseline_v01
    ) / len(neg)
    var_candidate = _sample_variance(candidate_v10) / len(pos) + _sample_variance(
        candidate_v01
    ) / len(neg)
    covar = _sample_covariance(baseline_v10, candidate_v10) / len(pos)
    covar += _sample_covariance(baseline_v01, candidate_v01) / len(neg)
    variance = max(0.0, var_baseline + var_candidate - 2 * covar)
    delta = candidate_auc - baseline_auc
    if variance == 0:
        z = math.copysign(math.inf, delta) if delta else 0.0
        p_value = 0.0 if delta else 1.0
    else:
        z = delta / math.sqrt(variance)
        p_value = math.erfc(abs(z) / math.sqrt(2.0))
    return DeLongResult(
        baseline_auc=baseline_auc,
        candidate_auc=candidate_auc,
        delta=delta,
        z=z,
        p_value=p_value,
    )


def stratified_bootstrap_auc_ci(
    census_rows: Sequence[GoldenRow],
    tail_rows: Sequence[GoldenRow],
    *,
    positive: Iterable[str],
    iterations: int = 1000,
    confidence: float = 0.95,
    seed: int = 0,
) -> BootstrapCI | None:
    if iterations <= 0:
        raise ValueError("iterations must be positive")
    if not 0 < confidence < 1:
        raise ValueError("confidence must be between 0 and 1")
    point = weighted_auc([*census_rows, *tail_rows], positive=positive)
    if point is None:
        return None
    rng = random.Random(seed)
    values = []
    positives = set(positive)
    tail_pos = [row for row in tail_rows if row.label in positives]
    tail_neg = [
        row for row in tail_rows if row.label is not None and row.label not in positives
    ]
    for _ in range(iterations):
        sample = [
            *(rng.choice(tail_pos) for _ in range(len(tail_pos))),
            *(rng.choice(tail_neg) for _ in range(len(tail_neg))),
        ]
        value = weighted_auc([*census_rows, *sample], positive=positive)
        if value is not None:
            values.append(value)
    if not values:
        return None
    values.sort()
    alpha = 1.0 - confidence
    lower = _percentile(values, alpha / 2)
    upper = _percentile(values, 1 - alpha / 2)
    return BootstrapCI(point=point, lower=lower, upper=upper)


def _delong_vectors(
    pos_scores: Sequence[float],
    neg_scores: Sequence[float],
) -> tuple[float, list[float], list[float]]:
    v10 = [
        sum(_pair_credit(pos_score, neg_score) for neg_score in neg_scores)
        / len(neg_scores)
        for pos_score in pos_scores
    ]
    v01 = [
        sum(_pair_credit(pos_score, neg_score) for pos_score in pos_scores)
        / len(pos_scores)
        for neg_score in neg_scores
    ]
    return sum(v10) / len(v10), v10, v01


def _pair_credit(pos_score: float, neg_score: float) -> float:
    if pos_score > neg_score:
        return 1.0
    if pos_score == neg_score:
        return 0.5
    return 0.0


def _validate_score(value: float, *, field: str) -> float:
    score = float(value)
    if not math.isfinite(score):
        raise ValueError(f"invalid {field}")
    return score


def _sample_variance(values: Sequence[float]) -> float:
    return _sample_covariance(values, values)


def _sample_covariance(left: Sequence[float], right: Sequence[float]) -> float:
    if len(left) != len(right):
        raise ValueError("covariance inputs must have equal length")
    if len(left) < 2:
        return 0.0
    left_mean = sum(left) / len(left)
    right_mean = sum(right) / len(right)
    return sum(
        (left_value - left_mean) * (right_value - right_mean)
        for left_value, right_value in zip(left, right)
    ) / (len(left) - 1)


def _percentile(values: Sequence[float], q: float) -> float:
    if len(values) == 1:
        return values[0]
    position = q * (len(values) - 1)
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return values[lower]
    fraction = position - lower
    return values[lower] * (1 - fraction) + values[upper] * fraction


def _sign(value: float) -> int:
    if value > 0:
        return 1
    if value < 0:
        return -1
    return 0
