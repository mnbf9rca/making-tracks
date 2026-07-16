"""NOUS hosted provider.

The live client is OpenAI-compatible, but this module is intentionally named and
scoped to NOUS so callers do not route through a generic OpenAI provider.
"""

from __future__ import annotations

import asyncio
from collections.abc import Sequence
import math
import os
from typing import Any
from urllib.parse import urlparse

from ..costmodel import count_request_tokens, count_tokens
from ..models import LlmRequest, ProviderResponse
from ..provider import ProviderCredentialsMissing

DEFAULT_BASE_URL = "https://inference-api.nousresearch.com/v1"
ALLOWED_HOST = "inference-api.nousresearch.com"


class NousProvider:
    def __init__(
        self,
        *,
        api_key: str | None = None,
        concurrency: int = 4,
        base_url: str = DEFAULT_BASE_URL,
        input_per_m: float = 0.0,
        output_per_m: float = 0.0,
    ) -> None:
        self.api_key = (api_key if api_key is not None else os.getenv("NOUS_API_KEY", "")).strip()
        if not self.api_key or self.api_key.startswith("op:"):
            raise ProviderCredentialsMissing("NOUS_API_KEY is required for live NOUS calls")
        self._validate_base_url(base_url)
        self.concurrency = concurrency
        self.base_url = base_url
        self.input_per_m = self._validate_price(input_per_m, "input_per_m")
        self.output_per_m = self._validate_price(output_per_m, "output_per_m")
        self._client: Any | None = None

    @staticmethod
    def _validate_base_url(base_url: str) -> None:
        parsed = urlparse(base_url)
        if parsed.scheme != "https" or parsed.hostname != ALLOWED_HOST:
            raise ProviderCredentialsMissing("NOUS base_url must be https://inference-api.nousresearch.com")
        if parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ProviderCredentialsMissing("NOUS base_url must not include credentials, query, or fragment")

    @staticmethod
    def _validate_price(value: float, name: str) -> float:
        if isinstance(value, bool):
            raise ValueError(f"{name} must be numeric")
        number = float(value)
        if not math.isfinite(number) or number < 0.0:
            raise ValueError(f"{name} must be finite and non-negative")
        return number

    @property
    def is_gpu_batchable(self) -> bool:
        return False

    async def acomplete(self, req: LlmRequest) -> ProviderResponse:
        client = self._client_instance()
        response: Any = await client.chat.completions.create(**self._chat_completion_kwargs(req))
        text = response.choices[0].message.content or ""
        usage = getattr(response, "usage", None)
        prompt_tokens = getattr(usage, "prompt_tokens", None)
        completion_tokens = getattr(usage, "completion_tokens", None)
        input_tokens = int(prompt_tokens) if prompt_tokens is not None and int(prompt_tokens) > 0 else count_request_tokens(req)
        output_tokens = (
            int(completion_tokens)
            if completion_tokens is not None and int(completion_tokens) > 0
            else count_tokens(text)
        )
        cost_usd, cost_source = self._response_cost(
            response,
            usage,
            fallback_input_tokens=input_tokens,
            fallback_output_tokens=output_tokens,
        )
        return ProviderResponse(
            text=text,
            model_fingerprint=getattr(response, "system_fingerprint", None) or req.model_id,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            latency_ms=0,
            cost_usd=cost_usd,
            cost_source=cost_source,
            app_id=None,
        )

    def _chat_completion_kwargs(self, req: LlmRequest) -> dict[str, Any]:
        kwargs: dict[str, Any] = {
            "model": req.model_id,
            "messages": [
                {"role": "system", "content": req.system},
                *[{"role": msg.role, "content": msg.content} for msg in req.messages],
            ],
            "max_tokens": req.max_tokens,
            "temperature": req.temperature,
            "top_p": req.top_p,
            "response_format": {"type": "json_object"},
        }
        if req.seed is not None:
            kwargs["seed"] = req.seed
        if req.reasoning is not None:
            kwargs["extra_body"] = {"reasoning": req.reasoning}
        return kwargs

    def _client_instance(self) -> Any:
        if self._client is not None:
            return self._client
        try:
            from openai import AsyncOpenAI
        except ModuleNotFoundError as exc:
            raise ProviderCredentialsMissing("openai SDK is required for live NOUS calls") from exc
        self._client = AsyncOpenAI(api_key=self.api_key, base_url=self.base_url)
        return self._client

    def cost_from_usage(self, *, input_tokens: int, output_tokens: int) -> float:
        return (input_tokens * self.input_per_m + output_tokens * self.output_per_m) / 1_000_000

    def _response_cost(
        self,
        response: Any,
        usage: Any,
        *,
        fallback_input_tokens: int,
        fallback_output_tokens: int,
    ) -> tuple[float, str]:
        for container in (usage, response):
            if container is None:
                continue
            for field in ("cost", "cost_usd", "total_cost", "total_cost_usd"):
                value = getattr(container, field, None)
                if value is None and hasattr(container, "model_extra"):
                    value = container.model_extra.get(field)
                parsed = self._parse_reported_cost(value)
                if parsed is not None:
                    return parsed, "measured"
        return (
            self.cost_from_usage(input_tokens=fallback_input_tokens, output_tokens=fallback_output_tokens),
            "derived",
        )

    @staticmethod
    def _parse_reported_cost(value: object) -> float | None:
        if value is None or isinstance(value, bool):
            return None
        if isinstance(value, int | float | str):
            try:
                number = float(value)
            except ValueError:
                return None
            if math.isfinite(number) and number >= 0.0:
                return number
        return None

    async def acomplete_batch(self, reqs: Sequence[LlmRequest]) -> list[ProviderResponse]:
        semaphore = asyncio.Semaphore(self.concurrency)

        async def one(req: LlmRequest) -> ProviderResponse:
            async with semaphore:
                return await self.acomplete(req)

        return list(await asyncio.gather(*(one(req) for req in reqs)))

    async def shutdown(self) -> float | None:
        if self._client is not None:
            await self._client.close()
            self._client = None
        return None

    def __repr__(self) -> str:
        return f"NousProvider(api_key=<redacted>, concurrency={self.concurrency}, base_url={self.base_url!r})"
