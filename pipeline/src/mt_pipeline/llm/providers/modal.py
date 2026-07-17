"""Modal open-weight provider placeholder with key-gated live RPCs."""

from __future__ import annotations

from collections.abc import Sequence
import os

from ..models import LlmRequest, ProviderResponse
from ..provider import ProviderCredentialsMissing


class ModalProvider:
    def __init__(self, *, concurrency: int, model_id: str) -> None:
        self.concurrency = concurrency
        self.model_id = model_id
        self._started = False

    @property
    def is_gpu_batchable(self) -> bool:
        return True

    def _ensure_credentials(self) -> None:
        if not (os.getenv("MODAL_TOKEN_ID") and os.getenv("MODAL_TOKEN_SECRET")):
            raise ProviderCredentialsMissing("MODAL_TOKEN_ID and MODAL_TOKEN_SECRET are required for live Modal calls")

    async def acomplete(self, req: LlmRequest) -> ProviderResponse:
        responses = await self.acomplete_batch((req,))
        return responses[0]

    async def acomplete_batch(self, reqs: Sequence[LlmRequest]) -> list[ProviderResponse]:
        self._ensure_credentials()
        try:
            import modal  # noqa: F401
        except ModuleNotFoundError as exc:
            raise ProviderCredentialsMissing("modal SDK is required for live Modal calls") from exc
        raise NotImplementedError("live Modal RPC is gated for Rob's op-run smoke test")

    async def shutdown(self) -> float | None:
        return 0.0 if self._started else None

    def __repr__(self) -> str:
        return f"ModalProvider(model_id={self.model_id!r}, concurrency={self.concurrency})"
