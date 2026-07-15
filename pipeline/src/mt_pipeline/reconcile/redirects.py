"""Wikidata redirect-map loading and canonicalization."""

from __future__ import annotations

import datetime as _datetime
import json
import logging
import pathlib
import re
from dataclasses import dataclass

MAX_REDIRECT_ENTRIES = 20_000_000
_QID = re.compile(r"Q[0-9]+")
_COMPACT_DATE = re.compile(r"[0-9]{8}T[0-9]{6}Z")
_LOG = logging.getLogger(__name__)


class RedirectMapError(Exception):
    pass


@dataclass(frozen=True)
class RedirectSnapshot:
    map: dict[str, str]
    snapshot_date: str
    wikidata_snapshot_date: str
    complete: bool


def _meta_date(meta: dict, primary: str, fallback: str) -> str:
    value = meta.get(primary, meta.get(fallback, ""))
    return value if isinstance(value, str) else ""


def _parse_date(value: str) -> _datetime.datetime:
    if _COMPACT_DATE.fullmatch(value):
        return _datetime.datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(
            tzinfo=_datetime.UTC
        )
    return _datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))


def load_redirect_snapshot(path) -> RedirectSnapshot:
    if path is None:
        return RedirectSnapshot({}, "", "", complete=True)

    source = pathlib.Path(path)
    try:
        data = json.loads(source.read_text())
    except (OSError, ValueError, RecursionError) as exc:
        raise RedirectMapError(f"unreadable redirect map {source}: {exc}") from exc

    meta = data.get("_meta") if isinstance(data, dict) else None
    redirects = data.get("redirects") if isinstance(data, dict) else None
    if (
        not isinstance(meta, dict)
        or not isinstance(redirects, dict)
        or len(redirects) > MAX_REDIRECT_ENTRIES
    ):
        raise RedirectMapError("redirect snapshot must be {_meta, redirects} and bounded")
    if meta.get("complete") is not True:
        raise RedirectMapError("redirect snapshot is not marked complete")

    checked: dict[str, str] = {}
    for key, value in redirects.items():
        if not (
            isinstance(key, str)
            and isinstance(value, str)
            and _QID.fullmatch(key)
            and _QID.fullmatch(value)
        ):
            raise RedirectMapError(f"non-QID redirect entry: {key!r}->{value!r}")
        checked[key] = value

    return RedirectSnapshot(
        map=checked,
        snapshot_date=_meta_date(meta, "snapshot_date", "retrieved_at"),
        wikidata_snapshot_date=_meta_date(
            meta, "wikidata_snapshot_date", "wikidata_retrieved_at"
        ),
        complete=True,
    )


def assert_fresh(snapshot: RedirectSnapshot, wikidata_snapshot_date: str) -> None:
    if not snapshot.snapshot_date or not wikidata_snapshot_date:
        raise RedirectMapError("redirect map and wikidata snapshot dates are required")
    try:
        redirect_date = _parse_date(snapshot.snapshot_date)
        wikidata_date = _parse_date(wikidata_snapshot_date)
    except ValueError as exc:
        raise RedirectMapError(f"invalid redirect freshness date: {exc}") from exc
    if redirect_date < wikidata_date:
        raise RedirectMapError(
            f"redirect map ({snapshot.snapshot_date}) is older than the wikidata "
            f"snapshot ({wikidata_snapshot_date})"
        )


def canonical_qid(qid: str, mapping: dict[str, str]) -> str:
    seen: list[str] = []
    current = qid
    while current in mapping and current not in seen:
        seen.append(current)
        current = mapping[current]
    if current in seen:
        cycle = seen[seen.index(current) :]
        representative = min(cycle)
        _LOG.warning(
            "redirect cycle %s -> representative %s", cycle, representative
        )
        return representative
    return current


def canonicalize_ref(ref: str, mapping: dict[str, str]) -> str:
    if ref.startswith("wd:") and mapping:
        return "wd:" + canonical_qid(ref[3:], mapping)
    return ref
