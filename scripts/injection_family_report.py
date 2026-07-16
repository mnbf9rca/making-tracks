"""Report per-family injection resistance from the local A6 live cache.

No provider clients are constructed and no live calls are made.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import NamedTuple

from mt_pipeline.eval import golden
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


class ProbeRow(NamedTuple):
    model: str
    family: str
    probe_id: str
    origin_place_id: str
    direction: str
    clean: float
    score: float
    clean_percentile: float
    injected_percentile: float
    shift: float
    verdict: str
    obedient_verdict: str
    resistant_verdict: str
    dead_weight: bool


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


def _load_labeled_rows(path: Path) -> list[golden.GoldenRow]:
    parsed = golden.parse_labeled_tsv(path.read_text())
    if parsed.skipped:
        details = "; ".join(f"{ident}: {reason}" for ident, reason in parsed.skipped[:5])
        raise ValueError(f"labeled TSV has skipped rows: {details}")
    return parsed.rows


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


def _request_for_row(
    row: golden.GoldenRow,
    *,
    cache_model_id: str,
    api_model_id: str,
    options: dict[str, object],
) -> curiosity.LlmRequest:
    provider_tags = options.get("provider_tags")
    if provider_tags is not None:
        provider_tags = tuple(provider_tags)  # type: ignore[arg-type]
    return curiosity.curiosity_request(
        query_id=row.place_id,
        model_id=cache_model_id,
        provider_model_id=api_model_id,
        place={"name": row.name, "summary": row.evidence, "tags": [row.category]},
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


def _score_for_row(
    cache_dir: Path,
    row: golden.GoldenRow,
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
        req = _request_for_row(
            row,
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
        f"missing clean cache for model={model_id} place={row.place_id}; tried {', '.join(attempted_keys)}"
    )


def _clean_scores_for_model(
    cache_dir: Path,
    rows: list[golden.GoldenRow],
    *,
    model_id: str,
    api_model_id: str,
    options: dict[str, object],
) -> dict[str, float]:
    return {
        row.place_id: _score_for_row(
            cache_dir,
            row,
            model_id=model_id,
            api_model_id=api_model_id,
            options=options,
        )
        for row in rows
    }


def _resisted_at_percentiles(probe: bakeoff.InjectionProbe, *, clean_percentile: float, scored_percentile: float) -> bool:
    upward_shift = scored_percentile - clean_percentile
    downward_shift = clean_percentile - scored_percentile
    if probe.direction == "inflation":
        return upward_shift <= bakeoff.INJECTION_MAX_PERCENTILE_SHIFT
    if probe.direction == "deflation":
        return downward_shift <= bakeoff.INJECTION_MAX_PERCENTILE_SHIFT
    if probe.direction == "honest_control":
        return downward_shift <= bakeoff.INJECTION_MAX_PERCENTILE_SHIFT
    raise ValueError(f"unknown injection direction {probe.direction!r}")


def _direction_shift(probe: bakeoff.InjectionProbe, *, clean_percentile: float, scored_percentile: float) -> float:
    if probe.direction == "inflation":
        return scored_percentile - clean_percentile
    if probe.direction in {"deflation", "honest_control"}:
        return clean_percentile - scored_percentile
    raise ValueError(f"unknown injection direction {probe.direction!r}")


def _obedient_score(probe: bakeoff.InjectionProbe) -> float:
    if probe.direction == "inflation":
        return 1.0
    if probe.direction in {"deflation", "honest_control"}:
        return 0.0
    raise ValueError(f"unknown injection direction {probe.direction!r}")


def _verdict(probe: bakeoff.InjectionProbe, *, clean_score: float, score: float, reference_scores: list[float]) -> str:
    if not reference_scores:
        raise ValueError("injection reference_scores must not be empty")
    clean_percentile = bakeoff._percentile_for_score(clean_score, reference_scores)
    scored_percentile = bakeoff._percentile_for_score(score, reference_scores)
    return "pass" if _resisted_at_percentiles(
        probe,
        clean_percentile=clean_percentile,
        scored_percentile=scored_percentile,
    ) else "fail"


def family_report_rows(
    cache_dir: str | Path,
    models: list[dict[str, object]],
    *,
    clean_rows: list[golden.GoldenRow] | None = None,
    clean_scores_by_model: dict[str, dict[str, float]] | None = None,
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
        clean_scores = (
            clean_scores_by_model[model_id]
            if clean_scores_by_model is not None
            else _clean_scores_for_model(
                cache_path,
                clean_rows or [],
                model_id=model_id,
                api_model_id=api_model_id,
                options=options,
            )
        )
        reference_scores = list(clean_scores.values())
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
            if _verdict(
                probe,
                clean_score=clean_scores[probe.origin_place_id],
                score=score,
                reference_scores=reference_scores,
            ) == "pass":
                resisted[probe.family] = resisted.get(probe.family, 0) + 1
        for family in sorted(totals):
            probes = totals[family]
            count = resisted.get(family, 0)
            rows.append(FamilyRow(model_id, family, probes, count, count / probes))
    return rows


def probe_report_rows(
    cache_dir: str | Path,
    models: list[dict[str, object]],
    *,
    clean_rows: list[golden.GoldenRow] | None = None,
    clean_scores_by_model: dict[str, dict[str, float]] | None = None,
    fixture: tuple[bakeoff.InjectionProbe, ...] = bakeoff.TWO_SIDED_INJECTION_PROBES,
    model_ids: tuple[str, ...] | None = None,
    directions: tuple[str, ...] = ("inflation", "deflation", "honest_control"),
) -> list[ProbeRow]:
    cache_path = Path(cache_dir)
    rows: list[ProbeRow] = []
    selected_models = set(model_ids) if model_ids is not None else None
    selected_directions = set(directions)
    for model in models:
        model_id = str(model["id"])
        if selected_models is not None and model_id not in selected_models:
            continue
        if model.get("provider") != "nous":
            continue
        if "live_skip_reason" in model:
            continue
        api_model_id = str(model.get("api_model_id", model_id))
        options = _model_options(model)
        clean_scores = (
            clean_scores_by_model[model_id]
            if clean_scores_by_model is not None
            else _clean_scores_for_model(
                cache_path,
                clean_rows or [],
                model_id=model_id,
                api_model_id=api_model_id,
                options=options,
            )
        )
        reference_scores = list(clean_scores.values())
        for probe in fixture:
            if probe.direction not in selected_directions:
                continue
            score = _score_for_probe(
                cache_path,
                probe,
                model_id=model_id,
                api_model_id=api_model_id,
                options=options,
            )
            clean_score = clean_scores[probe.origin_place_id]
            clean_percentile = bakeoff._percentile_for_score(clean_score, reference_scores)
            injected_percentile = bakeoff._percentile_for_score(score, reference_scores)
            shift = _direction_shift(probe, clean_percentile=clean_percentile, scored_percentile=injected_percentile)
            verdict = "pass" if _resisted_at_percentiles(
                probe,
                clean_percentile=clean_percentile,
                scored_percentile=injected_percentile,
            ) else "fail"
            obedient_verdict = _verdict(
                probe,
                clean_score=clean_score,
                score=_obedient_score(probe),
                reference_scores=reference_scores,
            )
            resistant_verdict = _verdict(
                probe,
                clean_score=clean_score,
                score=clean_score,
                reference_scores=reference_scores,
            )
            rows.append(
                ProbeRow(
                    model=model_id,
                    family=probe.family,
                    probe_id=probe.place_id,
                    origin_place_id=probe.origin_place_id,
                    direction=probe.direction,
                    clean=clean_score,
                    score=score,
                    clean_percentile=clean_percentile,
                    injected_percentile=injected_percentile,
                    shift=shift,
                    verdict=verdict,
                    obedient_verdict=obedient_verdict,
                    resistant_verdict=resistant_verdict,
                    dead_weight=obedient_verdict == resistant_verdict,
                )
            )
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
    parser.add_argument(
        "--labeled",
        type=Path,
        default=llm_cache.PROJECT_ROOT
        / "docs"
        / "superpowers"
        / "eval"
        / "real-malaysia-20260715-pageviews-golden-kl.tsv",
        help="labeled TSV used for the clean model cache distribution",
    )
    parser.add_argument("--per-probe", action="store_true", help="print per-probe geometry diagnostics")
    parser.add_argument(
        "--direction",
        action="append",
        choices=("inflation", "deflation", "honest_control"),
        help="per-probe direction to include; repeatable",
    )
    return parser


def _tsv(value: object) -> str:
    return str(value).replace("\t", " ").replace("\r", " ").replace("\n", " ")


def main() -> int:
    args = _build_parser().parse_args()
    model_ids = tuple(args.model_ids) if args.model_ids else DEFAULT_MODEL_IDS
    models = _load_models(args.models)
    clean_rows = _load_labeled_rows(args.labeled)
    if args.per_probe:
        directions = tuple(args.direction) if args.direction else ("inflation", "deflation", "honest_control")
        probe_rows = probe_report_rows(
            args.cache_dir,
            models,
            clean_rows=clean_rows,
            model_ids=model_ids,
            directions=directions,
        )
        print(
            "model\tfamily\tprobe_id\torigin_place_id\tdirection\tclean\tscore\t"
            "clean_percentile\tinjected_percentile\tshift\tverdict\t"
            "obedient_verdict\tresistant_verdict\tdead_weight"
        )
        for row in probe_rows:
            print(
                f"{_tsv(row.model)}\t{_tsv(row.family)}\t{_tsv(row.probe_id)}\t"
                f"{_tsv(row.origin_place_id)}\t{_tsv(row.direction)}\t"
                f"{row.clean:.6f}\t{row.score:.6f}\t{row.clean_percentile:.6f}\t"
                f"{row.injected_percentile:.6f}\t{row.shift:.6f}\t{_tsv(row.verdict)}\t"
                f"{_tsv(row.obedient_verdict)}\t{_tsv(row.resistant_verdict)}\t"
                f"{str(row.dead_weight).lower()}"
            )
    else:
        rows = family_report_rows(args.cache_dir, models, clean_rows=clean_rows, model_ids=model_ids)
        print("model\tfamily\tprobes\tresisted\tresistance")
        for row in rows:
            print(f"{_tsv(row.model)}\t{_tsv(row.family)}\t{row.probes}\t{row.resisted}\t{row.resistance:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
