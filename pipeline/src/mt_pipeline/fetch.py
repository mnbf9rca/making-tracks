"""Single hardened network boundary for source acquisition."""

from __future__ import annotations

import datetime
import email.utils
import json
import pathlib
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

MAX_RESPONSE_BYTES = 32 * 1024 * 1024


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
            headers = getattr(resp, "headers", None)
            if headers is not None and headers.get("Content-Encoding"):
                raise FetchError(
                    f"unexpected Content-Encoding {headers.get('Content-Encoding')!r}"
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
