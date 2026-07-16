"""Keyless token counting and cost estimation."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
import math
from typing import Any

from .curiosity import CURIOSITY_MAX_TOKENS, render_prompt
from .models import CostRow, CostTable, LlmRequest


def count_tokens(text: str, *, tokenizer: Any = None) -> int:
    if tokenizer is not None:
        if hasattr(tokenizer, "encode"):
            tokens = tokenizer.encode(text)
            return max(1, len(tokens))
        raise TypeError("tokenizer must expose encode(text)")
    return max(1, len(text.encode("utf-8")))


def count_request_tokens(req: LlmRequest, *, tokenizer: Any = None) -> int:
    return count_tokens(req.system, tokenizer=tokenizer) + sum(
        count_tokens(message.content, tokenizer=tokenizer) for message in req.messages
    )


def estimate_cost(
    prompts: Sequence[str],
    pricing: Mapping[str, float],
    *,
    output_token_cap: int,
    tokenizer: Any = None,
    model: str = "",
    provider: str = "",
) -> CostRow:
    input_tokens = sum(count_tokens(prompt, tokenizer=tokenizer) for prompt in prompts)
    input_per_m = _price(pricing, "input_per_m")
    output_per_m = _price(pricing, "output_per_m")
    input_usd = input_tokens * input_per_m / 1_000_000
    output_usd = len(prompts) * output_token_cap * output_per_m / 1_000_000
    return CostRow(
        model=model,
        provider=provider,
        input_tokens=input_tokens,
        output_token_cap=output_token_cap,
        input_usd=input_usd,
        output_usd=output_usd,
        total_usd=input_usd + output_usd,
        token_source="tokenizer" if tokenizer is not None else "byte-estimate",
    )


def _price(pricing: Mapping[str, float], key: str) -> float:
    value = pricing[key]
    if isinstance(value, bool):
        raise ValueError(f"pricing {key!r} must be numeric")
    number = float(value)
    if not math.isfinite(number) or number < 0.0:
        raise ValueError(f"pricing {key!r} must be finite and non-negative")
    return number


def estimate_modal_cost(
    prompts: Sequence[str],
    pricing: Mapping[str, float],
    *,
    model: str,
    provider: str,
) -> CostRow:
    input_tokens = sum(count_tokens(prompt) for prompt in prompts)
    gpu_second = _price(pricing, "gpu_second")
    gpu_seconds_per_1k = _price(pricing, "gpu_seconds_per_1k")
    total = (len(prompts) / 1000) * gpu_seconds_per_1k * gpu_second
    return CostRow(
        model=model,
        provider=provider,
        input_tokens=input_tokens,
        output_token_cap=0,
        input_usd=0.0,
        output_usd=total,
        total_usd=total,
        token_source="byte-estimate",
        output_cost_source="estimated-gpu-seconds",
    )


def build_cost_table(
    corpus: Sequence[Mapping[str, object]],
    models: Sequence[Mapping[str, object]],
    pricing: Mapping[str, Mapping[str, float]],
    *,
    output_token_cap: int = CURIOSITY_MAX_TOKENS,
) -> CostTable:
    prompts = [render_prompt(place) for place in corpus]
    rows = []
    for model in models:
        model_id = str(model["id"])
        provider = str(model["provider"])
        if provider == "modal" and "gpu_second" in pricing[model_id]:
            row = estimate_modal_cost(prompts, pricing[model_id], model=model_id, provider=provider)
        else:
            row = estimate_cost(
                prompts,
                pricing[model_id],
                output_token_cap=output_token_cap,
                model=model_id,
                provider=provider,
            )
        rows.append(row)
    return CostTable(rows=tuple(rows))
