import json

import pytest

from mt_pipeline.llm import cache as C
from mt_pipeline.llm import costmodel as K
from mt_pipeline.llm import curiosity as Q
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


def test_build_cost_table_honors_per_model_output_token_cap():
    corpus = [{"name": "Old Windmill", "summary": "A mill", "tags": ["heritage"]}]
    models = [
        {"id": "tencent/hy3:free", "provider": "nous"},
        {"id": "nex-agi/nex-n2-mini", "provider": "nous", "max_tokens": 128},
    ]
    pricing = {
        "tencent/hy3:free": {"input_per_m": 0.0, "output_per_m": 0.0},
        "nex-agi/nex-n2-mini": {"input_per_m": 0.025, "output_per_m": 0.10},
    }

    rows = {row.model: row for row in K.build_cost_table(corpus, models, pricing).rows}

    assert rows["tencent/hy3:free"].output_token_cap == 16
    assert rows["nex-agi/nex-n2-mini"].output_token_cap == 128


@pytest.mark.parametrize("max_tokens", [0, -1, True, 128.0, "128", 4097])
def test_build_cost_table_rejects_invalid_model_output_token_cap(max_tokens):
    corpus = [{"name": "Old Windmill", "summary": "A mill", "tags": ["heritage"]}]
    models = [{"id": "nex-agi/nex-n2-mini", "provider": "nous", "max_tokens": max_tokens}]
    pricing = {"nex-agi/nex-n2-mini": {"input_per_m": 0.025, "output_per_m": 0.10}}

    with pytest.raises(ValueError):
        K.build_cost_table(corpus, models, pricing)


def test_default_round1_roster_and_pricing_bind_real_portal_ids():
    root = C.PROJECT_ROOT / "pipeline" / "config"
    models = json.loads((root / "llm_models.json").read_text())["models"]
    pricing = json.loads((root / "llm_pricing.json").read_text())["models"]
    by_id = {row["id"]: row for row in models}
    expected = {
        "nous-tencent-hy3-free": ("tencent/hy3:free", 16),
        "nous-meta-llama-3.1-8b-instruct": ("meta-llama/llama-3.1-8b-instruct", 16),
        "nous-hermes-4-70b": ("nousresearch/hermes-4-70b", 16),
        "nous-nex-n2-mini": ("nex-agi/nex-n2-mini", 256),
    }

    for model_id, (api_model_id, max_tokens) in expected.items():
        assert by_id[model_id]["provider"] == "nous"
        assert by_id[model_id]["api_model_id"] == api_model_id
        assert by_id[model_id].get("max_tokens", 16) == max_tokens
        assert pricing[model_id]["provider"] == "nous"

    assert pricing["nous-tencent-hy3-free"]["input_per_m"] == 0.0
    assert pricing["nous-tencent-hy3-free"]["output_per_m"] == 0.0
    assert by_id["nous-tencent-hy3-free"]["provider_tags"] == ["making-tracks", "curiosity"]
    assert by_id["nous-tencent-hy3-free"]["live_skip_reason"].startswith("admission-failed:")
    assert pricing["nous-hermes-4-70b"]["input_per_m"] == 0.05
    assert pricing["nous-hermes-4-70b"]["output_per_m"] == 0.20
    assert by_id["nous-hermes-4-70b"]["seed"] is None
    assert by_id["nous-nex-n2-mini"]["seed"] is None
    assert by_id["nous-nex-n2-mini"]["reasoning"] == {
        "enabled": True,
        "effort": "low",
        "exclude": True,
    }


def test_default_round1_roster_entries_construct_requests_and_cache_keys():
    root = C.PROJECT_ROOT / "pipeline" / "config"
    models = json.loads((root / "llm_models.json").read_text())["models"]
    expected_ids = {
        "nous-meta-llama-3.1-8b-instruct",
        "nous-hermes-4-70b",
        "nous-nex-n2-mini",
    }

    for model in models:
        if model["id"] not in expected_ids:
            continue
        req = Q.curiosity_request(
            query_id="mt1_00000000000000000000000000",
            model_id=model["api_model_id"],
            place={"name": "Old Windmill", "summary": "A mill", "tags": ["heritage"]},
            max_tokens=model.get("max_tokens", Q.CURIOSITY_MAX_TOKENS),
            provider_tags=tuple(model["provider_tags"]) if "provider_tags" in model else None,
            reasoning=model.get("reasoning"),
            seed=model.get("seed", 0),
        )
        rendered_prompt = req.messages[0].content
        input_hash = C.input_hash(
            task_id=req.task_id,
            prompt_version=req.prompt_version,
            rendered_prompt=rendered_prompt,
        )
        key = C.cache_key(req.task_id, req.model_id, req.prompt_version, input_hash)

        assert "/" not in key.split("/")[1]
        assert ":" not in key.split("/")[1]
        assert req.model_id == model["api_model_id"]
        assert req.max_tokens == model.get("max_tokens", Q.CURIOSITY_MAX_TOKENS)
        assert req.provider_tags == (tuple(model["provider_tags"]) if "provider_tags" in model else None)
        assert req.reasoning == model.get("reasoning")
        assert req.seed == model.get("seed", 0)


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
