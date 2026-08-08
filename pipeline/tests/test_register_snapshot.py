import email.message
import hashlib
import io
import json
import pathlib
from types import SimpleNamespace
import urllib.request
import urllib.response

import pytest

from mt_pipeline import acquire
from mt_pipeline import fetch
from mt_pipeline.extractors import _snapshot


class _FakeOpener:
    def __init__(self, body):
        self._body = body

    def open(self, url, timeout=None):
        return io.BytesIO(self._body)


class _HeaderOpener:
    def __init__(self, body: bytes, header_values: dict[str, str]):
        self._body = body
        self._header_values = header_values

    def open(self, url, timeout=None):
        headers = email.message.Message()
        for key, value in self._header_values.items():
            headers[key] = value
        return urllib.response.addinfourl(io.BytesIO(self._body), headers, url, 200)


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


def test_get_to_file_reports_header_and_cumulative_byte_progress(tmp_path, monkeypatch):
    monkeypatch.setattr(
        fetch,
        "_opener",
        lambda _hosts: _HeaderOpener(b"abcdef", {"Content-Length": "6"}),
    )
    events = []

    written = fetch.get_to_file(
        "https://historicengland.org.uk/x",
        tmp_path / "o",
        expected_hosts={"historicengland.org.uk"},
        max_bytes=10,
        on_progress=lambda done, total: events.append((done, total)),
    )

    assert written == 6
    assert events == [(0, 6), (6, 6)]


def test_get_to_file_reports_unknown_only_when_content_length_is_absent(
    tmp_path, monkeypatch
):
    monkeypatch.setattr(
        fetch,
        "_opener",
        lambda _hosts: _HeaderOpener(b"abc", {}),
    )
    events = []

    fetch.get_to_file(
        "https://historicengland.org.uk/x",
        tmp_path / "o",
        expected_hosts={"historicengland.org.uk"},
        max_bytes=10,
        on_progress=lambda done, total: events.append((done, total)),
    )

    assert events == [(0, None), (3, None)]


@pytest.mark.parametrize("value", ["-1", "+1", "1, 1", "nope", "11"])
def test_get_to_file_rejects_invalid_or_over_limit_content_length(
    tmp_path, monkeypatch, value
):
    monkeypatch.setattr(
        fetch,
        "_opener",
        lambda _hosts: _HeaderOpener(b"abc", {"Content-Length": value}),
    )

    with pytest.raises(fetch.FetchError, match="Content-Length"):
        fetch.get_to_file(
            "https://historicengland.org.uk/x",
            tmp_path / "o",
            expected_hosts={"historicengland.org.uk"},
            max_bytes=10,
        )


def test_get_to_file_rejects_duplicate_content_length_headers(tmp_path, monkeypatch):
    class DuplicateLengthOpener:
        def open(self, url, timeout=None):
            headers = email.message.Message()
            headers["Content-Length"] = "3"
            headers["Content-Length"] = "3"
            return urllib.response.addinfourl(io.BytesIO(b"abc"), headers, url, 200)

    monkeypatch.setattr(fetch, "_opener", lambda _hosts: DuplicateLengthOpener())

    with pytest.raises(fetch.FetchError, match="Content-Length"):
        fetch.get_to_file(
            "https://historicengland.org.uk/x",
            tmp_path / "o",
            expected_hosts={"historicengland.org.uk"},
            max_bytes=10,
        )


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


def test_download_snapshot_default_fetch_uses_conditional_client(tmp_path, monkeypatch):
    cfg = {
        "historic_england": {
            "url": "https://historicengland.org.uk/nhle.geojson",
            "allowed_hosts": ["historicengland.org.uk"],
            "max_bytes": 99,
            "snapshot_date": "2026-07-14",
        }
    }
    calls = []

    def fake_conditional_fetch(url, dest, *, expected_hosts, max_bytes, store, **kwargs):
        calls.append(
            {
                "url": url,
                "dest": pathlib.Path(dest).name,
                "expected_hosts": expected_hosts,
                "max_bytes": max_bytes,
                "store": store,
            }
        )
        body = b'{"type":"FeatureCollection","features":[]}'
        pathlib.Path(dest).write_bytes(body)
        return SimpleNamespace(size=len(body), status="downloaded")

    monkeypatch.setattr(
        _snapshot.fetch,
        "conditional_get_to_file",
        fake_conditional_fetch,
        raising=False,
    )
    monkeypatch.setattr(
        _snapshot.fetch,
        "get_to_file",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("register snapshots must use conditional_get_to_file")
        ),
    )

    path = _snapshot.download_snapshot(
        "historic_england",
        tmp_path,
        config=cfg,
        fetch_fn=None,
        enabled=True,
    )

    assert calls == [
        {
            "url": "https://historicengland.org.uk/nhle.geojson",
            "dest": "historic_england.snapshot",
            "expected_hosts": {"historicengland.org.uk"},
            "max_bytes": 99,
            "store": fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json"),
        }
    ]
    assert json.loads(path.read_text()) == {"type": "FeatureCollection", "features": []}


def test_acquire_registers_reports_source_specific_byte_progress(
    tmp_path, capsys, monkeypatch
):
    config_path = tmp_path / "registers.json"
    config_path.write_text(
        json.dumps(
            {
                "historic_england": {
                    "url": "https://historicengland.org.uk/nhle.geojson",
                    "allowed_hosts": ["historicengland.org.uk"],
                },
                "open_plaques": {
                    "url": "https://openplaques.org/data.json",
                    "allowed_hosts": ["openplaques.org"],
                },
            }
        )
    )
    monkeypatch.setattr(acquire, "_DOWNLOAD_HEARTBEAT_EVERY_BYTES", 1, raising=False)

    def fake_conditional_fetch(
        url, dest, *, expected_hosts, max_bytes, store, on_progress=None
    ):
        body = (
            b'{"type":"FeatureCollection","features":[]}'
            if "historicengland" in url
            else b"[]"
        )
        if on_progress is not None:
            on_progress(0, len(body))
        pathlib.Path(dest).write_bytes(body)
        if on_progress is not None:
            on_progress(len(body), len(body))
        return SimpleNamespace(size=len(body), status="downloaded")

    monkeypatch.setattr(
        _snapshot.fetch, "conditional_get_to_file", fake_conditional_fetch
    )
    region = SimpleNamespace(
        region_id="united-kingdom",
        sources={"historic_england": True, "open_plaques": True},
    )

    paths = acquire.acquire_registers(
        tmp_path, region_config=region, config_path=config_path
    )

    assert set(paths) == {"historic_england", "open_plaques"}
    err = capsys.readouterr().err
    sizes = {"historic_england": 42, "open_plaques": 2}
    for source, size in sizes.items():
        phase = f"acquire.register.{source}.download"
        assert f"PHASE START {phase} region=united-kingdom bytes=unknown" in err
        assert (
            f"PHASE HEARTBEAT {phase} region=united-kingdom "
            f"processed={size}/{size}" in err
        )
        assert (
            f"PHASE DONE {phase} region=united-kingdom processed={size}/{size}"
            in err
        )
        assert f"source={source}" in err
    assert "status=downloaded" in err


def test_register_sidecar_failure_does_not_emit_done(tmp_path, capsys, monkeypatch):
    config_path = tmp_path / "registers.json"
    config_path.write_text(
        json.dumps(
            {
                "open_plaques": {
                    "url": "https://openplaques.org/data.json",
                    "allowed_hosts": ["openplaques.org"],
                }
            }
        )
    )

    def fake_conditional_fetch(
        url, dest, *, expected_hosts, max_bytes, store, on_progress=None
    ):
        pathlib.Path(dest).write_bytes(b"[]")
        if on_progress is not None:
            on_progress(2, 2)
        return SimpleNamespace(size=2, status="downloaded")

    monkeypatch.setattr(
        _snapshot.fetch, "conditional_get_to_file", fake_conditional_fetch
    )
    original_write_text = pathlib.Path.write_text

    def fail_sidecar(path, data, *args, **kwargs):
        if str(path).endswith(".meta.json"):
            raise OSError("disk full")
        return original_write_text(path, data, *args, **kwargs)

    monkeypatch.setattr(pathlib.Path, "write_text", fail_sidecar)
    region = SimpleNamespace(
        region_id="united-kingdom",
        sources={"historic_england": False, "open_plaques": True},
    )

    with pytest.raises(OSError, match="disk full"):
        acquire.acquire_registers(
            tmp_path, region_config=region, config_path=config_path
        )

    err = capsys.readouterr().err
    assert "PHASE START acquire.register.open_plaques.download" in err
    assert "PHASE DONE acquire.register.open_plaques.download" not in err


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
