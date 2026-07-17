from pathlib import Path

import pytest

from mt_pipeline.eval import golden as G
from mt_pipeline.eval import metrics as M
from test_eval_golden import A, B, C, row

LONDON = (
    Path(__file__).resolve().parents[2]
    / "docs/superpowers/eval/real-uk-20260715-open-plaques-rerun-golden-london.tsv"
)


def test_precision_at_k_requires_at_least_k_labeled_rows():
    ranked = [
        row(A, "yes", 0.9, "yes"),
        row(B, "blank", 0.8, None),
        row(C, "no", 0.7, "no"),
    ]
    assert M.precision_at_k(ranked, 5, positive={"yes"}) is None
    assert M.precision_at_k(ranked, 2, positive={"yes"}) == 0.5
    assert M.precision_at_k(ranked, 2, positive={"yes", "meh"}) == 0.5


def test_precision_at_k_is_ranking_sensitive_when_k_is_interior():
    good = [
        row(A, "yes1", 1.0, "yes"),
        row(B, "yes2", 0.9, "yes"),
        row(C, "no1", 0.8, "no"),
        row("mt1_" + "3" * 26, "no2", 0.7, "no"),
    ]
    bad = [good[2], good[3], good[0], good[1]]
    assert M.precision_at_k(good, 2, positive={"yes"}) == 1.0
    assert M.precision_at_k(bad, 2, positive={"yes"}) == 0.0


def test_precision_at_k_handles_undefined_and_edges():
    assert M.precision_at_k([], 5, positive={"yes"}) is None
    assert M.precision_at_k([row(A, "x", 1.0, None)], 5, positive={"yes"}) is None
    assert M.precision_at_k([row(A, "x", 1.0, "yes")], 2, positive={"yes"}) is None
    assert M.precision_at_k([row(A, "x", 1.0, "yes")], 0, positive={"yes"}) is None
    assert M.precision_at_k([row(A, "x", 1.0, "yes")], 1, positive={"yes"}) == 1.0
    assert M.precision_at_k([row(A, "x", 1.0, "no")], 1, positive={"yes"}) == 0.0


def test_precision_at_k_treats_meh_as_positive_only_when_requested():
    ranked = [row(A, "meh", 1.0, "meh"), row(B, "no", 0.9, "no")]
    assert M.precision_at_k(ranked, 1, positive={"yes"}) == 0.0
    assert M.precision_at_k(ranked, 1, positive={"yes", "meh"}) == 1.0


def test_weighted_auc_uses_sample_weight():
    middle_negative = row(A, "no", 0.5, "no", sample_weight=1.0)
    high_tail_positive = row(C, "tail yes", 0.8, "yes", sample_weight=47.0)
    low_census_positive = row(B, "top yes", 0.1, "yes", sample_weight=1.0)
    weighted_with_tail_positive = M.weighted_auc(
        [middle_negative, high_tail_positive, low_census_positive],
        positive={"yes"},
    )
    neutered = M.weighted_auc(
        [
            row(A, "no", 0.5, "no", sample_weight=1.0),
            row(C, "tail yes", 0.8, "yes", sample_weight=1.0),
            row(B, "top yes", 0.1, "yes", sample_weight=1.0),
        ],
        positive={"yes"},
    )

    assert weighted_with_tail_positive == 47 / 48
    assert neutered == 0.5


def test_weighted_auc_ignores_unlabeled_rows():
    ranked = [
        row(A, "unlabeled high", 1.0, None, sample_weight=1000.0),
        row(B, "yes", 0.8, "yes", sample_weight=1.0),
        row(C, "no", 0.2, "no", sample_weight=1.0),
    ]

    assert M.weighted_auc(ranked, positive={"yes"}) == 1.0


def test_weighted_auc_gives_ties_half_credit():
    ranked = [
        row(A, "yes", 0.5, "yes", sample_weight=2.0),
        row(B, "no", 0.5, "no", sample_weight=3.0),
    ]

    assert M.weighted_auc(ranked, positive={"yes"}) == 0.5


def test_weighted_auc_rejects_invalid_direct_weights():
    ranked = [
        row(A, "yes", 0.5, "yes", sample_weight=-1.0),
        row(B, "no", 0.4, "no", sample_weight=1.0),
    ]

    try:
        M.weighted_auc(ranked, positive={"yes"})
    except ValueError as exc:
        assert "sample_weight" in str(exc)
    else:
        raise AssertionError("expected invalid sample_weight to raise")

    oversized = [
        row(A, "yes", 0.5, "yes", sample_weight=1_000_001.0),
        row(B, "no", 0.4, "no", sample_weight=1.0),
    ]
    try:
        M.weighted_auc(oversized, positive={"yes"})
    except ValueError as exc:
        assert "sample_weight" in str(exc)
    else:
        raise AssertionError("expected oversized sample_weight to raise")


def test_weighted_auc_rejects_non_finite_scores():
    ranked = [
        row(A, "yes", float("nan"), "yes", sample_weight=1.0),
        row(B, "no", 0.4, "no", sample_weight=1.0),
    ]

    with pytest.raises(ValueError, match="score"):
        M.weighted_auc(ranked, positive={"yes"})


def test_somers_d_uses_label_untied_denominator_and_matches_binary_auc():
    good = [
        row(A, "yes", 0.9, "yes"),
        row(B, "meh", 0.5, "meh"),
        row(C, "no", 0.1, "no"),
    ]
    tied_score = [
        row(A, "yes", 0.5, "yes"),
        row(B, "meh", 0.5, "meh"),
        row(C, "no", 0.1, "no"),
    ]
    bad_binary = [
        row(A, "yes", 0.1, "yes"),
        row(B, "no", 0.9, "no"),
        row(C, "no2", 0.8, "no"),
    ]

    assert M.somers_d(good, label_order=("no", "meh", "yes")) == 1.0
    assert M.somers_d(tied_score, label_order=("no", "meh", "yes")) == pytest.approx(
        2 / 3
    )
    auc = M.weighted_auc(bad_binary, positive={"yes"})
    d = M.somers_d(bad_binary, label_order=("no", "yes"))
    assert (d + 1) / 2 == auc
    assert d < 0


def test_paired_delong_test_detects_candidate_auc_delta():
    rows = [
        row("mt1_" + "0" * 26, "yes1", 0.1, "yes"),
        row("mt1_" + "1" * 26, "yes2", 0.2, "yes"),
        row("mt1_" + "2" * 26, "yes3", 0.3, "yes"),
        row("mt1_" + "3" * 26, "no1", 0.8, "no"),
        row("mt1_" + "4" * 26, "no2", 0.9, "no"),
        row("mt1_" + "5" * 26, "no3", 1.0, "no"),
    ]
    candidate_scores = {
        "mt1_" + "0" * 26: 1.0,
        "mt1_" + "1" * 26: 0.9,
        "mt1_" + "2" * 26: 0.8,
        "mt1_" + "3" * 26: 0.3,
        "mt1_" + "4" * 26: 0.2,
        "mt1_" + "5" * 26: 0.1,
    }
    result = M.paired_delong_test(rows, candidate_scores, positive={"yes"})

    assert result is not None
    assert result.baseline_auc == 0.0
    assert result.candidate_auc == 1.0
    assert result.delta == 1.0
    assert result.p_value < 0.05


def test_paired_delong_test_uses_finite_covariance_path():
    rows = [
        row("mt1_" + "0" * 26, "yes1", 0.9, "yes"),
        row("mt1_" + "1" * 26, "yes2", 0.4, "yes"),
        row("mt1_" + "2" * 26, "yes3", 0.3, "yes"),
        row("mt1_" + "3" * 26, "no1", 0.8, "no"),
        row("mt1_" + "4" * 26, "no2", 0.5, "no"),
        row("mt1_" + "5" * 26, "no3", 0.2, "no"),
    ]
    candidate_scores = {
        "mt1_" + "0" * 26: 0.95,
        "mt1_" + "1" * 26: 0.85,
        "mt1_" + "2" * 26: 0.3,
        "mt1_" + "3" * 26: 0.7,
        "mt1_" + "4" * 26: 0.45,
        "mt1_" + "5" * 26: 0.1,
    }

    result = M.paired_delong_test(rows, candidate_scores, positive={"yes"})
    same = M.paired_delong_test(
        rows,
        {row.place_id: row.score for row in rows},
        positive={"yes"},
    )

    assert result is not None
    assert result.baseline_auc == pytest.approx(5 / 9)
    assert result.candidate_auc == pytest.approx(7 / 9)
    assert result.z == pytest.approx(0.8944271909999163)
    assert result.p_value == pytest.approx(0.3710933695226974)
    assert same is not None
    assert same.delta == 0.0
    assert same.z == 0.0
    assert same.p_value == 1.0


def test_paired_delong_rejects_missing_or_non_finite_candidate_scores():
    rows = [
        row(A, "yes", 0.8, "yes"),
        row(B, "no", 0.2, "no"),
    ]

    with pytest.raises(ValueError, match="missing candidate scores"):
        M.paired_delong_test(rows, {A: 0.9}, positive={"yes"})

    with pytest.raises(ValueError, match="candidate score"):
        M.paired_delong_test(
            rows,
            {A: 0.9, B: float("nan")},
            positive={"yes"},
        )

    weighted = [
        row(A, "yes", 0.8, "yes", sample_weight=46.8066666667),
        row(B, "no", 0.2, "no", sample_weight=1.0),
    ]
    with pytest.raises(ValueError, match="unit sample_weight"):
        M.paired_delong_test(weighted, {A: 0.9, B: 0.1}, positive={"yes"})


def test_stratified_bootstrap_auc_ci_resamples_tail_only_deterministically():
    census = [
        row(A, "top yes", 0.9, "yes", sample_weight=1.0),
        row(B, "top no", 0.8, "no", sample_weight=1.0),
    ]
    tail = [
        row(C, "tail yes", 0.7, "yes", sample_weight=46.8066666667),
        row("mt1_" + "3" * 26, "tail no", 0.1, "no", sample_weight=46.8066666667),
    ]

    first = M.stratified_bootstrap_auc_ci(
        census,
        tail,
        positive={"yes"},
        iterations=200,
        seed=17,
    )
    second = M.stratified_bootstrap_auc_ci(
        census,
        tail,
        positive={"yes"},
        iterations=200,
        seed=17,
    )

    assert first == second
    assert first.point == M.weighted_auc([*census, *tail], positive={"yes"})
    assert 0.0 <= first.lower <= first.point <= first.upper <= 1.0


def test_stratified_bootstrap_auc_ci_resamples_tail_classes_separately():
    census = [
        row(A, "top yes", 0.9, "yes", sample_weight=1.0),
        row(B, "top no", 0.8, "no", sample_weight=1.0),
    ]
    one_per_class_tail = [
        row(C, "tail yes", 0.7, "yes", sample_weight=46.8066666667),
        row("mt1_" + "3" * 26, "tail no", 0.1, "no", sample_weight=46.8066666667),
        row("mt1_" + "4" * 26, "tail unlabeled", 1.0, None, sample_weight=46.8066666667),
        row("mt1_" + "5" * 26, "tail unlabeled 2", 0.0, None, sample_weight=46.8066666667),
    ]
    ci = M.stratified_bootstrap_auc_ci(
        census,
        one_per_class_tail,
        positive={"yes"},
        iterations=100,
        seed=23,
    )

    assert ci is not None
    assert ci.lower == ci.point == ci.upper


def test_stratified_bootstrap_auc_ci_has_non_degenerate_tail_interval():
    census = [
        row(A, "top yes", 0.9, "yes", sample_weight=1.0),
        row(B, "top no", 0.8, "no", sample_weight=1.0),
    ]
    tail = [
        row(C, "tail yes high", 0.7, "yes", sample_weight=46.8066666667),
        row("mt1_" + "3" * 26, "tail yes low", 0.05, "yes", sample_weight=46.8066666667),
        row("mt1_" + "4" * 26, "tail no high", 0.6, "no", sample_weight=46.8066666667),
        row("mt1_" + "5" * 26, "tail no low", 0.1, "no", sample_weight=46.8066666667),
    ]
    ci = M.stratified_bootstrap_auc_ci(
        census,
        tail,
        positive={"yes"},
        iterations=300,
        seed=29,
    )

    assert ci is not None
    assert ci.lower < ci.point < ci.upper


def test_london_tail_sample_weight_matches_design_ratio():
    lines = LONDON.read_text().splitlines()
    data_lines = lines[4:]
    tail_weight = (len(data_lines) - 150) / 150
    assert tail_weight == pytest.approx(46.8066666667)
    parsed = G.parse_labeled_tsv(LONDON.read_text())
    assert parsed.skipped == []

    assert {row.sample_weight for row in parsed.rows[:150]} == {1.0}
    tail_weights = {row.sample_weight for row in parsed.rows[150:]}
    assert len(tail_weights) == 1
    assert next(iter(tail_weights)) == pytest.approx(tail_weight)
