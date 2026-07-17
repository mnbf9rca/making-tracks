import json
from pathlib import Path

import pytest

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
        return "https://commons.wikimedia.org/wiki/Commons:Copyright_tags/Public_domain"
    return f"https://creativecommons.org/licenses/{normalized}"


def _expected_license_url_for_code(code: str) -> str:
    if code == "PD":
        return "https://commons.wikimedia.org/wiki/Commons:Copyright_tags/Public_domain"
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


def test_commons_license_rejects_deed_url_for_different_port():
    decision = images.metadata_from_commons_imageinfo(
        _imageinfo(
            license_short_name="cc-by-sa-3.0-de",
            license_url="https://creativecommons.org/licenses/by-sa/3.0/",
        )
    )

    assert decision.accepted is False
    assert decision.reason == "license_url_mismatch"


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

    def fake_imageinfo(filenames):
        metadata_calls.append(list(filenames))
        return {
            filename: _imageinfo(license_short_name="CC BY 4.0")
            for filename in filenames
        }

    monkeypatch.setattr(images, "fetch_commons_imageinfo_batch", fake_imageinfo)

    def fake_download(url, dest, **kwargs):
        downloads.append((url, Path(dest).name, kwargs))
        Path(dest).write_bytes(b"raw-image")
        return 9

    monkeypatch.setattr(images.fetch, "get_to_file", fake_download)
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
        lambda filenames: {
            filename: _imageinfo(license_short_name="CC BY 4.0")
            for filename in filenames
        },
    )

    def fake_download(url, dest, **kwargs):
        downloads.append(url)
        if "Special:FilePath" in url:
            raise images.fetch.FetchError("prescaled unavailable")
        Path(dest).write_bytes(b"raw-image")
        return 9

    monkeypatch.setattr(images.fetch, "get_to_file", fake_download)
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

    def fake_imageinfo(filenames):
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

    def raise_transient(_filenames):
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

    def fake_imageinfo(filenames):
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
        lambda filenames: {filename: [] for filename in filenames},
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
        lambda filenames: {
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
        lambda filenames: {
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


def test_image_worker_transcodes_allowed_jpeg_to_bounded_webp(tmp_path):
    from PIL import Image

    src = tmp_path / "source.jpg"
    Image.new("RGB", (800, 400), color=(128, 64, 32)).save(src, format="JPEG")

    payload = image_worker.transcode(src)

    assert payload["width"] == 512
    assert payload["height"] == 256
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
    image_path = tmp_path / "uk/20260717T120000Z/images/10/1/2.json"
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
