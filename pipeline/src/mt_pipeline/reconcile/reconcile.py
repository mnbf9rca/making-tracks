"""Pure reconcile core: clusters to stable registry records and places."""

from __future__ import annotations

from dataclasses import dataclass, replace

from mt_contracts.place_id import (
    assert_canonical_mint_key,
    mint_place_id,
    select_mint_anchor,
)
from mt_contracts.registry import AmbiguousRefsError, RegistryRecord
from mt_pipeline import progress

from .cluster import Cluster, FuzzyConfig, Member, cluster_by_refs, fuzzy_defer
from .redirects import canonicalize_ref

MAX_REFS_PER_PLACE = 256


@dataclass
class ReconcileResult:
    records: list[RegistryRecord]
    places: list[dict]
    review: list[dict]


@dataclass
class ResolveStats:
    records_scanned: int = 0


class _RegistryRefIndex:
    def __init__(
        self,
        records: list[RegistryRecord],
        *,
        stats: ResolveStats | None = None,
    ) -> None:
        self._refs_by_place_id: dict[str, set[str]] = {}
        self._place_ids_by_ref: dict[str, set[str]] = {}
        for record in records:
            if stats is not None:
                stats.records_scanned += 1
            self.add_record(record)

    def add_record(self, record: RegistryRecord) -> None:
        self._set_refs(record.place_id, set(record.refs))

    def update_record(self, record: RegistryRecord) -> None:
        self._set_refs(record.place_id, set(record.refs))

    def resolve(self, incoming_refs: set[str]) -> str | None:
        matches: set[str] = set()
        for ref in incoming_refs:
            matches.update(self._place_ids_by_ref.get(ref, set()))
        if len(matches) > 1:
            raise AmbiguousRefsError(matches)
        return next(iter(matches), None)

    def _set_refs(self, place_id: str, refs: set[str]) -> None:
        old_refs = self._refs_by_place_id.get(place_id, set())
        for ref in old_refs - refs:
            place_ids = self._place_ids_by_ref.get(ref)
            if place_ids is None:
                continue
            place_ids.discard(place_id)
            if not place_ids:
                del self._place_ids_by_ref[ref]
        for ref in refs - old_refs:
            self._place_ids_by_ref.setdefault(ref, set()).add(place_id)
        self._refs_by_place_id[place_id] = refs


def _scan_resolve_by_refs(
    records: list[RegistryRecord],
    incoming_refs: set[str],
    *,
    stats: ResolveStats | None = None,
) -> str | None:
    matches = set()
    for record in records:
        if stats is not None:
            stats.records_scanned += 1
        if record.refs & incoming_refs:
            matches.add(record.place_id)
    if len(matches) > 1:
        raise AmbiguousRefsError(matches)
    return next(iter(matches), None)


def _is_mint_key(ref: str) -> bool:
    try:
        assert_canonical_mint_key(ref)
    except ValueError:
        return False
    return True


def _copy_records(records: list[RegistryRecord]) -> list[RegistryRecord]:
    return [
        RegistryRecord(
            place_id=record.place_id,
            refs=set(record.refs),
            mint_anchor=record.mint_anchor,
            status=record.status,
            superseded_by=record.superseded_by,
            first_shipped_version=record.first_shipped_version,
            last_seen_version=record.last_seen_version,
            schema_version=record.schema_version,
        )
        for record in records
    ]


def _bridge_records(
    records: list[RegistryRecord], redirect_map: dict[str, str]
) -> list[RegistryRecord]:
    bridged = []
    for record in records:
        bridged_refs = {canonicalize_ref(ref, redirect_map) for ref in record.refs}
        bridged_refs.update(record.refs)
        bridged.append(replace(record, refs=bridged_refs))
    return bridged


def _member_sources(record: RegistryRecord) -> set[str]:
    return {ref.split(":", 1)[0] for ref in record.refs}


def _trim_refs(record: RegistryRecord, review: list[dict]) -> None:
    if len(record.refs) <= MAX_REFS_PER_PLACE:
        return
    wd_refs = sorted(ref for ref in record.refs if ref.startswith("wd:"))
    required = {record.mint_anchor, *wd_refs}
    if len(required) > MAX_REFS_PER_PLACE:
        raise ValueError(f"place {record.place_id} exceeds ref cap with required refs")
    optional = sorted(record.refs - required)
    keep = set(sorted(required) + optional[: MAX_REFS_PER_PLACE - len(required)])
    evicted = sorted(record.refs - keep)
    record.refs = keep
    review.append(
        {
            "kind": "ref_cap",
            "place_id": record.place_id,
            "evicted_refs": evicted,
            "refs_kept": len(keep),
        }
    )


def _representative_member(cluster: Cluster) -> Member:
    mintable_by_ref = {
        member.source_ref: member
        for member in cluster.members
        if _is_mint_key(member.source_ref)
    }
    if mintable_by_ref:
        return mintable_by_ref[select_mint_anchor(mintable_by_ref)]
    return sorted(cluster.members, key=lambda member: member.source_ref)[0]


def _place_for_cluster(place_id: str, cluster: Cluster, status: str) -> dict:
    representative = _representative_member(cluster)
    return {
        "lat": representative.lat,
        "lon": representative.lon,
        "member_refs": sorted(member.source_ref for member in cluster.members),
        "name": representative.name,
        "place_id": place_id,
        "refs": sorted(cluster.refs),
        "status": status,
    }


def _review_for_fuzzy(deferred) -> dict:
    return {
        "anchor_a": deferred.anchor_a,
        "anchor_b": deferred.anchor_b,
        "dist_m": deferred.dist_m,
        "kind": "fuzzy_defer",
        "sim": deferred.sim,
    }


def reconcile(
    members: list[Member],
    existing: list[RegistryRecord],
    redirect_map: dict[str, str],
    *,
    version: str,
    succeeded_sources: set[str],
    cfg: FuzzyConfig,
    telemetry_region: str | None = None,
    fuzzy_heartbeat_every_pairs: int | None = None,
    resolve_heartbeat_every_clusters: int | None = None,
) -> ReconcileResult:
    records = _copy_records(existing)
    bridged_records = _bridge_records(records, redirect_map)
    by_place_id = {record.place_id: record for record in records}
    resolver = _RegistryRefIndex(bridged_records)
    present_place_ids: set[str] = set()
    review: list[dict] = []
    places: list[dict] = []

    clusters = cluster_by_refs(members)
    fuzzy_kwargs = {}
    if fuzzy_heartbeat_every_pairs is not None:
        fuzzy_kwargs["heartbeat_every_pairs"] = fuzzy_heartbeat_every_pairs
    review.extend(
        _review_for_fuzzy(deferred)
        for deferred in fuzzy_defer(
            clusters,
            cfg,
            telemetry_region=telemetry_region,
            **fuzzy_kwargs,
        )
    )

    phase = None
    if telemetry_region is not None:
        phase = progress.PhaseProgress(
            "reconcile.resolve_mint",
            region=telemetry_region,
            total=len(clusters),
            total_label="clusters",
            heartbeat_every_records=(
                resolve_heartbeat_every_clusters
                if resolve_heartbeat_every_clusters is not None
                else progress.HEARTBEAT_EVERY_RECORDS
            ),
        )
        phase.start()

    processed = 0
    minted = 0
    matched = 0
    try:
        for cluster in clusters:
            processed += 1
            if phase is not None:
                phase.tick(processed)
            anchor_refs = sorted(ref for ref in cluster.refs if _is_mint_key(ref))
            if not anchor_refs:
                review.append(
                    {
                        "cluster_refs": sorted(cluster.refs),
                        "kind": "unmintable",
                        "members": sorted(member.source_ref for member in cluster.members),
                    }
                )
                continue

            try:
                place_id = resolver.resolve(set(cluster.refs))
            except AmbiguousRefsError as exc:
                review.append(
                    {
                        "candidate_place_ids": sorted(exc.place_ids),
                        "cluster_refs": sorted(cluster.refs),
                        "kind": "ambiguous_refs",
                        "members": sorted(member.source_ref for member in cluster.members),
                    }
                )
                continue

            if place_id is None:
                mint_anchor = select_mint_anchor(anchor_refs)
                place_id = mint_place_id(mint_anchor)
                record = RegistryRecord(
                    place_id=place_id,
                    refs=set(cluster.refs),
                    mint_anchor=mint_anchor,
                    status="live",
                    first_shipped_version=version,
                    last_seen_version=version,
                )
                records.append(record)
                by_place_id[place_id] = record
                resolver.add_record(record)
                minted += 1
            else:
                record = by_place_id[place_id]
                canonical_cluster_refs = {
                    canonicalize_ref(ref, redirect_map) for ref in cluster.refs
                }
                record.refs.update(cluster.refs)
                record.refs.update(canonical_cluster_refs)
                record.last_seen_version = version
                _trim_refs(record, review)
                resolver.update_record(record)
                matched += 1

            present_place_ids.add(place_id)
            places.append(_place_for_cluster(place_id, cluster, record.status))
    finally:
        if phase is not None:
            phase.done(processed, extra=f" minted={minted} matched={matched}")

    for record in records:
        if record.place_id in present_place_ids or record.status != "live":
            continue
        sources = _member_sources(record)
        if sources and sources <= succeeded_sources:
            continue
        record.last_seen_version = version

    return ReconcileResult(
        records=sorted(records, key=lambda record: record.place_id),
        places=sorted(places, key=lambda place: place["place_id"]),
        review=sorted(review, key=lambda item: repr(sorted(item.items()))),
    )
