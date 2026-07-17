"""Probe NOUS S1/S4 request shapes.

Run from the repo root with:
op run --env-file=.env.tpl -- uv run --project pipeline --extra dev python scripts/probe_s1s4.py

The script prints no key material. It makes one tiny request per variant.
"""

from __future__ import annotations

import asyncio
import json
from typing import Any

from mt_pipeline.llm.curiosity import curiosity_request
from mt_pipeline.llm.providers.nous import NousProvider


PLACE = {"name": "Old Windmill", "summary": "a mill", "tags": ["heritage"]}
USER = "making-tracks-eval"
EXCERPT_LIMIT = 500


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
    return {
        key: value
        for key, value in kwargs.items()
        if key not in {"messages"}
    }


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


async def _try_create(provider: NousProvider, label: str, kwargs: dict[str, Any]) -> None:
    print(f"--- {label} ---")
    print("request", json.dumps(_redact(_request_summary(kwargs)), sort_keys=True, default=str)[:EXCERPT_LIMIT])
    try:
        response = await provider._client_instance().chat.completions.create(**kwargs)
    except Exception as exc:
        print("error", type(exc).__name__, _excerpt(str(exc)))
        body = _body(exc)
        if body is not None:
            print("body", _excerpt(body))
        return

    text = response.choices[0].message.content or ""
    print("ok", "text=", _excerpt(text))
    print("usage", _excerpt(getattr(response, "usage", None)))


def _s1_variants(provider: NousProvider) -> list[tuple[str, dict[str, Any]]]:
    request = curiosity_request(
        query_id="shape_s1",
        model_id="tencent/hy3:free",
        place=PLACE,
        provider_tags=("making-tracks", "curiosity"),
        seed=0,
    )
    base = provider._chat_completion_kwargs(request)
    variants: list[tuple[str, dict[str, Any]]] = [("s1-current-tags", dict(base))]

    kwargs = dict(base)
    kwargs["user"] = USER
    variants.append(("s1-current-tags-plus-user", kwargs))

    kwargs = dict(base)
    kwargs["metadata"] = {"user": USER, "app": "making-tracks"}
    variants.append(("s1-current-tags-plus-metadata-user", kwargs))

    kwargs = dict(base)
    kwargs["extra_body"] = dict(kwargs.get("extra_body", {}))
    kwargs["extra_body"]["tags"] = ["making-tracks", "curiosity", f"user:{USER}"]
    variants.append(("s1-tags-with-user-tag", kwargs))

    kwargs = dict(base)
    kwargs["extra_body"] = dict(kwargs.get("extra_body", {}))
    kwargs["extra_body"]["user"] = USER
    variants.append(("s1-extra-body-user", kwargs))

    kwargs = dict(base)
    kwargs["extra_headers"] = {
        "HTTP-Referer": "https://making-tracks.app",
        "X-OpenRouter-Title": "Making Tracks",
    }
    variants.append(("s1-current-tags-plus-app-headers", kwargs))

    return variants


def _s4_variants(provider: NousProvider) -> list[tuple[str, dict[str, Any]]]:
    request = curiosity_request(
        query_id="shape_s4",
        model_id="nex-agi/nex-n2-mini",
        place=PLACE,
        max_tokens=128,
        reasoning={"enabled": True, "effort": "low", "exclude": True},
        seed=None,
    )
    base = provider._chat_completion_kwargs(request)
    variants: list[tuple[str, dict[str, Any]]] = [("s4-current-reasoning", dict(base))]

    kwargs = dict(base)
    kwargs.pop("extra_body", None)
    kwargs["max_tokens"] = 16
    variants.append(("s4-reasoning-disabled-cap16", kwargs))

    kwargs = dict(base)
    kwargs["extra_body"] = {"reasoning": {"enabled": False}}
    kwargs["max_tokens"] = 16
    variants.append(("s4-reasoning-explicit-disabled-cap16", kwargs))

    kwargs = dict(base)
    kwargs["extra_body"] = {"reasoning": {"enabled": True, "effort": "low", "exclude": True}}
    kwargs["max_tokens"] = 256
    variants.append(("s4-current-reasoning-cap256", kwargs))

    return variants


async def main() -> None:
    provider = NousProvider(concurrency=1, input_per_m=0.0, output_per_m=0.0)
    try:
        for label, kwargs in [*_s1_variants(provider), *_s4_variants(provider)]:
            await _try_create(provider, label, kwargs)
    finally:
        await provider.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
