import json
import pathlib
import hashlib
from io import BytesIO

import pytest

from mt_contracts.versions import SCHEMA_VERSIONS
from mt_pipeline.publish import r2 as R
from mt_pipeline.publish import images as I
from mt_pipeline.publish import descriptions as D
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


def _image_arts():
    return [
        I.ImageIndexArtifact(
            x=1,
            y=2,
            json_bytes=b'{"schema_version":1,"z":10,"x":1,"y":2,"places":[]}',
            sha256="1" * 64,
            byte_len=53,
        )
    ]


def _thumb_arts():
    return [I.ThumbArtifact(sha256="a" * 64, webp_bytes=b"thumb", byte_len=5)]


def _description_arts():
    return [
        D.DescriptionIndexArtifact(
            x=1,
            y=2,
            json_bytes=b'{"schema_version":1,"z":10,"x":1,"y":2,"places":[]}',
            sha256="2" * 64,
            byte_len=53,
        )
    ]


def _real_thumb_bytes():
    body = b"thumb"
    return hashlib.sha256(body).hexdigest(), body


def _write_min_pack_descriptor(version_root):
    (version_root / "pack-descriptor.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "min_reader_version": 1,
                "region": version_root.parent.name,
                "publish_version": version_root.name,
                "generated_at": "2026-07-15T12:00:00Z",
                "objects": [],
            },
            sort_keys=True,
            separators=(",", ":"),
        )
    )


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


def test_build_staging_replaces_stale_version_directory(tmp_path):
    basemap = tmp_path / "uk.pmtiles"
    basemap.write_bytes(b"basemap")
    stale = tmp_path / "stage/uk/20260715T120000Z/zone-catalog.json"
    stale.parent.mkdir(parents=True)
    stale.write_text("{}")

    root = S.build_staging(
        tmp_path / "stage",
        "uk",
        "20260715T120000Z",
        tile_arts=_arts(),
        manifest_obj={"schema_version": 1, "publish_version": "20260715T120000Z", "region": "uk"},
        basemap_path=basemap,
    )

    assert not (root / "zone-catalog.json").exists()


def test_build_staging_writes_image_indexes_and_global_thumb_blobs(tmp_path):
    basemap = tmp_path / "uk.pmtiles"
    basemap.write_bytes(b"basemap")

    root = S.build_staging(
        tmp_path / "stage",
        "uk",
        "20260715T120000Z",
        tile_arts=_arts(),
        image_index_arts=_image_arts(),
        thumb_arts=_thumb_arts(),
        manifest_obj={
            "schema_version": 1,
            "publish_version": "20260715T120000Z",
            "region": "uk",
        },
        basemap_path=basemap,
    )

    assert (root / "images/10/1/2.json").read_bytes() == _image_arts()[0].json_bytes
    assert (tmp_path / "stage/thumbs/aa" / f"{'a' * 64}.webp").read_bytes() == b"thumb"


def test_build_staging_writes_description_indexes(tmp_path):
    basemap = tmp_path / "uk.pmtiles"
    basemap.write_bytes(b"basemap")

    root = S.build_staging(
        tmp_path / "stage",
        "uk",
        "20260715T120000Z",
        tile_arts=_arts(),
        description_index_arts=_description_arts(),
        manifest_obj={
            "schema_version": 1,
            "publish_version": "20260715T120000Z",
            "region": "uk",
        },
        basemap_path=basemap,
    )

    assert (
        root / "descriptions/10/1/2.json"
    ).read_bytes() == _description_arts()[0].json_bytes
    descriptor = json.loads((root / "pack-descriptor.json").read_text())
    assert descriptor["schema_version"] == 1
    assert descriptor["objects"][0]["kind"] == "description_index"
    assert descriptor["objects"][0]["path"] == "descriptions/10/1/2.json"


def test_manifest_is_the_last_region_content_op_after_images_then_current_flip():
    plan = R.PublishPlan.for_version(
        _layout(),
        "uk",
        "20260715T120000Z",
        _arts(),
        basemap=True,
        image_index_arts=_image_arts(),
        description_index_arts=_description_arts(),
        thumb_arts=_thumb_arts(),
    )
    assert [op.kind for op in plan.ops] == [
        "thumb",
        "image",
        "description",
        "tile",
        "basemap",
        "pack_descriptor",
        "manifest",
        "current",
    ]


def test_all_private_kind_ops_target_the_private_bucket_and_layout_is_distinct():
    layout = _layout()
    plan = R.PublishPlan.for_version(
        layout,
        "uk",
        "20260715T120000Z",
        _arts(),
        basemap=True,
        registry_blob=b'{"x":1}\n',
        cache_blob={"y": 1},
    )
    for op in plan.ops:
        if op.kind in ("registry", "cache", "feedback"):
            assert op.bucket == layout["private_bucket"]
        if op.kind in (
            "tile",
            "image",
            "description",
            "thumb",
            "basemap",
            "manifest",
            "current",
        ):
            assert op.bucket == layout["public_bucket"]

    bad = {**layout, "private_bucket": layout["public_bucket"]}
    with pytest.raises(R.LayoutInvalid):
        R.PublishPlan.for_version(bad, "uk", "20260715T120000Z", _arts(), basemap=True)


def test_for_version_uses_registry_jsonl_extension():
    blob = b'{"place_id":"mt1"}\n'
    layout = _layout()
    plan = R.PublishPlan.for_version(
        layout,
        "uk",
        "20260715T120000Z",
        _arts(),
        basemap=True,
        registry_blob=blob,
    )

    registry_ops = [op for op in plan.ops if op.kind == "registry"]
    assert [op.key for op in registry_ops] == ["registry/uk.jsonl"]
    assert [op.body for op in registry_ops] == [blob]


def test_for_version_rejects_non_bytes_registry_jsonl_blob():
    with pytest.raises(R.RegistryBlobInvalid):
        R.PublishPlan.for_version(
            _layout(),
            "uk",
            "20260715T120000Z",
            _arts(),
            basemap=True,
            registry_blob={"x": 1},
        )


def test_existing_version_prefix_is_refused_even_with_a_ledger(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10/1").mkdir(parents=True)
    (version_root / "tiles/10/1/2.json.gz").write_bytes(b"tile")
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    _write_min_pack_descriptor(version_root)
    (version_root / "manifest.json").write_text("{}")

    class ExistingPrefixClient:
        def __init__(self):
            self.deleted = []

        def get_object(self, *, Bucket, Key):
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys):
            return {"KeyCount": 1, "Contents": [{"Key": Prefix + "manifest.json"}]}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            assert Key == "uk/publish.lock"
            return {"ETag": '"lock-etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            self.deleted.append((Bucket, Key, IfMatch))

    with pytest.raises(R.ExistingVersionPrefix):
        R.publish_to_r2(
            version_root,
            _layout(),
            client=ExistingPrefixClient(),
            upload=True,
        )


def test_upload_path_locks_uploads_content_manifest_private_registry_then_current(tmp_path):
    thumb_sha, thumb_body = _real_thumb_bytes()
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10/1").mkdir(parents=True)
    (version_root / "images/10/1").mkdir(parents=True)
    (version_root / "descriptions/10/1").mkdir(parents=True)
    (version_root / "tiles/10/1/2.json.gz").write_bytes(b"tile")
    (version_root / "images/10/1/2.json").write_bytes(b"image")
    (version_root / "descriptions/10/1/2.json").write_bytes(b"description")
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    _write_min_pack_descriptor(version_root)
    (version_root / "manifest.json").write_text("{}")
    (tmp_path / f"stage/thumbs/{thumb_sha[:2]}").mkdir(parents=True)
    (tmp_path / f"stage/thumbs/{thumb_sha[:2]}" / f"{thumb_sha}.webp").write_bytes(thumb_body)

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
            if Key == "uk/publish.lock":
                return {"ETag": '"lock-etag"'}
            return {"ETag": '"content-etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            self.deleted.append((Bucket, Key, IfMatch))

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
        f"thumbs/{thumb_sha[:2]}/{thumb_sha}.webp",
        "uk/20260715T120000Z/images/10/1/2.json",
        "uk/20260715T120000Z/descriptions/10/1/2.json",
        "uk/20260715T120000Z/tiles/10/1/2.json.gz",
        "uk/20260715T120000Z/uk.pmtiles",
        "uk/20260715T120000Z/pack-descriptor.json",
        "uk/20260715T120000Z/manifest.json",
        "registry/uk.jsonl",
        "uk/current.json",
    ]
    assert client.puts[0][2] == "*"
    assert [
        if_none_match
        for _bucket, key, if_none_match in client.puts
        if key.startswith("uk/20260715T120000Z/") or key.startswith("thumbs/")
    ] == ["*"] * 7
    assert client.deleted == [("making-tracks-state", "uk/publish.lock", '"lock-etag"')]


def test_upload_rechecks_existing_prefix_after_lock(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10/1").mkdir(parents=True)
    (version_root / "tiles/10/1/2.json.gz").write_bytes(b"tile")
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    _write_min_pack_descriptor(version_root)
    (version_root / "manifest.json").write_text("{}")

    class RacingPrefixClient:
        def __init__(self):
            self.list_calls = 0
            self.deleted = []

        def get_object(self, *, Bucket, Key):
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys):
            self.list_calls += 1
            if self.list_calls == 1:
                return {"KeyCount": 0}
            return {"KeyCount": 1, "Contents": [{"Key": Prefix + "manifest.json"}]}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            assert Key == "uk/publish.lock"
            return {"ETag": '"lock-etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            self.deleted.append((Bucket, Key, IfMatch))

    client = RacingPrefixClient()
    with pytest.raises(R.ExistingVersionPrefix):
        R.publish_to_r2(version_root, _layout(), client=client, upload=True)
    assert client.list_calls == 2
    assert client.deleted == [("making-tracks-state", "uk/publish.lock", '"lock-etag"')]


def test_prepared_multi_region_upload_flips_currents_then_merges_region_index(tmp_path):
    thumb_sha, thumb_body = _real_thumb_bytes()
    layout = _layout()
    uk_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    sub_root = tmp_path / "stage" / "uk_london" / "20260715T120000Z"
    for root, region in [(uk_root, "uk"), (sub_root, "uk_london")]:
        (root / "tiles/10/1").mkdir(parents=True)
        (root / "images/10/1").mkdir(parents=True)
        (root / "descriptions/10/1").mkdir(parents=True)
        (root / "tiles/10/1/2.json.gz").write_bytes(f"tile:{region}".encode())
        (root / "images/10/1/2.json").write_bytes(f"image:{region}".encode())
        (root / "descriptions/10/1/2.json").write_bytes(
            f"description:{region}".encode()
        )
        (root / f"{region}.pmtiles").write_bytes(f"basemap:{region}".encode())
        if region == "uk":
            (root / "zone-catalog.proposal.json").write_text(
                json.dumps(
                    {
                        "schema_version": SCHEMA_VERSIONS["zone_catalog"],
                        "min_reader_version": 1,
                        "region": "uk",
                        "publish_version": "20260715T120000Z",
                        "generated_at": "2026-07-15T12:00:00Z",
                        "tile_z": 10,
                        "zones": [],
                    },
                    sort_keys=True,
                )
            )
            (root / "zone-catalog.json").write_text(
                json.dumps(
                    {
                        "schema_version": SCHEMA_VERSIONS["zone_catalog"],
                        "min_reader_version": 1,
                        "region": "uk",
                        "publish_version": "20260715T120000Z",
                        "generated_at": "2026-07-15T12:00:00Z",
                        "tile_z": 10,
                        "zones": [],
                    },
                    sort_keys=True,
                )
            )
        _write_min_pack_descriptor(root)
        (root / "manifest.json").write_text("{}")
    (tmp_path / f"stage/thumbs/{thumb_sha[:2]}").mkdir(parents=True)
    (tmp_path / f"stage/thumbs/{thumb_sha[:2]}" / f"{thumb_sha}.webp").write_bytes(thumb_body)
    region_index = tmp_path / "stage" / "regions.json"
    region_index.write_text(
        json.dumps(
            {
                "schema_version": SCHEMA_VERSIONS["region_index"],
                "min_reader_version": 1,
                "generated_at": "2026-07-15T12:00:00Z",
                "regions": [
                    {
                        "id": "uk",
                        "display_name": "United Kingdom",
                        "parent": None,
                        "bbox": [-8.65, 49.84, 1.77, 60.86],
                        "publish_version": "20260715T120000Z",
                        "basemap_bytes": 7,
                        "tile_count": 1,
                        "bytes_without_thumbs": 11,
                        "bytes_with_thumbs": 11,
                    },
                    {
                        "id": "uk_london",
                        "display_name": "London",
                        "parent": "uk",
                        "bbox": [-0.5, 51.2, 0.3, 51.8],
                        "publish_version": "20260715T120000Z",
                        "basemap_bytes": 7,
                        "tile_count": 1,
                        "bytes_without_thumbs": 11,
                        "bytes_with_thumbs": 11,
                    },
                ],
            },
            sort_keys=True,
        )
    )

    existing_index = {
        "schema_version": 1,
        "min_reader_version": 1,
        "generated_at": "2026-07-14T12:00:00Z",
        "regions": [
            {
                "id": "malaysia",
                "display_name": "Malaysia",
                "parent": None,
                "bbox": [99.64, 0.85, 119.27, 7.36],
                "publish_version": "20260714T120000Z",
                "basemap_bytes": 7,
                "tile_count": 1,
                "bytes_without_thumbs": 11,
                "bytes_with_thumbs": 11,
            }
        ],
    }

    class MissingCurrentsClient:
        def __init__(self):
            self.puts = []
            self.deleted = []

        def get_object(self, *, Bucket, Key):
            if Key == "regions.json":
                return {"Body": BytesIO(json.dumps(existing_index).encode("utf-8"))}
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            body = Body.read() if hasattr(Body, "read") else Body
            self.puts.append((Bucket, Key, body, IfNoneMatch))
            return {"ETag": f'"etag-{len(self.puts)}"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            self.deleted.append((Bucket, Key, IfMatch))

    plans = [
        R.publish_to_r2(uk_root, layout, upload=False, registry_blob=b"registry\n").plan,
        R.publish_to_r2(sub_root, layout, upload=False).plan,
    ]
    client = MissingCurrentsClient()

    result = R.publish_prepared_to_r2(plans, region_index, layout, client=client)

    keys = [
        key
        for _bucket, key, _body, _if_none_match in client.puts
        if not key.endswith("/publish.lock")
    ]
    assert keys == [
        f"thumbs/{thumb_sha[:2]}/{thumb_sha}.webp",
        "uk/20260715T120000Z/images/10/1/2.json",
        "uk/20260715T120000Z/descriptions/10/1/2.json",
        "uk/20260715T120000Z/tiles/10/1/2.json.gz",
        "uk/20260715T120000Z/uk.pmtiles",
        "uk/20260715T120000Z/zone-catalog.proposal.json",
        "uk/20260715T120000Z/zone-catalog.json",
        "uk/20260715T120000Z/pack-descriptor.json",
        "uk/20260715T120000Z/manifest.json",
        "uk_london/20260715T120000Z/images/10/1/2.json",
        "uk_london/20260715T120000Z/descriptions/10/1/2.json",
        "uk_london/20260715T120000Z/tiles/10/1/2.json.gz",
        "uk_london/20260715T120000Z/uk_london.pmtiles",
        "uk_london/20260715T120000Z/pack-descriptor.json",
        "uk_london/20260715T120000Z/manifest.json",
        "registry/uk.jsonl",
        "uk/current.json",
        "uk_london/current.json",
        "regions.json",
    ]
    immutable_if_none_match = [
        if_none_match
        for _bucket, key, _body, if_none_match in client.puts
        if key.startswith("thumbs/")
        or "/20260715T120000Z/" in key
    ]
    assert immutable_if_none_match == ["*"] * 15
    merged_body = next(body for _bucket, key, body, _if_none_match in client.puts if key == "regions.json")
    merged_index = json.loads(merged_body)
    assert [entry["id"] for entry in merged_index["regions"]] == [
        "malaysia",
        "uk",
        "uk_london",
    ]
    assert result.region_index_result.dry_run is False


def test_region_index_dry_run_with_client_previews_merged_upload_body(tmp_path):
    layout = _layout()
    region_index = tmp_path / "stage" / "regions.json"
    region_index.parent.mkdir()
    region_index.write_text(
        json.dumps(
            {
                "schema_version": SCHEMA_VERSIONS["region_index"],
                "min_reader_version": 1,
                "generated_at": "2026-07-15T12:00:00Z",
                "regions": [
                    {
                        "id": "uk",
                        "display_name": "United Kingdom",
                        "parent": None,
                        "bbox": [-8.65, 49.84, 1.77, 60.86],
                        "publish_version": "20260715T120000Z",
                        "basemap_bytes": 7,
                        "tile_count": 1,
                        "bytes_without_thumbs": 11,
                        "bytes_with_thumbs": 11,
                    }
                ],
            }
        )
    )
    existing_index = {
        "schema_version": 1,
        "min_reader_version": 1,
        "generated_at": "2026-07-14T12:00:00Z",
        "regions": [
            {
                "id": "malaysia",
                "display_name": "Malaysia",
                "parent": None,
                "bbox": [99.64, 0.85, 119.27, 7.36],
                "publish_version": "20260714T120000Z",
                "basemap_bytes": 7,
                "tile_count": 1,
                "bytes_without_thumbs": 11,
                "bytes_with_thumbs": 11,
            }
        ],
    }

    class RegionIndexClient:
        def get_object(self, *, Bucket, Key):
            assert (Bucket, Key) == ("making-tracks-tiles", "regions.json")
            return {"Body": BytesIO(json.dumps(existing_index).encode("utf-8"))}

    result = R.publish_region_index(
        region_index, layout, client=RegionIndexClient(), upload=False
    )

    assert result.dry_run is True
    assert result.plan.ops[0].source_path is None
    merged = json.loads(result.plan.ops[0].body)
    assert [entry["id"] for entry in merged["regions"]] == ["malaysia", "uk"]


def test_region_index_offline_dry_run_plan_serializes_the_planned_body(tmp_path):
    layout = _layout()
    region_index = tmp_path / "stage" / "regions.json"
    region_index.parent.mkdir()
    region_index.write_text(
        json.dumps(
            {
                "schema_version": SCHEMA_VERSIONS["region_index"],
                "min_reader_version": 1,
                "generated_at": "2026-07-15T12:00:00Z",
                "regions": [
                    {
                        "id": "uk",
                        "display_name": "United Kingdom",
                        "parent": None,
                        "bbox": [-8.65, 49.84, 1.77, 60.86],
                        "publish_version": "20260715T120000Z",
                        "basemap_bytes": 7,
                        "tile_count": 1,
                        "bytes_without_thumbs": 11,
                        "bytes_with_thumbs": 11,
                    }
                ],
            }
        )
    )

    result = R.publish_region_index(region_index, layout, upload=False)

    assert result.dry_run is True
    assert result.plan.ops[0].source_path is None
    assert json.loads(result.plan.ops[0].body)["regions"][0]["id"] == "uk"


def test_thumb_uploads_are_hash_verified_and_write_if_absent(tmp_path):
    thumb_sha, thumb_body = _real_thumb_bytes()
    thumb_path = tmp_path / "thumb.webp"
    thumb_path.write_bytes(thumb_body)
    op = R.PublishOp(
        kind="thumb",
        bucket="making-tracks-tiles",
        key=f"thumbs/{thumb_sha[:2]}/{thumb_sha}.webp",
        source_path=thumb_path,
    )

    class Client:
        def __init__(self):
            self.puts = []

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            self.puts.append((Bucket, Key, Body, IfNoneMatch))

    client = Client()
    R._upload_op(client, op)

    assert client.puts == [
        ("making-tracks-tiles", f"thumbs/{thumb_sha[:2]}/{thumb_sha}.webp", thumb_body, "*")
    ]

    bad_path = tmp_path / "bad.webp"
    bad_path.write_bytes(b"not-that-thumb")
    bad = R.PublishOp(
        kind="thumb",
        bucket="making-tracks-tiles",
        key=f"thumbs/{thumb_sha[:2]}/{thumb_sha}.webp",
        source_path=bad_path,
    )
    with pytest.raises(ValueError, match="thumb content hash mismatch"):
        R._upload_op(client, bad)


def test_existing_content_addressed_thumb_is_treated_as_uploaded(tmp_path):
    thumb_sha, thumb_body = _real_thumb_bytes()
    thumb_path = tmp_path / "thumb.webp"
    thumb_path.write_bytes(thumb_body)
    op = R.PublishOp(
        kind="thumb",
        bucket="making-tracks-tiles",
        key=f"thumbs/{thumb_sha[:2]}/{thumb_sha}.webp",
        source_path=thumb_path,
    )

    class PreconditionFailed(Exception):
        response = {"Error": {"Code": "PreconditionFailed"}}

    class Client:
        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            raise PreconditionFailed()

    R._upload_op(Client(), op)


def test_default_client_uses_committed_r2_s3_endpoint_contract(monkeypatch):
    calls = []

    class FakeBoto3:
        def client(self, service, **kwargs):
            calls.append((service, kwargs))
            return object()

    monkeypatch.setattr(R, "_import_module", lambda name: FakeBoto3())
    monkeypatch.setenv("R2_S3_ENDPOINT", "https://example.r2.cloudflarestorage.com")
    monkeypatch.setenv("R2_ACCESS_KEY_ID", "access-key")
    monkeypatch.setenv("R2_SECRET_ACCESS_KEY", "secret-key")
    monkeypatch.delenv("R2_ACCOUNT_ID", raising=False)

    R._default_client()

    assert calls == [
        (
            "s3",
            {
                "endpoint_url": "https://example.r2.cloudflarestorage.com",
                "aws_access_key_id": "access-key",
                "aws_secret_access_key": "secret-key",
            },
        )
    ]


def test_upload_env_preflight_reports_missing_names_without_values(monkeypatch):
    monkeypatch.setattr(R, "_import_module", lambda name: object())
    monkeypatch.delenv("R2_S3_ENDPOINT", raising=False)
    monkeypatch.setenv("R2_ACCESS_KEY_ID", "visible-access")
    monkeypatch.delenv("R2_SECRET_ACCESS_KEY", raising=False)

    with pytest.raises(R.R2EnvironmentUnavailable) as excinfo:
        R.require_upload_environment()

    message = str(excinfo.value)
    assert "R2_S3_ENDPOINT" in message
    assert "R2_SECRET_ACCESS_KEY" in message
    assert "R2_ACCESS_KEY_ID" not in message
    assert "visible-access" not in message


def test_upload_env_preflight_treats_empty_and_whitespace_as_missing(monkeypatch):
    monkeypatch.setattr(R, "_import_module", lambda name: object())
    monkeypatch.setenv("R2_S3_ENDPOINT", "   ")
    monkeypatch.setenv("R2_ACCESS_KEY_ID", "")
    monkeypatch.setenv("R2_SECRET_ACCESS_KEY", "visible-secret")

    with pytest.raises(R.R2EnvironmentUnavailable) as excinfo:
        R.require_upload_environment()

    message = str(excinfo.value)
    assert "R2_S3_ENDPOINT" in message
    assert "R2_ACCESS_KEY_ID" in message
    assert "R2_SECRET_ACCESS_KEY" not in message
    assert "visible-secret" not in message


@pytest.mark.parametrize(
    "endpoint",
    [
        "op:/making-tracks/cloudflare/r2_s3_endpoint",
        "op://making-tracks/cloudflare/r2_s3_endpoint",
        "http://example.r2.cloudflarestorage.com",
        "https://r2.cloudflarestorage.com",
        "https://attacker.example.com",
        "https://example.r2.cloudflarestorage.com.evil.com",
    ],
)
def test_upload_env_preflight_rejects_invalid_r2_endpoint_without_value(
    monkeypatch, endpoint
):
    monkeypatch.setattr(R, "_import_module", lambda name: object())
    monkeypatch.setenv("R2_S3_ENDPOINT", endpoint)
    monkeypatch.setenv("R2_ACCESS_KEY_ID", "access-key")
    monkeypatch.setenv("R2_SECRET_ACCESS_KEY", "secret-key")

    with pytest.raises(R.R2EnvironmentUnavailable) as excinfo:
        R.require_upload_environment()

    message = str(excinfo.value)
    assert "R2_S3_ENDPOINT" in message
    assert endpoint not in message
    assert "access-key" not in message
    assert "secret-key" not in message


def test_live_current_and_unavailable_current_are_fail_closed(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    _write_min_pack_descriptor(version_root)
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
    _write_min_pack_descriptor(version_root)
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
            return {"Body": BytesIO(b'{"expires_at":0}'), "ETag": '"stale-etag"'}

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "uk/publish.lock":
                self.lock_attempts += 1
                if self.lock_attempts == 1:
                    raise PreconditionFailed()
                return {"ETag": '"fresh-etag"'}
            return {"ETag": '"content-etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            self.deleted.append((Bucket, Key, IfMatch))

    client = StaleLockClient()
    R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert client.lock_attempts == 2
    assert ("making-tracks-state", "uk/publish.lock", '"stale-etag"') in client.deleted
    assert ("making-tracks-state", "uk/publish.lock", '"fresh-etag"') in client.deleted


def test_stale_lock_delete_is_conditional_on_the_stale_object(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    _write_min_pack_descriptor(version_root)
    (version_root / "manifest.json").write_text("{}")

    class PreconditionFailed(Exception):
        response = {"Error": {"Code": "PreconditionFailed"}}

    class StaleDeleteRaceClient:
        def __init__(self):
            self.lock_attempts = 0
            self.delete_if_match = []

        def get_object(self, *, Bucket, Key):
            if Key == "uk/current.json":
                raise FileNotFoundError(Key)
            return {"Body": BytesIO(b'{"expires_at":0}'), "ETag": '"old-lock"'}

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "uk/publish.lock":
                self.lock_attempts += 1
                raise PreconditionFailed()
            return {"ETag": '"content-etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            self.delete_if_match.append(IfMatch)
            raise PreconditionFailed()

    client = StaleDeleteRaceClient()

    with pytest.raises(R.PublishLockUnavailable, match="publish lock is held"):
        R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert client.lock_attempts == 1
    assert client.delete_if_match == ['"old-lock"']


def test_stale_lock_retry_race_reports_lock_unavailable(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    _write_min_pack_descriptor(version_root)
    (version_root / "manifest.json").write_text("{}")

    class PreconditionFailed(Exception):
        response = {"Error": {"Code": "PreconditionFailed"}}

    class RetryRaceClient:
        def __init__(self):
            self.lock_attempts = 0

        def get_object(self, *, Bucket, Key):
            if Key == "uk/current.json":
                raise FileNotFoundError(Key)
            return {"Body": BytesIO(b'{"expires_at":0}'), "ETag": '"stale-etag"'}

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "uk/publish.lock":
                self.lock_attempts += 1
                raise PreconditionFailed()
            return {"ETag": '"content-etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = RetryRaceClient()

    with pytest.raises(R.PublishLockUnavailable, match="publish lock is held"):
        R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert client.lock_attempts == 2


def test_file_body_is_closed_when_upload_fails(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10/1").mkdir(parents=True)
    (version_root / "tiles/10/1/2.json.gz").write_bytes(b"tile")
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    _write_min_pack_descriptor(version_root)
    (version_root / "manifest.json").write_text("{}")

    class FailingUploadClient:
        def __init__(self):
            self.tile_body = None
            self.deleted = []

        def get_object(self, *, Bucket, Key):
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "uk/publish.lock":
                return {"ETag": '"lock-etag"'}
            if Key == "uk/20260715T120000Z/tiles/10/1/2.json.gz":
                self.tile_body = Body
                raise RuntimeError("upload failed")
            return {"ETag": '"content-etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            self.deleted.append((Bucket, Key, IfMatch))

    client = FailingUploadClient()

    with pytest.raises(RuntimeError, match="upload failed"):
        R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert client.tile_body is not None
    assert client.tile_body.closed is True
    assert client.deleted == [("making-tracks-state", "uk/publish.lock", '"lock-etag"')]


def test_the_real_r2_layout_config_has_two_distinct_buckets():
    layout = json.loads((PIPELINE_ROOT / "config/r2_layout.json").read_text())
    assert layout["public_bucket"] != layout["private_bucket"]
