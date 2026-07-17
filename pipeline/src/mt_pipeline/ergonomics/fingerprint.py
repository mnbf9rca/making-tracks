"""Stage input fingerprints for loud, deterministic stage memoization."""

from __future__ import annotations

import hashlib
import json
import pathlib
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from .. import extract_stage, stages, store
from ..extractors import pageviews

SOURCE_RECORD_RECONCILE_COLS = ("source", "source_ref", "name", "lat", "lon", "props_json")
SOURCE_RECORD_PROPS_COLS = ("source", "source_ref", "props_json")
MAX_PAGEVIEW_FINGERPRINT_FILES = 50_000
MAX_PAGEVIEW_FINGERPRINT_TOTAL_BYTES = 2_000_000_000

_SOURCE_RECORD_RECONCILE_SQL = """
SELECT source, source_ref, name, lat, lon, props_json
FROM source_records
WHERE region = ?
ORDER BY region, source, source_ref
"""

_SOURCE_RECORD_PROPS_SQL = """
SELECT source, source_ref, props_json
FROM source_records
WHERE region = ?
ORDER BY region, source, source_ref
"""

_PLACES_SCORE_SQL = """
SELECT place_id, name, lat, lon, member_refs_json, status
FROM places
WHERE region = ?
ORDER BY region, place_id
"""

_PLACES_CATEGORIZE_SQL = """
SELECT place_id, member_refs_json, status
FROM places
WHERE region = ?
ORDER BY region, place_id
"""

_CONTENT_HASH_QUERIES = {
    ("source_records", SOURCE_RECORD_RECONCILE_COLS): _SOURCE_RECORD_RECONCILE_SQL,
    ("source_records", SOURCE_RECORD_PROPS_COLS): _SOURCE_RECORD_PROPS_SQL,
    (
        "places",
        ("place_id", "name", "lat", "lon", "member_refs_json", "status"),
    ): _PLACES_SCORE_SQL,
    ("places", ("place_id", "member_refs_json", "status")): _PLACES_CATEGORIZE_SQL,
}

STAGE_READS = {
    "extract": {
        "snapshots",
        "wikidata_class_allowlist",
        "osm_candidate_tags",
        "enabled_sources",
        "only_source",
        "languages",
        "pageview_window",
        "pageview_cache_files",
        "module_marker",
    },
    "reconcile": {
        "source_records.source",
        "source_records.source_ref",
        "source_records.name",
        "source_records.lat",
        "source_records.lon",
        "source_records.props_json",
        "succeeded_sources",
        "version",
        "reconcile_config",
        "redirect_map",
        "registry",
        "module_marker",
    },
    "score": {
        "places",
        "source_records.source",
        "source_records.source_ref",
        "source_records.props_json",
        "scoring_config",
        "module_marker",
    },
    "categorize": {
        "places",
        "source_records.source",
        "source_records.source_ref",
        "source_records.props_json",
        "taxonomy_config",
        "osm_candidate_tags",
        "module_marker",
    },
}

_FINGERPRINT_COMPONENT_COVERAGE = {
    "extract": {
        "snapshots": {"snapshots"},
        "wikidata_class_allowlist": {"wikidata_class_allowlist"},
        "osm_candidate_tags": {"osm_candidate_tags"},
        "enabled_sources": {"enabled_sources"},
        "only_source": {"only_source"},
        "languages": {"languages"},
        "pageview_window": {"pageview_window"},
        "pageview_cache_files": {"pageview_cache_files"},
        "module_marker": {"module_marker"},
    },
    "reconcile": {
        "source_records": {
            "source_records.source",
            "source_records.source_ref",
            "source_records.name",
            "source_records.lat",
            "source_records.lon",
            "source_records.props_json",
        },
        "succeeded_sources": {"succeeded_sources"},
        "version": {"version"},
        "reconcile_config": {"reconcile_config"},
        "redirect_map": {"redirect_map"},
        "registry": {"registry"},
        "module_marker": {"module_marker"},
    },
    "score": {
        "places": {"places"},
        "source_records": {
            "source_records.source",
            "source_records.source_ref",
            "source_records.props_json",
        },
        "scoring_config": {"scoring_config"},
        "module_marker": {"module_marker"},
    },
    "categorize": {
        "places": {"places"},
        "source_records": {
            "source_records.source",
            "source_records.source_ref",
            "source_records.props_json",
        },
        "taxonomy_config": {"taxonomy_config"},
        "osm_candidate_tags": {"osm_candidate_tags"},
        "module_marker": {"module_marker"},
    },
}


@dataclass(frozen=True)
class FingerprintInputs:
    region_config: Any | None = None
    snapshots: dict[str, str | pathlib.Path] | None = None
    config_paths: dict[str, str | pathlib.Path] | None = None
    succeeded_sources: set[str] | None = None
    version: str | None = None
    only_source: str | None = None
    pageview_cache_dir: str | pathlib.Path | None = None
    pageview_cache_files: tuple[str | pathlib.Path, ...] = ()
    pageview_window: tuple[str, str] | None = None


def fingerprint_covers(stage: str, components: Mapping[str, Any]) -> set[str]:
    coverage = _FINGERPRINT_COMPONENT_COVERAGE[stage]
    unknown = set(components) - set(coverage)
    if unknown:
        raise ValueError(
            f"{stage} fingerprint component(s) lack coverage metadata: {sorted(unknown)}"
        )
    covered: set[str] = set()
    for component in components:
        covered.update(coverage[component])
    return covered


def stage_fingerprint(conn, region: str, stage: str, *, inputs: FingerprintInputs) -> str:
    return _hash_obj(fingerprint_components(conn, region, stage, inputs=inputs))


def fingerprint_components(
    conn,
    region: str,
    stage: str,
    *,
    inputs: FingerprintInputs,
) -> dict[str, Any]:
    if stage == "extract":
        return _extract_components(inputs)
    elif stage == "reconcile":
        return _reconcile_components(conn, region, inputs)
    elif stage == "score":
        return {
            "places": content_hash(
                conn,
                region,
                "places",
                ("place_id", "name", "lat", "lon", "member_refs_json", "status"),
            ),
            "scoring_config": _file_hash_from_inputs(inputs, "scoring_config"),
            "source_records": content_hash(
                conn,
                region,
                "source_records",
                SOURCE_RECORD_PROPS_COLS,
            ),
            "module_marker": module_marker("score"),
        }
    elif stage == "categorize":
        return {
            "places": content_hash(
                conn,
                region,
                "places",
                ("place_id", "member_refs_json", "status"),
            ),
            "taxonomy_config": _file_hash_from_inputs(inputs, "taxonomy_config"),
            "osm_candidate_tags": _file_hash_from_inputs(inputs, "osm_candidate_tags"),
            "source_records": content_hash(
                conn,
                region,
                "source_records",
                SOURCE_RECORD_PROPS_COLS,
            ),
            "module_marker": module_marker("categorize"),
        }
    else:
        raise ValueError(f"unknown stage: {stage!r}")


def content_hash(conn, region: str, table: str, cols: tuple[str, ...]) -> str:
    query = _CONTENT_HASH_QUERIES.get((table, cols))
    if query is None:
        raise ValueError(f"unsupported content-hash shape: {table} {cols}")
    rows = conn.execute(query, (region,)).fetchall()
    payload = [
        [_canonical_value(col, value) for col, value in zip(cols, row, strict=True)]
        for row in rows
    ]
    return _hash_obj(payload)


def record(conn, region: str, stage: str, fingerprint: str, *, completed_at: str) -> None:
    conn.execute(
        """
        INSERT INTO stage_fingerprints (region, stage, fingerprint, completed_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(region, stage) DO UPDATE SET
            fingerprint = excluded.fingerprint,
            completed_at = excluded.completed_at
        """,
        (region, stage, fingerprint, completed_at),
    )
    conn.commit()


def record_no_commit(
    conn,
    region: str,
    stage: str,
    fingerprint: str,
    *,
    completed_at: str,
) -> None:
    conn.execute(
        """
        INSERT INTO stage_fingerprints (region, stage, fingerprint, completed_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(region, stage) DO UPDATE SET
            fingerprint = excluded.fingerprint,
            completed_at = excluded.completed_at
        """,
        (region, stage, fingerprint, completed_at),
    )


def should_skip(conn, region: str, stage: str, fingerprint: str, *, force: bool) -> bool:
    if force:
        return False
    row = conn.execute(
        """
        SELECT fingerprint
        FROM stage_fingerprints
        WHERE region = ? AND stage = ?
        """,
        (region, stage),
    ).fetchone()
    return row is not None and row[0] == fingerprint


def module_marker(stage: str) -> str:
    return _hash_obj(
        {
            _code_path_key(path): _file_hash(path)
            for path in _stage_code_paths(stage)
        }
    )


def _stage_code_paths(stage: str) -> tuple[pathlib.Path, ...]:
    package_root = pathlib.Path(__file__).resolve().parents[1]
    repo_root = _repo_root()
    fingerprint_path = pathlib.Path(__file__).resolve()
    paths = {
        "extract": (
            fingerprint_path,
            pathlib.Path(extract_stage.__file__).resolve(),
            package_root / "ergonomics" / "merge.py",
            package_root / "ergonomics" / "parallel.py",
            package_root / "ergonomics" / "staging.py",
            package_root / "source_record.py",
            *_py_files(package_root / "extractors"),
            *_contract_runtime_files(repo_root),
        ),
        "reconcile": (
            fingerprint_path,
            pathlib.Path(stages.__file__).resolve(),
            *_py_files(package_root / "reconcile"),
            *_contract_runtime_files(repo_root),
        ),
        "score": (
            fingerprint_path,
            package_root / "source_record.py",
            *_py_files(package_root / "score"),
            *_contract_runtime_files(repo_root),
        ),
        "categorize": (
            fingerprint_path,
            package_root / "categorize.py",
            package_root / "extractors" / "osm.py",
            package_root / "source_record.py",
            *_contract_runtime_files(repo_root),
        ),
    }[stage]
    return tuple(sorted({path.resolve() for path in paths}, key=_code_path_key))


def _py_files(directory: pathlib.Path) -> tuple[pathlib.Path, ...]:
    return tuple(sorted(directory.rglob("*.py"), key=_code_path_key))


def _contract_runtime_files(repo_root: pathlib.Path) -> tuple[pathlib.Path, ...]:
    contracts_root = repo_root / "contracts"
    paths = [
        *_py_files(contracts_root / "src" / "mt_contracts"),
        contracts_root / "versions.json",
        *(contracts_root / "schemas").glob("*.schema.json"),
    ]
    return tuple(sorted({path.resolve() for path in paths}, key=_code_path_key))


def _code_path_key(path: pathlib.Path) -> str:
    try:
        return path.resolve().relative_to(_repo_root()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def _repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[4]


def _extract_components(inputs: FingerprintInputs) -> dict[str, Any]:
    region_config = inputs.region_config
    enabled_sources = sorted(
        source
        for source, value in getattr(region_config, "sources", {}).items()
        if value is True
        and (inputs.only_source is None or source == inputs.only_source)
    )
    snapshots = {
        source: _file_hash(path)
        for source, path in sorted((inputs.snapshots or {}).items())
        if source in enabled_sources
    }
    components = {
        "snapshots": snapshots,
        "enabled_sources": enabled_sources,
        "only_source": inputs.only_source or "",
        "languages": sorted(getattr(region_config, "languages", [])),
        "module_marker": module_marker("extract"),
    }
    if "wikidata" in enabled_sources:
        components["wikidata_class_allowlist"] = _file_hash_from_inputs(
            inputs, "wikidata_class_allowlist"
        )
    if "osm" in enabled_sources:
        components["osm_candidate_tags"] = _file_hash_from_inputs(
            inputs, "osm_candidate_tags"
        )
    if "wikipedia" in enabled_sources:
        components["pageview_window"] = (
            list(inputs.pageview_window) if inputs.pageview_window is not None else []
        )
        components["pageview_cache_files"] = _file_list_hash_limited(
            inputs.pageview_cache_files
        )
    return components


def _reconcile_components(conn, region: str, inputs: FingerprintInputs) -> dict[str, Any]:
    return {
        "source_records": content_hash(
            conn, region, "source_records", SOURCE_RECORD_RECONCILE_COLS
        ),
        "succeeded_sources": sorted(inputs.succeeded_sources or []),
        "version": inputs.version or "",
        "reconcile_config": _file_hash_from_inputs(inputs, "reconcile_config"),
        "redirect_map": _file_hash_from_inputs(inputs, "redirect_map"),
        "registry": _file_hash_from_inputs(inputs, "registry"),
        "module_marker": module_marker("reconcile"),
    }


def _file_hash_from_inputs(inputs: FingerprintInputs, key: str) -> str:
    path = (inputs.config_paths or {}).get(key)
    if path is None:
        return ""
    if not pathlib.Path(path).exists():
        return f"MISSING:{path}"
    return _file_hash(path)


def _file_hash(path: str | pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _file_list_hash_limited(files: tuple[str | pathlib.Path, ...]) -> str:
    markers: list[list[Any]] = []
    total_bytes = 0
    for raw_path in sorted(files, key=lambda value: pathlib.Path(value).as_posix()):
        if len(markers) >= MAX_PAGEVIEW_FINGERPRINT_FILES:
            markers.append(["TOO_MANY_FILES", len(files)])
            break
        path = pathlib.Path(raw_path)
        name = path.name
        try:
            if path.is_symlink():
                markers.append(["SYMLINK", name])
                continue
            stat = path.stat()
        except OSError:
            markers.append(["MISSING", name])
            continue
        if not path.is_file():
            markers.append(["NOTFILE", name])
            continue
        if stat.st_size > pageviews.MAX_CACHE_BYTES:
            markers.append(["TOO_LARGE", name, stat.st_size])
            continue
        total_bytes += stat.st_size
        if total_bytes > MAX_PAGEVIEW_FINGERPRINT_TOTAL_BYTES:
            markers.append(["TOO_MANY_BYTES", total_bytes])
            break
        markers.append(["FILE", name, stat.st_size, _file_hash(path)])
    return _hash_obj(markers)


def _hash_obj(value: Any) -> str:
    payload = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _canonical_value(column: str, value):
    if isinstance(value, float):
        return round(value, 7)
    if column.endswith("_json") and isinstance(value, str):
        try:
            return json.loads(value)
        except (ValueError, RecursionError):
            return value
    return value
