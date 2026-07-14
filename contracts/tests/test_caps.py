import gzip
import json

import pytest

from mt_contracts import caps
from mt_contracts import tilecodec
from mt_contracts.validation import load_schema


def test_schema_literals_match_caps_via_map():
    for (schema, path, keyword), const_name in caps.CAPS_SCHEMA_MAP.items():
        node = load_schema(schema)
        for key in path:
            node = node[key]
        assert node[keyword] == getattr(caps, const_name), (schema, path, keyword)
    mapped = set(caps.CAPS_SCHEMA_MAP.values())
    for name in dir(caps):
        if name.endswith("_MAX"):
            assert name in mapped, f"{name} has no parity assertion"


def test_overflow_is_deterministic_and_keeps_best():
    places = [
        {"place_id": "mt1_" + "a" * 26, "tier": 4, "score": 0.1},
        {"place_id": "mt1_" + "b" * 26, "tier": 1, "score": 0.9},
        {"place_id": "mt1_" + "c" * 26, "tier": 2, "score": 0.5},
    ]
    kept, dropped = caps.select_tile_places(places, max_per_tile=2)
    assert [p["place_id"] for p in kept] == [
        "mt1_" + "b" * 26,
        "mt1_" + "c" * 26,
    ]
    assert [p["place_id"] for p in dropped] == ["mt1_" + "a" * 26]
    assert caps.select_tile_places(places, max_per_tile=2) == (kept, dropped)


def test_overflow_stable_tie_break_by_place_id():
    a = {"place_id": "mt1_" + "1" * 26, "tier": 1, "score": 0.5}
    b = {"place_id": "mt1_" + "2" * 26, "tier": 1, "score": 0.5}
    kept, dropped = caps.select_tile_places([b, a], max_per_tile=1)
    assert [p["place_id"] for p in kept] == ["mt1_" + "1" * 26]
    assert [p["place_id"] for p in dropped] == ["mt1_" + "2" * 26]


def test_overflow_also_bounds_bytes():
    big = [
        {
            "place_id": "mt1_" + f"{i:026d}"[:26],
            "tier": 1,
            "score": 0.5,
            "blob": "x" * 1000,
        }
        for i in range(50)
    ]
    kept, dropped = caps.select_tile_places(big, max_per_tile=999, byte_budget=5000)
    assert dropped
    assert len(json.dumps(kept).encode("utf-8")) <= 5000


def test_gzip_is_deterministic():
    obj = {"schema_version": 1, "z": 10, "x": 1, "y": 2, "places": []}
    assert tilecodec.gzip_tile(obj) == tilecodec.gzip_tile(obj)


def test_safe_gunzip_roundtrip():
    obj = {"a": 1}
    assert json.loads(tilecodec.safe_gunzip(tilecodec.gzip_tile(obj))) == obj


def test_safe_gunzip_aborts_on_bomb():
    bomb = gzip.compress(b"\0" * (2 * 1024 * 1024))
    with pytest.raises(ValueError):
        tilecodec.safe_gunzip(bomb, max_bytes=1024)
