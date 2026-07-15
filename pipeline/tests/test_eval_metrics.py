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
