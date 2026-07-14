"""ID registry record shape and union-of-refs lookup contract."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass


class AmbiguousRefsError(Exception):
    def __init__(self, place_ids: set[str]):
        self.place_ids = place_ids
        super().__init__(f"refs match multiple places: {sorted(place_ids)}")


@dataclass
class RegistryRecord:
    place_id: str
    refs: set[str]
    mint_anchor: str
    status: str
    superseded_by: str | None = None
    first_shipped_version: str = ""
    last_seen_version: str = ""
    schema_version: int = 1


def resolve_by_refs(
    records: Iterable[RegistryRecord], incoming_refs: set[str]
) -> str | None:
    matches = {record.place_id for record in records if record.refs & incoming_refs}
    if len(matches) > 1:
        raise AmbiguousRefsError(matches)
    return next(iter(matches), None)


def resolve_superseded(records: Iterable[RegistryRecord], place_id: str) -> str:
    by_id = {record.place_id: record for record in records}
    seen: set[str] = set()
    current = place_id
    while True:
        record = by_id.get(current)
        next_id = record.superseded_by if record else None
        if not next_id:
            return current
        if next_id in seen:
            raise ValueError(f"superseded_by cycle at {next_id}")
        seen.add(current)
        current = next_id


def assert_no_supersede_cycles(records: Iterable[RegistryRecord]) -> None:
    records = list(records)
    for record in records:
        resolve_superseded(records, record.place_id)


def tile_winner_violations(
    tile_place_ids: Iterable[str], records: Iterable[RegistryRecord]
) -> list[str]:
    records = list(records)
    return [pid for pid in tile_place_ids if resolve_superseded(records, pid) != pid]
