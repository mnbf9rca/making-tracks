import email.message
import hashlib
import io
import json
import pathlib
import urllib.response

import pytest

from mt_pipeline import acquire


class _HeaderOpener:
    def __init__(self, body: bytes):
        self._body = body

    def open(self, url, timeout=None):
        headers = email.message.Message()
        headers["Content-Length"] = str(len(self._body))
        return urllib.response.addinfourl(io.BytesIO(self._body), headers, url, 200)


def test_osm_production_download_reports_known_byte_progress(
    tmp_path, capsys, monkeypatch
):
    body = b"PBF"
    md5 = hashlib.md5(body, usedforsecurity=False).hexdigest()
    monkeypatch.setattr(acquire, "_DOWNLOAD_HEARTBEAT_EVERY_BYTES", 1, raising=False)
    monkeypatch.setattr(acquire.fetch, "_opener", lambda _hosts: _HeaderOpener(body))

    path = acquire.acquire_osm(
        tmp_path,
        region_id="united-kingdom",
        config={
            "united-kingdom": {
                "url": "https://download.geofabrik.de/europe/x.osm.pbf",
                "md5_url": "https://download.geofabrik.de/europe/x.osm.pbf.md5",
                "allowed_hosts": ["download.geofabrik.de"],
                "max_bytes": 99,
            }
        },
        fetch_text=lambda *_args, **_kwargs: md5,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    assert pathlib.Path(str(path) + ".meta.json").exists()
    err = capsys.readouterr().err
    assert "PHASE START acquire.osm.download region=united-kingdom bytes=unknown" in err
    assert (
        "PHASE HEARTBEAT acquire.osm.download region=united-kingdom processed=3/3"
        in err
    )
    assert "source=osm bytes_downloaded=3" in err
    assert "PHASE DONE acquire.osm.download region=united-kingdom processed=3/3" in err


def test_osm_acquisition_verifies_md5_and_writes_sha256_sidecar(tmp_path):
    body = b"PBF"
    md5 = hashlib.md5(body, usedforsecurity=False).hexdigest()

    def download(url, dest, *, expected_hosts, max_bytes):
        assert url == "https://download.geofabrik.de/asia/x.osm.pbf"
        assert expected_hosts == {"download.geofabrik.de"}
        assert max_bytes == 99
        pathlib.Path(dest).write_bytes(body)
        return len(body)

    def fetch_text(url, *, expected_hosts, max_bytes):
        assert url == "https://download.geofabrik.de/asia/x.osm.pbf.md5"
        assert expected_hosts == {"download.geofabrik.de"}
        return f"{md5}  x.osm.pbf\n"

    path = acquire.acquire_osm(
        tmp_path,
        region_id="malaysia-singapore-brunei",
        config={
            "malaysia-singapore-brunei": {
                "url": "https://download.geofabrik.de/asia/x.osm.pbf",
                "md5_url": "https://download.geofabrik.de/asia/x.osm.pbf.md5",
                "allowed_hosts": ["download.geofabrik.de"],
                "max_bytes": 99,
                "geofabrik_date": "2026-07-15",
            }
        },
        download_file=download,
        fetch_text=fetch_text,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    assert path == tmp_path / "osm.osm.pbf"
    meta = json.loads(pathlib.Path(str(path) + ".meta.json").read_text())
    assert meta == {
        "geofabrik_date": "2026-07-15",
        "sha256": hashlib.sha256(body).hexdigest(),
        "size": len(body),
        "source_url": "https://download.geofabrik.de/asia/x.osm.pbf",
    }


def test_osm_acquisition_aborts_loudly_on_md5_mismatch(tmp_path, capsys):
    def download(_url, dest, **_kwargs):
        pathlib.Path(dest).write_bytes(b"PBF")
        return 3

    with pytest.raises(acquire.AcquireError, match="md5"):
        acquire.acquire_osm(
            tmp_path,
            region_id="united-kingdom",
            config={
                "united-kingdom": {
                    "url": "https://download.geofabrik.de/europe/x.osm.pbf",
                    "md5_url": "https://download.geofabrik.de/europe/x.osm.pbf.md5",
                    "allowed_hosts": ["download.geofabrik.de"],
                }
            },
            download_file=download,
            fetch_text=lambda *_args, **_kwargs: "0" * 32,
            retrieved_at="2026-07-15T00:00:00Z",
        )

    assert not (tmp_path / "osm.osm.pbf").exists()
    assert not (tmp_path / "osm.osm.pbf.meta.json").exists()
    err = capsys.readouterr().err
    assert "PHASE START acquire.osm.download" in err
    assert "PHASE DONE acquire.osm.download" not in err


def test_osm_acquisition_cleans_transient_md5_file_on_download_failure(
    tmp_path, monkeypatch
):
    def download(_url, dest, **_kwargs):
        pathlib.Path(dest).write_bytes(b"PBF")
        return 3

    def fail_md5_download(_url, dest, **_kwargs):
        pathlib.Path(dest).write_text("partial")
        raise RuntimeError("network failed")

    monkeypatch.setattr(acquire.fetch, "get_to_file", fail_md5_download)

    with pytest.raises(RuntimeError, match="network failed"):
        acquire.acquire_osm(
            tmp_path,
            region_id="united-kingdom",
            config={
                "united-kingdom": {
                    "url": "https://download.geofabrik.de/europe/x.osm.pbf",
                    "md5_url": "https://download.geofabrik.de/europe/x.osm.pbf.md5",
                    "allowed_hosts": ["download.geofabrik.de"],
                }
            },
            download_file=download,
            retrieved_at="2026-07-15T00:00:00Z",
        )

    assert not (tmp_path / "osm.osm.pbf").exists()
    assert not (tmp_path / "osm.osm.pbf.md5").exists()
    assert not (tmp_path / "osm.osm.pbf.meta.json").exists()
