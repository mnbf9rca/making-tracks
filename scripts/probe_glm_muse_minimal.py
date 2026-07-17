"""Probe GLM/Muse minimal NOUS reasoning shape.

Run from the repo root with:
op run --env-file=.env.tpl -- uv run --project pipeline --extra dev python scripts/probe_glm_muse_minimal.py

The script prints no key material. It makes one tiny request per model using the
candidate minimal production shape: reasoning {"enabled": false}.
"""

from __future__ import annotations

import asyncio
import json
from typing import Any

from mt_pipeline.llm.curiosity import curiosity_request, parse_curiosity
from mt_pipeline.llm.providers.nous import NousProvider


PLACE = {"name": "Old Windmill", "summary": "a mill", "tags": ["heritage"]}
EXCERPT_LIMIT = 500
MODELS = (
    ("nous-glm-5.2", "z-ai/glm-5.2"),
    ("nous-muse-spark-1.1", "meta/muse-spark-1.1"),
)


def _excerpt(value: object, *, limit: int = EXCERPT_LIMIT) -> str:
    return repr(value)[:limit]


def _redact(value: Any) -> Any:
    if isinstance(value, dict):
        redacted: dict[str, Any] = {}
        for key, item in value.items():
            key_text = str(key).lower()
            if key_text in {"authorization", "api-key", "x-api-key"} or "header" in key_text:
                redacted[str(key)] = "<redacted>"
            else:
                redacted[str(key)] = _redact(item)
        return redacted
    if isinstance(value, list):
        return [_redact(item) for item in value]
    if isinstance(value, tuple):
        return tuple(_redact(item) for item in value)
    return value


def _request_summary(kwargs: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in kwargs.items() if key != "messages"}


def _body(exc: Exception) -> object | None:
    body = getattr(exc, "body", None)
    if body is not None:
        return body
    response = getattr(exc, "response", None)
    if response is None:
        return None
    try:
        return response.json()
    except Exception:
        return getattr(response, "text", None)


def _reasoning_tokens(usage: object) -> object | None:
    details = getattr(usage, "completion_tokens_details", None)
    if details is None:
        return None
    return getattr(details, "reasoning_tokens", None)


async def _try_model(provider: NousProvider, cache_model_id: str, api_model_id: str) -> None:
    request = curiosity_request(
        query_id=f"shape_{cache_model_id}",
        model_id=cache_model_id,
        provider_model_id=api_model_id,
        place=PLACE,
        max_tokens=256,
        reasoning={"enabled": False},
        seed=None,
    )
    kwargs = provider._chat_completion_kwargs(request)
    print(f"--- {cache_model_id} ---")
    print("request", json.dumps(_redact(_request_summary(kwargs)), sort_keys=True, default=str)[:EXCERPT_LIMIT])
    try:
        response = await provider._client_instance().chat.completions.create(**kwargs)
    except Exception as exc:
        print("error", type(exc).__name__, _excerpt(str(exc)))
        body = _body(exc)
        if body is not None:
            print("body", _excerpt(body))
        return

    choice = response.choices[0]
    text = choice.message.content or ""
    print("finish_reason", getattr(choice, "finish_reason", None))
    print("text", _excerpt(text))
    usage = getattr(response, "usage", None)
    print("reasoning_tokens", _reasoning_tokens(usage))
    print("usage", _excerpt(usage))
    try:
        parsed = parse_curiosity(text)
    except Exception as exc:
        print("parse", "fail", type(exc).__name__, _excerpt(str(exc)))
    else:
        print("parse", "ok", parsed.model_dump())


async def main() -> None:
    provider = NousProvider(concurrency=1, input_per_m=0.0, output_per_m=0.0)
    try:
        for cache_model_id, api_model_id in MODELS:
            await _try_model(provider, cache_model_id, api_model_id)
    finally:
        await provider.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
