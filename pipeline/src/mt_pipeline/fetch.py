"""Single hardened network boundary for source acquisition."""

from __future__ import annotations

import datetime
import email.utils
import hashlib
import json
import logging
import pathlib
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from urllib.parse import urlparse

MAX_RESPONSE_BYTES = 32 * 1024 * 1024
CONDITIONAL_FETCH_SCHEMA_VERSION = 1
_CONDITIONAL_REQUEST_HEADERS = frozenset({"if-none-match", "if-modified-since"})

_log = logging.getLogger(__name__)


class FetchError(Exception):
    def __init__(
        self,
        message: str,
        *,
        status: int | None = None,
        retry_after: float | None = None,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.retry_after = retry_after


@dataclass(frozen=True)
class ConditionalFetchStore:
    path: pathlib.Path

    def __post_init__(self) -> None:
        object.__setattr__(self, "path", pathlib.Path(self.path))


@dataclass(frozen=True)
class ConditionalFetchResult:
    status: str
    size: int
    sha256: str
    bytes_downloaded: int
    etag: str | None = None
    last_modified: str | None = None


def _conditional_store_payload(store: ConditionalFetchStore) -> dict:
    if not store.path.exists():
        return {"schema_version": CONDITIONAL_FETCH_SCHEMA_VERSION, "entries": {}}
    try:
        payload = json.loads(store.path.read_text(encoding="utf-8"))
    except (ValueError, RecursionError) as exc:
        raise FetchError(f"invalid conditional-fetch store {store.path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise FetchError(f"invalid conditional-fetch store {store.path}: expected object")
    if payload.get("schema_version") != CONDITIONAL_FETCH_SCHEMA_VERSION:
        raise FetchError(f"unsupported conditional-fetch store {store.path}")
    entries = payload.get("entries")
    if not isinstance(entries, dict):
        raise FetchError(f"invalid conditional-fetch store {store.path}: missing entries")
    return payload


def _write_conditional_store(store: ConditionalFetchStore, payload: dict) -> None:
    store.path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = store.path.with_name(f".{store.path.name}.tmp")
    tmp_path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
    tmp_path.replace(store.path)


def _conditional_cache_key(url: str, headers: dict[str, str] | None) -> str:
    request_headers = {
        str(key).lower(): str(value)
        for key, value in (headers or {}).items()
        if str(key).lower() not in _CONDITIONAL_REQUEST_HEADERS
    }
    payload = {
        "method": "GET",
        "url": url,
        "headers": sorted(request_headers.items()),
    }
    encoded = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _conditional_entry(
    store: ConditionalFetchStore, url: str, headers: dict[str, str] | None
) -> tuple[dict, str, dict | None]:
    payload = _conditional_store_payload(store)
    key = _conditional_cache_key(url, headers)
    entry = payload["entries"].get(key)
    if not isinstance(entry, dict):
        entry = None
    return payload, key, entry


def _conditional_request_headers(
    headers: dict[str, str] | None, entry: dict | None
) -> dict[str, str]:
    out = dict(headers or {})
    if entry is None:
        return out
    etag = entry.get("etag")
    last_modified = entry.get("last_modified")
    if isinstance(etag, str) and etag:
        out["If-None-Match"] = etag
    if isinstance(last_modified, str) and last_modified:
        out["If-Modified-Since"] = last_modified
    return out


def _usable_json_entry(
    store: ConditionalFetchStore,
    entry: dict | None,
    *,
    max_bytes: int,
) -> dict | None:
    if entry is None:
        return None
    sha = entry.get("sha256")
    size = entry.get("size")
    if not isinstance(sha, str) or not isinstance(size, int):
        return None
    if size > max_bytes:
        return None
    if not _json_blob_path(store, sha).exists():
        return None
    return entry


def _usable_file_entry(
    entry: dict | None,
    dest_path: pathlib.Path,
    *,
    max_bytes: int,
) -> dict | None:
    if entry is None:
        return None
    sha = entry.get("sha256")
    size = entry.get("size")
    if not isinstance(sha, str) or not isinstance(size, int):
        return None
    if size > max_bytes:
        return None
    if not dest_path.exists() or dest_path.stat().st_size > max_bytes:
        return None
    return entry


def _response_validators(response_headers) -> tuple[str | None, str | None]:
    if response_headers is None:
        return None, None
    etag = response_headers.get("ETag")
    last_modified = response_headers.get("Last-Modified")
    return (
        etag if isinstance(etag, str) and etag else None,
        last_modified if isinstance(last_modified, str) and last_modified else None,
    )


def _read_response_bytes(resp, *, max_bytes: int, deadline: int) -> bytes:
    response_headers = getattr(resp, "headers", None)
    if response_headers is not None and response_headers.get("Content-Encoding"):
        raise FetchError(
            "unexpected Content-Encoding "
            f"{response_headers.get('Content-Encoding')!r}"
        )

    start = time.monotonic()
    chunks: list[bytes] = []
    total = 0
    while True:
        if time.monotonic() - start > deadline:
            raise FetchError("exceeded total download deadline")
        chunk = resp.read(65536)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise FetchError(f"response exceeded {max_bytes} bytes")
        chunks.append(chunk)
    return b"".join(chunks)


def _stream_response_to_file(
    resp, tmp_path: pathlib.Path, *, max_bytes: int, deadline: int
) -> tuple[int, str]:
    response_headers = getattr(resp, "headers", None)
    if response_headers is not None and response_headers.get("Content-Encoding"):
        raise FetchError(
            "unexpected Content-Encoding "
            f"{response_headers.get('Content-Encoding')!r}"
        )

    start = time.monotonic()
    total = 0
    digest = hashlib.sha256()
    with open(tmp_path, "wb") as out:
        while True:
            if time.monotonic() - start > deadline:
                raise FetchError("exceeded total download deadline")
            chunk = resp.read(65536)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise FetchError(f"response exceeded {max_bytes} bytes")
            digest.update(chunk)
            out.write(chunk)
    return total, digest.hexdigest()


def _http_error_to_fetch_error(exc: urllib.error.HTTPError) -> FetchError:
    retry_after = None
    header_value = exc.headers.get("Retry-After") if exc.headers is not None else None
    if header_value is not None:
        retry_after = _retry_after_seconds(header_value)
    return FetchError(
        f"http {exc.code}: {exc.reason}",
        status=exc.code,
        retry_after=retry_after,
    )


def _json_blob_path(store: ConditionalFetchStore, sha256: str) -> pathlib.Path:
    return store.path.parent / "conditional-fetch-bodies" / sha256[:2] / f"{sha256}.json"


def _write_json_blob(store: ConditionalFetchStore, sha256: str, body: bytes) -> pathlib.Path:
    blob_path = _json_blob_path(store, sha256)
    blob_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = blob_path.with_name(f".{blob_path.name}.tmp")
    tmp_path.write_bytes(body)
    tmp_path.replace(blob_path)
    return blob_path


def _sha256_file(path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _log_conditional_result(
    *,
    url: str,
    status: str,
    size: int,
    bytes_downloaded: int,
    elapsed: float,
    etag: str | None,
    last_modified: str | None,
) -> None:
    validator_state = "supported" if etag or last_modified else "unsupported"
    _log.info(
        "CONDITIONAL_FETCH status=%s validators=%s bytes_downloaded=%d size=%d "
        "elapsed=%.3fs url=%s",
        status,
        validator_state,
        bytes_downloaded,
        size,
        elapsed,
        url,
    )


def _retry_after_seconds(value: str) -> float | None:
    try:
        return max(0.0, float(value))
    except ValueError:
        pass
    try:
        parsed = email.utils.parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.UTC)
    now = datetime.datetime.now(datetime.UTC)
    return max(0.0, (parsed - now).total_seconds())


def _validate_target(url: str, expected_hosts: set[str]) -> bool:
    parsed = urlparse(url)
    return parsed.scheme == "https" and parsed.hostname in expected_hosts


class _AllowlistRedirect(urllib.request.HTTPRedirectHandler):
    def __init__(self, expected_hosts: set[str]) -> None:
        self.expected_hosts = expected_hosts

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not _validate_target(newurl, self.expected_hosts):
            raise FetchError(f"blocked redirect to {newurl!r}")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _opener(expected_hosts: set[str]):
    return urllib.request.build_opener(_AllowlistRedirect(expected_hosts))


def get_json(
    url: str,
    *,
    expected_hosts: set[str],
    max_bytes: int = MAX_RESPONSE_BYTES,
    timeout: int = 30,
    deadline: int = 120,
    headers: dict[str, str] | None = None,
) -> dict:
    if not _validate_target(url, expected_hosts):
        raise FetchError(f"invalid target: {url!r}")

    try:
        request = urllib.request.Request(url, headers=headers or {})
        with _opener(expected_hosts).open(request, timeout=timeout) as resp:
            response_headers = getattr(resp, "headers", None)
            if response_headers is not None and response_headers.get("Content-Encoding"):
                raise FetchError(
                    "unexpected Content-Encoding "
                    f"{response_headers.get('Content-Encoding')!r}"
                )

            start = time.monotonic()
            chunks: list[bytes] = []
            total = 0
            while True:
                if time.monotonic() - start > deadline:
                    raise FetchError("exceeded total download deadline")
                chunk = resp.read(65536)
                if not chunk:
                    break
                total += len(chunk)
                if total > max_bytes:
                    raise FetchError(f"response exceeded {max_bytes} bytes")
                chunks.append(chunk)
    except FetchError:
        raise
    except urllib.error.HTTPError as exc:
        retry_after = None
        header_value = exc.headers.get("Retry-After") if exc.headers is not None else None
        if header_value is not None:
            retry_after = _retry_after_seconds(header_value)
        raise FetchError(
            f"http {exc.code}: {exc.reason}",
            status=exc.code,
            retry_after=retry_after,
        ) from exc
    except Exception as exc:
        raise FetchError(str(exc)) from exc

    try:
        return json.loads(b"".join(chunks).decode("utf-8"))
    except (ValueError, UnicodeDecodeError, RecursionError) as exc:
        raise FetchError(f"invalid JSON: {exc}") from exc


def get_to_file(
    url: str,
    dest,
    *,
    expected_hosts: set[str],
    max_bytes: int = MAX_RESPONSE_BYTES,
    timeout: int = 30,
    deadline: int = 120,
    headers: dict[str, str] | None = None,
) -> int:
    if not _validate_target(url, expected_hosts):
        raise FetchError(f"invalid target: {url!r}")

    written = 0
    dest_path = pathlib.Path(dest)
    tmp_path = dest_path.with_name(f".{dest_path.name}.tmp")
    try:
        request = urllib.request.Request(url, headers=headers or {})
        with _opener(expected_hosts).open(request, timeout=timeout) as resp:
            response_headers = getattr(resp, "headers", None)
            if response_headers is not None and response_headers.get("Content-Encoding"):
                raise FetchError(
                    f"unexpected Content-Encoding {response_headers.get('Content-Encoding')!r}"
                )

            start = time.monotonic()
            with open(tmp_path, "wb") as out:
                while True:
                    if time.monotonic() - start > deadline:
                        raise FetchError("exceeded total download deadline")
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    written += len(chunk)
                    if written > max_bytes:
                        raise FetchError(f"response exceeded {max_bytes} bytes")
                    out.write(chunk)
        tmp_path.replace(dest_path)
    except FetchError:
        tmp_path.unlink(missing_ok=True)
        raise
    except urllib.error.HTTPError as exc:
        tmp_path.unlink(missing_ok=True)
        retry_after = None
        header_value = exc.headers.get("Retry-After") if exc.headers is not None else None
        if header_value is not None:
            retry_after = _retry_after_seconds(header_value)
        raise FetchError(
            f"http {exc.code}: {exc.reason}",
            status=exc.code,
            retry_after=retry_after,
        ) from exc
    except Exception as exc:
        tmp_path.unlink(missing_ok=True)
        raise FetchError(str(exc)) from exc
    return written


def conditional_get_json(
    url: str,
    *,
    expected_hosts: set[str],
    store: ConditionalFetchStore,
    max_bytes: int = MAX_RESPONSE_BYTES,
    timeout: int = 30,
    deadline: int = 120,
    headers: dict[str, str] | None = None,
) -> tuple[dict, ConditionalFetchResult]:
    if not _validate_target(url, expected_hosts):
        raise FetchError(f"invalid target: {url!r}")

    payload, key, entry = _conditional_entry(store, url, headers)
    request_entry = _usable_json_entry(store, entry, max_bytes=max_bytes)
    request_headers = _conditional_request_headers(headers, request_entry)
    started = time.monotonic()
    try:
        request = urllib.request.Request(url, headers=request_headers)
        with _opener(expected_hosts).open(request, timeout=timeout) as resp:
            body = _read_response_bytes(resp, max_bytes=max_bytes, deadline=deadline)
            etag, last_modified = _response_validators(getattr(resp, "headers", None))
    except FetchError:
        raise
    except urllib.error.HTTPError as exc:
        if exc.code != 304:
            raise _http_error_to_fetch_error(exc) from exc
        if entry is None:
            raise FetchError("received 304 without retained conditional-fetch metadata") from exc
        sha = entry.get("sha256")
        size = entry.get("size")
        if not isinstance(sha, str) or not isinstance(size, int):
            raise FetchError("received 304 without retained body metadata") from exc
        if size > max_bytes:
            raise FetchError(f"retained JSON body exceeded {max_bytes} bytes") from exc
        blob_path = _json_blob_path(store, sha)
        if not blob_path.exists():
            raise FetchError("received 304 but retained JSON body is missing") from exc
        body = blob_path.read_bytes()
        if hashlib.sha256(body).hexdigest() != sha:
            raise FetchError("received 304 but retained JSON body hash does not match") from exc
        try:
            data = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError, RecursionError) as json_exc:
            raise FetchError(f"invalid JSON: {json_exc}") from json_exc
        result = ConditionalFetchResult(
            status="not_modified",
            size=size,
            sha256=sha,
            bytes_downloaded=0,
            etag=entry.get("etag") if isinstance(entry.get("etag"), str) else None,
            last_modified=(
                entry.get("last_modified")
                if isinstance(entry.get("last_modified"), str)
                else None
            ),
        )
        _log_conditional_result(
            url=url,
            status=result.status,
            size=result.size,
            bytes_downloaded=result.bytes_downloaded,
            elapsed=time.monotonic() - started,
            etag=result.etag,
            last_modified=result.last_modified,
        )
        return data, result
    except Exception as exc:
        raise FetchError(str(exc)) from exc

    sha = hashlib.sha256(body).hexdigest()
    previous_sha = entry.get("sha256") if isinstance(entry, dict) else None
    status = "hash_hit" if previous_sha == sha else "downloaded"
    try:
        data = json.loads(body.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, RecursionError) as exc:
        raise FetchError(f"invalid JSON: {exc}") from exc
    _write_json_blob(store, sha, body)
    payload["entries"][key] = {
        "url": url,
        "headers": {
            str(header_key).lower(): str(value)
            for header_key, value in (headers or {}).items()
            if str(header_key).lower() not in _CONDITIONAL_REQUEST_HEADERS
        },
        "sha256": sha,
        "size": len(body),
        "etag": etag,
        "last_modified": last_modified,
    }
    _write_conditional_store(store, payload)
    result = ConditionalFetchResult(
        status=status,
        size=len(body),
        sha256=sha,
        bytes_downloaded=len(body),
        etag=etag,
        last_modified=last_modified,
    )
    _log_conditional_result(
        url=url,
        status=result.status,
        size=result.size,
        bytes_downloaded=result.bytes_downloaded,
        elapsed=time.monotonic() - started,
        etag=result.etag,
        last_modified=result.last_modified,
    )
    return data, result


def conditional_get_to_file(
    url: str,
    dest,
    *,
    expected_hosts: set[str],
    store: ConditionalFetchStore,
    max_bytes: int = MAX_RESPONSE_BYTES,
    timeout: int = 30,
    deadline: int = 120,
    headers: dict[str, str] | None = None,
) -> ConditionalFetchResult:
    if not _validate_target(url, expected_hosts):
        raise FetchError(f"invalid target: {url!r}")

    dest_path = pathlib.Path(dest)
    tmp_path = dest_path.with_name(f".{dest_path.name}.tmp")
    payload, key, entry = _conditional_entry(store, url, headers)
    request_entry = _usable_file_entry(entry, dest_path, max_bytes=max_bytes)
    request_headers = _conditional_request_headers(headers, request_entry)
    started = time.monotonic()
    try:
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        request = urllib.request.Request(url, headers=request_headers)
        with _opener(expected_hosts).open(request, timeout=timeout) as resp:
            size, sha = _stream_response_to_file(
                resp,
                tmp_path,
                max_bytes=max_bytes,
                deadline=deadline,
            )
            etag, last_modified = _response_validators(getattr(resp, "headers", None))
    except FetchError:
        tmp_path.unlink(missing_ok=True)
        raise
    except urllib.error.HTTPError as exc:
        tmp_path.unlink(missing_ok=True)
        if exc.code != 304:
            raise _http_error_to_fetch_error(exc) from exc
        if entry is None:
            raise FetchError("received 304 without retained conditional-fetch metadata") from exc
        sha = entry.get("sha256")
        size = entry.get("size")
        if not isinstance(sha, str) or not isinstance(size, int):
            raise FetchError("received 304 without retained file metadata") from exc
        if size > max_bytes:
            raise FetchError(f"retained file exceeded {max_bytes} bytes") from exc
        if not dest_path.exists():
            raise FetchError("received 304 but retained file is missing") from exc
        actual_sha = _sha256_file(dest_path)
        if actual_sha != sha:
            raise FetchError("received 304 but retained file hash does not match") from exc
        actual_size = dest_path.stat().st_size
        if actual_size > max_bytes:
            raise FetchError(f"retained file exceeded {max_bytes} bytes") from exc
        result = ConditionalFetchResult(
            status="not_modified",
            size=actual_size,
            sha256=actual_sha,
            bytes_downloaded=0,
            etag=entry.get("etag") if isinstance(entry.get("etag"), str) else None,
            last_modified=(
                entry.get("last_modified")
                if isinstance(entry.get("last_modified"), str)
                else None
            ),
        )
        _log_conditional_result(
            url=url,
            status=result.status,
            size=result.size,
            bytes_downloaded=result.bytes_downloaded,
            elapsed=time.monotonic() - started,
            etag=result.etag,
            last_modified=result.last_modified,
        )
        return result
    except Exception as exc:
        tmp_path.unlink(missing_ok=True)
        raise FetchError(str(exc)) from exc

    previous_sha = entry.get("sha256") if isinstance(entry, dict) else None
    status = "hash_hit" if previous_sha == sha else "downloaded"
    try:
        tmp_path.replace(dest_path)
    except Exception as exc:
        tmp_path.unlink(missing_ok=True)
        raise FetchError(str(exc)) from exc
    payload["entries"][key] = {
        "url": url,
        "headers": {
            str(header_key).lower(): str(value)
            for header_key, value in (headers or {}).items()
            if str(header_key).lower() not in _CONDITIONAL_REQUEST_HEADERS
        },
        "sha256": sha,
        "size": size,
        "etag": etag,
        "last_modified": last_modified,
    }
    _write_conditional_store(store, payload)
    result = ConditionalFetchResult(
        status=status,
        size=size,
        sha256=sha,
        bytes_downloaded=size,
        etag=etag,
        last_modified=last_modified,
    )
    _log_conditional_result(
        url=url,
        status=result.status,
        size=result.size,
        bytes_downloaded=result.bytes_downloaded,
        elapsed=time.monotonic() - started,
        etag=result.etag,
        last_modified=result.last_modified,
    )
    return result
