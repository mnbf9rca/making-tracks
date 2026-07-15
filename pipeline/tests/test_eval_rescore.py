from mt_pipeline.eval import golden as G
from mt_pipeline.eval import rescore as RS
from test_eval_golden import A, B, Z, row


def fake_score(sig, cfg):
    return sum(cfg.get(k, 0) * v for k, v in sig.items() if v is not None)


def test_rescore_ranks_by_config_offline():
    rows = [row(A, "x", 0.0, article=0.9), row(B, "y", 0.0, article=0.1)]
    ranked = RS.rescore(rows, {"article": 1.0}, score_fn=fake_score)
    assert [r.place_id for r in ranked] == [A, B]
    assert [r.score for r in ranked] == [0.9, 0.1]


def test_llm_off_flips_the_ranking():
    rows = [
        G.GoldenRow(
            A,
            "l",
            "a",
            0,
            0,
            "c",
            1,
            0,
            {"article": 0.5, "llm_curiosity": 0.0},
            None,
            "v1",
        ),
        G.GoldenRow(
            Z,
            "l",
            "z",
            0,
            0,
            "c",
            1,
            0,
            {"article": 0.5, "llm_curiosity": 0.9},
            None,
            "v1",
        ),
    ]
    on = [
        r.place_id
        for r in RS.rescore(
            rows,
            {"article": 1, "llm_curiosity": 1},
            score_fn=fake_score,
            llm_on=True,
        )
    ]
    off = [
        r.place_id
        for r in RS.rescore(
            rows,
            {"article": 1, "llm_curiosity": 1},
            score_fn=fake_score,
            llm_on=False,
        )
    ]
    assert on == [Z, A]
    assert off == [A, Z]


def test_real_a4_composite_signature_is_bound():
    from mt_pipeline.score.composite import score

    cfg = {"weights": {"article": 1.0, "llm_curiosity": 1.0}, "boost_weight": 0.0}
    assert score({"article": 1.0, "llm_curiosity": None}, cfg) == 1.0
