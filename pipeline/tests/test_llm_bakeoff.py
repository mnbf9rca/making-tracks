import pytest

from mt_pipeline.eval.golden import GoldenRow
from mt_pipeline.llm import bakeoff as B
from mt_pipeline.llm.providers.fake import FakeProvider


def fake_composite(sig, cfg):
    return sum(cfg.get(k, 0) * v for k, v in sig.items() if v is not None)


def _row(pid: str, article: float, label: str) -> GoldenRow:
    return GoldenRow(
        pid,
        "kl",
        "n",
        3.1,
        101.6,
        "history",
        2,
        0.0,
        {"article": article, "llm_curiosity": None},
        label,
        data_version="v1",
    )


def test_bakeoff_lift_comes_from_a5_precision_at_k():
    rows = [_row("mt1_" + "0" * 26, 0.1, "yes"), _row("mt1_" + "1" * 26, 0.9, "no")]
    good = FakeProvider(
        scorer=lambda r: 0.9 if r.query_id.endswith("0" * 26) else 0.1,
        price_per_call_usd=0.001,
    )

    rep = B.run_bakeoff(
        rows,
        rows,
        models=[("good", "fake")],
        providers={"fake": good},
        pricing={"good": {"input_per_m": 0.1, "output_per_m": 0.4}},
        k=1,
        config={"article": 1.0, "llm_curiosity": 3.0},
        score_fn=fake_composite,
    )

    row = rep.rows[0]
    assert row.precision_at_k_llm_off_baseline == 0.0
    assert row.precision_at_k_llm_on == 1.0
    assert row.lift == 1.0
    assert row.lift_per_usd is not None and row.lift_per_usd > 0


def test_injection_resistance_is_a_scored_dimension():
    resistant = FakeProvider(scorer=lambda r: 0.1, price_per_call_usd=0.001)
    obedient = FakeProvider(
        scorer=lambda r: 1.0
        if "instructions" in r.messages[0].content.lower() or "system:" in r.messages[0].content.lower()
        else 0.1,
        price_per_call_usd=0.001,
    )
    rows = [_row("mt1_" + "0" * 26, 0.1, "yes")]

    rep = B.run_bakeoff(
        rows,
        rows,
        models=[("resistant", "r"), ("obedient", "o")],
        providers={"r": resistant, "o": obedient},
        pricing={
            "resistant": {"input_per_m": 0.1, "output_per_m": 0.4},
            "obedient": {"input_per_m": 0.1, "output_per_m": 0.4},
        },
        k=1,
        config={"article": 1.0, "llm_curiosity": 3.0},
        score_fn=fake_composite,
    )

    by_model = {row.model: row.injection_resistance for row in rep.rows}
    assert by_model["resistant"] == 1.0
    assert by_model["obedient"] < 1.0


def test_shutdown_runs_even_when_scoring_raises():
    torn = {"down": False}

    class BoomProvider(FakeProvider):
        def __init__(self):
            super().__init__(scorer=lambda r: (_ for _ in ()).throw(RuntimeError("boom")))

        async def shutdown(self):
            torn["down"] = True
            return 0.0

    provider = BoomProvider()
    rows = [_row("mt1_" + "0" * 26, 0.1, "yes")]

    rep = B.run_bakeoff(
        rows,
        rows,
        models=[("m", "p")],
        providers={"p": provider},
        pricing={"m": {"input_per_m": 0.1, "output_per_m": 0.4}},
        k=1,
        config={"article": 1.0},
        score_fn=fake_composite,
    )

    assert torn["down"] is True
    assert rep.rows[0].error is not None
    assert rep.rows[0].lift is None


def test_each_model_uses_its_own_provider_instance_for_shutdown():
    down = []
    rows = [_row("mt1_" + "0" * 26, 0.1, "yes")]

    class CountingProvider(FakeProvider):
        def __init__(self, name):
            self.name = name
            super().__init__(scorer=lambda r: 0.9, price_per_call_usd=0.001)

        async def shutdown(self):
            down.append(self.name)
            return 0.001

    rep = B.run_bakeoff(
        rows,
        rows,
        models=[("m1", "p1"), ("m2", "p2")],
        providers={"p1": CountingProvider("p1"), "p2": CountingProvider("p2")},
        pricing={"m1": {"input_per_m": 0.1, "output_per_m": 0.4}, "m2": {"input_per_m": 0.1, "output_per_m": 0.4}},
        k=1,
        config={"article": 1.0, "llm_curiosity": 3.0},
        score_fn=fake_composite,
    )

    assert down == ["p1", "p2"]
    assert [row.error for row in rep.rows] == [None, None]


def test_provider_instances_are_not_reused_between_candidates():
    rows = [_row("mt1_" + "0" * 26, 0.1, "yes")]
    provider = FakeProvider(scorer=lambda r: 0.9, price_per_call_usd=0.001)

    with pytest.raises(ValueError):
        B.run_bakeoff(
            rows,
            rows,
            models=[("m1", "shared"), ("m2", "shared")],
            providers={"shared": provider},
            pricing={"m1": {"input_per_m": 0.1, "output_per_m": 0.4}, "m2": {"input_per_m": 0.1, "output_per_m": 0.4}},
            k=1,
            config={"article": 1.0, "llm_curiosity": 3.0},
            score_fn=fake_composite,
        )
