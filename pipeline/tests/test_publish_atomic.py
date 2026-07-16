import json

import pytest

from mt_pipeline.publish import r2 as R
from mt_pipeline.publish import staging as S
from mt_pipeline.publish.tiles import TileArtifact


def _layout():
    return {
        "public_bucket": "making-tracks-tiles",
        "private_bucket": "making-tracks-state",
        "public_domain": "tiles.making-tracks.app",
        "private_prefixes": {
            "registry": "registry/",
            "llm_cache": "llm-cache/",
            "feedback": "feedback/",
        },
    }


def _arts():
    return [
        TileArtifact(x=1, y=2, gz_bytes=b"tile", sha256="0" * 64, byte_len=4)
    ]


def test_unsafe_region_or_version_is_refused_before_any_path_is_built():
    for region, version in [
        ("../../mt-state", "20260715T120000Z"),
        ("uk", "../current"),
        ("UK", "20260715T120000Z"),
    ]:
        with pytest.raises(R.UnsafePathComponent):
            R.validate_path_components(region, version)
    R.validate_path_components("uk", "20260715T120000Z")


def test_build_staging_writes_the_public_r2_shape(tmp_path):
    basemap = tmp_path / "uk.pmtiles"
    basemap.write_bytes(b"basemap")
    manifest = {
        "schema_version": 1,
        "publish_version": "20260715T120000Z",
        "region": "uk",
    }

    root = S.build_staging(
        tmp_path / "stage",
        "uk",
        "20260715T120000Z",
        tile_arts=_arts(),
        manifest_obj=manifest,
        basemap_path=basemap,
    )

    assert (root / "tiles/10/1/2.json.gz").read_bytes() == b"tile"
    assert (root / "uk.pmtiles").read_bytes() == b"basemap"
    assert json.loads((root / "manifest.json").read_text()) == manifest


def test_manifest_is_the_LAST_content_op_then_current_flip():
    plan = R.PublishPlan.for_version(
        _layout(), "uk", "20260715T120000Z", _arts(), basemap=True
    )
    manifest_index = plan.manifest_index()
    assert all(op.kind in ("tile", "basemap") for op in plan.ops[:manifest_index])
    assert plan.ops[manifest_index].kind == "manifest"
    assert plan.ops[manifest_index + 1].kind == "current"


def test_all_private_kind_ops_target_the_private_bucket_and_layout_is_distinct():
    layout = _layout()
    plan = R.PublishPlan.for_version(
        layout,
        "uk",
        "20260715T120000Z",
        _arts(),
        basemap=True,
        registry_blob={"x": 1},
        cache_blob={"y": 1},
    )
    for op in plan.ops:
        if op.kind in ("registry", "cache", "feedback"):
            assert op.bucket == layout["private_bucket"]
        if op.kind in ("tile", "basemap", "manifest", "current"):
            assert op.bucket == layout["public_bucket"]

    bad = {**layout, "private_bucket": layout["public_bucket"]}
    with pytest.raises(R.LayoutInvalid):
        R.PublishPlan.for_version(bad, "uk", "20260715T120000Z", _arts(), basemap=True)


def test_the_real_r2_layout_config_has_two_distinct_buckets():
    layout = json.loads(open("config/r2_layout.json").read())
    assert layout["public_bucket"] != layout["private_bucket"]
