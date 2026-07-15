"""Review-file seam for ambiguous reconcile decisions."""

from __future__ import annotations

import json
import pathlib
from dataclasses import dataclass

from mt_contracts.registry import RegistryRecord, assert_no_supersede_cycles


@dataclass(frozen=True)
class ReviewItem:
    kind: str
    reason: str
    cluster_refs: list[str]
    candidate_place_ids: list[str]
    members: list[str]

    def to_json(self) -> dict:
        return {
            "candidate_place_ids": sorted(self.candidate_place_ids),
            "cluster_refs": sorted(self.cluster_refs),
            "kind": self.kind,
            "members": sorted(self.members),
            "reason": self.reason,
        }


def write_review(path, items: list[ReviewItem]) -> None:
    destination = pathlib.Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    rows = [
        json.dumps(item.to_json(), sort_keys=True, separators=(",", ":"))
        for item in sorted(
            items,
            key=lambda item: (
                item.kind,
                sorted(item.cluster_refs),
                sorted(item.candidate_place_ids),
                sorted(item.members),
            ),
        )
    ]
    tmp = destination.with_name(f".{destination.name}.tmp")
    tmp.write_text("\n".join(rows) + ("\n" if rows else ""))
    tmp.replace(destination)


def supersede(
    records: list[RegistryRecord], loser: str, winner: str
) -> list[RegistryRecord]:
    out = [
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
    by_id = {record.place_id: record for record in out}
    if loser not in by_id:
        raise KeyError(loser)
    if winner not in by_id:
        raise KeyError(winner)
    by_id[loser].superseded_by = winner
    assert_no_supersede_cycles(out)
    return sorted(out, key=lambda record: record.place_id)
