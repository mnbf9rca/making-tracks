import hashlib
import json

from mt_contracts.checksums import sha256_hex
from mt_contracts.validation import is_valid, validate_instance


def test_valid_manifest_passes(contracts_root):
    inst = json.loads((contracts_root / "fixtures/manifest/valid/uk.json").read_text())
    validate_instance("manifest", inst)


def test_manifest_missing_provenance_fails(contracts_root):
    inst = json.loads(
        (contracts_root / "fixtures/manifest/invalid/no_provenance.json").read_text()
    )
    assert not is_valid("manifest", inst)


def test_manifest_bad_checksum_length_fails(contracts_root):
    inst = json.loads(
        (contracts_root / "fixtures/manifest/invalid/bad_checksum.json").read_text()
    )
    assert not is_valid("manifest", inst)


def test_sha256_hex_matches_hashlib():
    data = b"making tracks"
    assert sha256_hex(data) == hashlib.sha256(data).hexdigest()
    assert len(sha256_hex(data)) == 64
