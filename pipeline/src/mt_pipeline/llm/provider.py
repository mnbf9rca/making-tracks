"""Provider protocol and provider-level errors."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Protocol, runtime_checkable

from .models import LlmRequest, ProviderResponse


class BatchNotSupportedError(Exception):
    """Raised when a provider cannot perform a requested batch operation."""


class ProviderCredentialsMissing(Exception):
    """Raised before any live call when a provider lacks credentials."""


@runtime_checkable
class Provider(Protocol):
    @property
    def is_gpu_batchable(self) -> bool:
        """True when a provider can run one GPU-batched RPC per candidate chunk."""

    async def acomplete(self, req: LlmRequest) -> ProviderResponse:
        """Complete a single request."""

    async def acomplete_batch(self, reqs: Sequence[LlmRequest]) -> list[ProviderResponse]:
        """Complete requests deterministically in input order."""

    async def shutdown(self) -> float | None:
        """Tear down provider resources and return session cost when known."""
