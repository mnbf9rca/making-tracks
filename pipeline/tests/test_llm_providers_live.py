import asyncio
import os

import pytest

from mt_pipeline.llm import provider as P


def test_providers_conform_and_gate_on_credentials():
    from mt_pipeline.llm.providers.modal import ModalProvider
    from mt_pipeline.llm.providers.nous import NousProvider

    assert isinstance(ModalProvider(concurrency=1, model_id="meta-llama/Meta-Llama-3.1-8B-Instruct"), P.Provider)
    with pytest.raises(P.ProviderCredentialsMissing):
        NousProvider(api_key="", concurrency=1)


def test_api_key_is_not_leaked_by_repr():
    from mt_pipeline.llm.providers.nous import NousProvider

    provider = NousProvider(api_key="sk-secret-123", concurrency=1)

    assert "sk-secret-123" not in repr(provider)


def test_nous_rejects_non_https_or_unexpected_base_url():
    from mt_pipeline.llm.providers.nous import NousProvider

    with pytest.raises(P.ProviderCredentialsMissing):
        NousProvider(api_key="sk-secret-123", concurrency=1, base_url="http://inference-api.nousresearch.com/v1")
    with pytest.raises(P.ProviderCredentialsMissing):
        NousProvider(api_key="sk-secret-123", concurrency=1, base_url="https://evil.test/v1")


def test_nous_usage_cost_is_computed_from_pricing():
    from mt_pipeline.llm.providers.nous import NousProvider

    provider = NousProvider(api_key="sk-secret-123", concurrency=1, input_per_m=0.15, output_per_m=0.60)

    assert provider.cost_from_usage(input_tokens=1000, output_tokens=100) == pytest.approx(0.00021)


def test_nous_request_kwargs_include_per_model_cap_and_reasoning():
    from mt_pipeline.llm.curiosity import curiosity_request
    from mt_pipeline.llm.providers.nous import NousProvider

    provider = NousProvider(api_key="sk-secret-123", concurrency=1)
    req = curiosity_request(
        query_id="mt1_reasoning",
        model_id="nex-agi/nex-n2-mini",
        place={"name": "Old Windmill", "summary": "a mill", "tags": ["heritage"]},
        max_tokens=128,
        reasoning={"enabled": True, "effort": "low", "exclude": True},
        seed=None,
    )

    kwargs = provider._chat_completion_kwargs(req)

    assert kwargs["model"] == "nex-agi/nex-n2-mini"
    assert kwargs["max_tokens"] == 128
    assert "seed" not in kwargs
    assert kwargs["extra_body"] == {"reasoning": {"enabled": True, "effort": "low", "exclude": True}}


@pytest.mark.skipif(not os.getenv("NOUS_API_KEY"), reason="live run BLOCKED-ON keys")
def test_nous_live_smoke():
    from mt_pipeline.llm.curiosity import curiosity_request, parse_curiosity
    from mt_pipeline.llm.providers.nous import NousProvider

    provider = NousProvider(api_key=os.environ["NOUS_API_KEY"], concurrency=1)
    req = curiosity_request(
        query_id="mt1_smoke",
        model_id="tencent/hy3:free",
        place={"name": "Old Windmill", "summary": "a mill", "tags": ["heritage"]},
    )
    resp = asyncio.run(provider.acomplete(req))

    assert 0.0 <= parse_curiosity(resp.text).curiosity <= 1.0
