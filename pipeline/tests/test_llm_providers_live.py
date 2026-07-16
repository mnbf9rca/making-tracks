import asyncio
import os
import pathlib
from types import SimpleNamespace
import tomllib

import pytest

from mt_pipeline.llm import provider as P


def _live_enabled(request) -> bool:
    return bool(request.config.getoption("--live"))


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


def test_nous_prefers_provider_reported_usage_cost():
    from mt_pipeline.llm.curiosity import curiosity_request
    from mt_pipeline.llm.providers.nous import NousProvider

    class FakeCompletions:
        async def create(self, **_kwargs):
            return SimpleNamespace(
                choices=[SimpleNamespace(message=SimpleNamespace(content='{"curiosity": 0.5}'))],
                usage=SimpleNamespace(prompt_tokens=1000, completion_tokens=100, cost=0.000123),
                system_fingerprint="fake",
            )

    provider = NousProvider(api_key="sk-secret-123", concurrency=1, input_per_m=999.0, output_per_m=999.0)
    provider._client = SimpleNamespace(chat=SimpleNamespace(completions=FakeCompletions()))
    req = curiosity_request(
        query_id="mt1_smoke",
        model_id="meta-llama/llama-3.1-8b-instruct",
        place={"name": "Old Windmill", "summary": "a mill", "tags": ["heritage"]},
    )

    response = asyncio.run(provider.acomplete(req))

    assert response.cost_usd == pytest.approx(0.000123)
    assert response.cost_source == "measured"


def test_nous_labels_pricing_fallback_cost_as_derived():
    from mt_pipeline.llm.curiosity import curiosity_request
    from mt_pipeline.llm.providers.nous import NousProvider

    class FakeCompletions:
        async def create(self, **_kwargs):
            return SimpleNamespace(
                choices=[SimpleNamespace(message=SimpleNamespace(content='{"curiosity": 0.5}'))],
                usage=SimpleNamespace(prompt_tokens=1000, completion_tokens=100),
                system_fingerprint="fake",
            )

    provider = NousProvider(api_key="sk-secret-123", concurrency=1, input_per_m=0.15, output_per_m=0.60)
    provider._client = SimpleNamespace(chat=SimpleNamespace(completions=FakeCompletions()))
    req = curiosity_request(
        query_id="mt1_smoke",
        model_id="meta-llama/llama-3.1-8b-instruct",
        place={"name": "Old Windmill", "summary": "a mill", "tags": ["heritage"]},
    )

    response = asyncio.run(provider.acomplete(req))

    assert response.cost_usd == pytest.approx(0.00021)
    assert response.cost_source == "derived"


def test_live_nous_sdk_dependency_is_declared():
    pyproject = tomllib.loads((pathlib.Path(__file__).parents[1] / "pyproject.toml").read_text())
    dependencies = pyproject["project"]["dependencies"]

    assert any(dep.startswith("openai") for dep in dependencies)


def test_nous_rejects_unresolved_op_reference_api_key():
    from mt_pipeline.llm.providers.nous import NousProvider

    with pytest.raises(P.ProviderCredentialsMissing):
        NousProvider(api_key="op://making-tracks/nous/api-key", concurrency=1)


def test_nous_live_smoke(request):
    if not _live_enabled(request) or not os.getenv("NOUS_API_KEY"):
        pytest.skip("requires --live + keys")
    from mt_pipeline.llm.curiosity import curiosity_request, parse_curiosity
    from mt_pipeline.llm.providers.nous import NousProvider

    provider = NousProvider(api_key=os.environ["NOUS_API_KEY"], concurrency=1)
    try:
        req = curiosity_request(
            query_id="mt1_smoke",
            model_id="meta-llama/llama-3.1-8b-instruct",
            place={"name": "Old Windmill", "summary": "a mill", "tags": ["heritage"]},
        )
        resp = asyncio.run(provider.acomplete(req))
    finally:
        asyncio.run(provider.shutdown())

    assert 0.0 <= parse_curiosity(resp.text).curiosity <= 1.0
