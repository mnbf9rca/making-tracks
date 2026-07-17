"""Wikipedia text extraction and description sidecar artifact emission."""

from __future__ import annotations

import hashlib
import json
import re
from collections.abc import Iterable, Mapping
from dataclasses import asdict, dataclass
from typing import Any
from urllib.parse import quote

from mt_contracts import strip_unsafe_text
from mt_contracts.validation import validate_instance

from . import partition

EXCERPT_MAX_CHARS = 500
TITLE_MAX_CHARS = 300
LANG_MAX_CHARS = 16
SOURCE_URL_MAX_CHARS = 512
WIKIPEDIA_LICENSE_CODE = "CC-BY-SA-4.0"
WIKIPEDIA_LICENSE_NAME = "Creative Commons Attribution-ShareAlike 4.0"
WIKIPEDIA_LICENSE_URL = "https://creativecommons.org/licenses/by-sa/4.0/"
_LANG_RE = re.compile(r"[a-z][a-z0-9-]{0,15}")
_SENTENCE_END_RE = re.compile(r"[.!?](?:[\"')\]]+)?(?:\s|$)")


@dataclass(frozen=True)
class PlaceDescription:
    place_id: str
    lat: float
    lon: float
    wikipedia_title: str
    excerpt: str
    source_ref: str
    source_url: str
    license_code: str
    license_name: str
    license_url: str
    modified: bool


@dataclass(frozen=True)
class DescriptionIndexArtifact:
    x: int
    y: int
    json_bytes: bytes
    sha256: str
    byte_len: int


def descriptions_from_source_records(
    places: Iterable[Mapping[str, Any]],
    source_rows: Iterable[Mapping[str, Any]],
) -> list[PlaceDescription]:
    rows_by_ref: dict[str, Mapping[str, Any]] = {
        str(row["source_ref"]): row
        for row in source_rows
        if isinstance(row.get("source_ref"), str)
    }
    out: list[PlaceDescription] = []
    for place in sorted(places, key=lambda item: str(item["place_id"])):
        source_ref = next(
            (
                str(ref)
                for ref in place.get("source_refs", ())
                if isinstance(ref, str) and ref.startswith("wp:")
            ),
            None,
        )
        if source_ref is None:
            continue
        row = rows_by_ref.get(source_ref)
        if row is None:
            continue
        props = row.get("props")
        if not isinstance(props, Mapping):
            continue
        desc = _description_from_props(place, source_ref, props)
        if desc is not None:
            out.append(desc)
    return out


def source_rows_from_db(conn, region: str) -> list[dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT source_ref, props_json
        FROM source_records
        WHERE region = ? AND source = 'wp'
        ORDER BY source_ref
        """,
        (region,),
    )
    out: list[dict[str, Any]] = []
    for source_ref, props_json in rows:
        try:
            props = json.loads(props_json)
        except (ValueError, RecursionError, TypeError):
            continue
        if isinstance(props, dict):
            out.append({"source_ref": str(source_ref), "props": props})
    return out


def emit_description_artifacts(
    descriptions: Iterable[PlaceDescription],
) -> list[DescriptionIndexArtifact]:
    grouped = partition.partition_places(
        {
            "place_id": desc.place_id,
            "lat": desc.lat,
            "lon": desc.lon,
            "wikipedia_title": desc.wikipedia_title,
            "excerpt": desc.excerpt,
            "source_ref": desc.source_ref,
            "source_url": desc.source_url,
            "license_code": desc.license_code,
            "license_name": desc.license_name,
            "license_url": desc.license_url,
            "modified": desc.modified,
        }
        for desc in descriptions
    )
    artifacts: list[DescriptionIndexArtifact] = []
    for (x, y), tile_records in grouped.items():
        payload = {
            "schema_version": 1,
            "min_reader_version": 1,
            "z": 10,
            "x": x,
            "y": y,
            "places": [
                {
                    key: value
                    for key, value in asdict(_record_to_description(record)).items()
                    if key not in {"lat", "lon"}
                }
                for record in tile_records
            ],
        }
        validate_instance("description-index", payload)
        data = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
        artifacts.append(
            DescriptionIndexArtifact(
                x=x,
                y=y,
                json_bytes=data,
                sha256=hashlib.sha256(data).hexdigest(),
                byte_len=len(data),
            )
        )
    return artifacts


def _record_to_description(record: Mapping[str, Any]) -> PlaceDescription:
    return PlaceDescription(
        place_id=str(record["place_id"]),
        lat=float(record["lat"]),
        lon=float(record["lon"]),
        wikipedia_title=str(record["wikipedia_title"]),
        excerpt=str(record["excerpt"]),
        source_ref=str(record["source_ref"]),
        source_url=str(record["source_url"]),
        license_code=str(record["license_code"]),
        license_name=str(record["license_name"]),
        license_url=str(record["license_url"]),
        modified=bool(record["modified"]),
    )


def _description_from_props(
    place: Mapping[str, Any],
    source_ref: str,
    props: Mapping[str, Any],
) -> PlaceDescription | None:
    lang = _sanitize_lang(props.get("lang"))
    title = _safe_single_line(props.get("title"), max_chars=TITLE_MAX_CHARS)
    excerpt = _excerpt(props.get("extract"))
    if lang is None or title is None or excerpt is None:
        return None
    source_url = _source_url(lang, title)
    if len(source_url) > SOURCE_URL_MAX_CHARS:
        return None
    try:
        lat = float(place["lat"])
        lon = float(place["lon"])
    except (KeyError, TypeError, ValueError):
        return None
    return PlaceDescription(
        place_id=str(place["place_id"]),
        lat=lat,
        lon=lon,
        wikipedia_title=title,
        excerpt=excerpt,
        source_ref=source_ref,
        source_url=source_url,
        license_code=WIKIPEDIA_LICENSE_CODE,
        license_name=WIKIPEDIA_LICENSE_NAME,
        license_url=WIKIPEDIA_LICENSE_URL,
        modified=True,
    )


def _safe_single_line(value: Any, *, max_chars: int) -> str | None:
    if not isinstance(value, str):
        return None
    text = " ".join(strip_unsafe_text(value).split())
    if not text:
        return None
    return text[:max_chars]


def _sanitize_lang(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    lang = value.casefold().strip()[:LANG_MAX_CHARS]
    return lang if _LANG_RE.fullmatch(lang) else None


def _excerpt(value: Any) -> str | None:
    text = _safe_single_line(value, max_chars=max(len(str(value)), EXCERPT_MAX_CHARS))
    if text is None:
        return None
    if len(text) <= EXCERPT_MAX_CHARS:
        return text
    clipped = text[:EXCERPT_MAX_CHARS].rstrip()
    sentence = _sentence_boundary_prefix(clipped)
    return sentence or clipped


def _sentence_boundary_prefix(value: str) -> str | None:
    last_end = None
    for match in _SENTENCE_END_RE.finditer(value):
        last_end = match.end()
    if last_end is None:
        return None
    return value[:last_end].strip()


def _source_url(lang: str, title: str) -> str:
    return f"https://{lang}.wikipedia.org/wiki/{quote(title.replace(' ', '_'), safe='')}"
