from mt_pipeline.eval import metrics as M
from test_eval_golden import A, B, C, row


def test_precision_at_k_uses_labeled_top_min_k_n_labeled():
    ranked = [
        row(A, "yes", 0.9, "yes"),
        row(B, "blank", 0.8, None),
        row(C, "no", 0.7, "no"),
    ]
    assert M.precision_at_k(ranked, 5, positive={"yes"}) == 0.5
    assert M.precision_at_k(ranked, 5, positive={"yes", "meh"}) == 0.5


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
