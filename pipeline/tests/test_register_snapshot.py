import email.message
import hashlib
import io
import json
import pathlib
import urllib.request
import urllib.response

import pytest

from mt_pipeline import fetch
from mt_pipeline.extractors import _snapshot


class _FakeOpener:
    def __init__(self, body):
        self._body = body

    def open(self, url, timeout=None):
        return io.BytesIO(self._body)


def test_get_to_file_rejects_non_https(tmp_path):
    with pytest.raises(fetch.FetchError):
        fetch.get_to_file(
            "http://insecure/x",
            tmp_path / "o",
            expected_hosts={"historicengland.org.uk"},
        )


def test_get_to_file_streams_and_caps(tmp_path, monkeypatch):
    monkeypatch.setattr(fetch, "_opener", lambda hosts: _FakeOpener(b"x" * 5000))

    with pytest.raises(fetch.FetchError, match="exceeded"):
        fetch.get_to_file(
            "https://historicengland.org.uk/x",
            tmp_path / "o",
            expected_hosts={"historicengland.org.uk"},
            max_bytes=1024,
        )
    assert not (tmp_path / "o").exists()


def test_get_to_file_writes_bytes(tmp_path, monkeypatch):
    monkeypatch.setattr(fetch, "_opener", lambda hosts: _FakeOpener(b"HELLO"))

    n = fetch.get_to_file(
        "https://historicengland.org.uk/x",
        tmp_path / "o",
        expected_hosts={"historicengland.org.uk"},
    )

    assert n == 5
    assert (tmp_path / "o").read_bytes() == b"HELLO"


def test_get_to_file_rejects_content_encoding(tmp_path, monkeypatch):
    class _HdrOpener:
        def open(self, url, timeout=None):
            headers = email.message.Message()
            headers["Content-Encoding"] = "gzip"
            return urllib.response.addinfourl(io.BytesIO(b"BODY"), headers, url, 200)

    monkeypatch.setattr(fetch, "_opener", lambda hosts: _HdrOpener())

    with pytest.raises(fetch.FetchError, match="Content-Encoding"):
        fetch.get_to_file(
            "https://historicengland.org.uk/x",
            tmp_path / "o",
            expected_hosts={"historicengland.org.uk"},
        )


class _RedirectThenServe(urllib.request.BaseHandler):
    def __init__(self, location):
        self.location = location

    def https_open(self, req):
        if req.full_url == self.location:
            return urllib.response.addinfourl(
                io.BytesIO(b"EVIL-BODY"),
                email.message.Message(),
                req.full_url,
                200,
            )
        headers = email.message.Message()
        headers["Location"] = self.location
        return urllib.request.HTTPError(
            req.full_url, 302, "Found", headers, io.BytesIO(b"")
        )


def _redirect_opener(hosts, location):
    opener = urllib.request.OpenerDirector()
    for handler in (
        urllib.request.HTTPErrorProcessor(),
        fetch._AllowlistRedirect(hosts),
        _RedirectThenServe(location),
    ):
        opener.add_handler(handler)
    return opener


def test_get_to_file_blocks_redirect_to_offallowlist_host(tmp_path, monkeypatch):
    monkeypatch.setattr(
        fetch, "_opener", lambda hosts: _redirect_opener(hosts, "https://evil.example/x")
    )

    with pytest.raises(fetch.FetchError, match="blocked redirect to"):
        fetch.get_to_file(
            "https://historicengland.org.uk/x",
            tmp_path / "o",
            expected_hosts={"historicengland.org.uk"},
        )


def test_verify_sha256_sidecar_loud_on_mismatch(tmp_path):
    snap = tmp_path / "he.geojson"
    snap.write_bytes(b"DATA")
    good = hashlib.sha256(b"DATA").hexdigest()
    (tmp_path / "he.geojson.meta.json").write_text(
        json.dumps(
            {
                "source_url": "u",
                "snapshot_date": "2026-07-14",
                "sha256": good,
                "size": 4,
            }
        )
    )
    _snapshot.verify_sha256_sidecar(snap)

    (tmp_path / "he.geojson.meta.json").write_text(json.dumps({"sha256": "deadbeef"}))
    with pytest.raises(_snapshot.ProvenanceError):
        _snapshot.verify_sha256_sidecar(snap)

    (tmp_path / "he.geojson.meta.json").write_text(
        json.dumps({"source_url": "u", "sha256": good, "size": 5})
    )
    with pytest.raises(_snapshot.ProvenanceError):
        _snapshot.verify_sha256_sidecar(snap)


def test_verify_sidecar_absent_warns(tmp_path, caplog):
    snap = tmp_path / "dev.json"
    snap.write_bytes(b"x")

    _snapshot.verify_sha256_sidecar(snap)

    assert any("provenance" in record.message.lower() for record in caplog.records)


def test_verify_sidecar_malformed_is_typed(tmp_path):
    snap = tmp_path / "he.geojson"
    snap.write_bytes(b"DATA")
    meta = tmp_path / "he.geojson.meta.json"

    meta.write_text("[1,2,3]")
    with pytest.raises(_snapshot.ProvenanceError):
        _snapshot.verify_sha256_sidecar(snap)

    meta.write_bytes(b"{" + b" " * (_snapshot.MAX_SIDECAR_BYTES + 10))
    with pytest.raises(_snapshot.ProvenanceError):
        _snapshot.verify_sha256_sidecar(snap)


def test_download_snapshot_writes_sidecar_via_injected_fetch(tmp_path):
    cfg = {
        "historic_england": {
            "url": "https://historicengland.org.uk/nhle.geojson",
            "allowed_hosts": ["historicengland.org.uk"],
            "max_bytes": 99,
            "snapshot_date": "2026-07-14",
        }
    }

    def fake_fetch(url, dest, *, expected_hosts, **kwargs):
        assert kwargs["max_bytes"] == 99
        body = b'{"type":"FeatureCollection","features":[]}'
        pathlib.Path(dest).write_bytes(body)
        return len(body)

    path = _snapshot.download_snapshot(
        "historic_england",
        tmp_path,
        config=cfg,
        fetch_fn=fake_fetch,
        enabled=True,
    )
    meta = json.loads(pathlib.Path(str(path) + ".meta.json").read_text())

    assert meta["sha256"] == hashlib.sha256(
        b'{"type":"FeatureCollection","features":[]}'
    ).hexdigest()
    assert meta["size"] == 42
    _snapshot.verify_sha256_sidecar(path)


def test_historic_england_download_rejects_arcgis_export_status(tmp_path):
    cfg = {
        "historic_england": {
            "url": "https://historicengland.org.uk/nhle.geojson",
            "allowed_hosts": ["historicengland.org.uk"],
        }
    }

    def fake_fetch(url, dest, *, expected_hosts, **kwargs):
        pathlib.Path(dest).write_text(
            json.dumps(
                {
                    "message": "Up to date download file is being generated.",
                    "status": "ExportingData",
                    "progressInPercent": 0,
                    "recordCount": 0,
                }
            )
        )
        return pathlib.Path(dest).stat().st_size

    with pytest.raises(_snapshot.SnapshotParseError, match="still exporting"):
        _snapshot.download_snapshot(
            "historic_england",
            tmp_path,
            config=cfg,
            fetch_fn=fake_fetch,
            enabled=True,
            retries=0,
        )

    assert not (tmp_path / "historic_england.snapshot").exists()
    assert not (tmp_path / "historic_england.snapshot.meta.json").exists()


def test_historic_england_download_retries_arcgis_export_status(tmp_path):
    cfg = {
        "historic_england": {
            "url": "https://historicengland.org.uk/nhle.geojson",
            "allowed_hosts": ["historicengland.org.uk"],
        }
    }
    calls = []
    sleeps = []

    def fake_fetch(url, dest, *, expected_hosts, **kwargs):
        calls.append(url)
        if len(calls) == 1:
            pathlib.Path(dest).write_text(
                json.dumps(
                    {
                        "message": "Up to date download file is being generated.",
                        "status": "ExportingData",
                    }
                )
            )
        else:
            pathlib.Path(dest).write_text('{"type":"FeatureCollection","features":[]}')
        return pathlib.Path(dest).stat().st_size

    path = _snapshot.download_snapshot(
        "historic_england",
        tmp_path,
        config=cfg,
        fetch_fn=fake_fetch,
        enabled=True,
        retries=1,
        sleep=sleeps.append,
    )

    assert calls == [
        "https://historicengland.org.uk/nhle.geojson",
        "https://historicengland.org.uk/nhle.geojson",
    ]
    assert sleeps == [1.0]
    assert json.loads(path.read_text()) == {"type": "FeatureCollection", "features": []}
    _snapshot.verify_sha256_sidecar(path)
