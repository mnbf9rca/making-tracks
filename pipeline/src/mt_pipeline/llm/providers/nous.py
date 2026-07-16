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

from ..costmodel import count_tokens
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
        self.api_key = api_key if api_key is not None else os.getenv("NOUS_API_KEY", "")
        if not self.api_key:
            raise ProviderCredentialsMissing("NOUS_API_KEY is required for live NOUS calls")
        self._validate_base_url(base_url)
        self.concurrency = concurrency
        self.base_url = base_url
        self.input_per_m = self._validate_price(input_per_m, "input_per_m")
        self.output_per_m = self._validate_price(output_per_m, "output_per_m")

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
        try:
            from openai import AsyncOpenAI
        except ModuleNotFoundError as exc:
            raise ProviderCredentialsMissing("openai SDK is required for live NOUS calls") from exc

        client = AsyncOpenAI(api_key=self.api_key, base_url=self.base_url)
        response: Any = await client.chat.completions.create(
            model=req.model_id,
            messages=[
                {"role": "system", "content": req.system},
                *[{"role": msg.role, "content": msg.content} for msg in req.messages],
            ],
            max_tokens=req.max_tokens,
            temperature=req.temperature,
            top_p=req.top_p,
            seed=req.seed,
            response_format={"type": "json_object"},
        )
        text = response.choices[0].message.content or ""
        usage = getattr(response, "usage", None)
        input_tokens = int(getattr(usage, "prompt_tokens", 0) or count_tokens(req.system))
        output_tokens = int(getattr(usage, "completion_tokens", 0) or count_tokens(text))
        return ProviderResponse(
            text=text,
            model_fingerprint=getattr(response, "system_fingerprint", None) or req.model_id,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            latency_ms=0,
            cost_usd=self.cost_from_usage(input_tokens=input_tokens, output_tokens=output_tokens),
            app_id=None,
        )

    def cost_from_usage(self, *, input_tokens: int, output_tokens: int) -> float:
        return (input_tokens * self.input_per_m + output_tokens * self.output_per_m) / 1_000_000

    async def acomplete_batch(self, reqs: Sequence[LlmRequest]) -> list[ProviderResponse]:
        semaphore = asyncio.Semaphore(self.concurrency)

        async def one(req: LlmRequest) -> ProviderResponse:
            async with semaphore:
                return await self.acomplete(req)

        return list(await asyncio.gather(*(one(req) for req in reqs)))

    async def shutdown(self) -> float | None:
        return None

    def __repr__(self) -> str:
        return f"NousProvider(api_key=<redacted>, concurrency={self.concurrency}, base_url={self.base_url!r})"
