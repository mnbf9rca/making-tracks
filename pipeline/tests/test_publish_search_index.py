import json
import sqlite3

import pytest

from mt_contracts.search import shard_key_for_token
from mt_contracts.search import split_shard_key_for_token
from mt_pipeline.publish import search_index


A = "mt1_" + "0" * 26


def _place(**overrides):
    data = {
        "place_id": A,
        "name": "古堡",
        "lat": 3.1,
        "lon": 101.7,
        "tier": 1,
        "category": "history",
        "source_refs": [],
    }
    data.update(overrides)
    return data


def test_non_latin_primary_name_uses_ascii_hash_shard_key():
    result = search_index.emit_search_indexes(
        [_place()],
        source_props_by_ref={},
        region="malaysia-singapore-brunei",
        publish_version="20260719T100000Z",
        generated_at="2026-07-19T10:00:00Z",
    )

    shard_keys = {artifact.shard_key for artifact in result.full_artifacts}
    assert shard_key_for_token("古堡") in shard_keys
    assert all(key is not None and key.isascii() for key in shard_keys)
    payload = json.loads(result.full_artifacts[0].json_bytes)
    assert payload["entries"][0]["tokens"] == ["古堡"]


def test_search_index_artifact_byte_cap_has_teeth(monkeypatch):
    monkeypatch.setattr(search_index.caps, "MAX_SEARCH_INDEX_BYTES", 64)

    with pytest.raises(ValueError, match="search-index artifact exceeds"):
        search_index.emit_search_indexes(
            [_place(name="Fort")],
            source_props_by_ref={},
            region="malaysia-singapore-brunei",
            publish_version="20260719T100000Z",
            generated_at="2026-07-19T10:00:00Z",
        )


def test_search_index_splits_oversize_full_shards(monkeypatch):
    places = [
        _place(
            place_id="mt1_" + f"{index:026d}",
            name=f"Station {index}",
            tier=3,
        )
        for index in range(12)
    ]
    monkeypatch.setattr(search_index.caps, "MAX_SEARCH_INDEX_BYTES", 1000)
    validated_shards: list[str | None] = []
    original_validate = search_index.validate_instance

    def spy_validate(name, payload):
        validated_shards.append(payload.get("shard_key"))
        original_validate(name, payload)

    monkeypatch.setattr(search_index, "validate_instance", spy_validate)

    result = search_index.emit_search_indexes(
        places,
        source_props_by_ref={},
        region="malaysia-singapore-brunei",
        publish_version="20260719T100000Z",
        generated_at="2026-07-19T10:00:00Z",
    )

    shard_keys = {artifact.shard_key for artifact in result.full_artifacts}
    assert "st" not in shard_keys
    assert "st" not in validated_shards
    assert "st_a" not in shard_keys
    assert any(
        key and key.startswith(f"{split_shard_key_for_token('station', A)}_h")
        for key in shard_keys
    )
    assert all(
        artifact.byte_len <= search_index.caps.MAX_SEARCH_INDEX_BYTES
        for artifact in result.full_artifacts
    )


def test_source_props_loader_only_reads_requested_shipped_refs():
    conn = sqlite3.connect(":memory:")
    conn.execute(
        "CREATE TABLE source_records (region TEXT, source_ref TEXT, props_json TEXT)"
    )
    conn.executemany(
        "INSERT INTO source_records (region, source_ref, props_json) VALUES (?, ?, ?)",
        [
            ("malaysia-singapore-brunei", "osm:node/1", '{"name:ms":"Kota"}'),
            ("malaysia-singapore-brunei", "123", '{"name:ms":"Wrong"}'),
            ("malaysia-singapore-brunei", "osm:node/unused", "{not-json"),
            ("other-region", "osm:node/1", '{"name:ms":"Wrong"}'),
        ],
    )

    rows = search_index.source_rows_from_db(
        conn,
        "malaysia-singapore-brunei",
        {"osm:node/1", 123, None},
    )

    assert rows == {"osm:node/1": {"name:ms": "Kota"}}
