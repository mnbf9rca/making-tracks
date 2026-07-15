"""Single hardened network boundary for source acquisition."""

from __future__ import annotations

import json
import pathlib
import time
import urllib.request
from urllib.parse import urlparse

MAX_RESPONSE_BYTES = 32 * 1024 * 1024


class FetchError(Exception):
    pass


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
) -> dict:
    if not _validate_target(url, expected_hosts):
        raise FetchError(f"invalid target: {url!r}")

    try:
        with _opener(expected_hosts).open(url, timeout=timeout) as resp:
            headers = getattr(resp, "headers", None)
            if headers is not None and headers.get("Content-Encoding"):
                raise FetchError(
                    f"unexpected Content-Encoding {headers.get('Content-Encoding')!r}"
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
) -> int:
    if not _validate_target(url, expected_hosts):
        raise FetchError(f"invalid target: {url!r}")

    written = 0
    dest_path = pathlib.Path(dest)
    tmp_path = dest_path.with_name(f".{dest_path.name}.tmp")
    try:
        with _opener(expected_hosts).open(url, timeout=timeout) as resp:
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
    except Exception as exc:
        tmp_path.unlink(missing_ok=True)
        raise FetchError(str(exc)) from exc
    return written
