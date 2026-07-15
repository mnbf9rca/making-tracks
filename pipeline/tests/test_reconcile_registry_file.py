import pytest

from mt_contracts.place_id import mint_place_id
from mt_contracts.registry import RegistryRecord
from mt_pipeline.reconcile.registry_file import LocalRegistryStore


def _record(ref, *, status="live"):
    return RegistryRecord(
        place_id=mint_place_id(ref),
        refs={ref},
        mint_anchor=ref,
        status=status,
        first_shipped_version="20260715T000000Z",
        last_seen_version="20260715T000000Z",
    )


def test_missing_registry_loads_empty(tmp_path):
    store = LocalRegistryStore(tmp_path / "registry.jsonl")

    assert store.load() == []


def test_registry_round_trips_sorted_records_and_refs(tmp_path):
    store = LocalRegistryStore(tmp_path / "registry.jsonl")
    first = _record("osm:node/2")
    second = _record("wd:Q1")
    first.refs.add("wd:Q9")

    store.save([first, second])
    first_bytes = (tmp_path / "registry.jsonl").read_bytes()
    store.save([first, second])
    second_bytes = (tmp_path / "registry.jsonl").read_bytes()

    loaded = store.load()
    assert [record.place_id for record in loaded] == sorted(
        [first.place_id, second.place_id]
    )
    assert loaded[0].refs == set(sorted(loaded[0].refs))
    assert first_bytes == second_bytes


def test_registry_save_rejects_malformed_records(tmp_path):
    store = LocalRegistryStore(tmp_path / "registry.jsonl")
    bad = _record("wd:Q1")
    bad.refs.clear()

    with pytest.raises(ValueError):
        store.save([bad])

    assert not (tmp_path / "registry.jsonl").exists()
