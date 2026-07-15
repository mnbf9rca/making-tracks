"""Pure reconcile core: clusters to stable registry records and places."""

from __future__ import annotations

from dataclasses import dataclass, replace

from mt_contracts.place_id import (
    assert_canonical_mint_key,
    mint_place_id,
    select_mint_anchor,
)
from mt_contracts.registry import AmbiguousRefsError, RegistryRecord, resolve_by_refs

from .cluster import Cluster, FuzzyConfig, Member, cluster_by_refs, fuzzy_defer
from .redirects import canonicalize_ref

MAX_REFS_PER_PLACE = 256


@dataclass
class ReconcileResult:
    records: list[RegistryRecord]
    places: list[dict]
    review: list[dict]


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


def _find_record(records: list[RegistryRecord], place_id: str) -> RegistryRecord:
    for record in records:
        if record.place_id == place_id:
            return record
    raise KeyError(place_id)


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
) -> ReconcileResult:
    records = _copy_records(existing)
    bridged_records = _bridge_records(records, redirect_map)
    by_place_id = {record.place_id: record for record in records}
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

    for cluster in clusters:
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
            place_id = resolve_by_refs(bridged_records, set(cluster.refs))
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
            bridged_records.append(replace(record, refs=set(record.refs)))
            by_place_id[place_id] = record
        else:
            record = _find_record(records, place_id)
            canonical_cluster_refs = {
                canonicalize_ref(ref, redirect_map) for ref in cluster.refs
            }
            record.refs.update(cluster.refs)
            record.refs.update(canonical_cluster_refs)
            record.last_seen_version = version
            _trim_refs(record, review)

        present_place_ids.add(place_id)
        places.append(_place_for_cluster(place_id, cluster, record.status))

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
