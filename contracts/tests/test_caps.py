import gzip
import hashlib
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
    code_only_caps = {
        "CAPS_VERSION",
        "MAX_DESCRIPTION_INDEX_BYTES",
        "MAX_TILE_UNCOMPRESSED_BYTES",
    }
    for name in dir(caps):
        if not name.isupper() or name in code_only_caps:
            continue
        value = getattr(caps, name)
        if isinstance(value, int):
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
    assert len(json.dumps(kept, separators=(",", ":")).encode("utf-8")) <= 5000


def test_overflow_does_not_serialize_growing_candidate_lists(monkeypatch):
    observed_list_lengths = []
    real_dumps = caps.json.dumps

    def spy(obj, *args, **kwargs):
        if isinstance(obj, list):
            observed_list_lengths.append(len(obj))
        return real_dumps(obj, *args, **kwargs)

    monkeypatch.setattr(caps.json, "dumps", spy)
    places = [
        {"place_id": "mt1_" + f"{i:026d}"[:26], "tier": 1, "score": 0.5}
        for i in range(8)
    ]

    caps.select_tile_places(places, max_per_tile=8)

    assert observed_list_lengths == []


def test_gzip_is_deterministic():
    obj = {"schema_version": 1, "z": 10, "x": 1, "y": 2, "places": []}
    encoded = tilecodec.gzip_tile(obj)
    assert encoded == tilecodec.gzip_tile(obj)
    assert encoded[4:8] == b"\0\0\0\0"
    assert encoded[9] == 255
    assert hashlib.sha256(encoded).hexdigest() == (
        "07fa61d1de7c43bdafd747d29f7a46028295b4fe5573599ed6c00d86549d0d42"
    )


def test_gzip_is_canonical_across_dict_insertion_order():
    a = {"schema_version": 1, "z": 10, "x": 1, "y": 2, "places": []}
    b = {"places": [], "y": 2, "x": 1, "z": 10, "schema_version": 1}
    assert tilecodec.gzip_tile(a) == tilecodec.gzip_tile(b)


def test_gzip_tile_rejects_compressed_bytes_over_cap():
    with pytest.raises(ValueError):
        tilecodec.gzip_tile({"blob": "x" * 1000}, max_compressed_bytes=10)


def test_gzip_tile_rejects_uncompressed_envelope_over_cap(monkeypatch):
    monkeypatch.setattr(tilecodec, "MAX_TILE_UNCOMPRESSED_BYTES", 10)
    with pytest.raises(ValueError):
        tilecodec.gzip_tile({"schema_version": 1, "z": 10, "x": 1, "y": 2, "places": []})


def test_safe_gunzip_roundtrip():
    obj = {"a": 1}
    assert json.loads(tilecodec.safe_gunzip(tilecodec.gzip_tile(obj))) == obj


def test_safe_gunzip_aborts_on_bomb():
    bomb = gzip.compress(b"\0" * (2 * 1024 * 1024))
    with pytest.raises(ValueError):
        tilecodec.safe_gunzip(bomb, max_bytes=1024)


def test_safe_gunzip_rejects_compressed_bytes_over_cap():
    encoded = gzip.compress(b"small", mtime=0)
    with pytest.raises(ValueError):
        tilecodec.safe_gunzip(encoded, max_compressed_bytes=len(encoded) - 1)
