import json
import types
import urllib.parse

import pytest

from mt_pipeline import acquire


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


def test_wikipedia_acquisition_writes_complete_snapshot(tmp_path):
    calls = []

    def fetch_json(url, *, expected_hosts, max_bytes, headers):
        calls.append(url)
        parsed = urllib.parse.urlparse(url)
        params = urllib.parse.parse_qs(parsed.query)
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
