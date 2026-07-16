"""Command-line entry point for the region-parameterised pipeline."""

from __future__ import annotations

import argparse
import asyncio
from contextlib import contextmanager
import fcntl
import json
import math
import os
import pathlib
import re
import sqlite3
import sys
from collections.abc import Sequence

from . import acquire, audit, categorize, config, extract_stage, stages, store
from .eval import golden, metrics as eval_metrics, report as eval_report, rescore
from .llm import bakeoff, cache as llm_cache, costmodel, curiosity
from .llm.providers.fake import FakeProvider

_DEFAULT_RUN_ID = "manual"
_COMMANDS = ("acquire", "acquire-redirects", "audit", *stages.STAGE_ORDER)
_PIPELINE_ROOT = pathlib.Path(__file__).resolve().parents[2]
_DEFAULT_GOLDEN_AREAS = _PIPELINE_ROOT / "config" / "golden_areas.json"
_DEFAULT_LLM_MODELS = _PIPELINE_ROOT / "config" / "llm_models.json"
_DEFAULT_LLM_PRICING = _PIPELINE_ROOT / "config" / "llm_pricing.json"
_DEFAULT_EVAL_OUT_DIR = _PIPELINE_ROOT.parent / "docs" / "superpowers" / "eval"
_MAX_JSON_BYTES = 1_000_000
_MAX_TSV_BYTES = 10_000_000
_SAFE_FILENAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
_VERSION_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mt-pipeline",
        description="Making Tracks data pipeline.",
    )
    parser.add_argument("--region", required=True, help="region id, e.g. uk")
    parser.add_argument("stage", choices=_COMMANDS, help="pipeline stage or acquisition step")
    parser.add_argument("--db", default="work.db", help="path to the SQLite store")
    parser.add_argument("--run-id", default=_DEFAULT_RUN_ID, help="run metadata tag")
    parser.add_argument(
        "--data-dir",
        default=".mt-data",
        help="base directory for acquired snapshots; region subdir is used",
    )
    parser.add_argument(
        "--snapshot-dir",
        help="directory containing snapshots for extract or redirect-map acquisition",
    )
    parser.add_argument(
        "--osm-index-type",
        default="flex_mem",
        help="pyosmium location index type for OSM extraction",
    )
    parser.add_argument(
        "--only-source",
        help="for extract, replace only one enabled source from cached snapshot",
    )
    parser.add_argument(
        "--audit-format",
        choices=("markdown", "json"),
        default="markdown",
        help="output format for the audit command",
    )
    parser.add_argument(
        "--version",
        help="publish version for reconcile, formatted YYYYMMDDThhmmssZ",
    )
    return parser

def _normalize_argv(argv: Sequence[str] | None) -> list[str]:
    """Normalize argv, including the `mt audit <region>` shortcut."""
    if argv is None:
        args = sys.argv[1:]
    else:
        args = list(argv)
    if len(args) >= 2 and args[0] == "audit" and not args[1].startswith("-"):
        return ["--region", args[1], "audit", *args[2:]]
    return args


def _build_eval_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mt-pipeline eval",
        description="Making Tracks ranking eval tools.",
    )
    subparsers = parser.add_subparsers(dest="eval_command", required=True)

    dump = subparsers.add_parser("dump", help="dump a golden area TSV+JSONL pair")
    dump.add_argument("area", help="golden area id, e.g. london or kl")
    dump.add_argument("--db", default="work.db", help="path to the SQLite store")
    dump.add_argument("--run-id", default=_DEFAULT_RUN_ID, help="data version tag")
    dump.add_argument(
        "--areas-config",
        default=str(_DEFAULT_GOLDEN_AREAS),
        help="path to golden_areas.json",
    )
    dump.add_argument(
        "--out-dir",
        default=str(_DEFAULT_EVAL_OUT_DIR),
        help="directory for TSV+JSONL dumps",
    )

    report = subparsers.add_parser("report", help="score a labeled golden TSV")
    report.add_argument("labeled_tsv", help="hand-labeled golden TSV")
    report.add_argument("--config", required=True, help="scoring JSON config")
    report.add_argument("--baseline", help="optional metric baseline JSON for regression gate")
    return parser


def _build_llm_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mt-pipeline llm",
        description="Making Tracks keyless LLM tooling.",
    )
    subparsers = parser.add_subparsers(dest="llm_command", required=True)

    cost = subparsers.add_parser("cost", help="estimate keyless curiosity prompt costs")
    cost.add_argument("--corpus", required=True, help="JSONL corpus of places or golden rows")
    cost.add_argument(
        "--models",
        default=str(_DEFAULT_LLM_MODELS),
        help="model roster JSON",
    )
    cost.add_argument(
        "--pricing",
        default=str(_DEFAULT_LLM_PRICING),
        help="pricing table JSON",
    )

    bakeoff_cmd = subparsers.add_parser("bakeoff", help="run keyless fake-provider bake-off")
    bakeoff_cmd.add_argument("--labeled", required=True, help="hand-labeled golden TSV")
    bakeoff_cmd.add_argument("--config", required=True, help="scoring JSON config")
    bakeoff_cmd.add_argument("--models", default=str(_DEFAULT_LLM_MODELS), help="model roster JSON")
    bakeoff_cmd.add_argument("--pricing", default=str(_DEFAULT_LLM_PRICING), help="pricing table JSON")
    bakeoff_cmd.add_argument("--k", type=int, default=5, help="precision@k cutoff")
    bakeoff_cmd.add_argument("--live", action="store_true", help="enable guarded live provider calls")
    bakeoff_cmd.add_argument("--max-places", type=int, help="required cap for --live provider calls")
    bakeoff_cmd.add_argument("--model", help="specific live model id; defaults to cheapest NOUS row")
    bakeoff_cmd.add_argument(
        "--budget-cap",
        type=float,
        default=10.0,
        help="hard cumulative live eval budget cap in USD",
    )
    bakeoff_cmd.add_argument(
        "--cache-dir",
        default=str(_PIPELINE_ROOT.parent / ".mt-data" / "llm-cache"),
        help="local validate-on-read LLM cache directory",
    )
    return parser


def _snapshot_dir(args) -> pathlib.Path:
    if args.snapshot_dir:
        return pathlib.Path(args.snapshot_dir)
    return pathlib.Path(args.data_dir) / args.region


def _initial_extract_statuses(sources: dict, *, only_source: str | None = None) -> dict:
    return {
        source: {
            "status": (
                "disabled"
                if enabled is not True
                else "preserved"
                if only_source is not None and source != only_source
                else "not_run"
            )
        }
        for source, enabled in sorted(sources.items())
    }


def _record_extract_metadata(conn, region, run_id: str, snap_dir, statuses: dict) -> None:
    wikidata_date = ""
    if region.sources.get("wikidata") is True:
        wikidata_date = acquire.wikidata_snapshot_retrieved_at(
            acquire.snapshot_paths(snap_dir)["wikidata"]
        )
    store.record_extract_run_metadata(
        conn,
        region=region.region_id,
        run_id=run_id,
        wikidata_snapshot_date=wikidata_date,
        source_statuses=statuses,
    )


def _read_text_limited(path: pathlib.Path, *, max_bytes: int) -> str:
    if path.stat().st_size > max_bytes:
        raise ValueError(f"{path} exceeds {max_bytes} byte limit")
    return path.read_text()


def _load_json(path: pathlib.Path, *, max_bytes: int = _MAX_JSON_BYTES):
    return json.loads(_read_text_limited(path, max_bytes=max_bytes))


def _load_mapping_json(path: pathlib.Path) -> dict:
    data = _load_json(path)
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return data


def _load_llm_corpus_jsonl(path: pathlib.Path) -> list[dict[str, object]]:
    text = _read_text_limited(path, max_bytes=_MAX_TSV_BYTES)
    rows: list[dict[str, object]] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            raw = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"invalid JSONL at line {lineno}: {exc}") from exc
        if not isinstance(raw, dict):
            raise ValueError(f"JSONL line {lineno} must be an object")
        name = raw.get("name", "")
        category = raw.get("category", "")
        evidence = raw.get("evidence", "")
        summary = raw.get("summary", evidence)
        signals = raw.get("signals", {})
        tags = [category] if category else []
        if isinstance(signals, dict):
            tags.extend(str(key) for key, value in sorted(signals.items()) if value is not None)
        rows.append({"name": name, "summary": summary, "tags": tags})
    return rows


def _load_metric_baseline(path: pathlib.Path) -> dict[str, float]:
    data = _load_mapping_json(path)
    baseline = {}
    for key, value in data.items():
        if not isinstance(key, str):
            raise ValueError("baseline metric keys must be strings")
        if not isinstance(value, int | float) or isinstance(value, bool):
            raise ValueError(f"baseline metric {key!r} must be numeric")
        number = float(value)
        if not math.isfinite(number):
            raise ValueError(f"baseline metric {key!r} must be finite")
        baseline[key] = number
    return baseline


def _require_nous_api_key() -> str:
    value = os.getenv("NOUS_API_KEY", "")
    if not value.strip() or value.strip().startswith("op:"):
        raise ValueError("NOUS_API_KEY is required and must be non-empty for --live")
    return value


def _format_optional_metric(value: float | None) -> str:
    return "undefined" if value is None else f"{value:.3f}"


def _validate_budget_cap(value: float) -> float:
    if isinstance(value, bool):
        raise ValueError("--budget-cap must be numeric")
    number = float(value)
    if not math.isfinite(number) or number <= 0.0:
        raise ValueError("--budget-cap must be finite and positive")
    return number


def _ledger_path(cache_dir: pathlib.Path) -> pathlib.Path:
    # Budget ledger/cap is eval-only; production enrichment uses provider-side budget-limit features.
    return cache_dir.parent / "live-cost-ledger.json"


def _ledger_lock_path(cache_dir: pathlib.Path) -> pathlib.Path:
    return cache_dir.parent / "live-cost-ledger.lock"


@contextmanager
def _locked_cost_ledger(cache_dir: pathlib.Path):
    path = _ledger_lock_path(cache_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


def _load_cost_ledger(cache_dir: pathlib.Path) -> dict[str, float | int]:
    path = _ledger_path(cache_dir)
    if not path.exists():
        return {"schema_version": 1, "total_usd": 0.0, "measured_usd": 0.0, "derived_usd": 0.0, "runs": 0}
    data = _load_mapping_json(path)
    if data.get("schema_version") != 1:
        raise ValueError("live cost ledger schema_version must be 1")
    ledger: dict[str, float | int] = {"schema_version": 1}
    for key in ("total_usd", "measured_usd", "derived_usd"):
        value = data.get(key)
        if not isinstance(value, int | float) or isinstance(value, bool):
            raise ValueError(f"live cost ledger {key} must be numeric")
        number = float(value)
        if not math.isfinite(number) or number < 0.0:
            raise ValueError(f"live cost ledger {key} must be finite and non-negative")
        ledger[key] = number
    runs = data.get("runs")
    if not isinstance(runs, int) or isinstance(runs, bool) or runs < 0:
        raise ValueError("live cost ledger runs must be a non-negative integer")
    ledger["runs"] = runs
    if abs(float(ledger["total_usd"]) - (float(ledger["measured_usd"]) + float(ledger["derived_usd"]))) > 1e-9:
        raise ValueError("live cost ledger total_usd must equal measured_usd + derived_usd")
    return ledger


def _save_cost_ledger(cache_dir: pathlib.Path, ledger: dict[str, float | int]) -> None:
    path = _ledger_path(cache_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(ledger, sort_keys=True, separators=(",", ":"), allow_nan=False)
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    tmp.write_text(payload)
    os.replace(tmp, path)


def _update_cost_ledger(
    cache_dir: pathlib.Path,
    ledger: dict[str, float | int],
    per_place: list[tuple[str, float, bool, float, str]],
) -> dict[str, float | int]:
    measured = sum(cost for _, _, _, cost, source in per_place if source == "measured")
    derived = sum(cost for _, _, _, cost, source in per_place if source == "derived")
    updated = {
        "schema_version": 1,
        "total_usd": float(ledger["total_usd"]) + measured + derived,
        "measured_usd": float(ledger["measured_usd"]) + measured,
        "derived_usd": float(ledger["derived_usd"]) + derived,
        "runs": int(ledger["runs"]) + 1,
    }
    _save_cost_ledger(cache_dir, updated)
    return updated


def _select_live_nous_model(
    model_rows: list[object],
    pricing: dict,
    rows: list[golden.GoldenRow],
    *,
    requested_model: str | None,
) -> tuple[str, str, dict, float]:
    candidates: list[tuple[float, str, str, dict]] = []
    prompts = [
        curiosity.render_prompt({"name": row.name, "summary": row.evidence, "tags": [row.category]})
        for row in rows
    ]
    for model in model_rows:
        if not isinstance(model, dict):
            raise ValueError("model roster entries must be objects")
        model_id = str(model["id"])
        provider_id = str(model["provider"])
        if requested_model is not None and model_id != requested_model:
            continue
        if provider_id != "nous":
            continue
        api_model_id = str(model.get("api_model_id", model_id))
        model_pricing = pricing.get(model_id)
        if not isinstance(model_pricing, dict):
            raise ValueError(f"pricing missing for model {model_id!r}")
        estimate = costmodel.estimate_cost(
            prompts,
            model_pricing,
            output_token_cap=curiosity.CURIOSITY_MAX_TOKENS,
            model=model_id,
            provider=provider_id,
        )
        candidates.append((estimate.total_usd, model_id, api_model_id, model_pricing))
    if not candidates:
        if requested_model is not None:
            raise ValueError(f"requested live model {requested_model!r} is not a NOUS model in the roster")
        raise ValueError("live bakeoff requires at least one NOUS model in the roster")
    estimated_cost, model_id, api_model_id, model_pricing = sorted(candidates, key=lambda item: (item[0], item[1]))[0]
    return model_id, api_model_id, model_pricing, estimated_cost


def _curiosity_cache(cache_dir: pathlib.Path) -> llm_cache.LlmCache:
    validators = {
        curiosity.CURIOSITY_TASK_ID: lambda blob: curiosity.parse_curiosity(json.dumps(blob))
    }
    return llm_cache.LlmCache(cache_dir, validators=validators)


def _live_request(row: golden.GoldenRow, *, api_model_id: str) -> curiosity.LlmRequest:
    return curiosity.curiosity_request(
        query_id=row.place_id,
        model_id=api_model_id,
        place={"name": row.name, "summary": row.evidence, "tags": [row.category]},
    )


def _collect_live_cache_state(
    rows: list[golden.GoldenRow],
    *,
    api_model_id: str,
    cache_dir: pathlib.Path,
) -> tuple[
    llm_cache.LlmCache,
    dict[str, float],
    list[tuple[str, float, bool, float, str]],
    list[tuple[golden.GoldenRow, str, curiosity.LlmRequest]],
]:
    cache = _curiosity_cache(cache_dir)
    curiosities: dict[str, float] = {}
    output_rows: list[tuple[str, float, bool, float, str]] = []
    misses: list[tuple[golden.GoldenRow, str, curiosity.LlmRequest]] = []

    for row in rows:
        req = _live_request(row, api_model_id=api_model_id)
        rendered_prompt = req.messages[0].content
        input_hash = llm_cache.input_hash(
            task_id=req.task_id,
            prompt_version=req.prompt_version,
            rendered_prompt=rendered_prompt,
        )
        cached = cache.get(req.task_id, req.model_id, req.prompt_version, input_hash)
        if cached is not None:
            value = cached.curiosity
            curiosities[row.place_id] = value
            output_rows.append((row.place_id, value, True, 0.0, "cache"))
        else:
            misses.append((row, input_hash, req))
    return cache, curiosities, output_rows, misses


def _estimate_request_cost(
    requests: list[tuple[golden.GoldenRow, str, curiosity.LlmRequest]],
    model_pricing: dict,
    *,
    model_id: str,
) -> float:
    prompts = [req.messages[0].content for _, _, req in requests]
    return costmodel.estimate_cost(
        prompts,
        model_pricing,
        output_token_cap=curiosity.CURIOSITY_MAX_TOKENS,
        model=model_id,
        provider="nous",
    ).total_usd


async def _score_live_with_cache_async(
    *,
    cache_dir: pathlib.Path,
    cache: llm_cache.LlmCache,
    ledger: dict[str, float | int],
    curiosities: dict[str, float],
    output_rows: list[tuple[str, float, bool, float, str]],
    misses: list[tuple[golden.GoldenRow, str, curiosity.LlmRequest]],
    model_pricing: dict,
    api_key: str,
) -> tuple[dict[str, float], list[tuple[str, float, bool, float, str]], float, int, dict[str, float | int]]:
    from .llm.providers import nous as nous_provider

    total_response_cost = 0.0
    charged_rows: list[tuple[str, float, bool, float, str]] = []
    provider = None
    session_cost: float | None = None
    try:
        if misses:
            provider = nous_provider.NousProvider(
                api_key=api_key,
                concurrency=1,
                input_per_m=float(model_pricing.get("input_per_m", 0.0)),
                output_per_m=float(model_pricing.get("output_per_m", 0.0)),
            )
            responses = await provider.acomplete_batch([req for _, _, req in misses])
            if len(responses) != len(misses):
                charged_rows.extend(
                    ("unknown", 0.0, False, response.cost_usd, response.cost_source)
                    for response in responses
                )
                raise ValueError("provider returned a different number of responses")
            for (row, input_hash, req), response in zip(misses, responses, strict=True):
                charged_rows.append((row.place_id, 0.0, False, response.cost_usd, response.cost_source))
                total_response_cost += response.cost_usd
                parsed = curiosity.parse_curiosity(response.text)
                cache.put(
                    llm_cache.cache_key(req.task_id, req.model_id, req.prompt_version, input_hash),
                    parsed.model_dump(),
                )
                value = parsed.curiosity
                curiosities[row.place_id] = value
                output_rows.append((row.place_id, value, False, response.cost_usd, response.cost_source))
    finally:
        if provider is not None:
            session_cost = await provider.shutdown()
        if charged_rows:
            ledger = _update_cost_ledger(cache_dir, ledger, charged_rows)

    output_rows.sort(key=lambda item: item[0])
    total_cost = session_cost if session_cost is not None else total_response_cost
    cache_hits = sum(1 for _, _, hit, _, _ in output_rows if hit)
    if not charged_rows:
        ledger = _update_cost_ledger(cache_dir, ledger, output_rows)
    return curiosities, output_rows, total_cost, cache_hits, ledger


def _run_live_bakeoff(args, *, parsed: golden.ParseResult, config_data: dict, model_rows: list, pricing: dict) -> int:
    if args.max_places is None:
        print("--max-places is required with --live", file=sys.stderr)
        return 2
    if args.max_places <= 0:
        print("--max-places must be positive with --live", file=sys.stderr)
        return 2
    try:
        budget_cap = _validate_budget_cap(args.budget_cap)
        api_key = _require_nous_api_key()
        rows = parsed.rows[: args.max_places]
        if not rows:
            raise ValueError("live bakeoff has no parsed rows to score")
        model_id, api_model_id, model_pricing, estimated_cost = _select_live_nous_model(
            model_rows,
            pricing,
            rows,
            requested_model=args.model,
        )
        cache_dir = pathlib.Path(args.cache_dir)
        with _locked_cost_ledger(cache_dir):
            cache, curiosities, per_place, misses = _collect_live_cache_state(
                rows,
                api_model_id=api_model_id,
                cache_dir=cache_dir,
            )
            ledger = _load_cost_ledger(cache_dir)
            estimated_miss_cost = _estimate_request_cost(misses, model_pricing, model_id=model_id)
            if float(ledger["total_usd"]) + estimated_miss_cost > budget_cap:
                raise ValueError(
                    "budget cap exceeded: "
                    f"ledger_total_usd={float(ledger['total_usd']):.8f} "
                    f"estimated_run_cost_usd={estimated_miss_cost:.8f} "
                    f"budget_cap_usd={budget_cap:.8f}"
                )
            curiosities, per_place, total_cost, cache_hits, ledger = asyncio.run(
                _score_live_with_cache_async(
                    cache_dir=cache_dir,
                    cache=cache,
                    ledger=ledger,
                    curiosities=curiosities,
                    output_rows=per_place,
                    misses=misses,
                    model_pricing=model_pricing,
                    api_key=api_key,
                )
            )
        with_signal = bakeoff.with_curiosity(rows, curiosities)
        ranked_on = rescore.rescore(with_signal, config_data, llm_on=True)
        ranked_off = rescore.rescore(rows, config_data, llm_on=False)
        precision_on = eval_metrics.precision_at_k(ranked_on, args.k, positive={"yes"})
        precision_off = eval_metrics.precision_at_k(ranked_off, args.k, positive={"yes"})
    except (
        OSError,
        json.JSONDecodeError,
        ValueError,
        KeyError,
        TypeError,
        RuntimeError,
        llm_cache.LlmCacheCorrupt,
        curiosity.CuriosityParseError,
    ) as exc:
        print(f"llm bakeoff error: {exc}", file=sys.stderr)
        return 1

    print(f"live\ttrue")
    print(f"model\t{model_id}")
    print(f"api_model\t{api_model_id}")
    print(f"provider\tnous")
    print(f"prompt_version\t{curiosity.CURIOSITY_PROMPT_VERSION}")
    print("place_id\tmodel\tcuriosity\tcache_hit\tcost_usd\tcost_source")
    for place_id, value, cache_hit, cost_usd, cost_source in per_place:
        print(f"{place_id}\t{model_id}\t{value:.6f}\t{str(cache_hit).lower()}\t{cost_usd:.8f}\t{cost_source}")
    print(f"cache_hits\t{cache_hits}/{len(per_place)}")
    print(f"total_incremental_cost_usd\t{total_cost:.8f}")
    print(f"estimated_total_cost_usd\t{estimated_cost:.8f}")
    print(f"ledger_total_usd\t{float(ledger['total_usd']):.8f}")
    print(f"ledger_budget_cap_usd\t{budget_cap:.8f}")
    print(f"ledger_measured_usd\t{float(ledger['measured_usd']):.8f}")
    print(f"ledger_derived_usd\t{float(ledger['derived_usd']):.8f}")
    print(f"precision_at_{args.k}_llm_on\t{_format_optional_metric(precision_on)}")
    print(f"precision_at_{args.k}_llm_off\t{_format_optional_metric(precision_off)}")
    return 0


def _safe_filename_token(value: str) -> str:
    if not _SAFE_FILENAME_RE.fullmatch(value):
        raise ValueError(f"{value!r} is not a safe filename token")
    return value


def _load_area_bbox(path: pathlib.Path, area: str) -> list[float]:
    data = _load_mapping_json(path)
    if data.get("version") != "1":
        raise ValueError("golden areas config version must be '1'")
    areas = data.get("areas")
    if not isinstance(areas, dict):
        raise ValueError("golden areas config must contain an areas object")
    bbox = areas.get(area)
    if not isinstance(bbox, list | tuple) or len(bbox) != 4:
        raise ValueError(f"golden area {area!r} must be a four-number bbox")
    out = []
    for value in bbox:
        if not isinstance(value, int | float) or isinstance(value, bool):
            raise ValueError(f"golden area {area!r} bbox values must be numeric")
        number = float(value)
        if not math.isfinite(number):
            raise ValueError(f"golden area {area!r} bbox values must be finite")
        out.append(number)
    minlon, minlat, maxlon, maxlat = out
    if not (-180 <= minlon < maxlon <= 180 and -90 <= minlat < maxlat <= 90):
        raise ValueError(f"golden area {area!r} bbox is out of range")
    return out


def _run_eval(argv) -> int:
    args = _build_eval_parser().parse_args(argv)
    if args.eval_command == "report":
        try:
            labeled_text = _read_text_limited(
                pathlib.Path(args.labeled_tsv), max_bytes=_MAX_TSV_BYTES
            )
            parsed = golden.parse_labeled_tsv(labeled_text)
        except (OSError, ValueError) as exc:
            print(f"eval report error: {exc}", file=sys.stderr)
            return 1
        if parsed.skipped:
            print("label parse skipped rows:", file=sys.stderr)
            for ident, reason in parsed.skipped:
                print(f"- {ident}: {reason}", file=sys.stderr)
            return 1
        try:
            config_data = _load_mapping_json(pathlib.Path(args.config))
            result = eval_report.eval_report(parsed.rows, config_data)
            if args.baseline:
                baseline = _load_metric_baseline(pathlib.Path(args.baseline))
                eval_report.assert_no_regression(parsed.rows, config_data, baseline)
        except (OSError, json.JSONDecodeError) as exc:
            print(f"eval report error: {exc}", file=sys.stderr)
            return 1
        except (AssertionError, RuntimeError, ValueError) as exc:
            print(str(exc), file=sys.stderr)
            return 1
        for key, value in sorted(result.metrics.items()):
            rendered = "undefined" if value is None else f"{value:.3f}"
            print(f"{key}\t{rendered}")
        return 0

    if args.eval_command == "dump":
        try:
            area_token = _safe_filename_token(args.area)
            run_token = _safe_filename_token(args.run_id)
            bbox = _load_area_bbox(pathlib.Path(args.areas_config), args.area)
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            print(f"eval dump config error: {exc}", file=sys.stderr)
            return 1
        try:
            conn = store.connect(args.db)
            rows = golden.dump_area(conn, args.area, bbox, data_version=args.run_id)
        except (sqlite3.Error, RuntimeError, ValueError) as exc:
            print(str(exc), file=sys.stderr)
            return 1
        out_dir = pathlib.Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        stem = f"{run_token}-golden-{area_token}"
        tsv_path = out_dir / f"{stem}.tsv"
        jsonl_path = out_dir / f"{stem}.jsonl"
        tsv_path.write_text(golden.render_tsv(rows))
        jsonl_path.write_text(golden.render_jsonl(rows))
        print(f"wrote {tsv_path}")
        print(f"wrote {jsonl_path}")
        return 0

    raise AssertionError(f"unhandled eval command: {args.eval_command}")


def _run_llm(argv) -> int:
    args = _build_llm_parser().parse_args(argv)
    if args.llm_command == "cost":
        try:
            corpus = _load_llm_corpus_jsonl(pathlib.Path(args.corpus))
            model_data = _load_mapping_json(pathlib.Path(args.models))
            pricing_data = _load_mapping_json(pathlib.Path(args.pricing))
            models = model_data.get("models")
            pricing = pricing_data.get("models")
            if not isinstance(models, list):
                raise ValueError("models JSON must contain a models list")
            if not isinstance(pricing, dict):
                raise ValueError("pricing JSON must contain a models object")
            table = costmodel.build_cost_table(corpus, models, pricing)
        except (OSError, json.JSONDecodeError, ValueError, KeyError, TypeError) as exc:
            print(f"llm cost error: {exc}", file=sys.stderr)
            return 1
        print("model\tprovider\tinput_tokens\toutput_token_cap\ttotal_usd\ttoken_source")
        for row in table.rows:
            print(
                f"{row.model}\t{row.provider}\t{row.input_tokens}\t"
                f"{row.output_token_cap}\t{row.total_usd:.8f}\t{row.token_source}"
            )
        return 0

    if args.llm_command == "bakeoff":
        if args.live and args.max_places is None:
            print("--max-places is required with --live", file=sys.stderr)
            return 2
        if args.live and args.max_places <= 0:
            print("--max-places must be positive with --live", file=sys.stderr)
            return 2
        if args.live:
            try:
                _require_nous_api_key()
            except ValueError as exc:
                print(f"llm bakeoff error: {exc}", file=sys.stderr)
                return 1
        try:
            labeled_text = _read_text_limited(pathlib.Path(args.labeled), max_bytes=_MAX_TSV_BYTES)
            parsed = golden.parse_labeled_tsv(labeled_text)
            if parsed.skipped:
                raise ValueError(f"label parse skipped {len(parsed.skipped)} rows")
            config_data = _load_mapping_json(pathlib.Path(args.config))
            model_data = _load_mapping_json(pathlib.Path(args.models))
            pricing_data = _load_mapping_json(pathlib.Path(args.pricing))
            model_rows = model_data.get("models")
            pricing = pricing_data.get("models")
            if not isinstance(model_rows, list):
                raise ValueError("models JSON must contain a models list")
            if not isinstance(pricing, dict):
                raise ValueError("pricing JSON must contain a models object")
            if args.live:
                return _run_live_bakeoff(
                    args,
                    parsed=parsed,
                    config_data=config_data,
                    model_rows=model_rows,
                    pricing=pricing,
                )
            selected: list[tuple[str, str]] = []
            providers = {}
            for model in model_rows:
                if not isinstance(model, dict):
                    raise ValueError("model roster entries must be objects")
                model_id = str(model["id"])
                provider_id = str(model["provider"])
                if provider_id != "fake":
                    continue
                selected.append((model_id, model_id))
                providers[model_id] = FakeProvider(
                    scorer=lambda req: 0.9 if req.query_id.endswith("0" * 26) else 0.1,
                    price_per_call_usd=0.0,
                )
            if not selected:
                raise ValueError("keyless CLI bakeoff only supports fake providers; live bakeoff is blocked on keys")
            report = bakeoff.run_bakeoff(
                parsed.rows,
                parsed.rows,
                selected,
                providers,
                pricing,
                k=args.k,
                config=config_data,
            )
        except (OSError, json.JSONDecodeError, ValueError, KeyError, TypeError, RuntimeError) as exc:
            print(f"llm bakeoff error: {exc}", file=sys.stderr)
            return 1
        print("model\tprovider\tprecision_at_k_llm_on\tprecision_at_k_llm_off_baseline\tlift\tcost_usd\tlift_per_usd\tinjection_resistance\terror")
        for row in report.rows:
            print(
                f"{row.model}\t{row.provider}\t{row.precision_at_k_llm_on}\t"
                f"{row.precision_at_k_llm_off_baseline}\t{row.lift}\t{row.cost_usd}\t"
                f"{row.lift_per_usd}\t{row.injection_resistance}\t{row.error or ''}"
            )
        return 0

    raise AssertionError(f"unhandled llm command: {args.llm_command}")


def main(argv=None) -> int:
    argv = _normalize_argv(argv)
    if argv and argv[0] == "eval":
        return _run_eval(argv[1:])
    if argv and argv[0] == "llm":
        return _run_llm(argv[1:])

    args = _build_parser().parse_args(argv)
    if args.version is not None and not _VERSION_RE.fullmatch(args.version):
        print("--version must match YYYYMMDDThhmmssZ", file=sys.stderr)
        return 2
    try:
        region = config.load(args.region)
    except config.UnknownRegionError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except config.ConfigError as exc:
        print(f"config error: {exc}", file=sys.stderr)
        return 3

    if args.stage == "acquire":
        try:
            paths = acquire.acquire_all(_snapshot_dir(args), region_config=region)
        except acquire.AcquireError as exc:
            print(f"acquisition error: {exc}", file=sys.stderr)
            return 1
        for source, path in sorted(paths.items()):
            print(f"{source}: {path}")
        return 0

    try:
        conn = store.connect(args.db)
        store.init_schema(conn)
    except sqlite3.Error as exc:
        print(f"database error opening {args.db!r}: {exc}", file=sys.stderr)
        return 3

    if args.stage == "acquire-redirects":
        try:
            snap_dir = _snapshot_dir(args)
            path = acquire.acquire_wikidata_redirect_map(
                snap_dir,
                qids=acquire.qids_from_store(conn, region=region.region_id),
                config=acquire.load_config()["wikidata"],
                wikidata_retrieved_at=acquire.wikidata_snapshot_retrieved_at(
                    acquire.snapshot_paths(snap_dir)["wikidata"]
                ),
            )
        except acquire.AcquireError as exc:
            print(f"acquisition error: {exc}", file=sys.stderr)
            return 1
        except sqlite3.Error as exc:
            print(f"database error running {args.stage!r}: {exc}", file=sys.stderr)
            return 3
        print(f"wikidata_redirects: {path}")
        return 0

    if args.stage == "audit":
        try:
            report = audit.audit_region(conn, region.region_id)
        except sqlite3.Error as exc:
            print(f"database error running {args.stage!r}: {exc}", file=sys.stderr)
            return 3
        rendered = (
            audit.render_json(report)
            if args.audit_format == "json"
            else audit.render_markdown(report)
        )
        print(rendered, end="" if rendered.endswith("\n") else "\n")
        return 0

    try:
        if args.stage == "extract" and args.snapshot_dir:
            snap_dir = pathlib.Path(args.snapshot_dir)
            registry = extract_stage.build_registry(
                acquire.DEFAULT_ALLOWLIST,
                languages=set(region.languages),
            )
            statuses = _initial_extract_statuses(
                region.sources, only_source=args.only_source
            )

            def record_status(source, status):
                statuses[source] = status

            try:
                counts = extract_stage.run_extract(
                    conn,
                    region,
                    acquire.snapshot_paths(snap_dir),
                    run_id=args.run_id,
                    registry=registry,
                    extractor_options={"osm": {"index_type": args.osm_index_type}},
                    status_recorder=record_status,
                    only_source=args.only_source,
                )
            except (
                extract_stage.MissingSnapshotError,
                extract_stage.UnregisteredEnabledSourceError,
                extract_stage.DiskSpaceError,
            ) as exc:
                _record_extract_metadata(conn, region, args.run_id, snap_dir, statuses)
                print(str(exc), file=sys.stderr)
                return 1
            except Exception as exc:
                _record_extract_metadata(conn, region, args.run_id, snap_dir, statuses)
                print(f"extract error: {exc}", file=sys.stderr)
                return 1
            _record_extract_metadata(conn, region, args.run_id, snap_dir, statuses)
            stages.run_stage(conn, region.region_id, args.stage, run_id=args.run_id)
            print(f"{args.stage} complete for {region.region_id}: {counts}")
            return 0
        stages.run_stage(
            conn,
            region.region_id,
            args.stage,
            run_id=args.run_id,
            version=args.version,
        )
    except stages.StageOrderError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except categorize.PlacesTableMissingError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except (
        extract_stage.MissingSnapshotError,
        extract_stage.UnregisteredEnabledSourceError,
        extract_stage.DiskSpaceError,
    ) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except sqlite3.Error as exc:
        print(f"database error running {args.stage!r}: {exc}", file=sys.stderr)
        return 3

    print(f"{args.stage} complete for {region.region_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
