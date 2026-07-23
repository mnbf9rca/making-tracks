import email.message
import hashlib
import io
import json
import logging
import urllib.error
import urllib.request
import urllib.response

import pytest

from mt_pipeline import fetch


class _FakeOpener:
    def __init__(self, body):
        self._body = body

    def open(self, url, timeout=None):
        return io.BytesIO(self._body)


def _body(monkeypatch, data):
    monkeypatch.setattr(fetch, "_opener", lambda hosts: _FakeOpener(data))


def test_rejects_non_https():
    with pytest.raises(fetch.FetchError):
        fetch.get_json("http://insecure/x", expected_hosts={"insecure"})


def test_rejects_unexpected_host():
    with pytest.raises(fetch.FetchError):
        fetch.get_json("https://evil.example/x", expected_hosts={"query.wikidata.org"})


def test_streams_and_caps_oversize_body(monkeypatch):
    _body(monkeypatch, b'{"x":"' + b"a" * 4096 + b'"}')
    with pytest.raises(fetch.FetchError):
        fetch.get_json(
            "https://query.wikidata.org/x",
            expected_hosts={"query.wikidata.org"},
            max_bytes=1024,
        )


def test_returns_parsed_json_within_cap(monkeypatch):
    _body(monkeypatch, json.dumps({"ok": 1}).encode())
    assert fetch.get_json(
        "https://query.wikidata.org/x", expected_hosts={"query.wikidata.org"}
    ) == {"ok": 1}


def test_http_error_carries_status_and_retry_after(monkeypatch):
    class Opener:
        def open(self, url, timeout=None):
            headers = email.message.Message()
            headers["Retry-After"] = "7"
            raise urllib.error.HTTPError(
                url,
                429,
                "Too Many Requests",
                headers,
                None,
            )

    monkeypatch.setattr(fetch, "_opener", lambda hosts: Opener())

    with pytest.raises(fetch.FetchError) as excinfo:
        fetch.get_json(
            "https://query.wikidata.org/x",
            expected_hosts={"query.wikidata.org"},
        )

    assert excinfo.value.status == 429
    assert excinfo.value.retry_after == 7.0


class _ClosableResponse:
    headers = None

    def __init__(self, body):
        self._body = io.BytesIO(body)
        self.closed = False

    def read(self, size=-1):
        return self._body.read(size)

    def close(self):
        self.closed = True

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
        return False


def test_response_is_closed_after_successful_read(monkeypatch):
    response = _ClosableResponse(json.dumps({"ok": 1}).encode())

    class Opener:
        def open(self, url, timeout=None):
            return response

    monkeypatch.setattr(fetch, "_opener", lambda hosts: Opener())
    assert fetch.get_json(
        "https://query.wikidata.org/x", expected_hosts={"query.wikidata.org"}
    ) == {"ok": 1}
    assert response.closed


def test_recursion_bomb_is_caught(monkeypatch):
    _body(monkeypatch, ("[" * 300000).encode())
    with pytest.raises(fetch.FetchError):
        fetch.get_json(
            "https://query.wikidata.org/x", expected_hosts={"query.wikidata.org"}
        )


class _Mock302Handler(urllib.request.BaseHandler):
    def __init__(self, location):
        self.location = location

    def https_open(self, req):
        headers = email.message.Message()
        headers["Location"] = self.location
        resp = urllib.response.addinfourl(io.BytesIO(b""), headers, req.full_url, 302)
        resp.msg = "Found"
        return resp


def _mock_opener(hosts, location):
    opener = urllib.request.OpenerDirector()
    for handler in (
        urllib.request.HTTPErrorProcessor(),
        fetch._AllowlistRedirect(hosts),
        _Mock302Handler(location),
    ):
        opener.add_handler(handler)
    return opener


def test_redirect_to_unexpected_host_is_blocked_THROUGH_get_json(monkeypatch):
    hosts = {"query.wikidata.org"}
    monkeypatch.setattr(
        fetch, "_opener", lambda h: _mock_opener(h, "https://evil.example/x")
    )
    with pytest.raises(fetch.FetchError, match="blocked redirect"):
        fetch.get_json("https://query.wikidata.org/x", expected_hosts=hosts)


def test_redirect_to_allowlisted_host_is_permitted():
    handler = fetch._AllowlistRedirect({"query.wikidata.org"})
    req = urllib.request.Request("https://query.wikidata.org/a")
    out = handler.redirect_request(
        req,
        io.BytesIO(b""),
        302,
        "Found",
        email.message.Message(),
        "https://query.wikidata.org/b",
    )
    assert out is not None


class _SequencedOpener:
    def __init__(self, responses):
        self.responses = list(responses)
        self.requests = []

    def open(self, request, timeout=None):
        self.requests.append(request)
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


def _response(body: bytes, headers: dict[str, str] | None = None):
    message = email.message.Message()
    for key, value in (headers or {}).items():
        message[key] = value
    response = _ClosableResponse(body)
    response.headers = message
    return response


def _http_304(url: str):
    return urllib.error.HTTPError(
        url,
        304,
        "Not Modified",
        email.message.Message(),
        io.BytesIO(b""),
    )


def _request_headers(request) -> dict[str, str]:
    return {key.lower(): value for key, value in request.header_items()}


def test_conditional_json_replays_opaque_validators_and_reuses_cached_body(
    tmp_path, monkeypatch
):
    url = "https://commons.wikimedia.org/w/api.php?action=query"
    opener = _SequencedOpener(
        [
            _response(
                b'{"ok": true}',
                {
                    "ETag": "unquoted-non-rfc-etag",
                    "Last-Modified": "Wed, 22 Jul 2026 06:00:00 GMT",
                },
            ),
            _http_304(url),
        ]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: opener)
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")

    data, first = fetch.conditional_get_json(
        url,
        expected_hosts={"commons.wikimedia.org"},
        headers={"User-Agent": "MakingTracksTest/1"},
        store=store,
    )
    cached_data, second = fetch.conditional_get_json(
        url,
        expected_hosts={"commons.wikimedia.org"},
        headers={"User-Agent": "MakingTracksTest/1"},
        store=store,
    )

    assert data == {"ok": True}
    assert cached_data == data
    assert first.status == "downloaded"
    assert first.sha256 == hashlib.sha256(b'{"ok": true}').hexdigest()
    assert second.status == "not_modified"
    assert second.bytes_downloaded == 0
    second_headers = _request_headers(opener.requests[1])
    assert second_headers["if-none-match"] == "unquoted-non-rfc-etag"
    assert second_headers["if-modified-since"] == "Wed, 22 Jul 2026 06:00:00 GMT"


def test_conditional_file_reuses_retained_file_on_304(tmp_path, monkeypatch):
    url = "https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg"
    dest = tmp_path / "Example.jpg"
    opener = _SequencedOpener(
        [
            _response(b"image-v1", {"ETag": "opaque-v1"}),
            _http_304(url),
        ]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: opener)
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")

    first = fetch.conditional_get_to_file(
        url,
        dest,
        expected_hosts={"upload.wikimedia.org"},
        store=store,
    )
    second = fetch.conditional_get_to_file(
        url,
        dest,
        expected_hosts={"upload.wikimedia.org"},
        store=store,
    )

    assert dest.read_bytes() == b"image-v1"
    assert first.status == "downloaded"
    assert first.size == len(b"image-v1")
    assert second.status == "not_modified"
    assert second.size == len(b"image-v1")
    assert _request_headers(opener.requests[1])["if-none-match"] == "opaque-v1"


def test_conditional_file_hash_hit_when_server_returns_200_for_unchanged_body(
    tmp_path, monkeypatch
):
    url = "https://tiles.making-tracks.app/regions.json"
    dest = tmp_path / "regions.json"
    opener = _SequencedOpener(
        [
            _response(b'{"regions":[]}', {"ETag": '"regions-v1"'}),
            _response(b'{"regions":[]}', {"ETag": '"regions-v1-still"'}),
        ]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: opener)
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")

    fetch.conditional_get_to_file(
        url,
        dest,
        expected_hosts={"tiles.making-tracks.app"},
        store=store,
    )
    second = fetch.conditional_get_to_file(
        url,
        dest,
        expected_hosts={"tiles.making-tracks.app"},
        store=store,
    )

    assert second.status == "hash_hit"
    assert second.bytes_downloaded == len(b'{"regions":[]}')
    assert _request_headers(opener.requests[1])["if-none-match"] == '"regions-v1"'


def test_conditional_file_updates_validator_after_drift_and_reuses_new_body(
    tmp_path, monkeypatch
):
    url = "https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg"
    dest = tmp_path / "Example.jpg"
    opener = _SequencedOpener(
        [
            _response(b"image-v1", {"ETag": "opaque-v1"}),
            _response(b"image-v2", {"ETag": "opaque-v2"}),
            _http_304(url),
        ]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: opener)
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")

    fetch.conditional_get_to_file(
        url,
        dest,
        expected_hosts={"upload.wikimedia.org"},
        store=store,
    )
    second = fetch.conditional_get_to_file(
        url,
        dest,
        expected_hosts={"upload.wikimedia.org"},
        store=store,
    )
    third = fetch.conditional_get_to_file(
        url,
        dest,
        expected_hosts={"upload.wikimedia.org"},
        store=store,
    )

    assert second.status == "downloaded"
    assert second.sha256 == hashlib.sha256(b"image-v2").hexdigest()
    assert third.status == "not_modified"
    assert dest.read_bytes() == b"image-v2"
    assert _request_headers(opener.requests[1])["if-none-match"] == "opaque-v1"
    assert _request_headers(opener.requests[2])["if-none-match"] == "opaque-v2"


def test_conditional_json_preserves_content_encoding_rejection(tmp_path, monkeypatch):
    opener = _SequencedOpener(
        [_response(b'{"ok": true}', {"Content-Encoding": "gzip"})]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: opener)

    with pytest.raises(fetch.FetchError, match="Content-Encoding"):
        fetch.conditional_get_json(
            "https://query.wikidata.org/x",
            expected_hosts={"query.wikidata.org"},
            store=fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json"),
        )


def test_conditional_json_preserves_host_and_byte_cap_checks(tmp_path, monkeypatch):
    with pytest.raises(fetch.FetchError, match="invalid target"):
        fetch.conditional_get_json(
            "https://evil.example/x",
            expected_hosts={"query.wikidata.org"},
            store=fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json"),
        )

    opener = _SequencedOpener([_response(b'{"x":"' + b"a" * 4096 + b'"}')])
    monkeypatch.setattr(fetch, "_opener", lambda hosts: opener)

    with pytest.raises(fetch.FetchError, match="exceeded 1024 bytes"):
        fetch.conditional_get_json(
            "https://query.wikidata.org/x",
            expected_hosts={"query.wikidata.org"},
            max_bytes=1024,
            store=fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json"),
        )


def test_conditional_json_logs_validator_absence(tmp_path, monkeypatch, caplog):
    opener = _SequencedOpener([_response(b'{"ok": true}')])
    monkeypatch.setattr(fetch, "_opener", lambda hosts: opener)

    with caplog.at_level(logging.INFO, logger="mt_pipeline.fetch"):
        _data, result = fetch.conditional_get_json(
            "https://en.wikipedia.org/w/api.php?action=query",
            expected_hosts={"en.wikipedia.org"},
            store=fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json"),
        )

    assert result.status == "downloaded"
    assert any("validators=unsupported" in record.message for record in caplog.records)


def test_conditional_json_refetches_when_retained_blob_is_missing(tmp_path, monkeypatch):
    url = "https://commons.wikimedia.org/w/api.php?action=query"
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")
    first_opener = _SequencedOpener(
        [_response(b'{"ok": true}', {"ETag": "opaque-json-v1"})]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: first_opener)

    fetch.conditional_get_json(
        url,
        expected_hosts={"commons.wikimedia.org"},
        store=store,
    )
    for blob_path in (tmp_path / "conditional-fetch-bodies").glob("*/*.json"):
        blob_path.unlink()

    second_opener = _SequencedOpener(
        [_response(b'{"ok": true, "refetched": true}', {"ETag": "opaque-json-v2"})]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: second_opener)

    data, result = fetch.conditional_get_json(
        url,
        expected_hosts={"commons.wikimedia.org"},
        store=store,
    )

    assert data == {"ok": True, "refetched": True}
    assert result.status == "downloaded"
    assert "if-none-match" not in _request_headers(second_opener.requests[0])


def test_conditional_json_refetches_when_cached_body_exceeds_new_cap(
    tmp_path, monkeypatch
):
    url = "https://commons.wikimedia.org/w/api.php?action=query"
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")
    first_opener = _SequencedOpener(
        [_response(b'{"body":"large"}', {"ETag": "opaque-json-v1"})]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: first_opener)

    fetch.conditional_get_json(
        url,
        expected_hosts={"commons.wikimedia.org"},
        store=store,
        max_bytes=64,
    )
    second_opener = _SequencedOpener(
        [_response(b'{"body":"still-large"}', {"ETag": "opaque-json-v2"})]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: second_opener)

    with pytest.raises(fetch.FetchError, match="exceeded 4 bytes"):
        fetch.conditional_get_json(
            url,
            expected_hosts={"commons.wikimedia.org"},
            store=store,
            max_bytes=4,
        )

    assert "if-none-match" not in _request_headers(second_opener.requests[0])


def test_conditional_json_raises_when_304_metadata_lacks_body_hash(
    tmp_path, monkeypatch
):
    url = "https://commons.wikimedia.org/w/api.php?action=query"
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")
    key = fetch._conditional_cache_key(url, None)
    store.path.write_text(
        json.dumps(
            {
                "schema_version": fetch.CONDITIONAL_FETCH_SCHEMA_VERSION,
                "entries": {key: {"etag": "metadata-only", "size": 2, "url": url}},
            }
        )
    )
    opener = _SequencedOpener([_http_304(url)])
    monkeypatch.setattr(fetch, "_opener", lambda hosts: opener)

    with pytest.raises(fetch.FetchError, match="without retained body metadata"):
        fetch.conditional_get_json(
            url,
            expected_hosts={"commons.wikimedia.org"},
            store=store,
        )


def test_conditional_json_raises_when_304_has_no_store_entry(tmp_path, monkeypatch):
    url = "https://commons.wikimedia.org/w/api.php?action=query"
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")
    opener = _SequencedOpener([_http_304(url)])
    monkeypatch.setattr(fetch, "_opener", lambda hosts: opener)

    with pytest.raises(fetch.FetchError, match="without retained conditional-fetch metadata"):
        fetch.conditional_get_json(
            url,
            expected_hosts={"commons.wikimedia.org"},
            store=store,
        )


def test_conditional_json_raises_when_304_retained_blob_is_missing(
    tmp_path, monkeypatch
):
    url = "https://commons.wikimedia.org/w/api.php?action=query"
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")
    body = b'{"ok": true}'
    sha = hashlib.sha256(body).hexdigest()
    key = fetch._conditional_cache_key(url, None)
    store.path.write_text(
        json.dumps(
            {
                "schema_version": fetch.CONDITIONAL_FETCH_SCHEMA_VERSION,
                "entries": {
                    key: {
                        "etag": "opaque-json-v1",
                        "sha256": sha,
                        "size": len(body),
                        "url": url,
                    }
                },
            }
        )
    )
    opener = _SequencedOpener([_http_304(url)])
    monkeypatch.setattr(fetch, "_opener", lambda hosts: opener)

    with pytest.raises(fetch.FetchError, match="retained JSON body is missing"):
        fetch.conditional_get_json(
            url,
            expected_hosts={"commons.wikimedia.org"},
            store=store,
        )


def test_conditional_json_raises_when_304_retained_blob_hash_mismatches(
    tmp_path, monkeypatch
):
    url = "https://commons.wikimedia.org/w/api.php?action=query"
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")
    body = b'{"ok": true}'
    sha = hashlib.sha256(body).hexdigest()
    fetch._write_json_blob(store, sha, body)
    fetch._json_blob_path(store, sha).write_bytes(b'{"ok": false}')
    key = fetch._conditional_cache_key(url, None)
    store.path.write_text(
        json.dumps(
            {
                "schema_version": fetch.CONDITIONAL_FETCH_SCHEMA_VERSION,
                "entries": {
                    key: {
                        "etag": "opaque-json-v1",
                        "sha256": sha,
                        "size": len(body),
                        "url": url,
                    }
                },
            }
        )
    )
    opener = _SequencedOpener([_http_304(url)])
    monkeypatch.setattr(fetch, "_opener", lambda hosts: opener)

    with pytest.raises(fetch.FetchError, match="hash does not match"):
        fetch.conditional_get_json(
            url,
            expected_hosts={"commons.wikimedia.org"},
            store=store,
        )


def test_conditional_file_refetches_when_retained_file_is_missing(tmp_path, monkeypatch):
    url = "https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg"
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")
    dest = tmp_path / "Example.jpg"
    first_opener = _SequencedOpener(
        [_response(b"image-v1", {"ETag": "opaque-file-v1"})]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: first_opener)

    fetch.conditional_get_to_file(
        url,
        dest,
        expected_hosts={"upload.wikimedia.org"},
        store=store,
    )
    dest.unlink()
    second_opener = _SequencedOpener(
        [_response(b"image-v2", {"ETag": "opaque-file-v2"})]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: second_opener)

    result = fetch.conditional_get_to_file(
        url,
        dest,
        expected_hosts={"upload.wikimedia.org"},
        store=store,
    )

    assert dest.read_bytes() == b"image-v2"
    assert result.status == "downloaded"
    assert "if-none-match" not in _request_headers(second_opener.requests[0])


def test_conditional_file_refetches_when_cached_file_exceeds_new_cap(
    tmp_path, monkeypatch
):
    url = "https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg"
    store = fetch.ConditionalFetchStore(tmp_path / "conditional-fetch.json")
    dest = tmp_path / "Example.jpg"
    first_opener = _SequencedOpener(
        [_response(b"large-file", {"ETag": "opaque-file-v1"})]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: first_opener)

    fetch.conditional_get_to_file(
        url,
        dest,
        expected_hosts={"upload.wikimedia.org"},
        store=store,
        max_bytes=64,
    )
    second_opener = _SequencedOpener(
        [_response(b"still-large", {"ETag": "opaque-file-v2"})]
    )
    monkeypatch.setattr(fetch, "_opener", lambda hosts: second_opener)

    with pytest.raises(fetch.FetchError, match="exceeded 4 bytes"):
        fetch.conditional_get_to_file(
            url,
            dest,
            expected_hosts={"upload.wikimedia.org"},
            store=store,
            max_bytes=4,
        )

    assert "if-none-match" not in _request_headers(second_opener.requests[0])
