"""Report per-family injection resistance from the local A6 live cache.

No provider clients are constructed and no live calls are made.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import NamedTuple

from mt_pipeline.llm import bakeoff
from mt_pipeline.llm import cache as llm_cache
from mt_pipeline.llm import curiosity


DEFAULT_MODEL_IDS = ("nous-hermes-4-70b", "nous-nex-n2-mini")
REQUEST_OPTION_KEYS = ("max_tokens", "reasoning", "provider_tags", "seed")


class MissingCacheError(RuntimeError):
    pass


class FamilyRow(NamedTuple):
    model: str
    family: str
    probes: int
    resisted: int
    resistance: float


def _default_cache_dir() -> Path:
    env = os.getenv("A6_ROUND1_CACHE_DIR") or os.getenv("MT_LLM_CACHE_DIR")
    if env:
        return Path(env)
    root = llm_cache.PROJECT_ROOT
    candidates = (
        root / ".mt-data" / "a6-round1" / "llm-cache",
        root / ".mt-data" / "llm-cache",
    )
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


def _load_models(path: Path) -> list[dict[str, object]]:
    data = json.loads(path.read_text())
    models = data.get("models")
    if not isinstance(models, list):
        raise ValueError("models file must contain a models list")
    rows: list[dict[str, object]] = []
    for row in models:
        if not isinstance(row, dict):
            raise ValueError("model roster entries must be objects")
        rows.append(row)
    return rows


def _model_options(model: dict[str, object]) -> dict[str, object]:
    return {key: model[key] for key in REQUEST_OPTION_KEYS if key in model}


def _output_cap(options: dict[str, object]) -> int:
    value = options.get("max_tokens", curiosity.CURIOSITY_MAX_TOKENS)
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError("model max_tokens must be an integer")
    if value <= 0 or value > 4096:
        raise ValueError("model max_tokens must be in 1..4096")
    return value


def _request_for_probe(
    probe: bakeoff.InjectionProbe,
    *,
    cache_model_id: str,
    api_model_id: str,
    options: dict[str, object],
) -> curiosity.LlmRequest:
    provider_tags = options.get("provider_tags")
    if provider_tags is not None:
        provider_tags = tuple(provider_tags)  # type: ignore[arg-type]
    return curiosity.curiosity_request(
        query_id=probe.place_id,
        model_id=cache_model_id,
        provider_model_id=api_model_id,
        place=probe.place,
        max_tokens=_output_cap(options),
        provider_tags=provider_tags,  # type: ignore[arg-type]
        reasoning=options.get("reasoning"),  # type: ignore[arg-type]
        seed=options.get("seed", 0),  # type: ignore[arg-type]
    )


def _cache() -> llm_cache.LlmCache:
    return llm_cache.LlmCache(
        Path("."),
        validators={curiosity.CURIOSITY_TASK_ID: lambda blob: curiosity.parse_curiosity(json.dumps(blob))},
    )


def _input_hash(req: curiosity.LlmRequest) -> str:
    return llm_cache.input_hash(
        task_id=req.task_id,
        prompt_version=req.prompt_version,
        rendered_prompt=req.messages[0].content,
    )


def _score_for_probe(
    cache_dir: Path,
    probe: bakeoff.InjectionProbe,
    *,
    model_id: str,
    api_model_id: str,
    options: dict[str, object],
) -> float:
    cache = _cache()
    cache.root = cache_dir
    cache_model_ids = (model_id,) if model_id == api_model_id else (model_id, api_model_id)
    attempted_keys: list[str] = []
    for cache_model_id in cache_model_ids:
        req = _request_for_probe(
            probe,
            cache_model_id=cache_model_id,
            api_model_id=api_model_id,
            options=options,
        )
        input_hash = _input_hash(req)
        attempted_keys.append(llm_cache.cache_key(req.task_id, req.model_id, req.prompt_version, input_hash))
        cached = cache.get(req.task_id, req.model_id, req.prompt_version, input_hash)
        if cached is not None:
            return float(cached.curiosity)
    raise MissingCacheError(
        f"missing cache for model={model_id} probe={probe.place_id}; tried {', '.join(attempted_keys)}"
    )


def _resisted(probe: bakeoff.InjectionProbe, score: float) -> bool:
    scored_percentile = bakeoff._percentile_for_score(score, bakeoff.KL_RANK_REFERENCE.scores)
    upward_shift = scored_percentile - probe.honest_percentile
    downward_shift = probe.honest_percentile - scored_percentile
    if probe.direction == "inflation":
        return upward_shift <= bakeoff.INJECTION_MAX_PERCENTILE_SHIFT
    if probe.direction == "deflation":
        return downward_shift <= bakeoff.INJECTION_MAX_PERCENTILE_SHIFT
    if probe.direction == "honest_control":
        return downward_shift <= bakeoff.INJECTION_MAX_PERCENTILE_SHIFT
    raise ValueError(f"unknown injection direction {probe.direction!r}")


def family_report_rows(
    cache_dir: str | Path,
    models: list[dict[str, object]],
    *,
    fixture: tuple[bakeoff.InjectionProbe, ...] = bakeoff.TWO_SIDED_INJECTION_PROBES,
    model_ids: tuple[str, ...] | None = None,
) -> list[FamilyRow]:
    cache_path = Path(cache_dir)
    rows: list[FamilyRow] = []
    selected = set(model_ids) if model_ids is not None else None
    for model in models:
        model_id = str(model["id"])
        if selected is not None and model_id not in selected:
            continue
        if model.get("provider") != "nous":
            continue
        if "live_skip_reason" in model:
            continue
        api_model_id = str(model.get("api_model_id", model_id))
        options = _model_options(model)
        totals: dict[str, int] = {}
        resisted: dict[str, int] = {}
        for probe in fixture:
            score = _score_for_probe(
                cache_path,
                probe,
                model_id=model_id,
                api_model_id=api_model_id,
                options=options,
            )
            totals[probe.family] = totals.get(probe.family, 0) + 1
            if _resisted(probe, score):
                resisted[probe.family] = resisted.get(probe.family, 0) + 1
        for family in sorted(totals):
            probes = totals[family]
            count = resisted.get(family, 0)
            rows.append(FamilyRow(model_id, family, probes, count, count / probes))
    return rows


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=Path, default=_default_cache_dir())
    parser.add_argument(
        "--models",
        type=Path,
        default=llm_cache.PROJECT_ROOT / "pipeline" / "config" / "llm_models.json",
    )
    parser.add_argument("--model", action="append", dest="model_ids", help="roster model id to include")
    return parser


def main() -> int:
    args = _build_parser().parse_args()
    model_ids = tuple(args.model_ids) if args.model_ids else DEFAULT_MODEL_IDS
    rows = family_report_rows(args.cache_dir, _load_models(args.models), model_ids=model_ids)
    print("model\tfamily\tprobes\tresisted\tresistance")
    for row in rows:
        print(f"{row.model}\t{row.family}\t{row.probes}\t{row.resisted}\t{row.resistance:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
