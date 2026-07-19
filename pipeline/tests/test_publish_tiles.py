import json

import pytest

from mt_contracts import registry as R
from mt_contracts.tilecodec import safe_gunzip
from mt_contracts.validation import validate_instance

from mt_pipeline.publish import tiles as T


def _pid(index: int) -> str:
    return "mt1_" + f"{index:026d}"[-26:]


def _p(pid: str, tier: int, score: float, cat: str = "history", lat=51.5, lon=-0.1):
    return {
        "place_id": pid,
        "name": "n",
        "lat": lat,
        "lon": lon,
        "category": cat,
        "tier": tier,
        "score": score,
        "source_refs": ["wd:Q1"],
    }


def _shipped(arts):
    return [
        place
        for artifact in arts
        for place in json.loads(safe_gunzip(artifact.gz_bytes))["places"]
    ]


def test_uncategorized_and_invalid_are_excluded_and_counted_not_silent():
    places = [
        _p(_pid(1), 1, 0.9),
        _p(_pid(2), 4, 0.1, cat="uncategorized"),
        _p("mt1_SHORT", 1, 0.9),
        _p(_pid(3), 1, 0.9, lat=float("nan")),
    ]
    arts, counts = T.emit_tiles(places, registry_records=[])
    assert counts.uncategorized_excluded == 1
    assert counts.invalid_excluded == 2
    assert counts.total_published == 1
    shipped = _shipped(arts)
    assert all(place["category"] != "uncategorized" for place in shipped)
    for artifact in arts:
        validate_instance("tile", json.loads(safe_gunzip(artifact.gz_bytes)))


def test_superseded_AND_tombstoned_without_successor_are_both_excluded():
    recs = [
        R.RegistryRecord(
            place_id=_pid(4),
            refs={"wd:Q1"},
            mint_anchor="wd:Q1",
            status="tombstoned",
            superseded_by=_pid(5),
            first_shipped_version="20260101T000000Z",
            last_seen_version="20260101T000000Z",
            schema_version=1,
        ),
        R.RegistryRecord(
            place_id=_pid(6),
            refs={"wd:Q2"},
            mint_anchor="wd:Q2",
            status="tombstoned",
            superseded_by=None,
            first_shipped_version="20260101T000000Z",
            last_seen_version="20260101T000000Z",
            schema_version=1,
        ),
    ]
    arts, counts = T.emit_tiles(
        [_p(_pid(4), 1, 0.9), _p(_pid(6), 1, 0.9), _p(_pid(1), 1, 0.9)],
        registry_records=recs,
    )
    assert counts.non_winner_excluded == 2
    assert counts.total_published == 1
    assert [place["place_id"] for place in _shipped(arts)] == [_pid(1)]


def test_publish_winner_resolver_matches_contract_for_chains_and_cycles():
    a, b, c, live = _pid(10), _pid(11), _pid(12), _pid(13)
    chain_records = [
        R.RegistryRecord(a, refs={"wd:Q10"}, mint_anchor="wd:Q10", status="live", superseded_by=b),
        R.RegistryRecord(b, refs={"wd:Q11"}, mint_anchor="wd:Q11", status="live", superseded_by=c),
        R.RegistryRecord(c, refs={"wd:Q12"}, mint_anchor="wd:Q12", status="live"),
        R.RegistryRecord(live, refs={"wd:Q13"}, mint_anchor="wd:Q13", status="live"),
    ]
    ids = [a, b, c, live, _pid(99)]

    assert T._winner_violations_for_publish(ids, chain_records) == R.tile_winner_violations(
        ids, chain_records
    )

    cycle_records = [
        R.RegistryRecord(a, refs={"wd:Q10"}, mint_anchor="wd:Q10", status="live", superseded_by=b),
        R.RegistryRecord(b, refs={"wd:Q11"}, mint_anchor="wd:Q11", status="live", superseded_by=a),
    ]
    with pytest.raises(ValueError, match="superseded_by cycle"):
        T._winner_violations_for_publish([a], cycle_records)
    with pytest.raises(ValueError, match="superseded_by cycle"):
        R.tile_winner_violations([a], cycle_records)


def test_emit_tiles_builds_registry_lookup_once_for_winner_pass(monkeypatch):
    calls = 0

    def fake_records_by_id(records):
        nonlocal calls
        calls += 1
        return {record.place_id: record for record in records}

    monkeypatch.setattr(T, "_registry_records_by_id", fake_records_by_id, raising=False)
    monkeypatch.setattr(
        T.registry,
        "tile_winner_violations",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("old quadratic contract helper must not be called by publish")
        ),
    )
    records = [
        R.RegistryRecord(_pid(i), refs={f"wd:Q{i}"}, mint_anchor=f"wd:Q{i}", status="live")
        for i in range(1, 8)
    ]

    T.emit_tiles([_p(_pid(i), 1, 1.0 - i * 0.01) for i in range(1, 8)], records)

    assert calls == 1


def test_publish_winner_resolver_memoizes_supersede_chains(monkeypatch):
    lookups = 0
    by_id = {
        _pid(i): R.RegistryRecord(
            _pid(i),
            refs={f"wd:Q{i}"},
            mint_anchor=f"wd:Q{i}",
            status="live",
            superseded_by=_pid(i + 1) if i < 20 else None,
        )
        for i in range(1, 21)
    }

    class CountingById(dict):
        def get(self, *args, **kwargs):
            nonlocal lookups
            lookups += 1
            return super().get(*args, **kwargs)

    monkeypatch.setattr(T, "_registry_records_by_id", lambda _records: CountingById(by_id))

    assert T._winner_violations_for_publish(list(by_id), list(by_id.values())) == [
        _pid(i) for i in range(1, 20)
    ]
    assert lookups <= 40


def test_emit_tiles_heartbeats_during_winner_pass(monkeypatch, capsys):
    monkeypatch.setattr(T, "_HEARTBEAT_EVERY_RECORDS", 1)
    records = [
        R.RegistryRecord(_pid(1), refs={"wd:Q1"}, mint_anchor="wd:Q1", status="live"),
        R.RegistryRecord(_pid(2), refs={"wd:Q2"}, mint_anchor="wd:Q2", status="live", superseded_by=_pid(1)),
    ]

    T.emit_tiles([_p(_pid(1), 1, 0.9), _p(_pid(2), 1, 0.8)], records, region="united-kingdom")

    err = capsys.readouterr().err
    assert "PHASE START publish.winner_validation region=united-kingdom places=2" in err
    assert "PHASE HEARTBEAT publish.winner_validation region=united-kingdom processed=1/2" in err
    assert "PHASE DONE publish.winner_validation region=united-kingdom processed=2/2" in err
    assert "non_winner_excluded=1" in err


def test_dense_cell_reselects_under_the_compressed_cap(monkeypatch):
    real_gzip = T.tilecodec.gzip_tile

    def tiny_cap(tile_obj):
        if len(tile_obj["places"]) > 2:
            raise ValueError("gzip tile exceeded max_compressed_bytes")
        return real_gzip(tile_obj)

    monkeypatch.setattr(T.tilecodec, "gzip_tile", tiny_cap)
    dense = [_p(_pid(i), 1, 1.0 - i * 0.001) for i in range(1, 5)]

    arts, counts = T.emit_tiles(dense, [])

    assert counts.overflow_dropped == 2
    assert len(_shipped(arts)) == 2
    assert [place["place_id"] for place in _shipped(arts)] == [_pid(1), _pid(2)]


def test_emission_consumes_a0_selection_and_publish_winner_resolver(monkeypatch):
    calls = {"select": 0, "winners": 0}

    def fake_select(places):
        calls["select"] += 1
        ordered = sorted(places, key=lambda p: p["place_id"])
        return ordered[:1], ordered[1:]

    def fake_winners(ids, records, *, region=None):
        calls["winners"] += 1
        return [ids[-1]]

    monkeypatch.setattr(T.caps, "select_tile_places", fake_select)
    monkeypatch.setattr(T, "_winner_violations_for_publish", fake_winners)

    arts, counts = T.emit_tiles(
        [_p(_pid(1), 1, 0.9), _p(_pid(2), 1, 0.8), _p(_pid(3), 1, 0.7)],
        [],
    )

    assert calls == {"select": 1, "winners": 1}
    assert counts.non_winner_excluded == 1
    assert counts.overflow_dropped == 1
    assert [place["place_id"] for place in _shipped(arts)] == [_pid(1)]


def test_emission_is_byte_identical_on_repeat():
    places = [_p(_pid(1), 1, 0.9), _p(_pid(3), 2, 0.5)]
    a1, _ = T.emit_tiles(places, [])
    a2, _ = T.emit_tiles(places, [])
    assert [artifact.gz_bytes for artifact in a1] == [artifact.gz_bytes for artifact in a2]
