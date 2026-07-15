import hashlib
import json
import pathlib

import pytest

from mt_pipeline.extractors import osm


def test_is_candidate_matches_key_wildcard_and_value_set():
    cfg = {
        "historic": True,
        "tourism": ["attraction", "artwork", "viewpoint"],
        "memorial": True,
    }
    assert osm.is_candidate({"historic": "castle"}, cfg)
    assert osm.is_candidate({"tourism": "artwork"}, cfg)
    assert not osm.is_candidate({"tourism": "hotel"}, cfg)
    assert not osm.is_candidate({"amenity": "bench"}, cfg)


def test_bootstrap_tag_config_loads_and_is_minimal():
    cfg = osm.load_tag_config(
        pathlib.Path(__file__).parents[1] / "config/osm_candidate_tags.json"
    )
    assert cfg and "historic" in cfg
    assert cfg["tourism"] == ["attraction", "artwork", "viewpoint"]


def test_provenance_verifies_sha256_and_is_loud_on_mismatch(tmp_path):
    pbf = tmp_path / "uk.pbf"
    pbf.write_bytes(b"PBFDATA")
    sha = hashlib.sha256(b"PBFDATA").hexdigest()
    (tmp_path / "uk.pbf.meta.json").write_text(
        json.dumps(
            {
                "source_url": "u",
                "geofabrik_date": "2026-07-14",
                "sha256": sha,
                "size": 7,
            }
        )
    )
    osm.verify_provenance(pbf)

    (tmp_path / "uk.pbf.meta.json").write_text(json.dumps({"sha256": "deadbeef"}))
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)


def test_provenance_absent_sidecar_proceeds_with_warning(tmp_path, caplog):
    pbf = tmp_path / "dev.pbf"
    pbf.write_bytes(b"x")

    osm.verify_provenance(pbf)

    assert any("provenance" in record.message.lower() for record in caplog.records)


def test_provenance_malformed_sidecar_is_a_typed_error_not_attributeerror(tmp_path):
    pbf = tmp_path / "uk.pbf"
    pbf.write_bytes(b"PBFDATA")
    meta = tmp_path / "uk.pbf.meta.json"

    meta.write_text('["not", "a", "dict"]')
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)

    meta.write_text(json.dumps({"source_url": "u"}))
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)

    meta.write_bytes(b"{" + b" " * (osm.MAX_SIDECAR_BYTES + 10))
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)
