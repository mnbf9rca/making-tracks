import asyncio
import json

import pytest

from mt_pipeline.llm import models as M
from mt_pipeline.llm import provider as P
from mt_pipeline.llm.providers.fake import FakeProvider


def _req(text: str = "Old Windmill\ntags: heritage") -> M.LlmRequest:
    return M.LlmRequest(
        model_id="fake-1",
        system="score",
        messages=(M.Message(role="user", content=text),),
        max_tokens=16,
        temperature=0.0,
        top_p=1.0,
        seed=7,
        prompt_version="curiosity-v1",
        task_id="curiosity",
        query_id="mt1_x",
    )


def test_fake_provider_is_deterministic_and_keyless():
    fp = FakeProvider(
        scorer=lambda r: 0.5 if "heritage" in r.messages[0].content else 0.1,
        price_per_call_usd=0.002,
    )

    a = asyncio.run(fp.acomplete(_req()))
    b = asyncio.run(fp.acomplete(_req()))

    assert a == b
    assert json.loads(a.text)["curiosity"] == 0.5
    assert a.cost_usd == 0.002
    assert a.input_tokens > 0


def test_fake_provider_satisfies_the_protocol():
    fp = FakeProvider(scorer=lambda r: 0.0)

    assert isinstance(fp, P.Provider)
    assert fp.is_gpu_batchable is False


def test_models_reject_bool_numeric_fields():
    with pytest.raises(ValueError):
        M.LlmRequest(
            model_id="fake-1",
            system="score",
            messages=(M.Message(role="user", content="x"),),
            max_tokens=True,
            temperature=0.0,
            top_p=1.0,
            seed=7,
            prompt_version="curiosity-v1",
            task_id="curiosity",
            query_id="mt1_x",
        )
    with pytest.raises(ValueError):
        M.ProviderResponse(
            text="{}",
            model_fingerprint="x",
            input_tokens=True,
            output_tokens=0,
            latency_ms=0,
            cost_usd=0.0,
        )


def test_fake_provider_batch_uses_same_deterministic_path():
    fp = FakeProvider(scorer=lambda r: 0.6 if r.query_id == "a" else 0.2)
    reqs = (_req("a").model_copy(update={"query_id": "a"}), _req("b").model_copy(update={"query_id": "b"}))

    responses = asyncio.run(fp.acomplete_batch(reqs))

    assert [json.loads(r.text)["curiosity"] for r in responses] == [0.6, 0.2]
