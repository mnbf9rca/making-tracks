import json

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


def test_emission_consumes_a0_selection_and_winner_primitives(monkeypatch):
    calls = {"select": 0, "winners": 0}

    def fake_select(places):
        calls["select"] += 1
        ordered = sorted(places, key=lambda p: p["place_id"])
        return ordered[:1], ordered[1:]

    def fake_winners(ids, records):
        calls["winners"] += 1
        return [ids[-1]]

    monkeypatch.setattr(T.caps, "select_tile_places", fake_select)
    monkeypatch.setattr(T.registry, "tile_winner_violations", fake_winners)

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
