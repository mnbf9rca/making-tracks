import email.message
import io
import json
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
