"""Pipeline stage dispatch with order enforcement."""

from __future__ import annotations

import json
import pathlib
import re

from . import config, runtime_paths, store
from .reconcile import cluster, reconcile as reconcile_core, redirects, refs, review
from .reconcile.registry_file import LocalRegistryStore

STAGE_ORDER = ("extract", "reconcile", "score", "categorize", "publish")
VERSION_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")
SOURCE_KEY_TO_PREFIX = {
    "historic_england": "hehle",
    "open_plaques": "plaque",
    "osm": "osm",
    "wikidata": "wd",
    "wikipedia": "wp",
}
RECONCILE_CONFIG = pathlib.Path(__file__).resolve().parents[2] / "config/reconcile.json"


class StageOrderError(RuntimeError):
    pass


class StageVersionError(StageOrderError):
    pass


def predecessor(stage: str) -> str | None:
    if stage not in STAGE_ORDER:
        raise ValueError(f"unknown stage: {stage!r}")
    index = STAGE_ORDER.index(stage)
    return None if index == 0 else STAGE_ORDER[index - 1]


def _load_reconcile_config() -> dict:
    return json.loads(RECONCILE_CONFIG.read_text())


def _enabled_sources(region_config) -> set[str]:
    return {source for source, value in region_config.sources.items() if value is True}


def _succeeded_source_prefixes(region_config, metadata: dict) -> set[str]:
    enabled = _enabled_sources(region_config)
    missing = enabled - set(SOURCE_KEY_TO_PREFIX)
    if missing:
        raise StageOrderError(
            f"enabled sources missing reconcile source mapping: {sorted(missing)}"
        )
    statuses = metadata["source_statuses"]
    return {
        SOURCE_KEY_TO_PREFIX[source]
        for source in enabled
        if statuses.get(source, {}).get("status") == "success"
    }


def _members_from_store(conn, region: str, redirect_map: dict[str, str]) -> list[cluster.Member]:
    rows = conn.execute(
        """
        SELECT source, source_ref, name, lat, lon, props_json
        FROM source_records
        WHERE region = ?
        ORDER BY source, source_ref
        """,
        (region,),
    ).fetchall()
    members = []
    for source, source_ref, name, lat, lon, props_json in rows:
        props = json.loads(props_json)
        members.append(
            cluster.Member(
                source=source,
                source_ref=source_ref,
                name=name,
                lat=lat,
                lon=lon,
                refs=frozenset(refs.refs_of(source, source_ref, props, redirect_map)),
            )
        )
    return members


def _review_items(items: list[dict]) -> list[review.ReviewItem]:
    out = []
    standard_fields = {
        "candidate_place_ids",
        "cluster_refs",
        "kind",
        "members",
        "reason",
    }
    for item in items:
        kind = str(item.get("kind", "unknown"))
        out.append(
            review.ReviewItem(
                kind=kind,
                reason=str(item.get("reason", kind)),
                cluster_refs=list(item.get("cluster_refs", [])),
                candidate_place_ids=list(item.get("candidate_place_ids", [])),
                members=list(item.get("members", [])),
                payload={
                    key: value
                    for key, value in item.items()
                    if key not in standard_fields
                },
            )
        )
    return out


def _run_reconcile(conn, region: str, *, run_id: str, version: str) -> None:
    if not VERSION_RE.fullmatch(version):
        raise StageVersionError("--version must match YYYYMMDDThhmmssZ for reconcile")
    region_config = config.load(region)
    metadata = store.load_extract_run_metadata(conn, region=region, run_id=run_id)
    if metadata is None:
        raise StageOrderError(f"cannot run reconcile for {region!r}: missing extract metadata")
    if not metadata["wikidata_snapshot_date"]:
        raise StageOrderError("cannot run reconcile: missing wikidata snapshot date")

    redirect_path = pathlib.Path(".mt-data") / region / "wikidata_redirects.snapshot.json"
    if not redirect_path.exists():
        raise StageOrderError(f"cannot run reconcile: missing redirect map {redirect_path}")
    try:
        redirect_snapshot = redirects.load_redirect_snapshot(redirect_path)
        redirects.assert_fresh(redirect_snapshot, metadata["wikidata_snapshot_date"])
    except redirects.RedirectMapError as exc:
        raise StageOrderError(f"cannot run reconcile: redirect map rejected: {exc}") from exc

    reconcile_config = _load_reconcile_config()
    fuzzy_config = cluster.FuzzyConfig(**reconcile_config["fuzzy"])
    registry_path = runtime_paths.resolve_near_db(
        conn, reconcile_config["registry_path"].format(region=region)
    )
    review_path = runtime_paths.resolve_near_db(
        conn, reconcile_config["review_path"].format(region=region)
    )

    registry = LocalRegistryStore(registry_path)
    result = reconcile_core.reconcile(
        _members_from_store(conn, region, redirect_snapshot.map),
        registry.load(),
        redirect_snapshot.map,
        version=version,
        succeeded_sources=_succeeded_source_prefixes(region_config, metadata),
        cfg=fuzzy_config,
        telemetry_region=region,
    )
    registry.save(result.records)
    review.write_review(review_path, _review_items(result.review))
    store.replace_places(conn, region=region, places=result.places)


def _run_score(conn, region: str, *, run_id: str) -> None:
    from .score import score_stage

    try:
        score_stage.run(conn, region, run_id=run_id)
    except score_stage.ScoreStageError as exc:
        raise StageOrderError(str(exc)) from exc


def run_stage(
    conn,
    region: str,
    stage: str,
    *,
    run_id: str,
    version: str | None = None,
    publish_version: str | None = None,
    generated_at: str | None = None,
    scoring_config_version: str | None = None,
    upload: bool = False,
    staging_root: str | pathlib.Path | None = None,
    fingerprint_inputs=None,
    force: bool = False,
) -> None:
    previous = predecessor(stage)
    if previous is not None and not store.stage_completed(conn, region, previous):
        raise StageOrderError(
            f"cannot run {stage!r} for region {region!r}: run {previous!r} first"
        )
    stage_fingerprint = None
    if fingerprint_inputs is not None:
        from .ergonomics import fingerprint, telemetry

        stage_fingerprint = fingerprint.stage_fingerprint(
            conn,
            region,
            stage,
            inputs=fingerprint_inputs,
        )
        if fingerprint.should_skip(
            conn,
            region,
            stage,
            stage_fingerprint,
            force=force,
        ):
            telemetry.emit(
                f"SKIP stage={stage} region={region} fingerprint={stage_fingerprint}"
            )
            return
    if stage == "reconcile":
        if version is None:
            raise StageVersionError("--version is required for reconcile")
        try:
            _run_reconcile(conn, region, run_id=run_id, version=version)
        except runtime_paths.RuntimePathError as exc:
            raise StageOrderError(str(exc)) from exc
    elif stage == "score":
        _run_score(conn, region, run_id=run_id)
    elif stage == "categorize":
        from . import categorize

        categorize.run(conn, region, run_id=run_id)
    elif stage == "publish":
        from .publish import publish_stage

        effective_version = publish_version or version
        if effective_version is None:
            raise StageVersionError("--publish-version is required for publish")
        if generated_at is None:
            raise StageVersionError("--generated-at is required for publish")
        kwargs = {}
        if staging_root is not None:
            kwargs["staging_root"] = staging_root
        try:
            publish_stage.run(
                conn,
                region,
                publish_version=effective_version,
                generated_at=generated_at,
                scoring_config_version=scoring_config_version,
                upload=upload,
                **kwargs,
            )
        except (
            publish_stage.PublishStageError,
            publish_stage.basemap.BasemapMeasurementMismatch,
            publish_stage.basemap.BasemapOverBudget,
            publish_stage.basemap.PmtilesUnavailable,
            runtime_paths.RuntimePathError,
        ) as exc:
            raise StageOrderError(str(exc)) from exc
    completed_at = _completed_at()
    store.mark_stage_complete_no_commit(
        conn,
        region,
        stage,
        run_id=run_id,
        completed_at=completed_at,
    )
    if stage_fingerprint is not None:
        from .ergonomics import fingerprint

        fingerprint.record_no_commit(
            conn,
            region,
            stage,
            stage_fingerprint,
            completed_at=completed_at,
        )
    conn.commit()


def _completed_at() -> str:
    import datetime

    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
