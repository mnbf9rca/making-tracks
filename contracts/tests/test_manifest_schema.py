import hashlib
import json

from mt_contracts.checksums import sha256_hex
from mt_contracts.validation import is_valid, validate_instance


def test_valid_manifest_passes(contracts_root):
    inst = json.loads((contracts_root / "fixtures/manifest/valid/united-kingdom.json").read_text())
    validate_instance("manifest", inst)


def test_manifest_missing_provenance_fails(contracts_root):
    inst = json.loads(
        (contracts_root / "fixtures/manifest/invalid/no_provenance.json").read_text()
    )
    assert not is_valid("manifest", inst)


def test_manifest_empty_provenance_fails(contracts_root):
    inst = json.loads(
        (contracts_root / "fixtures/manifest/invalid/empty_provenance.json").read_text()
    )
    assert not is_valid("manifest", inst)


def test_manifest_bad_checksum_length_fails(contracts_root):
    inst = json.loads(
        (contracts_root / "fixtures/manifest/invalid/bad_checksum.json").read_text()
    )
    assert not is_valid("manifest", inst)


def test_manifest_traversal_filename_fails(contracts_root):
    inst = json.loads(
        (contracts_root / "fixtures/manifest/invalid/traversal_filename.json").read_text()
    )
    assert not is_valid("manifest", inst)


def test_manifest_rejects_non_v1_basemap_maxzoom(contracts_root):
    inst = json.loads((contracts_root / "fixtures/manifest/valid/united-kingdom.json").read_text())
    inst["basemap"]["maxzoom"] = 15
    assert not is_valid("manifest", inst)


def test_manifest_with_attribution_requires_reader_v2(contracts_root):
    inst = json.loads((contracts_root / "fixtures/manifest/valid/united-kingdom.json").read_text())
    inst["min_reader_version"] = 1
    inst["attribution"] = [
        {
            "source": "osm",
            "license": "ODbL-1.0",
            "text": "Place data from OpenStreetMap contributors.",
        }
    ]
    assert not is_valid("manifest", inst)
    inst["min_reader_version"] = 2
    validate_instance("manifest", inst)


def test_sha256_hex_matches_hashlib():
    data = b"making tracks"
    assert sha256_hex(data) == hashlib.sha256(data).hexdigest()
    assert len(sha256_hex(data)) == 64
