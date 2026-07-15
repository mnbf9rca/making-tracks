"""Local ID registry storage."""

from __future__ import annotations

import json
import pathlib
from typing import Protocol

from jsonschema import ValidationError
from mt_contracts.registry import RegistryRecord
from mt_contracts.validation import validate_instance


class RegistryStore(Protocol):
    def load(self) -> list[RegistryRecord]:
        ...

    def save(self, records: list[RegistryRecord]) -> None:
        ...


def _record_to_json(record: RegistryRecord) -> dict:
    return {
        "first_shipped_version": record.first_shipped_version,
        "last_seen_version": record.last_seen_version,
        "mint_anchor": record.mint_anchor,
        "place_id": record.place_id,
        "refs": sorted(record.refs),
        "schema_version": record.schema_version,
        "status": record.status,
        "superseded_by": record.superseded_by,
    }


def _record_from_json(data: dict) -> RegistryRecord:
    return RegistryRecord(
        place_id=data["place_id"],
        refs=set(data["refs"]),
        mint_anchor=data["mint_anchor"],
        status=data["status"],
        superseded_by=data.get("superseded_by"),
        first_shipped_version=data.get("first_shipped_version", ""),
        last_seen_version=data.get("last_seen_version", ""),
        schema_version=data.get("schema_version", 1),
    )


class LocalRegistryStore:
    def __init__(self, path) -> None:
        self.path = pathlib.Path(path)

    def load(self) -> list[RegistryRecord]:
        if not self.path.exists():
            return []
        records = []
        for line_number, line in enumerate(self.path.read_text().splitlines(), start=1):
            if not line.strip():
                continue
            try:
                data = json.loads(line)
                validate_instance("registry-record", data)
            except (json.JSONDecodeError, ValidationError, ValueError, KeyError) as exc:
                raise ValueError(
                    f"invalid registry record at {self.path}:{line_number}: {exc}"
                ) from exc
            records.append(_record_from_json(data))
        return sorted(records, key=lambda record: record.place_id)

    def save(self, records: list[RegistryRecord]) -> None:
        payloads = []
        for record in sorted(records, key=lambda item: item.place_id):
            data = _record_to_json(record)
            try:
                validate_instance("registry-record", data)
            except (ValidationError, ValueError) as exc:
                raise ValueError(f"invalid registry record {record.place_id}: {exc}") from exc
            payloads.append(json.dumps(data, sort_keys=True, separators=(",", ":")))

        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_name(f".{self.path.name}.tmp")
        tmp.write_text("\n".join(payloads) + ("\n" if payloads else ""))
        tmp.replace(self.path)
