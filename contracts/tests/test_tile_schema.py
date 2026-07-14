import gzip
import json

from mt_contracts.caps import MAX_TILE_UNCOMPRESSED_BYTES
from mt_contracts.validation import is_valid, validate_instance


def test_valid_tile_fixture_passes(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/valid/one_place.json").read_text())
    validate_instance("tile", inst)


def test_tile_with_bad_place_fails(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/invalid/bad_place.json").read_text())
    assert not is_valid("tile", inst)


def test_tile_wrong_zoom_fails(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/invalid/wrong_zoom.json").read_text())
    assert not is_valid("tile", inst)


def test_tile_xy_out_of_range_fails(contracts_root):
    inst = json.loads(
        (contracts_root / "fixtures/tile/invalid/xy_out_of_range.json").read_text()
    )
    assert not is_valid("tile", inst)


def test_gzip_roundtrip_and_decode_cap(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/valid/one_place.json").read_text())
    raw = json.dumps(inst).encode("utf-8")
    packed = gzip.compress(raw)
    assert len(raw) <= MAX_TILE_UNCOMPRESSED_BYTES
    assert json.loads(gzip.decompress(packed).decode("utf-8")) == inst
