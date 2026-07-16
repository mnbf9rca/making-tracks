"""Deterministic keyless provider for tests and offline harness runs."""

from __future__ import annotations

from collections.abc import Callable, Sequence
import json

from ..costmodel import count_tokens
from ..models import LlmRequest, ProviderResponse


class FakeProvider:
    def __init__(self, scorer: Callable[[LlmRequest], float], *, price_per_call_usd: float = 0.0) -> None:
        self._scorer = scorer
        self._price_per_call_usd = price_per_call_usd

    @property
    def is_gpu_batchable(self) -> bool:
        return False

    async def acomplete(self, req: LlmRequest) -> ProviderResponse:
        curiosity = float(self._scorer(req))
        text = json.dumps({"curiosity": curiosity}, separators=(",", ":"))
        return ProviderResponse(
            text=text,
            model_fingerprint=f"fake:{req.model_id}",
            input_tokens=count_tokens(req.system + "\n" + "\n".join(m.content for m in req.messages)),
            output_tokens=count_tokens(text),
            latency_ms=0,
            cost_usd=self._price_per_call_usd,
            app_id=None,
        )

    async def acomplete_batch(self, reqs: Sequence[LlmRequest]) -> list[ProviderResponse]:
        return [await self.acomplete(req) for req in reqs]

    async def shutdown(self) -> float | None:
        return None

    def __repr__(self) -> str:
        return "FakeProvider(price_per_call_usd=redacted)"
