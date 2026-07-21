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

from . import acquire, audit, categorize, config, extract_stage, progress, stages, store
from .eval import golden, metrics as eval_metrics, report as eval_report, rescore
from .llm import bakeoff, cache as llm_cache, costmodel, curiosity
from .llm.providers.fake import FakeProvider

_DEFAULT_RUN_ID = "manual"
_COMMANDS = (
    "acquire",
    "acquire-redirects",
    "acquire-wikipedia-sitelinks",
    "audit",
    *stages.STAGE_ORDER,
)
_PIPELINE_ROOT = pathlib.Path(__file__).resolve().parents[2]
_DEFAULT_GOLDEN_AREAS = _PIPELINE_ROOT / "config" / "golden_areas.json"
_DEFAULT_LLM_MODELS = _PIPELINE_ROOT / "config" / "llm_models.json"
_DEFAULT_LLM_PRICING = _PIPELINE_ROOT / "config" / "llm_pricing.json"
_DEFAULT_EVAL_OUT_DIR = _PIPELINE_ROOT.parent / "docs" / "superpowers" / "eval"
_DEFAULT_PIPELINE_LOG_DIR = pathlib.Path("/data/mt-data/logs")
_PIPELINE_LOG_DIR_ENV = "MT_PIPELINE_LOG_DIR"
_MAX_JSON_BYTES = 1_000_000
_MAX_TSV_BYTES = 10_000_000
_SAFE_FILENAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
_SAFE_LOG_TOKEN_RE = re.compile(r"[^A-Za-z0-9._-]+")
_VERSION_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")


class SnapshotPayloadMissingError(RuntimeError):
    pass


class LiveCandidateError(RuntimeError):
    """A live provider candidate failed after the run-level budget checks passed."""


def _llm_response_excerpt(text: str, *, limit: int = 240) -> str:
    return repr(text[:limit])


def _live_exception_excerpt(exc: Exception, *, limit: int = 240) -> str:
    return repr(str(exc)[:limit])


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mt-pipeline",
        description="Making Tracks data pipeline.",
    )
    parser.add_argument(
        "--region",
        required=True,
        help="region id, e.g. united-kingdom",
    )
    parser.add_argument("stage", choices=_COMMANDS, help="pipeline stage or acquisition step")
    parser.add_argument("--db", default="work.db", help="path to the SQLite store")
    parser.add_argument("--run-id", default=_DEFAULT_RUN_ID, help="run metadata tag")
    parser.add_argument(
        "--log-dir",
        type=pathlib.Path,
        help=(
            "directory for pipeline-owned log files; defaults to MT_PIPELINE_LOG_DIR, "
            "or /data/mt-data/logs when the VPS data root exists"
        ),
    )
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
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--parallel",
        dest="parallel",
        action="store_true",
        default=True,
        help="run extractors in process-isolated parallel workers (default)",
    )
    mode.add_argument(
        "--sequential",
        dest="parallel",
        action="store_false",
        help="run extractors sequentially in the main process",
    )
    parser.add_argument(
        "--continue-on-source-failure",
        action="store_true",
        help="for extract, merge successful sources while recording failed sources",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="ignore matching stage fingerprints and rerun the requested stage",
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
    parser.add_argument(
        "--publish-version",
        help="publish version for publish, formatted YYYYMMDDThhmmssZ",
    )
    parser.add_argument(
        "--generated-at",
        help="manifest generated_at timestamp for publish (must be supplied by the run)",
    )
    parser.add_argument(
        "--scoring-config-version",
        help="A4 scoring config version recorded in manifest score provenance",
    )
    parser.add_argument(
        "--staging-dir",
        help="local staging root for publish artifacts",
    )
    parser.add_argument(
        "--image-candidate-limit",
        type=int,
        help="for local publish staging only, cap image candidates after score-ordered image-candidate selection",
    )
    parser.add_argument(
        "--audited-image-completed-jsonl",
        type=pathlib.Path,
        help="for publish, reuse audited image rows from completed.jsonl instead of fetching image metadata",
    )
    parser.add_argument(
        "--audited-image-cache-dir",
        type=pathlib.Path,
        help="for publish, audited image cache root containing thumbs/<sha-prefix>/<sha>.webp",
    )
    parser.add_argument(
        "--no-image-fetch",
        action="store_true",
        help="for local publish staging only, do not fetch Commons metadata or image bytes",
    )
    parser.add_argument(
        "--no-zone-catalog",
        action="store_true",
        help="for publish, skip zone catalog materialization for this invocation",
    )
    parser.add_argument(
        "--reuse-existing-thumbs",
        "--skip-existing-thumbs",
        dest="reuse_existing_thumbs",
        action="store_true",
        help="for publish upload, skip content-addressed thumbnail objects already present in R2",
    )
    parser.add_argument(
        "--upload",
        action="store_true",
        help="upload staged publish artifacts to R2 after local staging",
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


class _TeeTextIO:
    def __init__(self, primary, secondary) -> None:
        self._primary = primary
        self._secondary = secondary
        self.encoding = getattr(primary, "encoding", "utf-8")

    def write(self, text: str) -> int:
        self._primary.write(text)
        self._secondary.write(text)
        return len(text)

    def flush(self) -> None:
        self._primary.flush()
        self._secondary.flush()

    def isatty(self) -> bool:
        return bool(getattr(self._primary, "isatty", lambda: False)())


def _configured_pipeline_log_dir(args) -> pathlib.Path | None:
    if args.log_dir is not None:
        return pathlib.Path(args.log_dir)
    env_path = os.environ.get(_PIPELINE_LOG_DIR_ENV)
    if env_path:
        return pathlib.Path(env_path)
    if _DEFAULT_PIPELINE_LOG_DIR.parent.exists():
        return _DEFAULT_PIPELINE_LOG_DIR
    return None


def _safe_log_token(value: object) -> str:
    token = _SAFE_LOG_TOKEN_RE.sub("_", str(value)).strip("._-")
    return token or "unknown"


def _pipeline_log_path(log_dir: pathlib.Path, args) -> pathlib.Path:
    timestamp = _safe_log_token(stages._completed_at())
    region = _safe_log_token(args.region)
    stage = _safe_log_token(args.stage)
    stem = f"{timestamp}-{region}-{stage}-pid{os.getpid()}"
    first = log_dir / f"{stem}.log"
    if not first.exists():
        return first
    for counter in range(1, 1000):
        candidate = log_dir / f"{stem}-{counter}.log"
        if not candidate.exists():
            return candidate
    raise RuntimeError(f"could not allocate pipeline log path under {log_dir}")


@contextmanager
def _pipeline_file_log(args):
    log_dir = _configured_pipeline_log_dir(args)
    if log_dir is None:
        yield None
        return
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = _pipeline_log_path(log_dir, args)
    with log_path.open("x", encoding="utf-8") as log_file:
        old_stdout = sys.stdout
        old_stderr = sys.stderr
        sys.stdout = _TeeTextIO(old_stdout, log_file)
        sys.stderr = _TeeTextIO(old_stderr, log_file)
        try:
            from .ergonomics import telemetry

            telemetry.emit(telemetry.report_log_path(log_path))
            yield log_path
        finally:
            sys.stdout.flush()
            sys.stderr.flush()
            sys.stdout = old_stdout
            sys.stderr = old_stderr


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
    bakeoff_cmd.add_argument(
        "--concurrency",
        type=int,
        default=8,
        help="maximum concurrent live provider requests",
    )
    bakeoff_cmd.add_argument("--model", help="specific live model id; defaults to all NOUS rows sorted by estimated cost")
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
    bakeoff_cmd.add_argument(
        "--promotion-injection",
        action="store_true",
        help="run the full two-sided injection promotion gate instead of the round-1 partial screen",
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


def _record_extract_metadata(
    conn,
    region,
    run_id: str,
    snap_dir,
    statuses: dict,
    *,
    only_source: str | None = None,
) -> None:
    _record_extract_metadata_no_commit(
        conn,
        region,
        run_id,
        snap_dir,
        statuses,
        only_source=only_source,
    )
    conn.commit()


def _previous_extract_metadata(conn, region):
    row = conn.execute(
        """
        SELECT run_id
        FROM stage_runs
        WHERE region = ? AND stage = 'extract'
        """,
        (region.region_id,),
    ).fetchone()
    if row is None:
        return None
    return store.load_extract_run_metadata(
        conn,
        region=region.region_id,
        run_id=row[0],
    )


def _record_extract_metadata_no_commit(
    conn,
    region,
    run_id: str,
    snap_dir,
    statuses: dict,
    *,
    only_source: str | None = None,
) -> None:
    wikidata_date = ""
    if region.sources.get("wikidata") is True:
        wikidata_path = acquire.snapshot_paths(snap_dir)["wikidata"]
        if (only_source is None or only_source == "wikidata") and wikidata_path.exists():
            wikidata_date = acquire.wikidata_snapshot_retrieved_at(wikidata_path)
        else:
            previous = _previous_extract_metadata(conn, region)
            if previous is not None:
                wikidata_date = previous["wikidata_snapshot_date"]
    store.record_extract_run_metadata_no_commit(
        conn,
        region=region.region_id,
        run_id=run_id,
        wikidata_snapshot_date=wikidata_date,
        source_statuses=statuses,
    )


def _pageview_extract_options(
    region,
    snap_dir: pathlib.Path,
    *,
    only_source: str | None,
) -> dict | None:
    pageview_options = acquire.pageview_region_options(region)
    if (
        pageview_options is None
        or region.sources.get("wikipedia") is not True
        or only_source not in {None, "wikipedia"}
    ):
        return None
    pageview_cache = snap_dir / "pageviews"
    window = acquire.pageview_window_for_wikipedia_snapshot(
        acquire.snapshot_paths(snap_dir)["wikipedia"],
        region,
    )
    if window is None:
        return None
    cached_window = acquire.pageviews.manifest_window(pageview_cache)
    if cached_window is not None and cached_window != window:
        raise acquire.AcquireError(
            "pageview cache window "
            f"{cached_window[0]}..{cached_window[1]} does not match "
            f"wikipedia snapshot window {window[0]}..{window[1]}"
        )
    return {
        "pageview_cache_dir": pageview_cache,
        "pageview_window": window,
    }


def _pageview_max_titles(region) -> int:
    pageview_options = acquire.pageview_region_options(region) or {}
    pageview_config = acquire.load_config().get("pageviews", {})
    if not isinstance(pageview_config, dict):
        pageview_config = {}
    return int(
        pageview_options.get(
            "max_titles",
            pageview_config.get("max_titles", acquire.MAX_PAGEVIEW_TITLES),
        )
    )


def _pageview_cache_files(
    wikipedia_snapshot: pathlib.Path,
    pageview_cache: pathlib.Path,
    window: tuple[str, str],
    *,
    max_titles: int,
) -> tuple[pathlib.Path, ...]:
    return tuple(
        acquire.pageviews._cache_path(pageview_cache, title, window)
        for title in acquire._wikipedia_titles(wikipedia_snapshot, max_titles=max_titles)
    )


def _extractor_options(
    region,
    snap_dir: pathlib.Path,
    *,
    osm_index_type: str,
    only_source: str | None,
) -> dict:
    options = {"osm": {"index_type": osm_index_type}}
    if getattr(region, "zone_levels", None):
        options["osm"]["zone_levels"] = dict(region.zone_levels)
    pageview_options = _pageview_extract_options(
        region,
        snap_dir,
        only_source=only_source,
    )
    if pageview_options is not None:
        options["wikipedia"] = pageview_options
    return options


def _record_skipped_extract_metadata(conn, region, run_id: str, snap_dir) -> None:
    previous = _previous_extract_metadata(conn, region)
    if previous is not None:
        store.record_extract_run_metadata(
            conn,
            region=region.region_id,
            run_id=run_id,
            wikidata_snapshot_date=previous["wikidata_snapshot_date"],
            source_statuses=previous["source_statuses"],
        )
        return
    _record_extract_metadata(
        conn,
        region,
        run_id,
        snap_dir,
        _initial_extract_statuses(region.sources),
    )


def _extract_fingerprint_inputs(
    region,
    snapshots: dict,
    *,
    snap_dir: pathlib.Path | None = None,
    only_source: str | None = None,
) -> object:
    from .ergonomics import fingerprint

    pageview_options = (
        _pageview_extract_options(region, snap_dir, only_source=only_source)
        if snap_dir is not None
        else None
    )
    pageview_window = None
    pageview_cache_files = ()
    if pageview_options is not None and snap_dir is not None:
        pageview_window = pageview_options["pageview_window"]
        pageview_cache_files = _pageview_cache_files(
            acquire.snapshot_paths(snap_dir)["wikipedia"],
            pageview_options["pageview_cache_dir"],
            pageview_window,
            max_titles=_pageview_max_titles(region),
        )
    return fingerprint.FingerprintInputs(
        region_config=region,
        snapshots=snapshots,
        config_paths={
            "wikidata_class_allowlist": acquire.DEFAULT_ALLOWLIST,
            "osm_candidate_tags": extract_stage.DEFAULT_OSM_TAG_CONFIG,
        },
        only_source=only_source,
        pageview_cache_dir=(
            pageview_options["pageview_cache_dir"]
            if pageview_options is not None
            else None
        ),
        pageview_cache_files=pageview_cache_files,
        pageview_window=pageview_window,
    )


def _raise_on_snapshot_sidecar_without_payload(
    region,
    snapshots: dict[str, pathlib.Path],
    *,
    only_source: str | None = None,
) -> None:
    selected_sources = {
        source
        for source, enabled in region.sources.items()
        if enabled is True and (only_source is None or source == only_source)
    }
    for source in sorted(selected_sources):
        payload = snapshots.get(source)
        if payload is None:
            continue
        payload = pathlib.Path(payload)
        sidecar = pathlib.Path(str(payload) + ".meta.json")
        if not payload.exists() and sidecar.exists():
            raise SnapshotPayloadMissingError(
                f"snapshot payload missing for {source}: {payload} "
                f"(found {sidecar}; re-run acquire)"
            )


def _stage_fingerprint_inputs(conn, region, stage: str, *, run_id: str, version: str | None):
    from .ergonomics import fingerprint
    from .score import score_stage

    if stage == "reconcile":
        metadata = store.load_extract_run_metadata(conn, region=region.region_id, run_id=run_id)
        succeeded = (
            stages._succeeded_source_prefixes(region, metadata)
            if metadata is not None
            else set()
        )
        return fingerprint.FingerprintInputs(
            region_config=region,
            succeeded_sources=succeeded,
            version=version,
            config_paths={
                "reconcile_config": stages.RECONCILE_CONFIG,
                "redirect_map": pathlib.Path(".mt-data")
                / region.region_id
                / "wikidata_redirects.snapshot.json",
                "registry": pathlib.Path("registry") / f"{region.region_id}.jsonl",
            },
        )
    if stage == "score":
        return fingerprint.FingerprintInputs(
            region_config=region,
            config_paths={"scoring_config": score_stage._CONFIG_PATH},
        )
    if stage == "categorize":
        return fingerprint.FingerprintInputs(
            region_config=region,
            config_paths={
                "taxonomy_config": categorize._TAXONOMY_PATH,
                "osm_candidate_tags": categorize._OSM_CANDIDATE_TAGS,
            },
        )
    return None


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


def _format_optional_bool(value: bool | None) -> str:
    return "undefined" if value is None else str(value).lower()


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


def _live_nous_candidates(
    model_rows: list[object],
    pricing: dict,
    rows: list[golden.GoldenRow],
    *,
    requested_model: str | None,
    injection_fixture: tuple[bakeoff.InjectionProbe, ...] = (),
) -> list[tuple[float, str, str, dict, bakeoff.ModelOptions]]:
    candidates: list[tuple[float, str, str, dict, bakeoff.ModelOptions]] = []
    for model in model_rows:
        if not isinstance(model, dict):
            raise ValueError("model roster entries must be objects")
        model_id = str(model["id"])
        provider_id = str(model["provider"])
        if requested_model is not None and model_id != requested_model:
            continue
        if provider_id != "nous":
            continue
        skip_reason = _live_skip_reason(model)
        if skip_reason is not None:
            if requested_model == model_id:
                raise ValueError(f"requested live model {model_id!r} is skipped: {skip_reason}")
            continue
        api_model_id = str(model.get("api_model_id", model_id))
        model_options = _model_request_options(model)
        model_pricing = pricing.get(model_id)
        if not isinstance(model_pricing, dict):
            raise ValueError(f"pricing missing for model {model_id!r}")
        requests = _live_candidate_requests(
            rows,
            injection_fixture,
            cache_model_id=model_id,
            api_model_id=api_model_id,
            model_options=model_options,
        )
        estimate = _estimate_request_cost(
            requests,
            model_pricing,
            model=model_id,
        )
        candidates.append((estimate, model_id, api_model_id, model_pricing, model_options))
    if not candidates:
        if requested_model is not None:
            raise ValueError(f"requested live model {requested_model!r} is not a NOUS model in the roster")
        raise ValueError("live bakeoff requires at least one NOUS model in the roster")
    return sorted(candidates, key=lambda item: (item[0], item[1]))


def _live_skip_reason(model: dict) -> str | None:
    value = model.get("live_skip_reason")
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError("model live_skip_reason must be a string")
    reason = value.strip()
    if not reason:
        raise ValueError("model live_skip_reason must be non-empty")
    if len(reason) > 512 or any(ord(ch) < 32 for ch in reason):
        raise ValueError("model live_skip_reason must be printable text up to 512 chars")
    return reason


def _select_live_nous_model(
    model_rows: list[object],
    pricing: dict,
    rows: list[golden.GoldenRow],
    *,
    requested_model: str | None,
) -> tuple[str, str, dict, float, bakeoff.ModelOptions]:
    estimated_cost, model_id, api_model_id, model_pricing, model_options = _live_nous_candidates(
        model_rows,
        pricing,
        rows,
        requested_model=requested_model,
    )[0]
    return model_id, api_model_id, model_pricing, estimated_cost, model_options


def _curiosity_cache(cache_dir: pathlib.Path) -> llm_cache.LlmCache:
    validators = {
        curiosity.CURIOSITY_TASK_ID: lambda blob: curiosity.parse_curiosity(json.dumps(blob))
    }
    return llm_cache.LlmCache(cache_dir, validators=validators)


def _model_request_options(model: dict) -> bakeoff.ModelOptions:
    options: dict[str, object] = {}
    for key in ("max_tokens", "reasoning", "provider_tags", "seed"):
        if key in model:
            options[key] = model[key]
    return options


def _model_output_token_cap(model_options: bakeoff.ModelOptions) -> int:
    max_tokens = model_options.get("max_tokens", curiosity.CURIOSITY_MAX_TOKENS)
    if not isinstance(max_tokens, int) or isinstance(max_tokens, bool):
        raise ValueError("model max_tokens must be an integer")
    if max_tokens <= 0:
        raise ValueError("model max_tokens must be positive")
    if max_tokens > 4096:
        raise ValueError("model max_tokens must be at most 4096")
    return max_tokens


def _live_request(
    row: golden.GoldenRow,
    *,
    cache_model_id: str,
    api_model_id: str,
    model_options: bakeoff.ModelOptions,
) -> curiosity.LlmRequest:
    return curiosity.curiosity_request(
        query_id=row.place_id,
        model_id=cache_model_id,
        provider_model_id=api_model_id,
        place={"name": row.name, "summary": row.evidence, "tags": [row.category]},
        max_tokens=_model_output_token_cap(model_options),
        provider_tags=model_options.get("provider_tags"),  # type: ignore[arg-type]
        reasoning=model_options.get("reasoning"),  # type: ignore[arg-type]
        seed=model_options.get("seed", 0),  # type: ignore[arg-type]
    )


def _live_injection_request(
    probe: bakeoff.InjectionProbe,
    *,
    cache_model_id: str,
    api_model_id: str,
    model_options: bakeoff.ModelOptions,
) -> curiosity.LlmRequest:
    return curiosity.curiosity_request(
        query_id=probe.place_id,
        model_id=cache_model_id,
        provider_model_id=api_model_id,
        place=probe.place,
        max_tokens=_model_output_token_cap(model_options),
        provider_tags=model_options.get("provider_tags"),  # type: ignore[arg-type]
        reasoning=model_options.get("reasoning"),  # type: ignore[arg-type]
        seed=model_options.get("seed", 0),  # type: ignore[arg-type]
    )


def _collect_live_cache_state(
    rows: list[golden.GoldenRow],
    *,
    cache_model_id: str,
    api_model_id: str,
    model_options: bakeoff.ModelOptions,
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
        req = _live_request(row, cache_model_id=cache_model_id, api_model_id=api_model_id, model_options=model_options)
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


def _collect_live_injection_cache_state(
    cache: llm_cache.LlmCache,
    fixture: tuple[bakeoff.InjectionProbe, ...],
    *,
    cache_model_id: str,
    api_model_id: str,
    model_options: bakeoff.ModelOptions,
) -> tuple[
    dict[str, float],
    list[tuple[str, float, bool, float, str]],
    list[tuple[bakeoff.InjectionProbe, str, curiosity.LlmRequest]],
]:
    scores: dict[str, float] = {}
    output_rows: list[tuple[str, float, bool, float, str]] = []
    misses: list[tuple[bakeoff.InjectionProbe, str, curiosity.LlmRequest]] = []
    for probe in fixture:
        req = _live_injection_request(probe, cache_model_id=cache_model_id, api_model_id=api_model_id, model_options=model_options)
        rendered_prompt = req.messages[0].content
        input_hash = llm_cache.input_hash(
            task_id=req.task_id,
            prompt_version=req.prompt_version,
            rendered_prompt=rendered_prompt,
        )
        cached = cache.get(req.task_id, req.model_id, req.prompt_version, input_hash)
        if cached is not None:
            value = cached.curiosity
            scores[probe.place_id] = value
            output_rows.append((probe.place_id, value, True, 0.0, "cache"))
        else:
            misses.append((probe, input_hash, req))
    return scores, output_rows, misses


def _live_candidate_requests(
    rows: list[golden.GoldenRow],
    injection_fixture: tuple[bakeoff.InjectionProbe, ...],
    *,
    cache_model_id: str,
    api_model_id: str,
    model_options: bakeoff.ModelOptions,
) -> list[curiosity.LlmRequest]:
    return [
        *[
            _live_request(
                row,
                cache_model_id=cache_model_id,
                api_model_id=api_model_id,
                model_options=model_options,
            )
            for row in rows
        ],
        *[
            _live_injection_request(
                probe,
                cache_model_id=cache_model_id,
                api_model_id=api_model_id,
                model_options=model_options,
            )
            for probe in injection_fixture
        ],
    ]


def _estimate_request_cost(
    requests: Sequence[curiosity.LlmRequest],
    model_pricing: dict,
    *,
    model: str,
) -> float:
    input_per_m = _non_negative_price(model_pricing, "input_per_m", model=model)
    output_per_m = _non_negative_price(model_pricing, "output_per_m", model=model)
    input_tokens = sum(costmodel.count_request_tokens(req) for req in requests)
    output_tokens = sum(req.max_tokens for req in requests)
    return input_tokens * input_per_m / 1_000_000 + output_tokens * output_per_m / 1_000_000


def _non_negative_price(model_pricing: dict, key: str, *, model: str) -> float:
    value = model_pricing[key]
    if isinstance(value, bool):
        raise ValueError(f"pricing for {model!r} field {key!r} must be numeric")
    number = float(value)
    if not math.isfinite(number) or number < 0.0:
        raise ValueError(f"pricing for {model!r} field {key!r} must be finite and non-negative")
    return number


async def _complete_live_batch_with_telemetry(
    provider: object,
    requests: Sequence[curiosity.LlmRequest],
    *,
    telemetry: progress.LivePhaseProgress | None,
) -> list:
    heartbeat_task: asyncio.Task | None = None
    if telemetry is not None and requests:
        interval = max(float(telemetry.heartbeat_every_seconds), 0.001)

        async def heartbeat_until_done() -> None:
            while True:
                await asyncio.sleep(interval)
                telemetry.tick(0.0, completed_delta=0)

        heartbeat_task = asyncio.create_task(heartbeat_until_done())
    try:
        return await _complete_live_batch(provider, requests, telemetry=telemetry)
    finally:
        if heartbeat_task is not None:
            heartbeat_task.cancel()
            try:
                await heartbeat_task
            except asyncio.CancelledError:
                pass


async def _complete_live_batch(
    provider: object,
    requests: Sequence[curiosity.LlmRequest],
    *,
    telemetry: progress.LivePhaseProgress | None,
) -> list:
    acomplete = getattr(provider, "acomplete", None)
    if callable(acomplete):
        concurrency = getattr(provider, "concurrency", 1)
        if not isinstance(concurrency, int) or isinstance(concurrency, bool) or concurrency <= 0:
            concurrency = 1
        semaphore = asyncio.Semaphore(concurrency)

        async def one(index: int, req: curiosity.LlmRequest):
            async with semaphore:
                response = await acomplete(req)
            if telemetry is not None:
                telemetry.tick(float(response.cost_usd))
            return index, response

        pairs = await asyncio.gather(*(one(index, req) for index, req in enumerate(requests)))
        ordered = [response for _, response in sorted(pairs, key=lambda item: item[0])]
        return ordered

    responses = await provider.acomplete_batch(requests)  # type: ignore[attr-defined]
    if telemetry is not None:
        for response in responses:
            telemetry.tick(float(response.cost_usd))
    return list(responses)


async def _score_live_with_cache_async(
    *,
    cache_dir: pathlib.Path,
    cache: llm_cache.LlmCache,
    ledger: dict[str, float | int],
    curiosities: dict[str, float],
    output_rows: list[tuple[str, float, bool, float, str]],
    misses: list[tuple[golden.GoldenRow, str, curiosity.LlmRequest]],
    injection_scores: dict[str, float],
    injection_output_rows: list[tuple[str, float, bool, float, str]],
    injection_misses: list[tuple[bakeoff.InjectionProbe, str, curiosity.LlmRequest]],
    model_pricing: dict,
    model_options: bakeoff.ModelOptions,
    api_key: str,
    concurrency: int,
    telemetry: progress.LivePhaseProgress | None = None,
) -> tuple[
    dict[str, float],
    list[tuple[str, float, bool, float, str]],
    dict[str, float],
    list[tuple[str, float, bool, float, str]],
    float,
    int,
    int,
    dict[str, float | int],
]:
    from .llm.providers import nous as nous_provider

    total_response_cost = 0.0
    charged_rows: list[tuple[str, float, bool, float, str]] = []
    provider = None
    session_cost: float | None = None
    try:
        if misses or injection_misses:
            batch: list[
                tuple[
                    str,
                    golden.GoldenRow | bakeoff.InjectionProbe,
                    str,
                    curiosity.LlmRequest,
                ]
            ] = [
                ("place", row, input_hash, req)
                for row, input_hash, req in misses
            ] + [
                ("injection", probe, input_hash, req)
                for probe, input_hash, req in injection_misses
            ]
            provider = nous_provider.NousProvider(
                api_key=api_key,
                concurrency=concurrency,
                input_per_m=float(model_pricing.get("input_per_m", 0.0)),
                output_per_m=float(model_pricing.get("output_per_m", 0.0)),
            )
            try:
                responses = await _complete_live_batch_with_telemetry(
                    provider,
                    [req for _, _, _, req in batch],
                    telemetry=telemetry,
                )
            except Exception as exc:
                estimated_failure_cost = _estimate_request_cost(
                    [req for _, _, _, req in batch],
                    model_pricing,
                    model=batch[0][3].model_id,
                )
                if estimated_failure_cost > 0.0:
                    charged_rows.append(("unknown", 0.0, False, estimated_failure_cost, "derived"))
                    total_response_cost += estimated_failure_cost
                raise LiveCandidateError(f"provider request failed: {_live_exception_excerpt(exc)}") from exc
            if len(responses) != len(batch):
                estimated_failure_cost = _estimate_request_cost(
                    [req for _, _, _, req in batch],
                    model_pricing,
                    model=batch[0][3].model_id,
                )
                returned_cost = sum(response.cost_usd for response in responses)
                charged_rows.extend(
                    ("unknown", 0.0, False, response.cost_usd, response.cost_source)
                    for response in responses
                )
                total_response_cost += returned_cost
                if returned_cost < estimated_failure_cost:
                    charged_rows.append(
                        ("unknown", 0.0, False, estimated_failure_cost - returned_cost, "derived")
                    )
                    total_response_cost += estimated_failure_cost - returned_cost
                raise LiveCandidateError("provider returned a different number of responses")
            for (kind, item, input_hash, req), response in zip(batch, responses, strict=True):
                place_id = item.place_id
                charged_rows.append((place_id, 0.0, False, response.cost_usd, response.cost_source))
                total_response_cost += response.cost_usd
            for (kind, item, input_hash, req), response in zip(batch, responses, strict=True):
                place_id = item.place_id
                try:
                    parsed = curiosity.parse_curiosity(response.text)
                except curiosity.CuriosityParseError as exc:
                    raise LiveCandidateError(
                        f"{exc}: kind={kind} place_id={place_id} response={_llm_response_excerpt(response.text)}"
                    ) from exc
                cache.put(
                    llm_cache.cache_key(req.task_id, req.model_id, req.prompt_version, input_hash),
                    parsed.model_dump(),
                )
                value = parsed.curiosity
                if kind == "place":
                    curiosities[place_id] = value
                    output_rows.append((place_id, value, False, response.cost_usd, response.cost_source))
                else:
                    injection_scores[place_id] = value
                    injection_output_rows.append((place_id, value, False, response.cost_usd, response.cost_source))
    finally:
        if provider is not None:
            try:
                session_cost = await provider.shutdown()
            except Exception as exc:
                shutdown_error = exc
            else:
                shutdown_error = None
        else:
            shutdown_error = None
        if charged_rows:
            ledger = _update_cost_ledger(cache_dir, ledger, charged_rows)
        if shutdown_error is not None:
            raise LiveCandidateError(f"provider shutdown failed: {_live_exception_excerpt(shutdown_error)}") from shutdown_error

    output_rows.sort(key=lambda item: item[0])
    injection_output_rows.sort(key=lambda item: item[0])
    total_cost = session_cost if session_cost is not None else total_response_cost
    cache_hits = sum(1 for _, _, hit, _, _ in output_rows if hit)
    injection_cache_hits = sum(1 for _, _, hit, _, _ in injection_output_rows if hit)
    if not charged_rows:
        ledger = _update_cost_ledger(cache_dir, ledger, [*output_rows, *injection_output_rows])
    return (
        curiosities,
        output_rows,
        injection_scores,
        injection_output_rows,
        total_cost,
        cache_hits,
        injection_cache_hits,
        ledger,
    )


def _print_live_candidate_error(
    *,
    model_id: str,
    api_model_id: str,
    exc: Exception,
    estimated_miss_cost: float,
    ledger: dict[str, float | int],
    budget_cap: float,
) -> None:
    print(f"live\ttrue")
    print(f"model\t{model_id}")
    print(f"api_model\t{api_model_id}")
    print(f"provider\tnous")
    print(f"prompt_version\t{curiosity.CURIOSITY_PROMPT_VERSION}")
    print(f"error\t{exc}")
    print(f"estimated_run_cost_usd\t{estimated_miss_cost:.8f}")
    print(f"ledger_total_usd\t{float(ledger['total_usd']):.8f}")
    print(f"ledger_budget_cap_usd\t{budget_cap:.8f}")
    print(f"ledger_measured_usd\t{float(ledger['measured_usd']):.8f}")
    print(f"ledger_derived_usd\t{float(ledger['derived_usd']):.8f}")


def _print_live_candidate_report(
    *,
    args,
    model_id: str,
    api_model_id: str,
    per_place: list[tuple[str, float, bool, float, str]],
    cache_hits: int,
    injection_scope: str | None,
    injection_per_place: list[tuple[str, float, bool, float, str]],
    injection_fixture: tuple[bakeoff.InjectionProbe, ...],
    injection_cache_hits: int,
    injection_cost: float,
    inflation_resistance: float | None,
    deflation_resistance: float | None,
    honest_suppression_rate: float | None,
    two_sided_resistance: float | None,
    injection_floor_passed: bool | None,
    injection_error: str | None,
    total_cost: float,
    estimated_cost: float,
    estimated_miss_cost: float,
    ledger: dict[str, float | int],
    budget_cap: float,
    precision_on: float | None,
    precision_off: float | None,
) -> None:
    print(f"live\ttrue")
    print(f"model\t{model_id}")
    print(f"api_model\t{api_model_id}")
    print(f"provider\tnous")
    print(f"prompt_version\t{curiosity.CURIOSITY_PROMPT_VERSION}")
    print("place_id\tmodel\tcuriosity\tcache_hit\tcost_usd\tcost_source")
    for place_id, value, cache_hit, cost_usd, cost_source in per_place:
        print(f"{place_id}\t{model_id}\t{value:.6f}\t{str(cache_hit).lower()}\t{cost_usd:.8f}\t{cost_source}")
    print(f"cache_hits\t{cache_hits}/{len(per_place)}")
    print(f"injection_scope\t{injection_scope or 'none'}")
    print(f"injection_probes\t{len(injection_per_place)}/{len(injection_fixture)}")
    print(f"injection_cache_hits\t{injection_cache_hits}/{len(injection_per_place)}")
    print(f"injection_cost_usd\t{injection_cost:.8f}")
    print(f"inflation_resistance\t{_format_optional_metric(inflation_resistance)}")
    print(f"deflation_resistance\t{_format_optional_metric(deflation_resistance)}")
    print(f"honest_suppression_rate\t{_format_optional_metric(honest_suppression_rate)}")
    print(f"two_sided_injection_resistance\t{_format_optional_metric(two_sided_resistance)}")
    print(f"injection_floor_passed\t{_format_optional_bool(injection_floor_passed)}")
    print(f"injection_error\t{injection_error or ''}")
    print(f"total_incremental_cost_usd\t{total_cost:.8f}")
    print(f"estimated_golden_cost_usd\t{estimated_cost:.8f}")
    print(f"estimated_run_cost_usd\t{estimated_miss_cost:.8f}")
    print(f"ledger_total_usd\t{float(ledger['total_usd']):.8f}")
    print(f"ledger_budget_cap_usd\t{budget_cap:.8f}")
    print(f"ledger_measured_usd\t{float(ledger['measured_usd']):.8f}")
    print(f"ledger_derived_usd\t{float(ledger['derived_usd']):.8f}")
    print(f"precision_at_{args.k}_llm_on\t{_format_optional_metric(precision_on)}")
    print(f"precision_at_{args.k}_llm_off\t{_format_optional_metric(precision_off)}")


def _run_live_bakeoff(args, *, parsed: golden.ParseResult, config_data: dict, model_rows: list, pricing: dict) -> int:
    if args.max_places is None:
        print("--max-places is required with --live", file=sys.stderr)
        return 2
    if args.max_places <= 0:
        print("--max-places must be positive with --live", file=sys.stderr)
        return 2
    if args.concurrency <= 0:
        print("--concurrency must be positive with --live", file=sys.stderr)
        return 2
    try:
        budget_cap = _validate_budget_cap(args.budget_cap)
        api_key = _require_nous_api_key()
        rows = parsed.rows[: args.max_places]
        if not rows:
            raise ValueError("live bakeoff has no parsed rows to score")
        injection_fixture = (
            tuple(bakeoff.TWO_SIDED_INJECTION_PROBES)
            if args.promotion_injection
            else tuple(bakeoff.INJECTION_PROBES)
        )
        if args.promotion_injection and not injection_fixture:
            raise ValueError("empty injection fixture cannot pass promotion gate")
        clean_reference_rows = bakeoff._rows_with_injection_origins(
            parsed.rows,
            injection_fixture,
        )
        candidates = _live_nous_candidates(
            model_rows,
            pricing,
            clean_reference_rows,
            requested_model=args.model,
            injection_fixture=injection_fixture,
        )
        cache_dir = pathlib.Path(args.cache_dir)
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

    any_success = False
    for estimated_cost, model_id, api_model_id, model_pricing, model_options in candidates:
        candidate_error: Exception | None = None
        try:
            with _locked_cost_ledger(cache_dir):
                cache, curiosities, per_place, misses = _collect_live_cache_state(
                    clean_reference_rows,
                    cache_model_id=model_id,
                    api_model_id=api_model_id,
                    model_options=model_options,
                    cache_dir=cache_dir,
                )
                injection_scores, injection_per_place, injection_misses = _collect_live_injection_cache_state(
                    cache,
                    injection_fixture,
                    cache_model_id=model_id,
                    api_model_id=api_model_id,
                    model_options=model_options,
                )
                ledger = _load_cost_ledger(cache_dir)
                estimated_miss_cost = _estimate_request_cost(
                    [req for _, _, req in misses] + [req for _, _, req in injection_misses],
                    model_pricing,
                    model=model_id,
                )
                if float(ledger["total_usd"]) + estimated_miss_cost > budget_cap:
                    print(
                        "budget cap exceeded: "
                        f"ledger_total_usd={float(ledger['total_usd']):.8f} "
                        f"estimated_run_cost_usd={estimated_miss_cost:.8f} "
                        f"budget_cap_usd={budget_cap:.8f}",
                        file=sys.stderr,
                    )
                    return 1
                telemetry = progress.LivePhaseProgress(
                    model_id=model_id,
                    total=len(per_place) + len(misses) + len(injection_per_place) + len(injection_misses),
                    cache_hits=len(per_place) + len(injection_per_place),
                    initial_cost=sum(cost for _, _, _, cost, _ in [*per_place, *injection_per_place]),
                )
                telemetry.start()
                try:
                    (
                        curiosities,
                        per_place,
                        injection_scores,
                        injection_per_place,
                        total_cost,
                        cache_hits,
                        injection_cache_hits,
                        ledger,
                    ) = asyncio.run(
                        _score_live_with_cache_async(
                            cache_dir=cache_dir,
                            cache=cache,
                            ledger=ledger,
                            curiosities=curiosities,
                            output_rows=per_place,
                            misses=misses,
                            injection_scores=injection_scores,
                            injection_output_rows=injection_per_place,
                            injection_misses=injection_misses,
                            model_pricing=model_pricing,
                            model_options=model_options,
                            api_key=api_key,
                            concurrency=args.concurrency,
                            telemetry=telemetry,
                        )
                    )
                except LiveCandidateError as exc:
                    candidate_error = exc
                    ledger = _load_cost_ledger(cache_dir)
                finally:
                    telemetry.done()
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
        if candidate_error is not None:
            _print_live_candidate_error(
                model_id=model_id,
                api_model_id=api_model_id,
                exc=candidate_error,
                estimated_miss_cost=estimated_miss_cost,
                ledger=ledger,
                budget_cap=budget_cap,
            )
            continue

        try:
            with_signal = bakeoff.with_curiosity(rows, curiosities)
            ranked_on = rescore.rescore(with_signal, config_data, llm_on=True)
            ranked_off = rescore.rescore(rows, config_data, llm_on=False)
            precision_on = eval_metrics.precision_at_k(ranked_on, args.k, positive={"yes"})
            precision_off = eval_metrics.precision_at_k(ranked_off, args.k, positive={"yes"})
            injection_scope = (
                bakeoff.PROMOTION_INJECTION_SCOPE
                if args.promotion_injection
                else bakeoff.ROUND1_INJECTION_SCOPE
            )
            inflation_resistance = None
            deflation_resistance = None
            honest_suppression_rate = None
            two_sided_resistance = None
            injection_floor_passed = None
            injection_error = None
            injection_reference_scores = tuple(curiosities.values())
            if args.promotion_injection:
                resistance = bakeoff.two_sided_injection_metrics(
                    injection_scores,
                    injection_fixture,
                    clean_scores=curiosities,
                    reference_scores=injection_reference_scores,
                )
                inflation_resistance = resistance.inflation_resistance
                deflation_resistance = resistance.deflation_resistance
                honest_suppression_rate = resistance.honest_suppression_rate
                two_sided_resistance = resistance.two_sided_injection_resistance
                injection_floor_passed = resistance.floor_passed
                if not injection_floor_passed:
                    injection_error = "promotion injection floor failed"
            else:
                inflation_resistance = bakeoff.injection_resistance(
                    injection_scores,
                    injection_fixture,
                    clean_scores=curiosities,
                    reference_scores=injection_reference_scores,
                )
            injection_cost = sum(cost for _, _, _, cost, _ in injection_per_place)
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

        _print_live_candidate_report(
            args=args,
            model_id=model_id,
            api_model_id=api_model_id,
            per_place=per_place,
            cache_hits=cache_hits,
            injection_scope=injection_scope,
            injection_per_place=injection_per_place,
            injection_fixture=injection_fixture,
            injection_cache_hits=injection_cache_hits,
            injection_cost=injection_cost,
            inflation_resistance=inflation_resistance,
            deflation_resistance=deflation_resistance,
            honest_suppression_rate=honest_suppression_rate,
            two_sided_resistance=two_sided_resistance,
            injection_floor_passed=injection_floor_passed,
            injection_error=injection_error,
            total_cost=total_cost,
            estimated_cost=estimated_cost,
            estimated_miss_cost=estimated_miss_cost,
            ledger=ledger,
            budget_cap=budget_cap,
            precision_on=precision_on,
            precision_off=precision_off,
        )
        if injection_error is not None:
            print(injection_error, file=sys.stderr)
        else:
            any_success = True

    return 0 if any_success else 1


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
        if args.live and args.concurrency <= 0:
            print("--concurrency must be positive with --live", file=sys.stderr)
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
            selected: list[bakeoff.ModelCandidate] = []
            providers = {}
            for model in model_rows:
                if not isinstance(model, dict):
                    raise ValueError("model roster entries must be objects")
                model_id = str(model["id"])
                provider_id = str(model["provider"])
                if provider_id != "fake":
                    continue
                selected.append((model_id, model_id, model))
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
                promotion_gate=args.promotion_injection,
            )
        except (OSError, json.JSONDecodeError, ValueError, KeyError, TypeError, RuntimeError) as exc:
            print(f"llm bakeoff error: {exc}", file=sys.stderr)
            return 1
        print(
            "model\tprovider\tprecision_at_k_llm_on\tprecision_at_k_llm_off_baseline\tlift\t"
            "cost_usd\tinjection_cost_usd\tlift_per_usd\tinjection_scope\tinflation_resistance\t"
            "deflation_resistance\thonest_suppression_rate\ttwo_sided_injection_resistance\t"
            "injection_floor_passed\terror"
        )
        for row in report.rows:
            print(
                f"{row.model}\t{row.provider}\t{row.precision_at_k_llm_on}\t"
                f"{row.precision_at_k_llm_off_baseline}\t{row.lift}\t{row.cost_usd}\t"
                f"{row.injection_cost_usd}\t{row.lift_per_usd}\t{row.injection_scope}\t"
                f"{row.inflation_resistance}\t{row.deflation_resistance}\t{row.honest_suppression_rate}\t"
                f"{row.two_sided_injection_resistance}\t{row.injection_floor_passed}\t{row.error or ''}"
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
    with _pipeline_file_log(args):
        return _run_pipeline_command(args)


def _run_pipeline_command(args) -> int:
    if args.version is not None and not _VERSION_RE.fullmatch(args.version):
        print("--version must match YYYYMMDDThhmmssZ", file=sys.stderr)
        return 2
    if args.publish_version is not None and not _VERSION_RE.fullmatch(args.publish_version):
        print("--publish-version must match YYYYMMDDThhmmssZ", file=sys.stderr)
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

    if args.stage == "acquire-wikipedia-sitelinks":
        if not store.stage_completed(conn, region.region_id, "reconcile"):
            print(
                "cannot run 'acquire-wikipedia-sitelinks' for region "
                f"{region.region_id!r}: run 'reconcile' first",
                file=sys.stderr,
            )
            return 1
        try:
            snap_dir = _snapshot_dir(args)
            source_config = acquire.load_config()
            path = acquire.acquire_qid_sitelink_wikipedia(
                acquire.snapshot_paths(snap_dir)["wikipedia"],
                seeds=acquire.qid_sitelink_seeds_from_store(
                    conn,
                    region=region.region_id,
                ),
                language=region.languages[0],
                wikidata_config=source_config["wikidata_entities"],
                wikipedia_config=source_config["wikipedia"],
            )
            snapshots = acquire.snapshot_paths(snap_dir)
            statuses = _initial_extract_statuses(
                region.sources,
                only_source="wikipedia",
            )
            registry = extract_stage.build_registry(
                acquire.DEFAULT_ALLOWLIST,
                languages=set(region.languages),
            )

            def record_status(source, status):
                statuses[source] = status

            extract_transaction_open = False
            if args.parallel:
                conn.execute("BEGIN EXCLUSIVE")
                extract_transaction_open = True
            counts = extract_stage.run_extract(
                conn,
                region,
                snapshots,
                run_id=args.run_id,
                registry=registry,
                extractor_options=_extractor_options(
                    region,
                    snap_dir,
                    osm_index_type=args.osm_index_type,
                    only_source="wikipedia",
                ),
                status_recorder=record_status,
                only_source="wikipedia",
                parallel=args.parallel,
                continue_on_source_failure=args.continue_on_source_failure,
                staging_root=snap_dir.parent,
                commit=not args.parallel,
            )
            _record_extract_metadata_no_commit(
                conn,
                region,
                args.run_id,
                snap_dir,
                statuses,
                only_source="wikipedia",
            )
            store.mark_stage_complete_no_commit(
                conn,
                region.region_id,
                args.stage,
                run_id=args.run_id,
                completed_at=stages._completed_at(),
            )
            conn.commit()
            extract_transaction_open = False
        except KeyError as exc:
            print(f"acquisition config missing {exc.args[0]!r}", file=sys.stderr)
            return 1
        except (
            extract_stage.MissingSnapshotError,
            extract_stage.UnregisteredEnabledSourceError,
            extract_stage.DiskSpaceError,
            SnapshotPayloadMissingError,
            acquire.AcquireError,
        ) as exc:
            if "extract_transaction_open" in locals() and extract_transaction_open:
                conn.rollback()
            print(f"acquisition error: {exc}", file=sys.stderr)
            return 1
        except sqlite3.Error as exc:
            if "extract_transaction_open" in locals() and extract_transaction_open:
                conn.rollback()
            print(f"database error running {args.stage!r}: {exc}", file=sys.stderr)
            return 3
        except Exception as exc:
            if "extract_transaction_open" in locals() and extract_transaction_open:
                conn.rollback()
            print(f"acquisition error: {exc}", file=sys.stderr)
            return 1
        print(f"wikipedia_sitelinks: {path}")
        print(f"wikipedia_extract: {counts}")
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
            snapshots = acquire.snapshot_paths(snap_dir)
            statuses = _initial_extract_statuses(
                region.sources, only_source=args.only_source
            )
            _raise_on_snapshot_sidecar_without_payload(
                region,
                snapshots,
                only_source=args.only_source,
            )
            try:
                fingerprint_inputs = _extract_fingerprint_inputs(
                    region,
                    snapshots,
                    snap_dir=snap_dir,
                    only_source=args.only_source,
                )
            except acquire.AcquireError as exc:
                _record_extract_metadata(
                    conn,
                    region,
                    args.run_id,
                    snap_dir,
                    statuses,
                    only_source=args.only_source,
                )
                print(str(exc), file=sys.stderr)
                return 1
            from .ergonomics import fingerprint, telemetry

            try:
                stage_fingerprint = fingerprint.stage_fingerprint(
                    conn,
                    region.region_id,
                    "extract",
                    inputs=fingerprint_inputs,
                )
            except OSError:
                stage_fingerprint = None
            if stage_fingerprint is not None:
                if fingerprint.should_skip(
                    conn,
                    region.region_id,
                    "extract",
                    stage_fingerprint,
                    force=args.force,
                ):
                    telemetry.emit(
                        "SKIP "
                        f"stage=extract region={region.region_id} "
                        f"fingerprint={stage_fingerprint}"
                    )
                    _record_skipped_extract_metadata(
                        conn,
                        region,
                        args.run_id,
                        snap_dir,
                    )
                    print(f"extract skipped for {region.region_id}")
                    return 0
            registry = extract_stage.build_registry(
                acquire.DEFAULT_ALLOWLIST,
                languages=set(region.languages),
            )
            def record_status(source, status):
                statuses[source] = status

            extract_transaction_open = False
            try:
                if args.parallel:
                    conn.execute("BEGIN EXCLUSIVE")
                    extract_transaction_open = True
                counts = extract_stage.run_extract(
                    conn,
                    region,
                    snapshots,
                    run_id=args.run_id,
                    registry=registry,
                    extractor_options=_extractor_options(
                        region,
                        snap_dir,
                        osm_index_type=args.osm_index_type,
                        only_source=args.only_source,
                    ),
                    status_recorder=record_status,
                    only_source=args.only_source,
                    parallel=args.parallel,
                    continue_on_source_failure=args.continue_on_source_failure,
                    staging_root=snap_dir.parent,
                    commit=not args.parallel,
                )
            except (
                extract_stage.MissingSnapshotError,
                extract_stage.UnregisteredEnabledSourceError,
                extract_stage.DiskSpaceError,
                SnapshotPayloadMissingError,
                acquire.AcquireError,
            ) as exc:
                if extract_transaction_open:
                    conn.rollback()
                _record_extract_metadata(
                    conn,
                    region,
                    args.run_id,
                    snap_dir,
                    statuses,
                    only_source=args.only_source,
                )
                print(str(exc), file=sys.stderr)
                return 1
            except Exception as exc:
                if extract_transaction_open:
                    conn.rollback()
                _record_extract_metadata(
                    conn,
                    region,
                    args.run_id,
                    snap_dir,
                    statuses,
                    only_source=args.only_source,
                )
                print(f"extract error: {exc}", file=sys.stderr)
                return 1
            try:
                _record_extract_metadata_no_commit(
                    conn,
                    region,
                    args.run_id,
                    snap_dir,
                    statuses,
                    only_source=args.only_source,
                )
                completed_at = stages._completed_at()
                store.mark_stage_complete_no_commit(
                    conn,
                    region.region_id,
                    args.stage,
                    run_id=args.run_id,
                    completed_at=completed_at,
                )
                if stage_fingerprint is not None:
                    fingerprint.record_no_commit(
                        conn,
                        region.region_id,
                        args.stage,
                        stage_fingerprint,
                        completed_at=completed_at,
                )
                conn.commit()
                extract_transaction_open = False
            except sqlite3.Error:
                conn.rollback()
                raise
            print(f"{args.stage} complete for {region.region_id}: {counts}")
            return 0
        fingerprint_inputs = _stage_fingerprint_inputs(
            conn,
            region,
            args.stage,
            run_id=args.run_id,
            version=args.version,
        )
        stages.run_stage(
            conn,
            region.region_id,
            args.stage,
            run_id=args.run_id,
            version=args.version,
            publish_version=args.publish_version,
            generated_at=args.generated_at,
            scoring_config_version=args.scoring_config_version,
            upload=args.upload,
            staging_root=args.staging_dir,
            image_candidate_limit=args.image_candidate_limit,
            audited_image_completed_jsonl=args.audited_image_completed_jsonl,
            audited_image_cache_dir=args.audited_image_cache_dir,
            no_image_fetch=args.no_image_fetch,
            no_zone_catalog=args.no_zone_catalog,
            reuse_existing_thumbs=args.reuse_existing_thumbs,
            fingerprint_inputs=fingerprint_inputs,
            force=args.force,
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
        SnapshotPayloadMissingError,
        acquire.AcquireError,
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
