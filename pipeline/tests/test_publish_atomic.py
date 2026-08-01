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
        ("bad region", "20260715T120000Z"),
    ]:
        with pytest.raises(R.UnsafePathComponent):
            R.validate_path_components(region, version)
    R.validate_path_components("uk", "20260715T120000Z")
    R.validate_path_components("malaysia-singapore-brunei", "20260715T120000Z")


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
    assert plan.ops[manifest_index + 2].kind == "catalog_current"


def test_publish_plan_does_not_pin_clobbering_single_region_catalog_body():
    plan = R.PublishPlan.for_version(
        _layout(), "united-kingdom", "20260715T120000Z", _arts(), basemap=True
    )
    op = next(op for op in plan.ops if op.kind == "catalog_current")

    assert op.bucket == "making-tracks-tiles"
    assert op.key == "catalog/current.json"
    assert op.body is None


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
        if op.kind in ("tile", "basemap", "manifest", "current", "catalog_current"):
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
    (version_root / "manifest.json").write_text("{}")

    class ExistingPrefixClient:
        def get_object(self, *, Bucket, Key):
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            return {"KeyCount": 1, "Contents": [{"Key": Prefix + "manifest.json"}]}

    with pytest.raises(R.ExistingVersionPrefix):
        R.publish_to_r2(
            version_root,
            _layout(),
            client=ExistingPrefixClient(),
            upload=True,
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

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if hasattr(Body, "read"):
                Body.read()
            self.puts.append((Bucket, Key, IfNoneMatch))
            if Key in {"uk/publish.lock", "catalog/publish.lock"}:
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
        "uk/20260715T120000Z/tiles/10/1/2.json.gz",
        "uk/20260715T120000Z/uk.pmtiles",
        "uk/20260715T120000Z/manifest.json",
        "uk/current.json",
        "catalog/publish.lock",
        "catalog/current.json",
        "registry/uk.jsonl",
    ]
    assert client.puts[0][2] == "*"
    assert client.puts[5][2] == "*"
    assert client.deleted == [
        ("making-tracks-state", "catalog/publish.lock", '"lock-etag"'),
        ("making-tracks-state", "uk/publish.lock", '"lock-etag"'),
    ]


def test_upload_bootstraps_shared_catalog_when_r2_reports_missing_key(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class MissingKey(Exception):
        response = {"Error": {"Code": "NoSuchKey"}}

    class MissingCatalogClient:
        def __init__(self):
            self.catalog_body = None

        def get_object(self, *, Bucket, Key):
            raise MissingKey(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "catalog/current.json":
                self.catalog_body = Body
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = MissingCatalogClient()

    R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert json.loads(client.catalog_body) == {
        "schema_version": 1,
        "publish_versions": {"uk": "20260715T120000Z"},
    }


def test_upload_flips_region_current_before_shared_catalog_so_advertised_updates_are_fulfillable(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class CatalogFailureClient:
        def __init__(self):
            self.put_keys = []

        def get_object(self, *, Bucket, Key):
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            self.put_keys.append(Key)
            if Key == "catalog/current.json":
                raise RuntimeError("catalog upload failed")
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = CatalogFailureClient()

    with pytest.raises(RuntimeError, match="catalog upload failed"):
        R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert client.put_keys.index("uk/current.json") < client.put_keys.index("catalog/current.json")


def test_upload_bootstraps_missing_shared_catalog_from_existing_region_currents(tmp_path):
    version_root = tmp_path / "stage" / "united-kingdom" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "united-kingdom.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class BackfillCatalogClient:
        def __init__(self):
            self.catalog_body = None

        def get_object(self, *, Bucket, Key):
            if Key == "united-kingdom/current.json":
                raise FileNotFoundError(Key)
            if Key == "catalog/current.json":
                raise FileNotFoundError(Key)
            if Key == "malaysia-singapore-brunei/current.json":
                return {"Body": BytesIO(b'{"schema_version":1,"publish_version":"20260714T000000Z"}')}
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            if Prefix == "united-kingdom/20260715T120000Z/":
                return {"KeyCount": 0}
            if Prefix == "":
                return {
                    "KeyCount": 2,
                    "CommonPrefixes": [
                        {"Prefix": "malaysia-singapore-brunei/"},
                        {"Prefix": "assets/"},
                    ],
                }
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "catalog/current.json":
                self.catalog_body = Body
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = BackfillCatalogClient()

    R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert json.loads(client.catalog_body) == {
        "schema_version": 1,
        "publish_versions": {
            "malaysia-singapore-brunei": "20260714T000000Z",
            "united-kingdom": "20260715T120000Z",
        },
    }


def test_upload_backfill_paginates_region_current_listing(tmp_path):
    version_root = tmp_path / "stage" / "united-kingdom" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "united-kingdom.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class PaginatedBackfillClient:
        def __init__(self):
            self.catalog_body = None
            self.list_requests = []

        def get_object(self, *, Bucket, Key):
            if Key == "united-kingdom/current.json":
                raise FileNotFoundError(Key)
            if Key == "catalog/current.json":
                raise FileNotFoundError(Key)
            if Key == "malaysia-singapore-brunei/current.json":
                return {"Body": BytesIO(b'{"schema_version":1,"publish_version":"20260714T000000Z"}')}
            raise FileNotFoundError(Key)

        def list_objects_v2(self, **kwargs):
            self.list_requests.append(kwargs)
            prefix = kwargs["Prefix"]
            if prefix == "united-kingdom/20260715T120000Z/":
                return {"KeyCount": 0}
            if prefix == "" and "ContinuationToken" not in kwargs:
                return {
                    "KeyCount": 1,
                    "IsTruncated": True,
                    "NextContinuationToken": "page-2",
                    "CommonPrefixes": [{"Prefix": "assets/"}],
                }
            if prefix == "" and kwargs.get("ContinuationToken") == "page-2":
                return {
                    "KeyCount": 1,
                    "IsTruncated": False,
                    "CommonPrefixes": [{"Prefix": "malaysia-singapore-brunei/"}],
                }
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "catalog/current.json":
                self.catalog_body = Body
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = PaginatedBackfillClient()

    R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert json.loads(client.catalog_body)["publish_versions"] == {
        "malaysia-singapore-brunei": "20260714T000000Z",
        "united-kingdom": "20260715T120000Z",
    }
    assert any(request.get("ContinuationToken") == "page-2" for request in client.list_requests)


def test_upload_backfill_lists_region_prefixes_with_delimiter_not_bucket_objects(tmp_path):
    version_root = tmp_path / "stage" / "united-kingdom" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "united-kingdom.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class DelimitedBackfillClient:
        def __init__(self):
            self.catalog_body = None
            self.list_requests = []

        def get_object(self, *, Bucket, Key):
            if Key == "united-kingdom/current.json":
                raise FileNotFoundError(Key)
            if Key == "catalog/current.json":
                raise FileNotFoundError(Key)
            if Key == "malaysia-singapore-brunei/current.json":
                return {"Body": BytesIO(b'{"schema_version":1,"publish_version":"20260714T000000Z"}')}
            raise FileNotFoundError(Key)

        def list_objects_v2(self, **kwargs):
            self.list_requests.append(kwargs)
            if kwargs["Prefix"] == "united-kingdom/20260715T120000Z/":
                return {"KeyCount": 0}
            assert kwargs["Prefix"] == ""
            assert kwargs.get("Delimiter") == "/"
            return {
                "KeyCount": 2,
                "CommonPrefixes": [
                    {"Prefix": "malaysia-singapore-brunei/"},
                    {"Prefix": "assets/"},
                ],
            }

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "catalog/current.json":
                self.catalog_body = Body
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = DelimitedBackfillClient()

    R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert json.loads(client.catalog_body)["publish_versions"] == {
        "malaysia-singapore-brunei": "20260714T000000Z",
        "united-kingdom": "20260715T120000Z",
    }
    assert client.list_requests[-1] == {
        "Bucket": "making-tracks-tiles",
        "Prefix": "",
        "MaxKeys": 1024,
        "Delimiter": "/",
    }


def test_upload_backfill_fails_closed_when_listed_region_current_is_unreadable(tmp_path):
    version_root = tmp_path / "stage" / "united-kingdom" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "united-kingdom.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class UnreadableBackfillClient:
        def __init__(self):
            self.put_keys = []

        def get_object(self, *, Bucket, Key):
            if Key == "united-kingdom/current.json":
                raise FileNotFoundError(Key)
            if Key == "catalog/current.json":
                raise FileNotFoundError(Key)
            if Key == "malaysia-singapore-brunei/current.json":
                raise RuntimeError("transient read failure")
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            if Prefix == "united-kingdom/20260715T120000Z/":
                return {"KeyCount": 0}
            if Prefix == "":
                return {"KeyCount": 1, "CommonPrefixes": [{"Prefix": "malaysia-singapore-brunei/"}]}
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            self.put_keys.append(Key)
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = UnreadableBackfillClient()

    with pytest.raises(R.CurrentPointerUnavailable, match="could not backfill current pointer"):
        R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert "catalog/current.json" not in client.put_keys


def test_upload_repairs_partial_shared_catalog_from_existing_region_currents(tmp_path):
    version_root = tmp_path / "stage" / "united-kingdom" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "united-kingdom.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class PartialCatalogBackfillClient:
        def __init__(self):
            self.catalog_body = None

        def get_object(self, *, Bucket, Key):
            if Key == "united-kingdom/current.json":
                raise FileNotFoundError(Key)
            if Key == "catalog/current.json":
                return {"Body": BytesIO(b'{"schema_version":1,"publish_versions":{"uk":"20260713T000000Z"}}')}
            if Key == "malaysia-singapore-brunei/current.json":
                return {"Body": BytesIO(b'{"schema_version":1,"publish_version":"20260714T000000Z"}')}
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            if Prefix == "united-kingdom/20260715T120000Z/":
                return {"KeyCount": 0}
            if Prefix == "":
                return {"KeyCount": 1, "CommonPrefixes": [{"Prefix": "malaysia-singapore-brunei/"}]}
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "catalog/current.json":
                self.catalog_body = Body
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = PartialCatalogBackfillClient()

    R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert json.loads(client.catalog_body) == {
        "schema_version": 1,
        "publish_versions": {
            "malaysia-singapore-brunei": "20260714T000000Z",
            "uk": "20260713T000000Z",
            "united-kingdom": "20260715T120000Z",
        },
    }


def test_upload_refreshes_stale_shared_catalog_entries_from_region_currents(tmp_path):
    version_root = tmp_path / "stage" / "united-kingdom" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "united-kingdom.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class StaleCatalogBackfillClient:
        def __init__(self):
            self.catalog_body = None

        def get_object(self, *, Bucket, Key):
            if Key == "united-kingdom/current.json":
                raise FileNotFoundError(Key)
            if Key == "catalog/current.json":
                return {
                    "Body": BytesIO(
                        b'{"schema_version":1,"publish_versions":{"malaysia-singapore-brunei":"20260701T000000Z"}}'
                    )
                }
            if Key == "malaysia-singapore-brunei/current.json":
                return {"Body": BytesIO(b'{"schema_version":1,"publish_version":"20260714T000000Z"}')}
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            if Prefix == "united-kingdom/20260715T120000Z/":
                return {"KeyCount": 0}
            if Prefix == "":
                return {"KeyCount": 1, "CommonPrefixes": [{"Prefix": "malaysia-singapore-brunei/"}]}
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "catalog/current.json":
                self.catalog_body = Body
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = StaleCatalogBackfillClient()

    R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert json.loads(client.catalog_body) == {
        "schema_version": 1,
        "publish_versions": {
            "malaysia-singapore-brunei": "20260714T000000Z",
            "united-kingdom": "20260715T120000Z",
        },
    }


def test_retry_of_live_region_repairs_missing_shared_catalog_without_reuploading_content(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10/1").mkdir(parents=True)
    (version_root / "tiles/10/1/2.json.gz").write_bytes(b"tile")
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class RepairCatalogClient:
        def __init__(self):
            self.put_keys = []
            self.head_keys = []

        def get_object(self, *, Bucket, Key):
            if Key == "uk/current.json":
                return {"Body": BytesIO(b'{"schema_version":1,"publish_version":"20260715T120000Z"}')}
            if Key == "catalog/current.json":
                raise FileNotFoundError(Key)
            raise FileNotFoundError(Key)

        def head_object(self, *, Bucket, Key):
            self.head_keys.append(Key)
            if Key == "uk/20260715T120000Z/manifest.json":
                return {}
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            if Prefix == "uk/20260715T120000Z/":
                return {"KeyCount": 1, "Contents": [{"Key": "uk/20260715T120000Z/manifest.json"}]}
            if Prefix == "":
                return {"KeyCount": 1, "CommonPrefixes": [{"Prefix": "uk/"}]}
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            self.put_keys.append(Key)
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = RepairCatalogClient()

    R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert client.put_keys == ["uk/publish.lock", "catalog/publish.lock", "catalog/current.json"]
    assert client.head_keys == ["uk/20260715T120000Z/manifest.json"]


def test_retry_of_live_region_refuses_catalog_repair_when_manifest_is_missing(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10/1").mkdir(parents=True)
    (version_root / "tiles/10/1/2.json.gz").write_bytes(b"tile")
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class MissingManifestRepairClient:
        def __init__(self):
            self.put_keys = []
            self.head_keys = []

        def get_object(self, *, Bucket, Key):
            if Key == "uk/current.json":
                return {"Body": BytesIO(b'{"schema_version":1,"publish_version":"20260715T120000Z"}')}
            if Key == "catalog/current.json":
                raise FileNotFoundError(Key)
            raise FileNotFoundError(Key)

        def head_object(self, *, Bucket, Key):
            self.head_keys.append(Key)
            if Key == "uk/20260715T120000Z/manifest.json":
                raise FileNotFoundError(Key)
            return {}

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            if Prefix == "uk/20260715T120000Z/":
                return {"KeyCount": 1, "Contents": [{"Key": "uk/20260715T120000Z/manifest.json"}]}
            if Prefix == "":
                return {"KeyCount": 1, "CommonPrefixes": [{"Prefix": "uk/"}]}
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            self.put_keys.append(Key)
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = MissingManifestRepairClient()

    with pytest.raises(R.CurrentPointerUnavailable, match="could not verify repaired manifest"):
        R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert client.head_keys == ["uk/20260715T120000Z/manifest.json"]
    assert "catalog/current.json" not in client.put_keys


def test_retry_of_live_region_uploads_registry_blob_after_catalog_repair(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10/1").mkdir(parents=True)
    (version_root / "tiles/10/1/2.json.gz").write_bytes(b"tile")
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class RepairCatalogAndRegistryClient:
        def __init__(self):
            self.puts = []
            self.head_keys = []

        def get_object(self, *, Bucket, Key):
            if Key == "uk/current.json":
                return {"Body": BytesIO(b'{"schema_version":1,"publish_version":"20260715T120000Z"}')}
            if Key == "catalog/current.json":
                raise FileNotFoundError(Key)
            raise FileNotFoundError(Key)

        def head_object(self, *, Bucket, Key):
            self.head_keys.append(Key)
            if Key == "uk/20260715T120000Z/manifest.json":
                return {}
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            if Prefix == "uk/20260715T120000Z/":
                return {"KeyCount": 1, "Contents": [{"Key": "uk/20260715T120000Z/manifest.json"}]}
            if Prefix == "":
                return {"KeyCount": 1, "CommonPrefixes": [{"Prefix": "uk/"}]}
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            self.puts.append((Bucket, Key, Body))
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = RepairCatalogAndRegistryClient()

    result = R.publish_to_r2(
        version_root,
        _layout(),
        client=client,
        upload=True,
        registry_blob=b'{"place_id":"mt1"}\n',
    )

    assert [key for _bucket, key, _body in client.puts] == [
        "uk/publish.lock",
        "catalog/publish.lock",
        "catalog/current.json",
        "registry/uk.jsonl",
    ]
    assert client.puts[-1] == ("making-tracks-state", "registry/uk.jsonl", b'{"place_id":"mt1"}\n')
    assert [op.kind for op in result.plan.ops] == ["catalog_current", "registry"]
    assert result.uploaded == 2
    assert client.head_keys == ["uk/20260715T120000Z/manifest.json"]


def test_catalog_lock_contention_does_not_block_content_or_region_current_upload(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10/1").mkdir(parents=True)
    (version_root / "tiles/10/1/2.json.gz").write_bytes(b"tile")
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class PreconditionFailed(Exception):
        response = {"Error": {"Code": "PreconditionFailed"}}

    class CatalogLockHeldClient:
        def __init__(self):
            self.put_keys = []

        def get_object(self, *, Bucket, Key):
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            self.put_keys.append(Key)
            if Key == "catalog/publish.lock":
                raise PreconditionFailed()
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = CatalogLockHeldClient()

    with pytest.raises(R.PublishLockUnavailable, match="publish lock is held"):
        R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert "uk/20260715T120000Z/manifest.json" in client.put_keys
    assert "uk/current.json" in client.put_keys
    assert client.put_keys.index("uk/current.json") < client.put_keys.index("catalog/publish.lock")
    assert "catalog/current.json" not in client.put_keys


def test_upload_merges_shared_current_catalog_without_dropping_other_regions(tmp_path):
    version_root = tmp_path / "stage" / "united-kingdom" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "united-kingdom.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class ExistingCatalogUploadClient:
        def __init__(self):
            self.catalog_body = None

        def get_object(self, *, Bucket, Key):
            if Key == "united-kingdom/current.json":
                raise FileNotFoundError(Key)
            if Key == "catalog/current.json":
                return {
                    "Body": BytesIO(
                        b'{"schema_version":1,"publish_versions":{"malaysia-singapore-brunei":"20260714T000000Z"}}'
                    )
                }
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key == "catalog/current.json":
                self.catalog_body = Body
            if Key == "united-kingdom/publish.lock":
                return {"ETag": '"lock-etag"'}
            return {"ETag": '"content-etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = ExistingCatalogUploadClient()

    R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert json.loads(client.catalog_body) == {
        "schema_version": 1,
        "publish_versions": {
            "malaysia-singapore-brunei": "20260714T000000Z",
            "united-kingdom": "20260715T120000Z",
        },
    }


@pytest.mark.parametrize(
    "catalog_body",
    [
        b'{"schema_version":1}',
        b'{"schema_version":1,"publish_versions":{},"extra":true}',
        b'{"schema_version":2,"publish_versions":{}}',
        b'{"schema_version":1,"publish_versions":[]}',
        b'{"schema_version":1,"publish_versions":{"bad region":"20260714T000000Z"}}',
        b'{"schema_version":1,"publish_versions":{"uk":"latest"}}',
    ],
)
def test_upload_rejects_malformed_shared_current_catalog_after_fulfillable_region_current(
    tmp_path, catalog_body
):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class MalformedCatalogClient:
        def __init__(self):
            self.put_keys = []

        def get_object(self, *, Bucket, Key):
            if Key == "uk/current.json":
                raise FileNotFoundError(Key)
            if Key == "catalog/current.json":
                return {"Body": BytesIO(catalog_body)}
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            self.put_keys.append(Key)
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    client = MalformedCatalogClient()

    with pytest.raises(R.CurrentPointerUnavailable):
        R.publish_to_r2(version_root, _layout(), client=client, upload=True)

    assert "uk/current.json" in client.put_keys
    assert "catalog/publish.lock" in client.put_keys
    assert "catalog/current.json" not in client.put_keys


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


def test_live_current_repairs_catalog_and_unavailable_current_fails_closed(tmp_path):
    version_root = tmp_path / "stage" / "uk" / "20260715T120000Z"
    (version_root / "tiles/10").mkdir(parents=True)
    (version_root / "uk.pmtiles").write_bytes(b"basemap")
    (version_root / "manifest.json").write_text("{}")

    class LiveCurrentClient:
        def __init__(self):
            self.puts = []
            self.head_keys = []

        def get_object(self, *, Bucket, Key):
            if Key == "uk/current.json":
                return {"Body": BytesIO(b'{"schema_version":1,"publish_version":"20260715T120000Z"}')}
            if Key == "catalog/current.json":
                raise FileNotFoundError(Key)
            raise FileNotFoundError(Key)

        def head_object(self, *, Bucket, Key):
            self.head_keys.append(Key)
            if Key == "uk/20260715T120000Z/manifest.json":
                return {}
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            if Prefix == "":
                return {"KeyCount": 1, "CommonPrefixes": [{"Prefix": "uk/"}]}
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            self.puts.append(Key)
            return {"ETag": '"etag"'}

        def delete_object(self, *, Bucket, Key, IfMatch=None):
            pass

    live_client = LiveCurrentClient()
    R.publish_to_r2(version_root, _layout(), client=live_client, upload=True)
    assert live_client.puts == ["uk/publish.lock", "catalog/publish.lock", "catalog/current.json"]
    assert live_client.head_keys == ["uk/20260715T120000Z/manifest.json"]

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
            if Key in {"uk/current.json", "catalog/current.json"}:
                raise FileNotFoundError(Key)
            return {"Body": BytesIO(b'{"expires_at":0}'), "ETag": '"stale-etag"'}

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
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

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
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

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
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
    (version_root / "manifest.json").write_text("{}")

    class FailingUploadClient:
        def __init__(self):
            self.tile_body = None
            self.deleted = []

        def get_object(self, *, Bucket, Key):
            raise FileNotFoundError(Key)

        def list_objects_v2(self, *, Bucket, Prefix, MaxKeys, Delimiter=None):
            return {"KeyCount": 0}

        def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
            if Key in {"uk/publish.lock", "catalog/publish.lock"}:
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
