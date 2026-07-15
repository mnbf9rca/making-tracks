from pathlib import Path

import pytest

from mt_pipeline.eval import golden as G
from mt_pipeline.eval import report as R

FIXTURE = Path(__file__).parent / "fixtures" / "eval" / "labeled_golden_sample.tsv"
BASELINE_CONFIG = {"heritage": 1.0}
WORSE_CONFIG = {"sitelinks": 1.0}
LLM_HEAVY_CONFIG = {"heritage": 1.0, "llm_curiosity": 2.0}


def fake_score(sig, cfg):
    return sum(cfg.get(k, 0) * v for k, v in sig.items() if v is not None)


def load_rows():
    parsed = G.parse_labeled_tsv(FIXTURE.read_text())
    assert parsed.skipped == []
    return parsed.rows


def test_eval_report_produces_stable_precision_at_k():
    rows = load_rows()
    assert sum(1 for row in rows if row.label is not None) == 48
    assert {row.area for row in rows} == {"kl"}
    result = R.eval_report(rows, BASELINE_CONFIG, score_fn=fake_score)
    assert result.metrics["kl.llm_on.strict@5"] == 1.0
    assert result.metrics["kl.llm_on.strict@10"] == 1.0
    assert result.metrics["kl.llm_on.strict@20"] == 1.0
    assert result.metrics == R.eval_report(rows, BASELINE_CONFIG, score_fn=fake_score).metrics


def test_assert_no_regression_passes_for_baseline_and_reds_for_worse_config():
    rows = load_rows()
    baseline = {
        "kl.llm_on.strict@5": 1.0,
        "kl.llm_on.strict@10": 1.0,
        "kl.llm_on.strict@20": 1.0,
    }
    R.assert_no_regression(rows, BASELINE_CONFIG, baseline, score_fn=fake_score)
    with pytest.raises(AssertionError, match="regression"):
        R.assert_no_regression(rows, WORSE_CONFIG, baseline, score_fn=fake_score)


def test_llm_off_fixture_floor_is_pinned():
    rows = load_rows()
    result = R.eval_report(rows, LLM_HEAVY_CONFIG, score_fn=fake_score)
    assert result.metrics["kl.llm_off.strict@20"] >= R.LLM_OFF_FLOOR
    assert result.metrics["kl.llm_off.strict@20"] > result.metrics["kl.llm_on.strict@20"]


def test_inactive_rows_are_not_scored_in_reports():
    rows = [
        G.GoldenRow(
            "mt1_" + "0" * 26,
            "kl",
            "active yes",
            0,
            0,
            "c",
            1,
            0,
            {"heritage": 1.0},
            "yes",
            "v1",
            active=True,
        ),
        G.GoldenRow(
            "mt1_" + "1" * 26,
            "kl",
            "retired no",
            0,
            0,
            "c",
            1,
            0,
            {"heritage": 2.0},
            "no",
            "v1",
            active=False,
        ),
    ]
    result = R.eval_report(rows, BASELINE_CONFIG, score_fn=fake_score, ks=(1,))
    assert result.metrics["kl.llm_on.strict@1"] == 1.0
