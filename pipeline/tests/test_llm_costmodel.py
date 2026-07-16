import pytest

from mt_pipeline.llm import costmodel as K
from mt_pipeline.llm import models as M


def test_token_count_upper_bounds_bytes():
    text = "Old Windmill heritage site"

    assert 0 < K.count_tokens(text) <= len(text.encode("utf-8"))


def test_request_token_count_includes_system_and_messages():
    req = M.LlmRequest(
        model_id="fake-1",
        system="score",
        messages=(M.Message(role="user", content="Old Windmill"), M.Message(role="user", content="heritage")),
        max_tokens=16,
        temperature=0.0,
        top_p=1.0,
        seed=7,
        prompt_version="curiosity-v1",
        task_id="curiosity",
        query_id="mt1_x",
    )

    assert K.count_request_tokens(req) == K.count_tokens("score") + K.count_tokens("Old Windmill") + K.count_tokens("heritage")


def test_cost_scales_with_corpus_and_pins_source():
    pricing = {"input_per_m": 0.15, "output_per_m": 0.60}

    row1 = K.estimate_cost(["a place"], pricing, output_token_cap=16)
    row2 = K.estimate_cost(["a place", "another place here"], pricing, output_token_cap=16)

    assert row2.total_usd > row1.total_usd
    assert row1.token_source in ("tokenizer", "byte-estimate")
    assert row1.output_token_cap == 16


def test_build_cost_table_uses_real_rendered_prompts():
    corpus = [{"name": "Old Windmill", "summary": "A mill", "tags": ["heritage"]}]
    models = [{"id": "fake-1", "provider": "fake"}]
    pricing = {"fake-1": {"input_per_m": 0.15, "output_per_m": 0.60}}

    table = K.build_cost_table(corpus, models, pricing)

    assert len(table.rows) == 1
    assert table.rows[0].model == "fake-1"
    assert table.rows[0].input_tokens > 0


def test_estimate_cost_rejects_non_finite_pricing():
    with pytest.raises(ValueError):
        K.estimate_cost(["a"], {"input_per_m": float("nan"), "output_per_m": 0.1}, output_token_cap=16)
    with pytest.raises(ValueError):
        K.estimate_cost(["a"], {"input_per_m": 0.1, "output_per_m": float("inf")}, output_token_cap=16)


def test_modal_cost_table_uses_gpu_second_estimate():
    corpus = [{"name": "Old Windmill", "summary": "A mill", "tags": ["heritage"]}]
    models = [{"id": "modal-test", "provider": "modal"}]
    pricing = {"modal-test": {"input_per_m": 0.0, "output_per_m": 0.0, "gpu_second": 0.25, "gpu_seconds_per_1k": 2.0}}

    table = K.build_cost_table(corpus, models, pricing)

    assert table.rows[0].total_usd > 0
    assert table.rows[0].output_cost_source == "estimated-gpu-seconds"
