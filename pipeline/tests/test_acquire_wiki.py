import json
import time
import types
import urllib.parse

import pytest

from mt_pipeline import acquire, store


def _binding(qid: str, p31: str, lat: float = 1.2, lon: float = 101.3):
    return {
        "item": {"value": f"http://www.wikidata.org/entity/{qid}"},
        "p31": {"value": f"http://www.wikidata.org/entity/{p31}"},
        "lat": {"value": str(lat)},
        "lon": {"value": str(lon)},
        "label": {"value": f"Label {qid}"},
        "sitelinks": {"value": "3"},
    }


def _binding_with_p31s(
    qid: str,
    p31s: str,
    matched_class: str,
    lat: float = 1.2,
    lon: float = 101.3,
):
    binding = _binding(qid, "Q999", lat, lon)
    binding["p31s"] = {"value": p31s}
    binding["matched_class"] = {
        "value": f"http://www.wikidata.org/entity/{matched_class}"
    }
    return binding


def test_bbox_tiles_cover_bbox_deterministically():
    assert list(acquire.bbox_tiles((0.0, 0.0, 2.5, 1.5), tile_degrees=1.0)) == [
        (0.0, 0.0, 1.0, 1.0),
        (0.0, 1.0, 1.0, 1.5),
        (1.0, 0.0, 2.0, 1.0),
        (1.0, 1.0, 2.0, 1.5),
        (2.0, 0.0, 2.5, 1.0),
        (2.0, 1.0, 2.5, 1.5),
    ]


def test_wikidata_acquisition_segments_and_marks_complete(tmp_path):
    calls = []

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        calls.append((url, expected_hosts, max_bytes, headers))
        parsed = urllib.parse.urlparse(url)
        query = urllib.parse.parse_qs(parsed.query)["query"][0]
        assert "SERVICE wikibase:box" in query
        assert "geof:latitude" not in query
        assert "wdt:P31 ?p31" in query
        assert "matched_class" in query
        assert "MakingTracksBot/0.1" in headers["User-Agent"]
        return {
            "results": {
                "bindings": [
                    _binding_with_p31s(f"Q{len(calls)}", "http://www.wikidata.org/entity/Q123", "Q33506")
                ]
            }
        }

    out = acquire.acquire_wikidata(
        tmp_path,
        bbox=(100.0, 1.0, 102.0, 2.0),
        class_qids=["Q33506", "Q16970", "Q570116"],
        config={
            "endpoint": "https://query.wikidata.org/sparql",
            "allowed_hosts": ["query.wikidata.org"],
            "max_bytes": 1234,
        },
        fetch_json=fetch_json,
        class_chunk_size=2,
        tile_degrees=1.0,
        sleep=lambda _seconds: None,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    data = json.loads(out.read_text())
    assert data["_meta"]["complete"] is True
    assert len(data["_meta"]["segments"]) == 4
    assert len(data["results"]["bindings"]) == 4
    assert all(call[1] == {"query.wikidata.org"} for call in calls)
    assert all(call[2] == 1234 for call in calls)
    first = data["results"]["bindings"][0]
    assert first["p31"]["value"] == "http://www.wikidata.org/entity/Q123"
    assert first["matched_class"]["value"] == "http://www.wikidata.org/entity/Q33506"


def test_wikidata_acquisition_normalizes_coord_literals(tmp_path):
    def fetch_json(*_args, **_kwargs):
        return {
            "results": {
                "bindings": [
                    {
                        "item": {"value": "http://www.wikidata.org/entity/Q1"},
                        "p31": {"value": "http://www.wikidata.org/entity/Q33506"},
                        "matched_class": {
                            "value": "http://www.wikidata.org/entity/Q570116"
                        },
                        "p31s": {
                            "value": "http://www.wikidata.org/entity/Q123|http://www.wikidata.org/entity/Q456"
                        },
                        "coord": {"value": "Point(101.5 3.25)"},
                        "label": {"value": "Place"},
                        "sitelinks": {"value": "4"},
                    }
                ]
            }
        }

    out = acquire.acquire_wikidata(
        tmp_path,
        bbox=(101.0, 3.0, 102.0, 4.0),
        class_qids=["Q33506"],
        config={
            "endpoint": "https://query.wikidata.org/sparql",
            "allowed_hosts": ["query.wikidata.org"],
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    binding = json.loads(out.read_text())["results"]["bindings"][0]
    assert binding["lat"]["value"] == "3.25"
    assert binding["lon"]["value"] == "101.5"
    assert binding["p31"]["value"] == "http://www.wikidata.org/entity/Q123"
    assert binding["matched_class"]["value"] == "http://www.wikidata.org/entity/Q570116"


def test_wikidata_acquisition_does_not_publish_incomplete_snapshot(tmp_path):
    def fetch_json(*_args, **_kwargs):
        raise acquire.RetryableAcquireError("busy", status=429)

    with pytest.raises(acquire.AcquireError):
        acquire.acquire_wikidata(
            tmp_path,
            bbox=(100.0, 1.0, 101.0, 2.0),
            class_qids=["Q33506"],
            config={
                "endpoint": "https://query.wikidata.org/sparql",
                "allowed_hosts": ["query.wikidata.org"],
            },
            fetch_json=fetch_json,
            retries=0,
            sleep=lambda _seconds: None,
            retrieved_at="2026-07-15T00:00:00Z",
        )

    assert not (tmp_path / "wikidata.snapshot.json").exists()


def test_retryable_wikidata_failures_backoff_then_succeed(tmp_path):
    attempts = []
    sleeps = []

    def fetch_json(*_args, **_kwargs):
        attempts.append(1)
        if len(attempts) == 1:
            raise acquire.RetryableAcquireError("rate limited", status=429)
        return {"results": {"bindings": []}}

    acquire.acquire_wikidata(
        tmp_path,
        bbox=(100.0, 1.0, 101.0, 2.0),
        class_qids=["Q33506"],
        config={
            "endpoint": "https://query.wikidata.org/sparql",
            "allowed_hosts": ["query.wikidata.org"],
        },
        fetch_json=fetch_json,
        sleep=sleeps.append,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    assert len(attempts) == 2
    assert sleeps == [1.0]


def test_retry_json_retries_wikimedia_maxlag_error_body(tmp_path):
    attempts = []
    sleeps = []

    def fetch_json(*_args, **_kwargs):
        attempts.append(1)
        if len(attempts) == 1:
            return {
                "error": {
                    "code": "maxlag",
                    "info": "Waiting for db101: 8 seconds lagged",
                }
            }
        return {"query": {"geosearch": []}}

    acquire.acquire_wikipedia(
        tmp_path,
        bbox=(100.0, 1.0, 101.0, 2.0),
        language="en",
        config={
            "endpoint": "https://en.wikipedia.org/w/api.php",
            "allowed_hosts": ["en.wikipedia.org"],
        },
        fetch_json=fetch_json,
        sleep=sleeps.append,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    assert len(attempts) == 2
    assert sleeps == [5.0]


def test_wikidata_timeouts_are_retryable(tmp_path):
    attempts = []

    def fetch_json(*_args, **_kwargs):
        attempts.append(1)
        if len(attempts) == 1:
            raise acquire.fetch.FetchError("The read operation timed out")
        return {"results": {"bindings": []}}

    acquire.acquire_wikidata(
        tmp_path,
        bbox=(100.0, 1.0, 101.0, 2.0),
        class_qids=["Q33506"],
        config={
            "endpoint": "https://query.wikidata.org/sparql",
            "allowed_hosts": ["query.wikidata.org"],
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    assert len(attempts) == 2


def test_retry_json_honors_retry_after_on_rate_limit(tmp_path):
    attempts = []
    sleeps = []

    def fetch_json(*_args, **_kwargs):
        attempts.append(1)
        if len(attempts) == 1:
            exc = acquire.fetch.FetchError("http 429: Too Many Requests")
            exc.status = 429
            exc.retry_after = 7.0
            raise exc
        return {"results": {"bindings": []}}

    acquire.acquire_wikidata(
        tmp_path,
        bbox=(100.0, 1.0, 101.0, 2.0),
        class_qids=["Q33506"],
        config={
            "endpoint": "https://query.wikidata.org/sparql",
            "allowed_hosts": ["query.wikidata.org"],
        },
        fetch_json=fetch_json,
        sleep=sleeps.append,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    assert len(attempts) == 2
    assert sleeps == [7.0]


def test_retry_json_clamps_excessive_retry_after(tmp_path):
    attempts = []
    sleeps = []

    def fetch_json(*_args, **_kwargs):
        attempts.append(1)
        if len(attempts) == 1:
            exc = acquire.fetch.FetchError(
                "http 429: Too Many Requests",
                status=429,
                retry_after=9999.0,
            )
            raise exc
        return {"results": {"bindings": []}}

    acquire.acquire_wikidata(
        tmp_path,
        bbox=(100.0, 1.0, 101.0, 2.0),
        class_qids=["Q33506"],
        config={
            "endpoint": "https://query.wikidata.org/sparql",
            "allowed_hosts": ["query.wikidata.org"],
        },
        fetch_json=fetch_json,
        sleep=sleeps.append,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    assert len(attempts) == 2
    assert sleeps == [acquire.MAX_RETRY_AFTER_SECONDS]


def test_wikidata_truncated_json_fetch_errors_are_retryable(tmp_path):
    attempts = []

    def fetch_json(*_args, **_kwargs):
        attempts.append(1)
        if len(attempts) == 1:
            raise acquire.fetch.FetchError("invalid JSON: Unterminated string")
        return {"results": {"bindings": []}}

    acquire.acquire_wikidata(
        tmp_path,
        bbox=(100.0, 1.0, 101.0, 2.0),
        class_qids=["Q33506"],
        config={
            "endpoint": "https://query.wikidata.org/sparql",
            "allowed_hosts": ["query.wikidata.org"],
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    assert len(attempts) == 2


def test_fetch_pageviews_for_title_uses_wikimedia_rest_and_normalizes_schema():
    calls = []

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        calls.append((url, expected_hosts, max_bytes, headers))
        parsed = urllib.parse.urlparse(url)
        assert parsed.path.endswith(
            "/metrics/pageviews/per-article/en.wikipedia/all-access/user/Big_Ben/daily/2025071400/2026071400"
        )
        assert expected_hosts == {"wikimedia.org"}
        assert max_bytes == 4321
        assert headers["User-Agent"].startswith("MakingTracksBot/")
        return {
            "items": [
                {
                    "project": "en.wikipedia",
                    "article": "Big_Ben",
                    "access": "all-access",
                    "agent": "user",
                    "granularity": "daily",
                    "timestamp": "2025071400",
                    "views": 5,
                },
                {
                    "project": "en.wikipedia",
                    "article": "Big_Ben",
                    "access": "all-access",
                    "agent": "user",
                    "granularity": "daily",
                    "timestamp": "2025071500",
                    "views": "8",
                },
                {
                    "project": "en.wikipedia",
                    "article": "Big_Ben",
                    "access": "all-access",
                    "agent": "user",
                    "granularity": "daily",
                    "timestamp": "2025071600",
                    "views": -3,
                },
            ]
        }

    result = acquire.fetch_pageviews_for_title(
        "Big Ben",
        ("2025-07-14", "2026-07-14"),
        language="en",
        config={
            "endpoint": "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article",
            "allowed_hosts": ["wikimedia.org"],
            "max_bytes": 4321,
            "access": "all-access",
            "agent": "user",
            "granularity": "daily",
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
    )

    assert result == {
        "title": "Big Ben",
        "window": ["2025-07-14", "2026-07-14"],
        "daily": [5, 8, 0],
    }
    assert len(calls) == 1


def test_acquire_all_applies_region_wikidata_tile_override(tmp_path, monkeypatch):
    config_path = tmp_path / "acquire_sources.json"
    config_path.write_text(
        json.dumps(
            {
                "wikidata": {
                    "endpoint": "https://query.wikidata.org/sparql",
                    "allowed_hosts": ["query.wikidata.org"],
                    "max_bytes": 1234,
                    "region_overrides": {"united-kingdom": {"tile_degrees": 0.5}},
                },
                "wikipedia": {
                    "endpoint": "https://en.wikipedia.org/w/api.php",
                    "allowed_hosts": ["en.wikipedia.org"],
                },
                "osm": {},
            }
        )
    )
    region_config = types.SimpleNamespace(
        region_id="united-kingdom",
        bbox=(-1.0, 50.0, 1.0, 51.0),
        languages=["en"],
        sources={"wikidata": True, "wikipedia": False, "osm": False},
    )
    captured = {}

    def fake_acquire_wikidata(_dest, *, bbox, class_qids, config, tile_degrees):
        captured.update(
            {
                "bbox": bbox,
                "class_qids": class_qids,
                "config": config,
                "tile_degrees": tile_degrees,
            }
        )
        return tmp_path / "wikidata.snapshot.json"

    monkeypatch.setattr(acquire, "load_class_qids", lambda: ["Q33506"])
    monkeypatch.setattr(acquire, "acquire_wikidata", fake_acquire_wikidata)
    monkeypatch.setattr(acquire, "acquire_registers", lambda *_args, **_kwargs: {})

    acquire.acquire_all(tmp_path, region_config=region_config, config_path=config_path)

    assert captured == {
        "bbox": region_config.bbox,
        "class_qids": ["Q33506"],
        "config": {
            "endpoint": "https://query.wikidata.org/sparql",
            "allowed_hosts": ["query.wikidata.org"],
            "max_bytes": 1234,
            "tile_degrees": 0.5,
        },
        "tile_degrees": 0.5,
    }


def test_acquire_all_runs_pageviews_when_region_opts_in(tmp_path, monkeypatch):
    config_path = tmp_path / "acquire_sources.json"
    config_path.write_text(
        json.dumps(
            {
                "wikidata": {
                    "endpoint": "https://query.wikidata.org/sparql",
                    "allowed_hosts": ["query.wikidata.org"],
                },
                "wikipedia": {
                    "endpoint": "https://en.wikipedia.org/w/api.php",
                    "allowed_hosts": ["en.wikipedia.org"],
                },
                "pageviews": {
                    "endpoint": "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article",
                    "allowed_hosts": ["wikimedia.org"],
                    "max_bytes": 1234,
                    "polite_interval_seconds": 0.5,
                },
                "osm": {},
            }
        )
    )
    region_config = types.SimpleNamespace(
        region_id="malaysia-singapore-brunei",
        bbox=(100.0, 1.0, 101.0, 2.0),
        languages=["en"],
        sources={"wikidata": False, "wikipedia": True, "osm": False},
        raw={"pageviews": {"enabled": True, "months": 12}},
    )
    wikipedia_snapshot = tmp_path / "wikipedia.snapshot.json"
    captured = {}

    def fake_acquire_wikipedia(*_args, **_kwargs):
        wikipedia_snapshot.write_text(
            json.dumps(
                {
                    "_meta": {
                        "complete": True,
                        "retrieved_at": "2026-07-15T08:03:37Z",
                    },
                    "lang": "en",
                    "pages": [
                        {"title": "Beta", "pageid": 2},
                        {"title": "Alpha", "pageid": 1},
                        {"title": "Alpha", "pageid": 3},
                    ],
                }
            )
        )
        return wikipedia_snapshot

    def fake_acquire_pageviews(titles, window, cache_dir, **kwargs):
        captured["titles"] = list(titles)
        captured["window"] = window
        captured["cache_dir"] = cache_dir
        captured["enabled"] = kwargs["enabled"]
        captured["polite_interval_seconds"] = kwargs["polite_interval_seconds"]
        return 2

    monkeypatch.setattr(acquire, "acquire_wikipedia", fake_acquire_wikipedia)
    monkeypatch.setattr(acquire, "acquire_registers", lambda *_args, **_kwargs: {})
    monkeypatch.setattr(acquire.pageviews, "acquire", fake_acquire_pageviews)

    paths = acquire.acquire_all(tmp_path, region_config=region_config, config_path=config_path)

    assert paths["pageviews"] == tmp_path / "pageviews"
    assert captured == {
        "titles": ["Alpha", "Beta"],
        "window": ("2025-07-15", "2026-07-15"),
        "cache_dir": tmp_path / "pageviews",
        "enabled": True,
        "polite_interval_seconds": 0.5,
    }


def test_acquire_all_skips_pageviews_when_region_opts_out(tmp_path, monkeypatch):
    config_path = tmp_path / "acquire_sources.json"
    config_path.write_text(
        json.dumps(
            {
                "wikidata": {
                    "endpoint": "https://query.wikidata.org/sparql",
                    "allowed_hosts": ["query.wikidata.org"],
                },
                "wikipedia": {
                    "endpoint": "https://en.wikipedia.org/w/api.php",
                    "allowed_hosts": ["en.wikipedia.org"],
                },
                "pageviews": {
                    "endpoint": "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article",
                    "allowed_hosts": ["wikimedia.org"],
                },
                "osm": {},
            }
        )
    )
    region_config = types.SimpleNamespace(
        region_id="united-kingdom",
        bbox=(100.0, 1.0, 101.0, 2.0),
        languages=["en"],
        sources={"wikidata": False, "wikipedia": True, "osm": False},
        raw={"pageviews": {"enabled": False, "months": 12}},
    )
    wikipedia_snapshot = tmp_path / "wikipedia.snapshot.json"

    def fake_acquire_wikipedia(*_args, **_kwargs):
        wikipedia_snapshot.write_text(
            json.dumps(
                {
                    "_meta": {
                        "complete": True,
                        "retrieved_at": "2026-07-15T08:03:37Z",
                    },
                    "lang": "en",
                    "pages": [{"title": "Alpha", "pageid": 1}],
                }
            )
        )
        return wikipedia_snapshot

    def fail_pageviews(*_args, **_kwargs):
        raise AssertionError("pageviews should not run")

    monkeypatch.setattr(acquire, "acquire_wikipedia", fake_acquire_wikipedia)
    monkeypatch.setattr(acquire, "acquire_registers", lambda *_args, **_kwargs: {})
    monkeypatch.setattr(acquire.pageviews, "acquire", fail_pageviews)

    paths = acquire.acquire_all(tmp_path, region_config=region_config, config_path=config_path)

    assert "pageviews" not in paths


def test_wikipedia_acquisition_writes_complete_snapshot(tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(acquire, "_WIKIPEDIA_HEARTBEAT_EVERY_PAGES", 1, raising=False)
    calls = []

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        calls.append(url)
        parsed = urllib.parse.urlparse(url)
        params = urllib.parse.parse_qs(parsed.query)
        assert params["maxlag"] == ["5"]
        assert expected_hosts == {"en.wikipedia.org"}
        assert headers["User-Agent"].startswith("MakingTracksBot/")
        if params.get("list") == ["geosearch"]:
            return {
                "query": {
                    "geosearch": [
                        {"pageid": 20, "title": "Beta", "lat": 1.1, "lon": 101.1},
                        {"pageid": 10, "title": "Alpha", "lat": 1.0, "lon": 101.0},
                    ]
                }
            }
        assert params["pageids"] == ["10|20"]
        assert params["exlimit"] == ["max"]
        assert params["maxlag"] == ["5"]
        return {
            "query": {
                "pages": {
                    "10": {
                        "pageid": 10,
                        "title": "Alpha",
                        "extract": "About Alpha",
                        "coordinates": [{"lat": 1.0, "lon": 101.0}],
                        "pageprops": {"wikibase_item": "Q10"},
                    },
                    "20": {
                        "pageid": 20,
                        "title": "Beta",
                        "extract": "About Beta",
                        "coordinates": [{"lat": 1.1, "lon": 101.1}],
                    },
                }
            }
        }

    out = acquire.acquire_wikipedia(
        tmp_path,
        bbox=(100.0, 1.0, 101.0, 2.0),
        language="en",
        config={
            "endpoint": "https://en.wikipedia.org/w/api.php",
            "allowed_hosts": ["en.wikipedia.org"],
            "max_bytes": 4321,
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    data = json.loads(out.read_text())
    assert data["_meta"]["complete"] is True
    assert data["lang"] == "en"
    assert [page["pageid"] for page in data["pages"]] == [10, 20]
    assert data["pages"][0]["wikidata"] == "Q10"
    assert len(calls) == 2
    err = capsys.readouterr().err
    assert "PHASE START acquire.wikipedia.geosearch region=en tiles=1" in err
    assert "PHASE DONE acquire.wikipedia.geosearch region=en processed=1/1" in err
    assert "segments=1 pageids=2" in err
    assert "PHASE START acquire.wikipedia.page_fetch region=en pages=2" in err
    assert "PHASE HEARTBEAT acquire.wikipedia.page_fetch region=en processed=2/2" in err
    assert "pages=2" in err
    assert "PHASE START acquire.wikipedia.persist region=en pages=2" in err
    assert "PHASE DONE acquire.wikipedia.persist region=en processed=2/2" in err


def test_wikipedia_acquisition_heartbeats_while_geosearch_worker_is_busy(
    tmp_path,
    capsys,
    monkeypatch,
):
    monkeypatch.setattr(acquire, "_WIKIPEDIA_HEARTBEAT_EVERY_SECONDS", 0.01, raising=False)

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        parsed = urllib.parse.urlparse(url)
        params = urllib.parse.parse_qs(parsed.query)
        if params.get("list") == ["geosearch"]:
            time.sleep(0.03)
            return {"query": {"geosearch": []}}
        raise AssertionError("page fetch should not run when geosearch is empty")

    acquire.acquire_wikipedia(
        tmp_path,
        bbox=(100.0, 1.0, 101.0, 2.0),
        language="en",
        config={
            "endpoint": "https://en.wikipedia.org/w/api.php",
            "allowed_hosts": ["en.wikipedia.org"],
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
        retrieved_at="2026-07-15T00:00:00Z",
    )

    err = capsys.readouterr().err
    assert "PHASE HEARTBEAT acquire.wikipedia.geosearch region=en processed=0/1" in err


def test_wikipedia_persist_done_is_not_logged_when_atomic_write_fails(
    tmp_path,
    capsys,
    monkeypatch,
):
    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        parsed = urllib.parse.urlparse(url)
        params = urllib.parse.parse_qs(parsed.query)
        if params.get("list") == ["geosearch"]:
            return {"query": {"geosearch": []}}
        raise AssertionError("page fetch should not run when geosearch is empty")

    def fail_write(*_args, **_kwargs):
        path = _args[0]
        if path.name == "wikipedia.snapshot.json":
            raise OSError("disk full")
        return original_write(*_args, **_kwargs)

    original_write = acquire._atomic_write_json
    monkeypatch.setattr(acquire, "_atomic_write_json", fail_write)

    with pytest.raises(OSError, match="disk full"):
        acquire.acquire_wikipedia(
            tmp_path,
            bbox=(100.0, 1.0, 101.0, 2.0),
            language="en",
            config={
                "endpoint": "https://en.wikipedia.org/w/api.php",
                "allowed_hosts": ["en.wikipedia.org"],
            },
            fetch_json=fetch_json,
            sleep=lambda _seconds: None,
            retrieved_at="2026-07-15T00:00:00Z",
        )

    err = capsys.readouterr().err
    assert "PHASE START acquire.wikipedia.persist region=en pages=0" in err
    assert "PHASE DONE acquire.wikipedia.persist" not in err


def test_qid_sitelink_acquisition_augments_wikipedia_snapshot_with_verified_pages(tmp_path):
    snapshot = tmp_path / "wikipedia.snapshot.json"
    snapshot.write_text(
        json.dumps(
            {
                "_meta": {
                    "complete": True,
                    "retrieved_at": "2026-07-20T00:00:00Z",
                    "segments": [],
                },
                "lang": "en",
                "pages": [],
            },
            sort_keys=True,
        )
    )
    calls = []

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        calls.append(url)
        parsed = urllib.parse.urlparse(url)
        params = urllib.parse.parse_qs(parsed.query)
        assert headers["User-Agent"].startswith("MakingTracksBot/")
        if parsed.netloc == "www.wikidata.org":
            assert expected_hosts == {"www.wikidata.org"}
            assert params["action"] == ["wbgetentities"]
            assert params["ids"] == ["Q42|Q99"]
            assert params["maxlag"] == ["5"]
            return {
                "entities": {
                    "Q42": {"sitelinks": {"enwiki": {"title": "QID Article"}}},
                    "Q99": {"sitelinks": {"enwiki": {"title": "Wrong Article"}}},
                }
            }
        assert expected_hosts == {"en.wikipedia.org"}
        assert params["titles"] == ["QID Article|Wrong Article"]
        assert params["prop"] == ["extracts|pageimages|pageprops"]
        assert params["exlimit"] == ["max"]
        assert params["maxlag"] == ["5"]
        return {
            "query": {
                "pages": {
                    "12345": {
                        "pageid": 12345,
                        "title": "QID Article",
                        "extract": "Verified extract.",
                        "pageprops": {"wikibase_item": "Q42"},
                        "original": {
                            "source": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg"
                        },
                    },
                    "999": {
                        "pageid": 999,
                        "title": "Wrong Article",
                        "extract": "Wrong extract.",
                        "pageprops": {"wikibase_item": "Q100"},
                    },
                }
            }
        }

    out = acquire.acquire_qid_sitelink_wikipedia(
        snapshot,
        seeds=[
            {"qid": "Q99", "lat": 1.2, "lon": 100.2},
            {"qid": "Q42", "lat": 3.1, "lon": 101.7},
            {"qid": "not-a-qid", "lat": 0, "lon": 0},
        ],
        language="en",
        wikidata_config={
            "endpoint": "https://www.wikidata.org/w/api.php",
            "allowed_hosts": ["www.wikidata.org"],
        },
        wikipedia_config={
            "endpoint": "https://en.wikipedia.org/w/api.php",
            "allowed_hosts": ["en.wikipedia.org"],
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
        retrieved_at="2026-07-20T01:00:00Z",
    )

    data = json.loads(out.read_text())
    assert out == snapshot
    assert data["_meta"]["complete"] is True
    assert data["_meta"]["qid_sitelink_retrieved_at"] == "2026-07-20T01:00:00Z"
    assert data["qid_pages"] == [
        {
            "extract": "Verified extract.",
            "image": "https://upload.wikimedia.org/wikipedia/commons/a/aa/Fort.jpg",
            "owner_lat": 3.1,
            "owner_lon": 101.7,
            "pageid": 12345,
            "qid": "Q42",
            "title": "QID Article",
            "wikibase_item": "Q42",
        }
    ]
    assert len(calls) == 2


def test_qid_sitelink_acquisition_refreshes_blank_accepted_extracts(tmp_path):
    snapshot = tmp_path / "wikipedia.snapshot.json"
    snapshot.write_text(
        json.dumps(
            {
                "_meta": {
                    "complete": True,
                    "retrieved_at": "2026-07-20T00:00:00Z",
                    "segments": [],
                },
                "lang": "en",
                "pages": [
                    {
                        "extract": "",
                        "lat": 3.1,
                        "lon": 101.7,
                        "pageid": 12345,
                        "title": "QID Article",
                        "wikidata": "Q42",
                    }
                ],
            },
            sort_keys=True,
        )
    )
    wikipedia_calls = 0

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        nonlocal wikipedia_calls
        parsed = urllib.parse.urlparse(url)
        if parsed.netloc == "www.wikidata.org":
            return {"entities": {"Q42": {"sitelinks": {"enwiki": {"title": "QID Article"}}}}}
        params = urllib.parse.parse_qs(parsed.query)
        assert params["exlimit"] == ["max"]
        assert params["maxlag"] == ["5"]
        wikipedia_calls += 1
        if wikipedia_calls == 1:
            return {
                "query": {
                    "pages": {
                        "12345": {
                            "pageid": 12345,
                            "title": "QID Article",
                            "extract": "",
                            "pageprops": {"wikibase_item": "Q42"},
                        }
                    }
                }
            }
        return {
            "query": {
                "pages": {
                    "12345": {
                        "pageid": 12345,
                        "title": "QID Article",
                        "extract": "Recovered extract.",
                        "pageprops": {"wikibase_item": "Q42"},
                    }
                }
            }
        }

    out = acquire.acquire_qid_sitelink_wikipedia(
        snapshot,
        seeds=[{"qid": "Q42", "lat": 3.1, "lon": 101.7}],
        language="en",
        wikidata_config={
            "endpoint": "https://www.wikidata.org/w/api.php",
            "allowed_hosts": ["www.wikidata.org"],
        },
        wikipedia_config={
            "endpoint": "https://en.wikipedia.org/w/api.php",
            "allowed_hosts": ["en.wikipedia.org"],
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
        retrieved_at="2026-07-20T01:00:00Z",
    )

    data = json.loads(out.read_text())
    assert wikipedia_calls == 2
    assert data["qid_pages"][0]["extract"] == "Recovered extract."
    assert data["pages"][0]["extract"] == "Recovered extract."
    assert data["_meta"]["qid_sitelink_blank_extract_refresh"] == {
        "accepted_pages": 1,
        "blank_before": 1,
        "content_sha256_after": data["_meta"]["qid_sitelink_blank_extract_refresh"][
            "content_sha256_after"
        ],
        "content_sha256_before": data["_meta"]["qid_sitelink_blank_extract_refresh"][
            "content_sha256_before"
        ],
        "recovered": 1,
        "skipped_mismatch": 0,
        "single_title_fallbacks": 0,
        "still_blank": 0,
    }
    assert (
        data["_meta"]["qid_sitelink_blank_extract_refresh"]["content_sha256_before"]
        != data["_meta"]["qid_sitelink_blank_extract_refresh"]["content_sha256_after"]
    )


def test_qid_sitelink_blank_extract_refresh_skips_wikibase_mismatch(tmp_path):
    snapshot = tmp_path / "wikipedia.snapshot.json"
    snapshot.write_text(
        json.dumps(
            {
                "_meta": {
                    "complete": True,
                    "retrieved_at": "2026-07-20T00:00:00Z",
                    "segments": [],
                },
                "lang": "en",
                "pages": [],
            },
            sort_keys=True,
        )
    )
    wikipedia_calls = 0

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        nonlocal wikipedia_calls
        parsed = urllib.parse.urlparse(url)
        if parsed.netloc == "www.wikidata.org":
            return {"entities": {"Q42": {"sitelinks": {"enwiki": {"title": "QID Article"}}}}}
        params = urllib.parse.parse_qs(parsed.query)
        assert params["exlimit"] == ["max"]
        assert params["maxlag"] == ["5"]
        wikipedia_calls += 1
        return {
            "query": {
                "pages": {
                    "12345": {
                        "pageid": 12345,
                        "title": "QID Article",
                        "extract": "" if wikipedia_calls == 1 else "Wrong QID extract.",
                        "pageprops": {
                            "wikibase_item": "Q42" if wikipedia_calls == 1 else "Q999"
                        },
                    }
                }
            }
        }

    out = acquire.acquire_qid_sitelink_wikipedia(
        snapshot,
        seeds=[{"qid": "Q42", "lat": 3.1, "lon": 101.7}],
        language="en",
        wikidata_config={
            "endpoint": "https://www.wikidata.org/w/api.php",
            "allowed_hosts": ["www.wikidata.org"],
        },
        wikipedia_config={
            "endpoint": "https://en.wikipedia.org/w/api.php",
            "allowed_hosts": ["en.wikipedia.org"],
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
        retrieved_at="2026-07-20T01:00:00Z",
    )

    data = json.loads(out.read_text())
    assert wikipedia_calls == 2
    assert data["qid_pages"][0]["extract"] == ""
    assert data["_meta"]["qid_sitelink_blank_extract_refresh"]["recovered"] == 0
    assert data["_meta"]["qid_sitelink_blank_extract_refresh"]["skipped_mismatch"] == 1
    assert data["_meta"]["qid_sitelink_blank_extract_refresh"]["still_blank"] == 1


def test_blank_extract_refresh_falls_back_to_single_title_when_batch_stays_blank(
    tmp_path,
    capsys,
    monkeypatch,
):
    monkeypatch.setattr(acquire, "_BLANK_EXTRACT_HEARTBEAT_EVERY_PAGES", 1, raising=False)
    snapshot = tmp_path / "wikipedia.snapshot.json"
    snapshot.write_text(
        json.dumps(
            {
                "_meta": {
                    "complete": True,
                    "retrieved_at": "2026-07-20T00:00:00Z",
                    "segments": [],
                },
                "lang": "en",
                "pages": [],
                "qid_pages": [
                    {
                        "extract": "",
                        "owner_lat": 3.1,
                        "owner_lon": 101.7,
                        "pageid": 42,
                        "qid": "Q42",
                        "title": "QID Article",
                        "wikibase_item": "Q42",
                    },
                    {
                        "extract": "",
                        "owner_lat": 3.2,
                        "owner_lon": 101.8,
                        "pageid": 43,
                        "qid": "Q43",
                        "title": "Other Article",
                        "wikibase_item": "Q43",
                    },
                ],
            },
            sort_keys=True,
        )
    )
    titles_seen = []

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        parsed = urllib.parse.urlparse(url)
        params = urllib.parse.parse_qs(parsed.query)
        assert params["maxlag"] == ["5"]
        titles = params["titles"][0]
        titles_seen.append(titles)
        pages = {
            "42": {
                "pageid": 42,
                "title": "QID Article",
                "extract": "",
                "pageprops": {"wikibase_item": "Q42"},
            },
            "43": {
                "pageid": 43,
                "title": "Other Article",
                "extract": "",
                "pageprops": {"wikibase_item": "Q43"},
            },
        }
        if titles == "QID Article":
            pages = {
                "42": {
                    "pageid": 42,
                    "title": "QID Article",
                    "extract": "Single-title recovered extract.",
                    "pageprops": {"wikibase_item": "Q42"},
                }
            }
        elif titles == "Other Article":
            pages = {
                "43": {
                    "pageid": 43,
                    "title": "Other Article",
                    "extract": "",
                    "pageprops": {"wikibase_item": "Q43"},
                }
            }
        return {"query": {"pages": pages}}

    out = acquire.refresh_blank_qid_page_extracts(
        snapshot,
        language="en",
        wikipedia_config={
            "endpoint": "https://en.wikipedia.org/w/api.php",
            "allowed_hosts": ["en.wikipedia.org"],
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
        refreshed_at="2026-07-20T02:00:00Z",
    )

    data = json.loads(out.read_text())
    by_qid = {page["qid"]: page for page in data["qid_pages"]}
    assert titles_seen == ["Other Article|QID Article", "Other Article", "QID Article"]
    assert by_qid["Q42"]["extract"] == "Single-title recovered extract."
    assert by_qid["Q43"]["extract"] == ""
    assert data["_meta"]["qid_sitelink_blank_extract_refresh"]["recovered"] == 1
    assert data["_meta"]["qid_sitelink_blank_extract_refresh"]["single_title_fallbacks"] == 2
    assert data["_meta"]["qid_sitelink_blank_extract_refresh"]["still_blank"] == 1
    err = capsys.readouterr().err
    assert "PHASE START blank_extract.batch_refresh region=en pages=2" in err
    assert (
        "PHASE HEARTBEAT blank_extract.batch_refresh region=en processed=2/2"
    ) in err
    assert "recovered=0 skipped_mismatch=0 fallback_count=0" in err
    assert "PHASE DONE blank_extract.batch_refresh region=en processed=2/2" in err
    assert "PHASE START blank_extract.single_title_fallback region=en pages=2" in err
    assert (
        "PHASE HEARTBEAT blank_extract.single_title_fallback region=en processed=1/2"
    ) in err
    assert (
        "PHASE HEARTBEAT blank_extract.single_title_fallback region=en processed=2/2"
    ) in err
    assert "recovered=1 skipped_mismatch=0 fallback_count=2" in err
    assert "PHASE DONE blank_extract.single_title_fallback region=en processed=2/2" in err
    assert "PHASE START blank_extract.persist region=en pages=2" in err
    assert "PHASE DONE blank_extract.persist region=en processed=2/2" in err


def test_blank_extract_batch_refresh_counts_duplicate_titles_as_pages(
    tmp_path,
    capsys,
    monkeypatch,
):
    monkeypatch.setattr(acquire, "_BLANK_EXTRACT_HEARTBEAT_EVERY_PAGES", 1, raising=False)
    snapshot = tmp_path / "wikipedia.snapshot.json"
    snapshot.write_text(
        json.dumps(
            {
                "_meta": {
                    "complete": True,
                    "retrieved_at": "2026-07-20T00:00:00Z",
                    "segments": [],
                },
                "lang": "en",
                "pages": [],
                "qid_pages": [
                    {
                        "extract": "",
                        "owner_lat": 3.1,
                        "owner_lon": 101.7,
                        "pageid": 42,
                        "qid": "Q42",
                        "title": "Shared Article",
                        "wikibase_item": "Q42",
                    },
                    {
                        "extract": "",
                        "owner_lat": 3.2,
                        "owner_lon": 101.8,
                        "pageid": 43,
                        "qid": "Q43",
                        "title": "Shared Article",
                        "wikibase_item": "Q43",
                    },
                ],
            },
            sort_keys=True,
        )
    )

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        return {
            "query": {
                "pages": {
                    "42": {
                        "pageid": 42,
                        "title": "Shared Article",
                        "extract": "",
                        "pageprops": {"wikibase_item": "Q42"},
                    }
                }
            }
        }

    acquire.refresh_blank_qid_page_extracts(
        snapshot,
        language="en",
        wikipedia_config={
            "endpoint": "https://en.wikipedia.org/w/api.php",
            "allowed_hosts": ["en.wikipedia.org"],
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
        refreshed_at="2026-07-20T02:00:00Z",
    )

    err = capsys.readouterr().err
    assert "PHASE START blank_extract.batch_refresh region=en pages=2" in err
    assert "PHASE DONE blank_extract.batch_refresh region=en processed=2/2" in err


def test_qid_sitelink_acquisition_skips_malformed_page_entries(tmp_path):
    snapshot = tmp_path / "wikipedia.snapshot.json"
    snapshot.write_text(
        json.dumps(
            {
                "_meta": {
                    "complete": True,
                    "retrieved_at": "2026-07-20T00:00:00Z",
                    "segments": [],
                },
                "lang": "en",
                "pages": [],
            },
            sort_keys=True,
        )
    )

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        parsed = urllib.parse.urlparse(url)
        if parsed.netloc == "www.wikidata.org":
            return {
                "entities": {
                    "Q42": {"sitelinks": {"enwiki": {"title": "Verified"}}},
                    "Q43": {"sitelinks": {"enwiki": {"title": "Bad Props"}}},
                }
            }
        return {
            "query": {
                "pages": {
                    "not-numeric": {
                        "pageid": "not-numeric",
                        "title": "Verified",
                        "pageprops": {"wikibase_item": "Q42"},
                    },
                    "43": {
                        "pageid": 43,
                        "title": "Bad Props",
                        "pageprops": "not-an-object",
                    },
                    "42": {
                        "pageid": 42,
                        "title": "Verified",
                        "extract": "Verified extract.",
                        "pageprops": {"wikibase_item": "Q42"},
                    },
                }
            }
        }

    out = acquire.acquire_qid_sitelink_wikipedia(
        snapshot,
        seeds=[
            {"qid": "Q42", "lat": 3.1, "lon": 101.7},
            {"qid": "Q43", "lat": 3.2, "lon": 101.8},
        ],
        language="en",
        wikidata_config={
            "endpoint": "https://www.wikidata.org/w/api.php",
            "allowed_hosts": ["www.wikidata.org"],
        },
        wikipedia_config={
            "endpoint": "https://en.wikipedia.org/w/api.php",
            "allowed_hosts": ["en.wikipedia.org"],
        },
        fetch_json=fetch_json,
        sleep=lambda _seconds: None,
        retrieved_at="2026-07-20T01:00:00Z",
    )

    assert [item["pageid"] for item in json.loads(out.read_text())["qid_pages"]] == [42]


def test_qid_sitelink_acquisition_rejects_malformed_response_containers(tmp_path):
    snapshot = tmp_path / "wikipedia.snapshot.json"
    snapshot.write_text(
        json.dumps(
            {
                "_meta": {
                    "complete": True,
                    "retrieved_at": "2026-07-20T00:00:00Z",
                    "segments": [],
                },
                "lang": "en",
                "pages": [],
            },
            sort_keys=True,
        )
    )

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        parsed = urllib.parse.urlparse(url)
        if parsed.netloc == "www.wikidata.org":
            return []
        return {"query": []}

    with pytest.raises(acquire.AcquireError, match="entities response"):
        acquire.acquire_qid_sitelink_wikipedia(
            snapshot,
            seeds=[{"qid": "Q42", "lat": 3.1, "lon": 101.7}],
            language="en",
            wikidata_config={
                "endpoint": "https://www.wikidata.org/w/api.php",
                "allowed_hosts": ["www.wikidata.org"],
            },
            wikipedia_config={
                "endpoint": "https://en.wikipedia.org/w/api.php",
                "allowed_hosts": ["en.wikipedia.org"],
            },
            fetch_json=fetch_json,
            sleep=lambda _seconds: None,
            retrieved_at="2026-07-20T01:00:00Z",
        )


def test_qid_sitelink_acquisition_rejects_malformed_wikipedia_query(tmp_path):
    snapshot = tmp_path / "wikipedia.snapshot.json"
    snapshot.write_text(
        json.dumps(
            {
                "_meta": {
                    "complete": True,
                    "retrieved_at": "2026-07-20T00:00:00Z",
                    "segments": [],
                },
                "lang": "en",
                "pages": [],
            },
            sort_keys=True,
        )
    )

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        parsed = urllib.parse.urlparse(url)
        if parsed.netloc == "www.wikidata.org":
            return {"entities": {"Q42": {"sitelinks": {"enwiki": {"title": "Verified"}}}}}
        return {"query": []}

    with pytest.raises(acquire.AcquireError, match="pages response"):
        acquire.acquire_qid_sitelink_wikipedia(
            snapshot,
            seeds=[{"qid": "Q42", "lat": 3.1, "lon": 101.7}],
            language="en",
            wikidata_config={
                "endpoint": "https://www.wikidata.org/w/api.php",
                "allowed_hosts": ["www.wikidata.org"],
            },
            wikipedia_config={
                "endpoint": "https://en.wikipedia.org/w/api.php",
                "allowed_hosts": ["en.wikipedia.org"],
            },
            fetch_json=fetch_json,
            sleep=lambda _seconds: None,
            retrieved_at="2026-07-20T01:00:00Z",
        )


def test_qid_sitelink_seeds_from_store_use_lowest_place_id_for_duplicate_qids(tmp_path):
    db = tmp_path / "w.db"
    conn = store.connect(db)
    store.init_schema(conn)
    store.replace_places(
        conn,
        region="malaysia-singapore-brunei",
        places=[
            {
                "place_id": "place-z",
                "name": "Later",
                "lat": 9.0,
                "lon": 109.0,
                "refs": ["wd:Q42"],
                "member_refs": ["osm:node/2"],
                "status": "active",
            },
            {
                "place_id": "place-a",
                "name": "Earlier",
                "lat": 1.0,
                "lon": 101.0,
                "refs": ["wd:Q42"],
                "member_refs": ["osm:node/1"],
                "status": "active",
            },
        ],
    )
    conn.execute("PRAGMA reverse_unordered_selects = ON")

    assert acquire.qid_sitelink_seeds_from_store(
        conn,
        region="malaysia-singapore-brunei",
    ) == [{"qid": "Q42", "lat": 1.0, "lon": 101.0}]


def test_wikipedia_acquisition_fails_loudly_on_api_error(tmp_path):
    with pytest.raises(acquire.AcquireError, match="toobig"):
        acquire.acquire_wikipedia(
            tmp_path,
            bbox=(100.0, 1.0, 101.0, 2.0),
            language="en",
            config={
                "endpoint": "https://en.wikipedia.org/w/api.php",
                "allowed_hosts": ["en.wikipedia.org"],
            },
            fetch_json=lambda *_args, **_kwargs: {
                "error": {"code": "toobig", "info": "Bounding box is too big"}
            },
            sleep=lambda _seconds: None,
            retrieved_at="2026-07-15T00:00:00Z",
        )


def test_wikidata_redirect_map_segments_known_qids_and_marks_complete(tmp_path):
    calls = []

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        calls.append(url)
        parsed = urllib.parse.urlparse(url)
        query = urllib.parse.parse_qs(parsed.query)["query"][0]
        assert "schema:about" in query
        assert "owl:sameAs" in query
        assert headers["User-Agent"].startswith("MakingTracksBot/")
        if "wd:Q1" in query:
            return {
                "results": {
                    "bindings": [
                        {
                            "from": {"value": "http://www.wikidata.org/entity/Q1"},
                            "to": {"value": "http://www.wikidata.org/entity/Q10"},
                        }
                    ]
                }
            }
        return {"results": {"bindings": []}}

    out = acquire.acquire_wikidata_redirect_map(
        tmp_path,
        qids=["Q1", "Q2", "not-a-qid", "Q3"],
        config={
            "endpoint": "https://query.wikidata.org/sparql",
            "allowed_hosts": ["query.wikidata.org"],
        },
        wikidata_retrieved_at="2026-07-15T00:00:00Z",
        fetch_json=fetch_json,
        qid_chunk_size=2,
        sleep=lambda _seconds: None,
        retrieved_at="2026-07-15T00:00:01Z",
    )

    data = json.loads(out.read_text())
    assert data["_meta"]["complete"] is True
    assert data["_meta"]["wikidata_retrieved_at"] == "2026-07-15T00:00:00Z"
    assert data["redirects"] == {"Q1": "Q10"}
    assert len(data["_meta"]["segments"]) == 2
    assert len(calls) == 2


def test_redirect_map_refuses_to_publish_if_older_than_wikidata(tmp_path):
    with pytest.raises(acquire.AcquireError, match="older"):
        acquire.acquire_wikidata_redirect_map(
            tmp_path,
            qids=["Q1"],
            config={
                "endpoint": "https://query.wikidata.org/sparql",
                "allowed_hosts": ["query.wikidata.org"],
            },
            wikidata_retrieved_at="2026-07-15T00:00:01Z",
            fetch_json=lambda *_args, **_kwargs: {"results": {"bindings": []}},
            sleep=lambda _seconds: None,
            retrieved_at="2026-07-15T00:00:00Z",
        )

    assert not (tmp_path / "wikidata_redirects.snapshot.json").exists()


def test_wikipedia_segment_merge_is_completion_order_independent(tmp_path):
    segments = []
    payloads = [
        {"bbox": [1, 0, 2, 1], "count": 1, "index": 1, "rows": [{"pageid": 20}]},
        {"bbox": [0, 0, 1, 1], "count": 2, "index": 0, "rows": [{"pageid": 10}, {"pageid": 20}]},
        {"bbox": [2, 0, 3, 1], "count": 1, "index": 2, "rows": [{"pageid": 30}]},
    ]
    for payload in payloads:
        path = tmp_path / f"{payload['index']:06d}.json"
        path.write_text(json.dumps(payload, sort_keys=True))
        segments.append(path)

    first = acquire._merge_wikipedia_segments([segments[2], segments[0], segments[1]])
    second = acquire._merge_wikipedia_segments([segments[1], segments[2], segments[0]])

    assert json.dumps(first, sort_keys=True).encode() == json.dumps(
        second, sort_keys=True
    ).encode()
