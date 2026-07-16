import json
import pathlib
from io import BytesIO

import pytest

from mt_pipeline.publish import r2 as R
from mt_pipeline.publish import staging as S
from mt_pipeline.publish.tiles import TileArtifact


PIPELINE_ROOT = pathlib.Path(__file__).resolve().parents[1]


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


def test_existing_version_prefix_is_refused_even_with_a_ledger(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10/1").mkdir(parents=True)
    (version_root / "tiles/10/1/2.json.gz").write_bytes(b"tile")
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class ExistingPrefixClient:
        def get_object(self, *, Bucket, Key):
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys):
            return {"KeyCount": 1, "Contents": [{"Key": Prefix + "manifest.json"}]}

    with pytest.raises(R.ExistingVersionPrefix):
        R.publish_to_r2(
            version_root,
            _layout(),
            client=ExistingPrefixClient(),
            upload=True,
            uploaded_ledger={("20260715T120000Z", 1, 2, "0" * 64)},
        )


def test_upload_path_locks_uploads_content_manifest_current_then_private_registry(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10/1").mkdir(parents=True)
    (version_root / "tiles/10/1/2.json.gz").write_bytes(b"tile")
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class MissingCurrentUploadClient:
        def __init__(self):
            self.puts = []
            self.deleted = []

        def get_object(self, *, Bucket, Key):
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if hasattr(Body, "read"):
                Body.read()
            self.puts.append((Bucket, Key, IfNoneMatch))

        def delete_object(self, *, Bucket, Key):
            self.deleted.append((Bucket, Key))

    client = MissingCurrentUploadClient()
    result = R.publish_to_r2(
        version_root,
        _layout(),
        client=client,
        upload=True,
        registry_blob=b"registry\n",
    )

    assert result.dry_run is False
    keys = [key for _bucket, key, _if_none_match in client.puts]
    assert keys[0] == "uk/publish.lock"
    assert keys[1:] == [
        "uk/20260715T120000Z/tiles/10/1/2.json.gz",
        "uk/20260715T120000Z/uk.pmtiles",
        "uk/20260715T120000Z/manifest.json",
        "uk/current.json",
        "registry/uk.jsonl",
    ]
    assert client.puts[0][2] == "*"
    assert client.deleted == [("making-tracks-state", "uk/publish.lock")]


def test_live_current_and_unavailable_current_are_fail_closed(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class LiveCurrentClient:
        def get_object(self, *, Bucket, Key):
            return {"Body": BytesIO(b'{"schema_version":1,"publish_version":"20260715T120000Z"}')}

    with pytest.raises(R.VersionAlreadyLive):
        R.publish_to_r2(version_root, _layout(), client=LiveCurrentClient(), upload=True)

    class BrokenCurrentClient:
        def get_object(self, *, Bucket, Key):
            raise RuntimeError("network")

    with pytest.raises(R.CurrentPointerUnavailable):
        R.publish_to_r2(version_root, _layout(), client=BrokenCurrentClient(), upload=True)


def test_upload_recovers_a_stale_publish_lock(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class PreconditionFailed(Exception):
        response = {"Error": {"Code": "PreconditionFailed"}}

    class StaleLockClient:
        def __init__(self):
            self.lock_attempts = 0
            self.deleted = []

        def get_object(self, *, Bucket, Key):
            if Key == "uk/current.json":
                raise FileNotFoundError(Key)
            return {"Body": BytesIO(b'{"expires_at":0}')}

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "uk/publish.lock":
                self.lock_attempts += 1
                if self.lock_attempts == 1:
                    raise PreconditionFailed()

        def delete_object(self, *, Bucket, Key):
            self.deleted.append((Bucket, Key))

    client = StaleLockClient()
    R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert client.lock_attempts == 2
    assert ("making-tracks-state", "uk/publish.lock") in client.deleted


def test_the_real_r2_layout_config_has_two_distinct_buckets():
    layout = json.loads((PIPELINE_ROOT / "config/r2_layout.json").read_text())
    assert layout["public_bucket"] != layout["private_bucket"]
