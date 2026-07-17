"""Frozen LLM request/response models."""

from __future__ import annotations

from collections.abc import Mapping
import math
from types import MappingProxyType

from pydantic import BaseModel, ConfigDict, Field, field_validator


class FrozenModel(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")


class Message(FrozenModel):
    role: str
    content: str


def _freeze_jsonish(value: object) -> object:
    if isinstance(value, Mapping):
        return MappingProxyType({str(key): _freeze_jsonish(item) for key, item in value.items()})
    if isinstance(value, (list, tuple)):
        return tuple(_freeze_jsonish(item) for item in value)
    return value


class LlmRequest(FrozenModel):
    model_id: str
    provider_model_id: str | None = None
    system: str
    messages: tuple[Message, ...]
    max_tokens: int = Field(ge=1, le=4096)
    provider_tags: tuple[str, ...] | None = None
    reasoning: object | None = None
    temperature: float = Field(ge=0.0, le=2.0)
    top_p: float = Field(gt=0.0, le=1.0)
    seed: int | None = None
    prompt_version: str
    task_id: str
    query_id: str

    @field_validator("provider_model_id")
    @classmethod
    def _validate_provider_model_id(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if not value or len(value) > 256 or any(ord(ch) < 32 for ch in value):
            raise ValueError("provider_model_id must be a non-empty printable string up to 256 chars")
        return value

    @field_validator("max_tokens", "seed", mode="before")
    @classmethod
    def _reject_bool_int_fields(cls, value: object) -> object:
        if isinstance(value, bool):
            raise ValueError("integer fields must not be bool")
        return value

    @field_validator("provider_tags", mode="before")
    @classmethod
    def _validate_provider_tags(cls, value: object) -> object:
        if value is None:
            return None
        if not isinstance(value, (list, tuple)):
            raise ValueError("provider_tags must be a list of strings")
        if len(value) > 16:
            raise ValueError("provider_tags must contain at most 16 tags")
        tags = []
        for tag in value:
            if not isinstance(tag, str):
                raise ValueError("provider_tags must be strings")
            if not tag or len(tag) > 64 or any(ord(ch) < 32 for ch in tag):
                raise ValueError("provider_tags entries must be non-empty printable strings up to 64 chars")
            tags.append(tag)
        return tuple(tags)

    @field_validator("reasoning", mode="before")
    @classmethod
    def _freeze_reasoning(cls, value: object) -> object:
        if value is None:
            return None
        if not isinstance(value, Mapping):
            raise ValueError("reasoning must be an object")
        return _freeze_jsonish(value)

    @field_validator("temperature", "top_p", mode="before")
    @classmethod
    def _reject_bool_float_fields(cls, value: object) -> object:
        if isinstance(value, bool):
            raise ValueError("numeric fields must not be bool")
        return value


class ProviderResponse(FrozenModel):
    text: str
    model_fingerprint: str
    input_tokens: int = Field(ge=0)
    output_tokens: int = Field(ge=0)
    latency_ms: int = Field(ge=0)
    cost_usd: float = Field(ge=0.0)
    cost_source: str = "derived"
    app_id: str | None = None

    @field_validator("input_tokens", "output_tokens", "latency_ms", mode="before")
    @classmethod
    def _reject_bool_int_fields(cls, value: object) -> object:
        if isinstance(value, bool):
            raise ValueError("integer fields must not be bool")
        return value

    @field_validator("cost_usd", mode="before")
    @classmethod
    def _reject_bool_cost(cls, value: object) -> object:
        if isinstance(value, bool):
            raise ValueError("cost_usd must not be bool")
        return value

    @field_validator("cost_source")
    @classmethod
    def _cost_source_known(cls, value: str) -> str:
        if value not in {"measured", "derived", "cache"}:
            raise ValueError("cost_source must be measured, derived, or cache")
        return value


class CuriosityResult(FrozenModel):
    curiosity: float

    @field_validator("curiosity", mode="before")
    @classmethod
    def _reject_bool_and_non_finite(cls, value: object) -> object:
        if isinstance(value, bool):
            raise ValueError("curiosity must be a number, not a bool")
        if isinstance(value, (int, float)) and not math.isfinite(float(value)):
            raise ValueError("curiosity must be finite")
        return value

    @field_validator("curiosity")
    @classmethod
    def _in_range(cls, value: float) -> float:
        if not math.isfinite(value):
            raise ValueError("curiosity must be finite")
        if value < 0.0 or value > 1.0:
            raise ValueError("curiosity must be in [0, 1]")
        return value


class CostRow(FrozenModel):
    model: str
    provider: str
    input_tokens: int
    output_token_cap: int
    input_usd: float
    output_usd: float
    total_usd: float
    token_source: str
    output_cost_source: str = "capped-at-max_tokens"

    @field_validator("input_tokens", "output_token_cap", mode="before")
    @classmethod
    def _reject_bool_int_fields(cls, value: object) -> object:
        if isinstance(value, bool):
            raise ValueError("integer fields must not be bool")
        return value

    @field_validator("input_usd", "output_usd", "total_usd", mode="before")
    @classmethod
    def _reject_bool_money(cls, value: object) -> object:
        if isinstance(value, bool):
            raise ValueError("money fields must not be bool")
        return value

    @field_validator("input_usd", "output_usd", "total_usd")
    @classmethod
    def _finite_money(cls, value: float) -> float:
        if not math.isfinite(value):
            raise ValueError("money fields must be finite")
        if value < 0.0:
            raise ValueError("money fields must be non-negative")
        return value


class CostTable(FrozenModel):
    rows: tuple[CostRow, ...]
