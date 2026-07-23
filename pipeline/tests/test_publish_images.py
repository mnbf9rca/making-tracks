import hashlib
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from mt_pipeline import store
from mt_pipeline.publish import images
from mt_pipeline.publish import image_worker


def _fixture_license_url(license_short_name: str) -> str:
    normalized = license_short_name.casefold().replace(" ", "-")
    normalized = normalized.replace("cc-", "").replace("-4.0", "/4.0/")
    normalized = normalized.replace("-3.0", "/3.0/")
    normalized = normalized.replace("-2.5", "/2.5/")
    normalized = normalized.replace("-2.1", "/2.1/")
    normalized = normalized.replace("-2.0", "/2.0/")
    normalized = normalized.replace("-1.0", "/1.0/")
    if normalized in {"0", "cc0"}:
        return "https://creativecommons.org/publicdomain/zero/1.0/"
    if normalized in {"public-domain", "pd"}:
        return "https://creativecommons.org/publicdomain/mark/1.0/"
    return f"https://creativecommons.org/licenses/{normalized}"


def _expected_license_url_for_code(code: str) -> str:
    if code == "PD":
        return "https://creativecommons.org/publicdomain/mark/1.0/"
    if code == "CC0-1.0":
        return "https://creativecommons.org/publicdomain/zero/1.0/"
    family = code.removeprefix("CC-").casefold()
    parts = family.rsplit("-", 1)
    if len(parts) == 2 and parts[1] in {"igo", "de", "fr", "jp", "es"}:
        family, port = parts
    else:
        family, port = family, None
    kind, version = family.rsplit("-", 1)
    version = version.replace(".", ".")
    port_suffix = f"{port}/" if port is not None else ""
    return f"https://creativecommons.org/licenses/{kind}/{version}/{port_suffix}"


def _imageinfo(
    *,
    license_short_name,
    license_value=None,
    include_license=True,
    license_url=None,
    artist="Jane Example",
    mime="image/jpeg",
    title="File:Fort.jpg",
):
    extmetadata = {
        "LicenseShortName": {"value": license_short_name},
        "LicenseUrl": {
            "value": license_url or _fixture_license_url(license_short_name)
        },
        "Artist": {"value": artist},
    }
    if include_license:
        extmetadata["License"] = {"value": license_value or license_short_name}
    return {
        "query": {
            "pages": {
                "123": {
                    "title": title,
                    "imageinfo": [
                        {
                            "url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
                            "mime": mime,
                            "extmetadata": extmetadata,
                        }
                    ],
                }
            }
        }
    }


def test_recover_commons_filename_from_upload_url():
    assert (
        images.commons_filename_from_upload_url(
            "https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort%20Knox.jpg"
        )
        == "Fort Knox.jpg"
    )
    assert (
        images.commons_prescaled_url("Folder/Fort Knox.jpg")
        == "https://commons.wikimedia.org/wiki/Special:FilePath/Folder%2FFort%20Knox.jpg?width=768"
    )
    assert (
        images.commons_filename_from_upload_url(
            "https://commons.wikimedia.org/wiki/Special:FilePath/Fort%20Knox.jpg"
        )
        == "Fort Knox.jpg"
    )


def test_image_candidates_use_qid_sitelink_wikipedia_row_for_wd_only_place(tmp_path):
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)
    conn.execute(
        """
        INSERT INTO source_records
            (region, source, source_ref, name, lat, lon, props_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "malaysia-singapore-brunei",
            "wp",
            "wp:12345",
            "QID Article",
            0.0,
            0.0,
            json.dumps(
                {
                    "wikidata": "Q42",
                    "image": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
                },
                sort_keys=True,
            ),
            "r1",
        ),
    )
    conn.commit()

    candidates = images.candidates_from_source_records(
        conn,
        "malaysia-singapore-brunei",
        [
            {
                "place_id": "mt1_00000000000000000000000001",
                "lat": 3.1,
                "lon": 101.7,
                "source_refs": ["wd:Q42"],
            }
        ],
    )

    assert candidates == [
        images.ImageCandidate(
            place_id="mt1_00000000000000000000000001",
            lat=3.1,
            lon=101.7,
            image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
        )
    ]


@pytest.mark.parametrize(
    "license_short_name,expected",
    [
        ("Public domain", "PD"),
        ("CC0", "CC0-1.0"),
        ("CC BY 1.0", "CC-BY-1.0"),
        ("CC BY 2.0", "CC-BY-2.0"),
        ("CC BY 2.5", "CC-BY-2.5"),
        ("CC BY 3.0", "CC-BY-3.0"),
        ("CC BY 4.0", "CC-BY-4.0"),
        ("cc-by-2.0-fr", "CC-BY-2.0-FR"),
        ("CC BY-SA 1.0", "CC-BY-SA-1.0"),
        ("CC BY-SA 2.0", "CC-BY-SA-2.0"),
        ("CC BY-SA 2.5", "CC-BY-SA-2.5"),
        ("CC BY-SA 3.0", "CC-BY-SA-3.0"),
        ("CC BY-SA 4.0", "CC-BY-SA-4.0"),
        ("cc-by-sa-3.0-de", "CC-BY-SA-3.0-DE"),
        ("cc-by-sa-3.0-igo", "CC-BY-SA-3.0-IGO"),
    ],
)
def test_commons_license_allowlist_includes_by_and_by_sa_without_nc_or_nd(
    license_short_name, expected
):
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(
            license_short_name=license_short_name,
            license_url=_expected_license_url_for_code(expected),
        )
    )

    assert decision.accepted is True
    assert decision.metadata.attribution.license_code == expected
    assert decision.metadata.attribution.modified is True


@pytest.mark.parametrize(
    "license_short_name",
    [
        "CC BY-NC 4.0",
        "cc-by-nc-3.0-es",
        "CC BY-NC-SA 4.0",
        "cc-by-nc-sa-3.0-igo",
    ],
)
def test_commons_license_rejects_noncommercial_family(license_short_name):
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(license_short_name=license_short_name)
    )

    assert decision.accepted is False
    assert decision.reason == "license_nc"


def test_commons_license_uses_exact_older_by_sa_deed_url():
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(license_short_name="cc-by-sa-3.0")
    )

    assert decision.accepted is True
    assert decision.metadata.attribution.license_code == "CC-BY-SA-3.0"
    assert decision.metadata.attribution.license_url == (
        "https://creativecommons.org/licenses/by-sa/3.0/"
    )


def test_commons_license_uses_exact_ported_deed_url():
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(
            license_short_name="cc-by-sa-3.0-de",
            license_url="https://creativecommons.org/licenses/by-sa/3.0/de/",
        )
    )

    assert decision.accepted is True
    assert decision.metadata.attribution.license_code == "CC-BY-SA-3.0-DE"
    assert decision.metadata.attribution.license_url == (
        "https://creativecommons.org/licenses/by-sa/3.0/de/"
    )


def test_commons_license_accepts_deed_url_without_trailing_slash():
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(
            license_short_name="cc-by-sa-3.0",
            license_url="https://creativecommons.org/licenses/by-sa/3.0",
        )
    )

    assert decision.accepted is True
    assert decision.metadata.attribution.license_url == (
        "https://creativecommons.org/licenses/by-sa/3.0/"
    )


@pytest.mark.parametrize(
    "license_url",
    [
        "https://creativecommons.org/licenses/by/4.0/deed.en",
        "https://creativecommons.org/licenses/by/4.0/legalcode",
    ],
)
def test_commons_license_rejects_noncanonical_deed_urls(license_url):
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(
            license_short_name="CC BY 4.0",
            license_url=license_url,
        )
    )

    assert decision.accepted is False
    assert decision.reason in {"license_url_invalid", "license_url_mismatch"}


def test_commons_license_canonicalizes_http_creative_commons_url():
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(
            license_short_name="CC BY 4.0",
            license_url="http://creativecommons.org/licenses/by/4.0/",
        )
    )

    assert decision.accepted is True
    assert decision.metadata.attribution.license_url == (
        "https://creativecommons.org/licenses/by/4.0/"
    )


def test_commons_license_rejects_deed_url_for_different_port():
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(
            license_short_name="cc-by-sa-3.0-de",
            license_url="https://creativecommons.org/licenses/by-sa/3.0/",
        )
    )

    assert decision.accepted is False
    assert decision.reason == "license_url_mismatch"


def test_public_domain_license_emits_canonical_creative_commons_mark_url():
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(license_short_name="Public domain")
    )

    assert decision.accepted is True
    assert decision.metadata.attribution.license_url == (
        "https://creativecommons.org/publicdomain/mark/1.0/"
    )


def test_commons_license_classifies_only_machine_readable_license_field():
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(license_short_name="CC BY 4.0", include_license=False)
    )

    assert decision.accepted is False
    assert decision.reason == "license_missing"


@pytest.mark.parametrize("license_short_name", ["CC BY-ND 4.0", "GFDL", "", "Fair use"])
def test_commons_license_filter_rejects_nd_gfdl_missing_and_fair_use(license_short_name):
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(license_short_name=license_short_name)
    )

    assert decision.accepted is False
    assert decision.reason in {"license_nd", "license_unaccepted", "license_missing"}


def test_commons_by_license_requires_creator_and_strips_artist_html():
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(license_short_name="CC BY 4.0", artist="<b>Jane</b><br>Example")
    )

    assert decision.accepted is True
    assert decision.metadata.attribution.creator == "Jane Example"

    rejected = images.metadata_from_commons_imageinfo(
        _imageinfo(license_short_name="CC BY 4.0", artist="  ")
    )
    assert rejected.accepted is False
    assert rejected.reason == "creator_missing"


def test_commons_text_fields_reject_control_bidi_and_oversize_values():
    rejected = images.metadata_from_commons_imageinfo(
        _imageinfo(license_short_name="CC BY 4.0", artist="Jane\u202eExample")
    )
    assert rejected.accepted is False
    assert rejected.reason == "creator_unsafe"

    rejected = images.metadata_from_commons_imageinfo(
        _imageinfo(license_short_name="CC BY 4.0", artist="x" * 257)
    )
    assert rejected.accepted is False
    assert rejected.reason == "creator_unsafe"

    rejected = images.metadata_from_commons_imageinfo(
        _imageinfo(
            license_short_name="CC BY 4.0\u202e",
            license_value="cc-by-4.0",
        )
    )
    assert rejected.accepted is False
    assert rejected.reason == "license_name_unsafe"


def test_commons_source_url_quotes_path_separators_and_rejects_fragments():
    accepted = images.metadata_from_commons_imageinfo(
        _imageinfo(
            license_short_name="CC BY 4.0",
            license_value="cc-by-4.0",
            title="File:Folder/Fort.jpg",
        )
    )

    assert accepted.accepted is True
    assert accepted.metadata.attribution.source_url == (
        "https://commons.wikimedia.org/wiki/File:Folder%2FFort.jpg"
    )

    for bad_title in ["File:../Fort.jpg", "File:Fort.jpg?x=1", "File:Fort.jpg#fragment"]:
        rejected = images.metadata_from_commons_imageinfo(
            _imageinfo(
                license_short_name="CC BY 4.0",
                license_value="cc-by-4.0",
                title=bad_title,
            )
        )
        assert rejected.accepted is False
        assert rejected.reason == "source_url_invalid"


def test_emit_image_indexes_groups_by_tile_and_counts_thumb_bytes(tmp_path):
    records = [
        images.PlaceImage(
            place_id="mt1_00000000000000000000000001",
            lat=51.5,
            lon=-0.1,
            thumb_sha256="b" * 64,
            thumb_bytes=b"thumb",
            width=320,
            height=240,
            attribution=images.ImageAttribution(
                creator="Jane Example",
                license_code="CC-BY-4.0",
                license_name="Creative Commons Attribution 4.0",
                license_url="https://creativecommons.org/licenses/by/4.0/",
                source_url="https://commons.wikimedia.org/wiki/File:Fort.jpg",
                modified=True,
            ),
        )
    ]

    index_arts, thumb_arts = images.emit_image_artifacts(records)

    assert len(index_arts) == 1
    assert len(thumb_arts) == 1
    payload = json.loads(index_arts[0].json_bytes)
    assert payload["schema_version"] == 1
    assert payload["min_reader_version"] == 1
    assert payload["z"] == 10
    assert payload["places"][0]["place_id"] == records[0].place_id
    assert payload["places"][0]["bytes"] == len(records[0].thumb_bytes)
    assert index_arts[0].byte_len == len(index_arts[0].json_bytes)
    assert thumb_arts[0].byte_len == len(b"thumb")


def test_emit_image_artifacts_accepts_emitted_public_domain_mark_url_through_schema():
    records = [
        images.PlaceImage(
            place_id="mt1_00000000000000000000000001",
            lat=51.5,
            lon=-0.1,
            thumb_sha256=hashlib.sha256(b"thumb").hexdigest(),
            thumb_bytes=b"thumb",
            width=320,
            height=240,
            attribution=images.ImageAttribution(
                creator=None,
                license_code="PD",
                license_name="Public domain",
                license_url="https://creativecommons.org/publicdomain/mark/1.0/",
                source_url="https://commons.wikimedia.org/wiki/File:Fort.jpg",
                modified=True,
            ),
        )
    ]

    index_arts, thumb_arts = images.emit_image_artifacts(records)

    assert len(index_arts) == 1
    assert len(thumb_arts) == 1
    payload = json.loads(index_arts[0].json_bytes)
    assert payload["places"][0]["attribution"]["license_url"] == (
        "https://creativecommons.org/publicdomain/mark/1.0/"
    )


def test_select_image_candidates_is_score_ordered_tier_agnostic_and_deterministic():
    rows = [
        (
            {
                "place_id": "mt1_00000000000000000000000003",
                "score": 0.5,
                "tier": 4,
            },
            images.ImageCandidate(
                place_id="mt1_00000000000000000000000003",
                lat=1.0,
                lon=1.0,
                image_url="https://commons.wikimedia.org/wiki/Special:FilePath/C.jpg",
            ),
        ),
        (
            {
                "place_id": "mt1_00000000000000000000000001",
                "score": 0.6,
                "tier": 4,
            },
            images.ImageCandidate(
                place_id="mt1_00000000000000000000000001",
                lat=1.0,
                lon=1.0,
                image_url="https://commons.wikimedia.org/wiki/Special:FilePath/A.jpg",
            ),
        ),
        (
            {
                "place_id": "mt1_00000000000000000000000002",
                "score": 0.6,
                "tier": 3,
            },
            images.ImageCandidate(
                place_id="mt1_00000000000000000000000002",
                lat=1.0,
                lon=1.0,
                image_url="https://commons.wikimedia.org/wiki/Special:FilePath/B.jpg",
            ),
        ),
    ]

    selected = images.select_image_candidates(rows, limit=2)

    assert [candidate.place_id for candidate in selected] == [
        "mt1_00000000000000000000000002",
        "mt1_00000000000000000000000001",
    ]


def test_build_place_images_fetches_filters_downloads_and_caches_thumb(tmp_path, monkeypatch):
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
    )
    downloads = []
    metadata_calls = []
    transcodes = []

    def fake_imageinfo(filenames, **_kwargs):
        metadata_calls.append(list(filenames))
        return {
            filename: _imageinfo(license_short_name="CC BY 4.0")
            for filename in filenames
        }

    monkeypatch.setattr(images, "fetch_commons_imageinfo_batch", fake_imageinfo)

    def fake_download(url, dest, **kwargs):
        downloads.append((url, Path(dest).name, kwargs))
        Path(dest).write_bytes(b"raw-image")
        return SimpleNamespace(size=9, status="downloaded")

    monkeypatch.setattr(images.fetch, "conditional_get_to_file", fake_download, raising=False)
    monkeypatch.setattr(
        images.fetch,
        "get_to_file",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("image downloads must use conditional_get_to_file")
        ),
    )
    def fake_transcode(path):
        transcodes.append(path)
        return images.ThumbTranscode(webp_bytes=b"webp", width=320, height=240)

    monkeypatch.setattr(images, "transcode_to_webp_thumb", fake_transcode)

    out = images.build_place_images([candidate], cache_dir=tmp_path)

    assert len(out) == 1
    assert out[0].place_id == candidate.place_id
    assert out[0].thumb_sha256 == "a57bb082e728a0cdce930ecfcccf4510a3a247be5f322b09b3a971a3f5ed34f8"
    assert out[0].thumb_bytes == b"webp"
    assert out[0].attribution.creator == "Jane Example"
    assert downloads == [
        (
            "https://commons.wikimedia.org/wiki/Special:FilePath/Fort.jpg?width=768",
            "mt1_00000000000000000000000001.source",
            {
                "expected_hosts": {"commons.wikimedia.org", "upload.wikimedia.org"},
                "headers": {"User-Agent": images.USER_AGENT},
                "max_bytes": images.MAX_PRESCALED_IMAGE_BYTES,
                "store": images.fetch.ConditionalFetchStore(
                    tmp_path / "conditional-fetch.json"
                ),
            },
        )
    ]
    assert metadata_calls == [["Fort.jpg"]]
    assert len(transcodes) == 1

    out = images.build_place_images([candidate], cache_dir=tmp_path)

    assert len(out) == 1
    assert out[0].thumb_bytes == b"webp"
    assert metadata_calls == [["Fort.jpg"]]
    assert len(downloads) == 1
    assert len(transcodes) == 1


def test_build_place_images_from_audit_reencodes_originals_without_fetching_metadata(
    tmp_path, monkeypatch, capsys
):
    old_thumb = b"audited-thumb"
    old_thumb_sha = hashlib.sha256(old_thumb).hexdigest()
    new_thumb = b"new-q50-256-thumb"
    new_thumb_sha = hashlib.sha256(new_thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    old_thumb_path = cache / "thumbs" / old_thumb_sha[:2] / f"{old_thumb_sha}.webp"
    old_thumb_path.parent.mkdir(parents=True)
    old_thumb_path.write_bytes(old_thumb)
    original_path = cache / "raw" / "mt1_00000000000000000000000001.source"
    original_path.parent.mkdir(parents=True)
    original_path.write_bytes(b"original-image")
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
                "thumb_sha256": old_thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": "Jane Example",
                    "license_code": "CC-BY-4.0",
                    "license_name": "Creative Commons Attribution 4.0",
                    "license_url": "https://creativecommons.org/licenses/by/4.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidates = [
        images.ImageCandidate(
            place_id="mt1_00000000000000000000000001",
            lat=51.5,
            lon=-0.1,
            image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
        ),
        images.ImageCandidate(
            place_id="mt1_00000000000000000000000002",
            lat=51.6,
            lon=-0.2,
            image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Missing.jpg",
        ),
    ]

    monkeypatch.setattr(
        images,
        "fetch_commons_imageinfo_batch",
        lambda _filenames: (_ for _ in ()).throw(AssertionError("metadata fetched")),
    )
    monkeypatch.setattr(
        images.fetch,
        "get_to_file",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(AssertionError("downloaded")),
    )
    transcodes = []

    def fake_transcode(path):
        transcodes.append(path)
        return images.ThumbTranscode(webp_bytes=new_thumb, width=256, height=192)

    monkeypatch.setattr(images, "transcode_to_webp_thumb", fake_transcode)

    out = images.build_place_images_from_audit(
        candidates,
        completed_jsonl=completed,
        audited_cache_dir=cache,
    )

    assert [(item.place_id, item.thumb_sha256, item.thumb_bytes) for item in out] == [
        ("mt1_00000000000000000000000001", new_thumb_sha, new_thumb)
    ]
    assert transcodes == [original_path]
    assert old_thumb_path.read_bytes() == old_thumb
    assert (cache / "thumbs" / new_thumb_sha[:2] / f"{new_thumb_sha}.webp").read_bytes() == new_thumb
    assert "AUDITED_IMAGE_REENCODE candidates=2 selected=1 missing_skipped=1 audited_total=1" in capsys.readouterr().out

    with pytest.raises(images.AuditedImageReuseError, match="missing 1 of 2"):
        images.build_place_images_from_audit(
            candidates,
            completed_jsonl=completed,
            audited_cache_dir=cache,
            require_complete=True,
        )


def test_build_place_images_from_audit_reuses_memoized_unchanged_original(
    tmp_path, monkeypatch, capsys
):
    retained_thumb = b"audited-thumb"
    retained_thumb_sha = hashlib.sha256(retained_thumb).hexdigest()
    reencoded_thumb = b"new-q50-256-thumb"
    reencoded_thumb_sha = hashlib.sha256(reencoded_thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    retained_thumb_path = cache / "thumbs" / retained_thumb_sha[:2] / f"{retained_thumb_sha}.webp"
    retained_thumb_path.parent.mkdir(parents=True)
    retained_thumb_path.write_bytes(retained_thumb)
    original_path = cache / "raw" / "mt1_00000000000000000000000001.source"
    original_path.parent.mkdir(parents=True)
    original_path.write_bytes(b"original-image")
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
                "thumb_sha256": retained_thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": "Jane Example",
                    "license_code": "CC-BY-4.0",
                    "license_name": "Creative Commons Attribution 4.0",
                    "license_url": "https://creativecommons.org/licenses/by/4.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )
    transcodes = []

    def fake_transcode(path):
        transcodes.append(path)
        return images.ThumbTranscode(webp_bytes=reencoded_thumb, width=256, height=192)

    monkeypatch.setattr(images, "transcode_to_webp_thumb", fake_transcode)

    first = images.build_place_images_from_audit(
        [candidate],
        completed_jsonl=completed,
        audited_cache_dir=cache,
    )

    assert [(item.thumb_sha256, item.thumb_bytes, item.width, item.height) for item in first] == [
        (reencoded_thumb_sha, reencoded_thumb, 256, 192)
    ]
    assert transcodes == [original_path]

    monkeypatch.setattr(
        images,
        "transcode_to_webp_thumb",
        lambda _path: pytest.fail("unchanged audited image should reuse the memoized thumb"),
    )

    second = images.build_place_images_from_audit(
        [candidate],
        completed_jsonl=completed,
        audited_cache_dir=cache,
    )

    assert [(item.thumb_sha256, item.thumb_bytes, item.width, item.height) for item in second] == [
        (reencoded_thumb_sha, reencoded_thumb, 256, 192)
    ]
    log = capsys.readouterr().out
    assert "memo_hits=1 memo_misses=0 memo_verification_failures=0 reencoded=0" in log
    assert "elapsed=" in log


def test_audited_thumb_encoder_identity_includes_runtime_encoder_versions():
    identity = images.AUDITED_THUMB_ENCODER_IDENTITY

    assert f"max_edge={images.image_worker.THUMB_MAX_EDGE}" in identity
    assert f"quality={images.image_worker.THUMB_WEBP_QUALITY}" in identity
    assert "pillow=" in identity
    assert "webp=" in identity


def test_build_place_images_from_audit_reencodes_when_original_hash_changes(
    tmp_path, monkeypatch
):
    retained_thumb = b"audited-thumb"
    retained_thumb_sha = hashlib.sha256(retained_thumb).hexdigest()
    first_thumb = b"first-thumb"
    first_thumb_sha = hashlib.sha256(first_thumb).hexdigest()
    second_thumb = b"second-thumb"
    second_thumb_sha = hashlib.sha256(second_thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    retained_thumb_path = cache / "thumbs" / retained_thumb_sha[:2] / f"{retained_thumb_sha}.webp"
    retained_thumb_path.parent.mkdir(parents=True)
    retained_thumb_path.write_bytes(retained_thumb)
    original_path = cache / "raw" / "mt1_00000000000000000000000001.source"
    original_path.parent.mkdir(parents=True)
    original_path.write_bytes(b"original-image-v1")
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
                "thumb_sha256": retained_thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": "Jane Example",
                    "license_code": "CC-BY-4.0",
                    "license_name": "Creative Commons Attribution 4.0",
                    "license_url": "https://creativecommons.org/licenses/by/4.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )
    thumbs = iter([first_thumb, second_thumb])
    transcodes = []

    def fake_transcode(path):
        transcodes.append(path.read_bytes())
        return images.ThumbTranscode(webp_bytes=next(thumbs), width=256, height=192)

    monkeypatch.setattr(images, "transcode_to_webp_thumb", fake_transcode)

    first = images.build_place_images_from_audit(
        [candidate],
        completed_jsonl=completed,
        audited_cache_dir=cache,
    )
    original_path.write_bytes(b"original-image-v2")
    second = images.build_place_images_from_audit(
        [candidate],
        completed_jsonl=completed,
        audited_cache_dir=cache,
    )

    assert [item.thumb_sha256 for item in first] == [first_thumb_sha]
    assert [item.thumb_sha256 for item in second] == [second_thumb_sha]
    assert transcodes == [b"original-image-v1", b"original-image-v2"]


def test_build_place_images_from_audit_reencodes_when_encoder_identity_changes(
    tmp_path, monkeypatch
):
    retained_thumb = b"audited-thumb"
    retained_thumb_sha = hashlib.sha256(retained_thumb).hexdigest()
    stale_thumb = b"stale-memo-thumb"
    stale_thumb_sha = hashlib.sha256(stale_thumb).hexdigest()
    new_thumb = b"new-encoder-thumb"
    new_thumb_sha = hashlib.sha256(new_thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    retained_thumb_path = cache / "thumbs" / retained_thumb_sha[:2] / f"{retained_thumb_sha}.webp"
    retained_thumb_path.parent.mkdir(parents=True)
    retained_thumb_path.write_bytes(retained_thumb)
    stale_thumb_path = cache / "thumbs" / stale_thumb_sha[:2] / f"{stale_thumb_sha}.webp"
    stale_thumb_path.parent.mkdir(parents=True)
    stale_thumb_path.write_bytes(stale_thumb)
    original_path = cache / "raw" / "mt1_00000000000000000000000001.source"
    original_path.parent.mkdir(parents=True)
    original_bytes = b"original-image"
    original_path.write_bytes(original_bytes)
    raw_sha = hashlib.sha256(original_bytes).hexdigest()
    (cache / images.AUDITED_THUMB_MEMO_FILENAME).write_text(
        json.dumps(
            {
                "encoder_identity": "old-encoder",
                "entries": {
                    raw_sha: {
                        "height": 192,
                        "thumb_sha256": stale_thumb_sha,
                        "width": 256,
                    }
                },
                "schema_version": images.AUDITED_THUMB_MEMO_SCHEMA_VERSION,
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
                "thumb_sha256": retained_thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": "Jane Example",
                    "license_code": "CC-BY-4.0",
                    "license_name": "Creative Commons Attribution 4.0",
                    "license_url": "https://creativecommons.org/licenses/by/4.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )
    transcodes = []

    def fake_transcode(path):
        transcodes.append(path)
        return images.ThumbTranscode(webp_bytes=new_thumb, width=256, height=192)

    monkeypatch.setattr(images, "transcode_to_webp_thumb", fake_transcode)

    out = images.build_place_images_from_audit(
        [candidate],
        completed_jsonl=completed,
        audited_cache_dir=cache,
    )

    assert [item.thumb_sha256 for item in out] == [new_thumb_sha]
    assert transcodes == [original_path]


def test_build_place_images_from_audit_reencodes_when_memo_thumb_hash_mismatches(
    tmp_path, monkeypatch, capsys
):
    retained_thumb = b"audited-thumb"
    retained_thumb_sha = hashlib.sha256(retained_thumb).hexdigest()
    bad_thumb_sha = hashlib.sha256(b"expected-memo-thumb").hexdigest()
    new_thumb = b"new-valid-thumb"
    new_thumb_sha = hashlib.sha256(new_thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    retained_thumb_path = cache / "thumbs" / retained_thumb_sha[:2] / f"{retained_thumb_sha}.webp"
    retained_thumb_path.parent.mkdir(parents=True)
    retained_thumb_path.write_bytes(retained_thumb)
    bad_thumb_path = cache / "thumbs" / bad_thumb_sha[:2] / f"{bad_thumb_sha}.webp"
    bad_thumb_path.parent.mkdir(parents=True)
    bad_thumb_path.write_bytes(b"tampered-memo-thumb")
    original_path = cache / "raw" / "mt1_00000000000000000000000001.source"
    original_path.parent.mkdir(parents=True)
    original_bytes = b"original-image"
    original_path.write_bytes(original_bytes)
    raw_sha = hashlib.sha256(original_bytes).hexdigest()
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
                "thumb_sha256": retained_thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": "Jane Example",
                    "license_code": "CC-BY-4.0",
                    "license_name": "Creative Commons Attribution 4.0",
                    "license_url": "https://creativecommons.org/licenses/by/4.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    audited_row = json.loads(completed.read_text(encoding="utf-8"))
    audited_row_sha = hashlib.sha256(
        json.dumps(audited_row, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    (cache / images.AUDITED_THUMB_MEMO_FILENAME).write_text(
        json.dumps(
            {
                "encoder_identity": images.AUDITED_THUMB_ENCODER_IDENTITY,
                "entries": {
                    raw_sha: {
                        "audited_row_sha256": audited_row_sha,
                        "byte_len": len(b"expected-memo-thumb"),
                        "height": 192,
                        "thumb_sha256": bad_thumb_sha,
                        "width": 256,
                    }
                },
                "schema_version": images.AUDITED_THUMB_MEMO_SCHEMA_VERSION,
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )
    transcodes = []

    def fake_transcode(path):
        transcodes.append(path)
        return images.ThumbTranscode(webp_bytes=new_thumb, width=256, height=192)

    monkeypatch.setattr(images, "transcode_to_webp_thumb", fake_transcode)

    out = images.build_place_images_from_audit(
        [candidate],
        completed_jsonl=completed,
        audited_cache_dir=cache,
    )

    assert [item.thumb_sha256 for item in out] == [new_thumb_sha]
    assert transcodes == [original_path]
    assert "memo_verification_failures=1" in capsys.readouterr().out


def test_build_place_images_from_audit_requires_original_for_reencode(tmp_path):
    thumb_sha = hashlib.sha256(b"old-thumb").hexdigest()
    cache = tmp_path / "audit-cache"
    thumb_path = cache / "thumbs" / thumb_sha[:2] / f"{thumb_sha}.webp"
    thumb_path.parent.mkdir(parents=True)
    thumb_path.write_bytes(b"old-thumb")
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
                "thumb_sha256": thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": None,
                    "license_code": "CC0-1.0",
                    "license_name": "CC0",
                    "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )

    with pytest.raises(images.AuditedImageReuseError, match="referenced original missing"):
        images.build_place_images_from_audit(
            [candidate],
            completed_jsonl=completed,
            audited_cache_dir=cache,
        )


def test_build_place_images_from_audit_requires_retained_audited_thumb(tmp_path):
    old_thumb_sha = hashlib.sha256(b"old-thumb").hexdigest()
    cache = tmp_path / "audit-cache"
    original_path = cache / "raw" / "mt1_00000000000000000000000001.source"
    original_path.parent.mkdir(parents=True)
    original_path.write_bytes(b"original-image")
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
                "thumb_sha256": old_thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": None,
                    "license_code": "CC0-1.0",
                    "license_name": "CC0",
                    "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )

    with pytest.raises(images.AuditedImageReuseError, match="referenced thumb missing"):
        images.build_place_images_from_audit(
            [candidate],
            completed_jsonl=completed,
            audited_cache_dir=cache,
        )


def test_build_place_images_from_audit_rejects_candidate_image_url_drift(tmp_path):
    old_thumb = b"old-thumb"
    old_thumb_sha = hashlib.sha256(old_thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    old_thumb_path = cache / "thumbs" / old_thumb_sha[:2] / f"{old_thumb_sha}.webp"
    old_thumb_path.parent.mkdir(parents=True)
    old_thumb_path.write_bytes(old_thumb)
    original_path = cache / "raw" / "mt1_00000000000000000000000001.source"
    original_path.parent.mkdir(parents=True)
    original_path.write_bytes(b"original-image")
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Audited.jpg",
                "thumb_sha256": old_thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": None,
                    "license_code": "CC0-1.0",
                    "license_name": "CC0",
                    "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Audited.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Current.jpg",
    )

    with pytest.raises(images.AuditedImageReuseError, match="image_url drift"):
        images.build_place_images_from_audit(
            [candidate],
            completed_jsonl=completed,
            audited_cache_dir=cache,
        )


def test_build_place_images_from_audit_requires_image_url_binding(tmp_path, monkeypatch):
    old_thumb = b"old-thumb"
    old_thumb_sha = hashlib.sha256(old_thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    old_thumb_path = cache / "thumbs" / old_thumb_sha[:2] / f"{old_thumb_sha}.webp"
    old_thumb_path.parent.mkdir(parents=True)
    old_thumb_path.write_bytes(old_thumb)
    original_path = cache / "raw" / "mt1_00000000000000000000000001.source"
    original_path.parent.mkdir(parents=True)
    original_path.write_bytes(b"original-image")
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "thumb_sha256": old_thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": None,
                    "license_code": "CC0-1.0",
                    "license_name": "CC0",
                    "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )
    monkeypatch.setattr(
        images,
        "transcode_to_webp_thumb",
        lambda _path: images.ThumbTranscode(webp_bytes=b"new-thumb", width=256, height=192),
    )

    with pytest.raises(images.AuditedImageReuseError, match="image_url is required"):
        images.build_place_images_from_audit(
            [candidate],
            completed_jsonl=completed,
            audited_cache_dir=cache,
        )


@pytest.mark.parametrize(
    "attribution_patch,match",
    [
        ({"creator": None}, "creator"),
        ({"modified": False}, "modified"),
        ({"source_url": "https://example.com/wiki/File:Example.jpg"}, "source_url"),
        ({"source_url": "https://commons.wikimedia.org/wiki/File:Folder/Example.jpg"}, "source_url"),
    ],
)
def test_build_place_images_from_audit_rejects_rows_the_image_schema_would_reject(
    tmp_path, attribution_patch, match
):
    thumb = b"audited-thumb"
    thumb_sha = hashlib.sha256(thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    (cache / "thumbs" / thumb_sha[:2]).mkdir(parents=True)
    (cache / "thumbs" / thumb_sha[:2] / f"{thumb_sha}.webp").write_bytes(thumb)
    attribution = {
        "creator": "Jane Example",
        "license_code": "CC-BY-4.0",
        "license_name": "Creative Commons Attribution 4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
        "modified": True,
    }
    attribution.update(attribution_patch)
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
                "thumb_sha256": thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": attribution,
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )

    with pytest.raises(images.AuditedImageReuseError, match=match):
        images.build_place_images_from_audit(
            [candidate],
            completed_jsonl=completed,
            audited_cache_dir=cache,
        )


def test_build_place_images_from_audit_rejects_oversized_reencoded_thumb_before_write(
    tmp_path, monkeypatch
):
    old_thumb = b"old-thumb"
    thumb_sha = hashlib.sha256(old_thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    thumb_path = cache / "thumbs" / thumb_sha[:2] / f"{thumb_sha}.webp"
    thumb_path.parent.mkdir(parents=True)
    thumb_path.write_bytes(old_thumb)
    original_path = cache / "raw" / "mt1_00000000000000000000000001.source"
    original_path.parent.mkdir(parents=True)
    original_path.write_bytes(b"original-image")
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
                "thumb_sha256": thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": None,
                    "license_code": "CC0-1.0",
                    "license_name": "CC0",
                    "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )

    monkeypatch.setattr(
        images,
        "transcode_to_webp_thumb",
        lambda _path: images.ThumbTranscode(
            webp_bytes=b"x" * (images.MAX_AUDITED_THUMB_BYTES + 1),
            width=256,
            height=256,
        ),
    )

    with pytest.raises(images.AuditedImageReuseError, match="thumb exceeds"):
        images.build_place_images_from_audit(
            [candidate],
            completed_jsonl=completed,
            audited_cache_dir=cache,
        )


def test_build_place_images_from_audit_wraps_original_decode_failure(tmp_path, monkeypatch):
    old_thumb = b"old-thumb"
    thumb_sha = hashlib.sha256(old_thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    thumb_path = cache / "thumbs" / thumb_sha[:2] / f"{thumb_sha}.webp"
    thumb_path.parent.mkdir(parents=True)
    thumb_path.write_bytes(old_thumb)
    original_path = cache / "raw" / "mt1_00000000000000000000000001.source"
    original_path.parent.mkdir(parents=True)
    original_path.write_bytes(b"not-an-image")
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
                "thumb_sha256": thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": None,
                    "license_code": "CC0-1.0",
                    "license_name": "CC0",
                    "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )

    monkeypatch.setattr(
        images,
        "transcode_to_webp_thumb",
        lambda _path: (_ for _ in ()).throw(RuntimeError("worker failed")),
    )

    with pytest.raises(images.AuditedImageReuseError, match="original decode failed"):
        images.build_place_images_from_audit(
            [candidate],
            completed_jsonl=completed,
            audited_cache_dir=cache,
        )


def test_build_place_images_from_audit_rejects_duplicate_place_id_rows(tmp_path):
    completed = tmp_path / "completed.jsonl"
    row = {
        "place_id": "mt1_00000000000000000000000001",
        "thumb_sha256": "a" * 64,
        "width": 320,
        "height": 240,
        "attribution": {
            "creator": None,
            "license_code": "CC0-1.0",
            "license_name": "CC0",
            "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
            "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
            "modified": True,
        },
    }
    completed.write_text(
        json.dumps(row, sort_keys=True) + "\n" + json.dumps(row, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    with pytest.raises(images.AuditedImageReuseError, match="duplicate place_id"):
        images.build_place_images_from_audit(
            [],
            completed_jsonl=completed,
            audited_cache_dir=tmp_path / "audit-cache",
        )


@pytest.mark.parametrize(
    "license_url",
    [
        "https://creativecommons.org/licenses/by/4.0/deed.en",
        "https://creativecommons.org/licenses/by/4.0/legalcode",
        "https://creativecommons.org/licenses/by-sa/4.0/",
    ],
)
def test_build_place_images_from_audit_rejects_noncanonical_or_mismatched_license_url(
    tmp_path, license_url
):
    thumb = b"audited-thumb"
    thumb_sha = hashlib.sha256(thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    (cache / "thumbs" / thumb_sha[:2]).mkdir(parents=True)
    (cache / "thumbs" / thumb_sha[:2] / f"{thumb_sha}.webp").write_bytes(thumb)
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "thumb_sha256": thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": "Jane Example",
                    "license_code": "CC-BY-4.0",
                    "license_name": "Creative Commons Attribution 4.0",
                    "license_url": license_url,
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )

    with pytest.raises(images.AuditedImageReuseError, match="license_url"):
        images.build_place_images_from_audit(
            [candidate],
            completed_jsonl=completed,
            audited_cache_dir=cache,
        )


def test_build_place_images_from_audit_canonicalizes_http_creative_commons_license_url(
    tmp_path, monkeypatch
):
    thumb = b"audited-thumb"
    thumb_sha = hashlib.sha256(thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    (cache / "thumbs" / thumb_sha[:2]).mkdir(parents=True)
    (cache / "thumbs" / thumb_sha[:2] / f"{thumb_sha}.webp").write_bytes(thumb)
    original_path = cache / "raw" / "mt1_00000000000000000000000001.source"
    original_path.parent.mkdir(parents=True)
    original_path.write_bytes(b"original-image")
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "image_url": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
                "thumb_sha256": thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": "Jane Example",
                    "license_code": "CC-BY-4.0",
                    "license_name": "Creative Commons Attribution 4.0",
                    "license_url": "http://creativecommons.org/licenses/by/4.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )
    monkeypatch.setattr(
        images,
        "transcode_to_webp_thumb",
        lambda _path: images.ThumbTranscode(webp_bytes=b"new-thumb", width=256, height=192),
    )

    out = images.build_place_images_from_audit(
        [candidate],
        completed_jsonl=completed,
        audited_cache_dir=cache,
    )

    assert out[0].attribution.license_url == "https://creativecommons.org/licenses/by/4.0/"


def test_build_place_images_from_audit_rejects_unknown_license_code_url_mismatch(
    tmp_path,
):
    thumb = b"audited-thumb"
    thumb_sha = hashlib.sha256(thumb).hexdigest()
    cache = tmp_path / "audit-cache"
    (cache / "thumbs" / thumb_sha[:2]).mkdir(parents=True)
    (cache / "thumbs" / thumb_sha[:2] / f"{thumb_sha}.webp").write_bytes(thumb)
    completed = tmp_path / "completed.jsonl"
    completed.write_text(
        json.dumps(
            {
                "place_id": "mt1_00000000000000000000000001",
                "thumb_sha256": thumb_sha,
                "width": 320,
                "height": 240,
                "attribution": {
                    "creator": "Jane Example",
                    "license_code": "CC-BY-ND-4.0",
                    "license_name": "Creative Commons Attribution-NoDerivatives 4.0",
                    "license_url": "https://creativecommons.org/licenses/by/4.0/",
                    "source_url": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "modified": True,
                },
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Example.jpg",
    )

    with pytest.raises(images.AuditedImageReuseError, match="license_url"):
        images.build_place_images_from_audit(
            [candidate],
            completed_jsonl=completed,
            audited_cache_dir=cache,
        )


def test_build_place_images_falls_back_to_original_after_prescaled_download_failure(
    tmp_path, monkeypatch
):
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
    )
    downloads = []
    monkeypatch.setattr(
        images,
        "fetch_commons_imageinfo_batch",
            lambda filenames, **_kwargs: {
            filename: _imageinfo(license_short_name="CC BY 4.0")
            for filename in filenames
        },
    )

    def fake_download(url, dest, **kwargs):
        downloads.append(url)
        if "Special:FilePath" in url:
            raise images.fetch.FetchError("prescaled unavailable")
        Path(dest).write_bytes(b"raw-image")
        return SimpleNamespace(size=9, status="downloaded")

    monkeypatch.setattr(images.fetch, "conditional_get_to_file", fake_download)
    monkeypatch.setattr(
        images.fetch,
        "get_to_file",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("image downloads must use conditional_get_to_file")
        ),
    )
    monkeypatch.setattr(
        images,
        "transcode_to_webp_thumb",
        lambda path: images.ThumbTranscode(webp_bytes=b"webp", width=320, height=240),
    )

    out = images.build_place_images([candidate], cache_dir=tmp_path)

    assert len(out) == 1
    assert downloads == [
        "https://commons.wikimedia.org/wiki/Special:FilePath/Fort.jpg?width=768",
        "https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
    ]
    assert (
        tmp_path
        / "thumbs"
        / "a5"
        / "a57bb082e728a0cdce930ecfcccf4510a3a247be5f322b09b3a971a3f5ed34f8.webp"
    ).read_bytes() == b"webp"


def test_build_place_images_reuses_cached_reject(tmp_path, monkeypatch):
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
    )
    reject_dir = tmp_path / "rejects"
    reject_dir.mkdir()
    (reject_dir / f"{candidate.place_id}.json").write_text(
        json.dumps({"image_url": candidate.image_url, "reason": "license_unaccepted"})
    )

    monkeypatch.setattr(
        images,
        "fetch_commons_imageinfo_batch",
        lambda _filenames: pytest.fail("metadata should not be refetched"),
    )

    assert images.build_place_images([candidate], cache_dir=tmp_path) == []


def test_build_place_images_retries_cached_transient_reject(tmp_path, monkeypatch):
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
    )
    reject_dir = tmp_path / "rejects"
    reject_dir.mkdir()
    (reject_dir / f"{candidate.place_id}.json").write_text(
        json.dumps({"image_url": candidate.image_url, "reason": "metadata_fetch_failed"})
    )
    metadata_calls = []

    def fake_imageinfo(filenames, **_kwargs):
        metadata_calls.append(list(filenames))
        return {
            filename: _imageinfo(license_short_name="CC BY 4.0")
            for filename in filenames
        }

    monkeypatch.setattr(images, "fetch_commons_imageinfo_batch", fake_imageinfo)
    monkeypatch.setattr(
        images.fetch,
        "get_to_file",
        lambda _url, dest, **_kwargs: Path(dest).write_bytes(b"raw-image"),
    )
    monkeypatch.setattr(
        images,
        "transcode_to_webp_thumb",
        lambda _path: images.ThumbTranscode(webp_bytes=b"webp", width=320, height=240),
    )

    out = images.build_place_images([candidate], cache_dir=tmp_path)

    assert [place_image.place_id for place_image in out] == [candidate.place_id]
    assert metadata_calls == [["Fort.jpg"]]


def test_build_place_images_does_not_cache_batch_fetch_exception(tmp_path, monkeypatch):
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
    )

    def raise_transient(_filenames, **_kwargs):
        raise images.fetch.FetchError("temporary commons outage")

    monkeypatch.setattr(images, "fetch_commons_imageinfo_batch", raise_transient)

    with pytest.raises(images.fetch.FetchError, match="temporary commons outage"):
        images.build_place_images([candidate], cache_dir=tmp_path)

    assert not (tmp_path / "rejects" / f"{candidate.place_id}.json").exists()


def test_build_place_images_records_missing_metadata_payload_as_cacheable_reject(
    tmp_path, monkeypatch
):
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
    )
    metadata_calls = []

    def fake_imageinfo(filenames, **_kwargs):
        metadata_calls.append(list(filenames))
        return {}

    monkeypatch.setattr(images, "fetch_commons_imageinfo_batch", fake_imageinfo)

    assert images.build_place_images([candidate], cache_dir=tmp_path) == []
    assert metadata_calls == [["Fort.jpg"]]
    reject = json.loads(
        (tmp_path / "rejects" / f"{candidate.place_id}.json").read_text()
    )
    assert reject == {"image_url": candidate.image_url, "reason": "metadata_missing"}

    monkeypatch.setattr(
        images,
        "fetch_commons_imageinfo_batch",
        lambda _filenames: pytest.fail("cacheable reject should not be refetched"),
    )

    assert images.build_place_images([candidate], cache_dir=tmp_path) == []


def test_build_place_images_records_invalid_metadata_payload_as_cacheable_reject(
    tmp_path, monkeypatch
):
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
    )
    monkeypatch.setattr(
        images,
        "fetch_commons_imageinfo_batch",
            lambda filenames, **_kwargs: {filename: [] for filename in filenames},
    )

    assert images.build_place_images([candidate], cache_dir=tmp_path) == []
    reject = json.loads(
        (tmp_path / "rejects" / f"{candidate.place_id}.json").read_text()
    )
    assert reject == {"image_url": candidate.image_url, "reason": "metadata_invalid"}


def test_build_place_images_records_rejects_without_downloading(tmp_path, monkeypatch):
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
    )
    monkeypatch.setattr(
        images,
        "fetch_commons_imageinfo_batch",
            lambda filenames, **_kwargs: {
            filename: _imageinfo(license_short_name="CC BY-ND 4.0")
            for filename in filenames
        },
    )

    def fail_download(*args, **kwargs):
        raise AssertionError("rejected image must not download")

    monkeypatch.setattr(images.fetch, "get_to_file", fail_download)

    out = images.build_place_images([candidate], cache_dir=tmp_path)

    assert out == []
    reject = json.loads(
        (tmp_path / "rejects/mt1_00000000000000000000000001.json").read_text()
    )
    assert reject == {"image_url": candidate.image_url, "reason": "license_nd"}


def test_build_place_images_records_decode_failure_without_aborting(tmp_path, monkeypatch):
    candidate = images.ImageCandidate(
        place_id="mt1_00000000000000000000000001",
        lat=51.5,
        lon=-0.1,
        image_url="https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
    )
    monkeypatch.setattr(
        images,
        "fetch_commons_imageinfo_batch",
            lambda filenames, **_kwargs: {
            filename: _imageinfo(license_short_name="CC BY 4.0")
            for filename in filenames
        },
    )

    def fake_download(url, dest, **kwargs):
        Path(dest).write_bytes(b"raw-image")
        return 9

    def fail_transcode(path):
        raise ValueError("unsupported image format: 'GIF'")

    monkeypatch.setattr(images.fetch, "get_to_file", fake_download)
    monkeypatch.setattr(images, "transcode_to_webp_thumb", fail_transcode)

    assert images.build_place_images([candidate], cache_dir=tmp_path) == []
    reject = json.loads(
        (tmp_path / "rejects/mt1_00000000000000000000000001.json").read_text()
    )
    assert reject == {"image_url": candidate.image_url, "reason": "decode_failed"}


def test_image_worker_transcodes_allowed_jpeg_to_bounded_webp(tmp_path, monkeypatch):
    from PIL import Image

    src = tmp_path / "source.jpg"
    Image.new("RGB", (800, 400), color=(128, 64, 32)).save(src, format="JPEG")
    saved_qualities = []
    original_save = Image.Image.save

    def save_spy(self, fp, format=None, **params):
        if format == "WEBP":
            saved_qualities.append(params.get("quality"))
        return original_save(self, fp, format=format, **params)

    monkeypatch.setattr(Image.Image, "save", save_spy)

    payload = image_worker.transcode(src)

    assert image_worker.THUMB_MAX_EDGE == 256
    assert image_worker.THUMB_WEBP_QUALITY == 50
    assert saved_qualities == [50]
    assert payload["width"] == 256
    assert payload["height"] == 128
    assert isinstance(payload["webp_b64"], str)


def test_transcode_to_webp_thumb_uses_hard_timeout(monkeypatch, tmp_path):
    calls = []

    def fake_run(*args, **kwargs):
        calls.append((args, kwargs))
        raise TimeoutError("stop")

    monkeypatch.setattr(images.subprocess, "run", fake_run)

    with pytest.raises(TimeoutError):
        images.transcode_to_webp_thumb(tmp_path / "source.jpg")

    assert calls[0][1]["timeout"] == images.IMAGE_WORKER_TIMEOUT_SECONDS


def test_fetch_commons_imageinfo_batch_uses_50_title_chunks_and_rehydrates_pages(monkeypatch):
    requested_urls = []

    def fake_request(operation):
        return operation()

    def fake_get_json(url, **kwargs):
        requested_urls.append(url)
        from urllib.parse import parse_qs, urlparse

        decoded = parse_qs(urlparse(url).query)["titles"][0].split("|")
        return {
            "query": {
                "pages": {
                    str(index): {
                        "title": title,
                        "imageinfo": [
                            {
                                "url": "https://upload.wikimedia.org/example.jpg",
                                "mime": "image/jpeg",
                                "extmetadata": {},
                            }
                        ],
                    }
                    for index, title in enumerate(decoded)
                }
            }
        }

    monkeypatch.setattr(images, "_wikimedia_request", fake_request)
    monkeypatch.setattr(images.fetch, "get_json", fake_get_json)

    result = images.fetch_commons_imageinfo_batch([f"Image {i}.jpg" for i in range(51)])

    assert len(requested_urls) == 2
    assert set(result) == {f"Image {i}.jpg" for i in range(51)}


def test_fetch_commons_imageinfo_batch_uses_conditional_json_when_store_available(
    tmp_path, monkeypatch
):
    calls = []
    store = images.fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")

    def fake_request(operation):
        return operation()

    def fake_conditional_get_json(url, **kwargs):
        calls.append((url, kwargs))
        return (
            {
                "query": {
                    "pages": {
                        "1": {
                            "title": "File:Fort.jpg",
                            "imageinfo": [
                                {
                                    "url": "https://upload.wikimedia.org/example.jpg",
                                    "mime": "image/jpeg",
                                    "extmetadata": {},
                                }
                            ],
                        }
                    }
                }
            },
            SimpleNamespace(status="downloaded"),
        )

    monkeypatch.setattr(images, "_wikimedia_request", fake_request)
    monkeypatch.setattr(images.fetch, "conditional_get_json", fake_conditional_get_json)
    monkeypatch.setattr(
        images.fetch,
        "get_json",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("metadata fetches must use conditional_get_json")
        ),
    )

    result = images.fetch_commons_imageinfo_batch(
        ["Fort.jpg"],
        conditional_store=store,
    )

    assert set(result) == {"Fort.jpg"}
    assert calls[0][1] == {
        "expected_hosts": {images.COMMONS_API_HOST},
        "headers": {"User-Agent": images.USER_AGENT},
        "store": store,
    }


def test_wikimedia_request_retries_429_after_retry_after(monkeypatch):
    calls = []
    sleeps = []

    class Limiter:
        def wait(self):
            calls.append("wait")

    class Semaphore:
        def __enter__(self):
            calls.append("enter")

        def __exit__(self, exc_type, exc, tb):
            calls.append("exit")
            return False

    attempts = iter(
        [
            images.fetch.FetchError("limited", status=429, retry_after=7),
            {"ok": True},
        ]
    )

    def operation():
        value = next(attempts)
        if isinstance(value, Exception):
            raise value
        return value

    monkeypatch.setattr(images, "WIKIMEDIA_RATE_LIMITER", Limiter())
    monkeypatch.setattr(images, "WIKIMEDIA_REQUEST_SEMAPHORE", Semaphore())
    monkeypatch.setattr(images.time, "sleep", lambda seconds: sleeps.append(seconds))

    assert images._wikimedia_request(operation) == {"ok": True}
    assert sleeps == [7.0]
    assert calls == ["wait", "enter", "exit", "wait", "enter", "exit"]


def test_wikimedia_request_does_not_retry_outside_policy_after_exhaustion(monkeypatch):
    calls = []

    class Limiter:
        def wait(self):
            calls.append("wait")

    class Semaphore:
        def __enter__(self):
            calls.append("enter")

        def __exit__(self, exc_type, exc, tb):
            calls.append("exit")
            return False

    def operation():
        calls.append("operation")
        raise images.fetch.FetchError("limited", status=429, retry_after=1)

    monkeypatch.setattr(images, "WIKIMEDIA_RETRY_ATTEMPTS", 2)
    monkeypatch.setattr(images, "WIKIMEDIA_RATE_LIMITER", Limiter())
    monkeypatch.setattr(images, "WIKIMEDIA_REQUEST_SEMAPHORE", Semaphore())
    monkeypatch.setattr(images.time, "sleep", lambda _seconds: None)

    with pytest.raises(images.fetch.FetchError):
        images._wikimedia_request(operation)

    assert calls == [
        "wait",
        "enter",
        "operation",
        "exit",
        "wait",
        "enter",
        "operation",
        "exit",
    ]


def test_image_worker_rejects_gif_and_oversized_dimensions(tmp_path, monkeypatch):
    from PIL import Image

    gif = tmp_path / "source.gif"
    Image.new("RGB", (10, 10), color=(0, 0, 0)).save(gif, format="GIF")
    with pytest.raises(ValueError, match="unsupported image format"):
        image_worker.transcode(gif)

    monkeypatch.setattr(image_worker, "MAX_IMAGE_PIXELS", 4)
    png = tmp_path / "source.png"
    Image.new("RGB", (3, 3), color=(0, 0, 0)).save(png, format="PNG")
    with pytest.raises(ValueError, match="image dimensions exceed decode cap"):
        image_worker.transcode(png)


def test_purge_nc_from_staging_removes_nc_entries_and_gc_removes_unreferenced_thumbs(tmp_path):
    image_path = tmp_path / "united-kingdom/20260717T120000Z/images/10/1/2.json"
    image_path.parent.mkdir(parents=True)
    kept_sha = "a" * 64
    purged_sha = "b" * 64
    image_path.write_text(
        json.dumps(
                {
                    "schema_version": 1,
                    "min_reader_version": 1,
                    "z": 10,
                    "x": 1,
                    "y": 2,
                "places": [
                    {
                            "place_id": "mt1_00000000000000000000000001",
                            "thumb_sha256": kept_sha,
                            "bytes": 64,
                            "width": 320,
                            "height": 240,
                        "attribution": {
                            "creator": "Jane Example",
                            "license_code": "CC-BY-4.0",
                            "license_name": "Creative Commons Attribution 4.0",
                            "license_url": "https://creativecommons.org/licenses/by/4.0/",
                            "source_url": "https://commons.wikimedia.org/wiki/File:Fort.jpg",
                            "modified": True,
                        },
                    },
                    {
                            "place_id": "mt1_00000000000000000000000002",
                            "thumb_sha256": purged_sha,
                            "bytes": 64,
                            "width": 320,
                        "height": 240,
                        "attribution": {
                            "creator": "Jane Example",
                            "license_code": "CC-BY-NC-4.0",
                            "license_name": "Creative Commons Attribution-NonCommercial 4.0",
                            "license_url": "https://creativecommons.org/licenses/by-nc/4.0/",
                            "source_url": "https://commons.wikimedia.org/wiki/File:House.jpg",
                            "modified": True,
                        },
                    },
                ],
            },
            sort_keys=True,
        )
    )
    for sha in [kept_sha, purged_sha, "c" * 64]:
        thumb = tmp_path / "thumbs" / sha[:2] / f"{sha}.webp"
        thumb.parent.mkdir(parents=True, exist_ok=True)
        thumb.write_bytes(sha.encode("ascii"))

    purge = images.purge_nc_from_staging(tmp_path)
    gc = images.gc_unreferenced_thumbs(tmp_path)

    rewritten = json.loads(image_path.read_text())
    assert [place["thumb_sha256"] for place in rewritten["places"]] == [kept_sha]
    assert purge == images.PurgeResult(files_changed=1, entries_removed=1)
    assert gc == images.GCResult(thumbs_removed=2, bytes_removed=128)
    assert (tmp_path / "thumbs" / kept_sha[:2] / f"{kept_sha}.webp").exists()
    assert not (tmp_path / "thumbs" / purged_sha[:2] / f"{purged_sha}.webp").exists()
