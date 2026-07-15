"""Golden-area dump and hand-label TSV handling."""

from __future__ import annotations

from dataclasses import dataclass, replace
import json
import math
import sqlite3
from collections.abc import Sequence

from mt_contracts.place_id import is_valid_place_id
from mt_contracts.text import strip_unsafe_text

LABELS = frozenset({"yes", "meh", "no"})
INSTRUCTION_LINE = (
    "# Label the 'label' column only: yes = worth a detour; meh = fine but "
    "skippable; no = not interesting; (blank = skip). Do NOT edit other columns."
)
BASE_COLUMNS = (
    "place_id",
    "area",
    "active",
    "name",
    "lat",
    "lon",
    "category",
    "tier",
    "score",
    "data_version",
)
MAX_SIGNALS_JSON_BYTES = 65536
MAX_SIGNAL_COUNT = 128
MAX_SIGNAL_KEY_LEN = 64


@dataclass(frozen=True)
class GoldenRow:
    place_id: str
    area: str
    name: str
    lat: float
    lon: float
    category: str
    tier: int
    score: float
    signals: dict[str, float | None]
    label: str | None
    data_version: str
    active: bool = True


@dataclass(frozen=True)
class ParseResult:
    rows: list[GoldenRow]
    parsed: int
    labeled: int
    skipped: list[tuple[str, str]]
    data_version: str | None


def _signal_columns(rows: Sequence[GoldenRow]) -> list[str]:
    return sorted({key for row in rows for key in row.signals})


def _format_float(value: float) -> str:
    return format(value, ".12g")


def _clean_text(value: object) -> str:
    cleaned = strip_unsafe_text(str(value))
    if cleaned[:1] in {"=", "+", "-", "@"}:
        return "'" + cleaned
    return cleaned


def _validate_signals_json(raw: str) -> dict[str, float | None]:
    if len(raw.encode("utf-8")) > MAX_SIGNALS_JSON_BYTES:
        raise ValueError("signals_json exceeds size limit")
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid signals_json: {exc}") from exc
    if not isinstance(payload, dict):
        raise ValueError("signals_json must be an object")
    if len(payload) > MAX_SIGNAL_COUNT:
        raise ValueError("signals_json has too many keys")
    signals: dict[str, float | None] = {}
    for key, value in payload.items():
        if not isinstance(key, str) or not key:
            raise ValueError("signals_json keys must be non-empty strings")
        if len(key) > MAX_SIGNAL_KEY_LEN or strip_unsafe_text(key) != key:
            raise ValueError(f"invalid signals_json key {key!r}")
        if value is None:
            signals[key] = None
        elif isinstance(value, int | float) and not isinstance(value, bool):
            number = float(value)
            if not math.isfinite(number):
                raise ValueError(f"non-finite signals_json value for {key!r}")
            signals[key] = number
        else:
            raise ValueError(f"invalid signals_json value for {key!r}")
    return signals


def render_tsv(rows: Sequence[GoldenRow]) -> str:
    active_versions = {row.data_version for row in rows if row.active}
    data_versions = active_versions or {row.data_version for row in rows}
    data_version = next(iter(data_versions)) if len(data_versions) == 1 else ""
    signal_columns = _signal_columns(rows)
    header = [*BASE_COLUMNS, *signal_columns, "label"]
    lines = [INSTRUCTION_LINE, f"# data_version: {data_version}", "\t".join(header)]
    for row in sorted(rows, key=lambda r: (-r.score, r.place_id)):
        fields = [
            row.place_id,
            _clean_text(row.area),
            "true" if row.active else "false",
            _clean_text(row.name),
            _format_float(row.lat),
            _format_float(row.lon),
            _clean_text(row.category),
            str(row.tier),
            _format_float(row.score),
            _clean_text(row.data_version),
        ]
        for column in signal_columns:
            value = row.signals.get(column)
            fields.append("" if value is None else _format_float(value))
        fields.append(row.label or "")
        lines.append("\t".join(fields))
    return "\n".join(lines) + "\n"


def render_jsonl(rows: Sequence[GoldenRow]) -> str:
    lines = []
    for row in sorted(rows, key=lambda r: (-r.score, r.place_id)):
        payload = {
            "place_id": row.place_id,
            "area": row.area,
            "name": _clean_text(row.name),
            "lat": row.lat,
            "lon": row.lon,
            "category": _clean_text(row.category),
            "tier": row.tier,
            "score": row.score,
            "signals": {key: row.signals[key] for key in sorted(row.signals)},
            "label": row.label,
            "data_version": row.data_version,
            "active": row.active,
        }
        lines.append(json.dumps(payload, sort_keys=False, separators=(",", ":")))
    return "\n".join(lines) + ("\n" if lines else "")


def _parse_optional_float(raw: str) -> float | None:
    value = raw.strip()
    if value == "":
        return None
    return float(value)


def parse_labeled_tsv(text: str) -> ParseResult:
    data_version: str | None = None
    header: list[str] | None = None
    rows: dict[str, GoldenRow] = {}
    order: list[str] = []
    skipped: list[tuple[str, str]] = []
    parsed = 0

    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        if not raw_line.strip():
            continue
        if raw_line.startswith("#"):
            if raw_line.startswith("# data_version:"):
                data_version = raw_line.partition(":")[2].strip() or None
            continue
        fields = raw_line.split("\t")
        if header is None:
            header = fields
            if "place_id" not in header or "label" not in header:
                return ParseResult([], 0, 0, [("header", "missing place_id or label column")], data_version)
            continue

        fields = (fields + [""] * len(header))[: len(header)]
        cells = dict(zip(header, fields, strict=True))
        place_id = cells.get("place_id", "").strip()
        if not is_valid_place_id(place_id):
            skipped.append((place_id or f"line {lineno}", "invalid place_id"))
            continue
        raw_label = cells.get("label", "")
        label = raw_label.strip().lower()
        if label not in LABELS and label != "":
            skipped.append((place_id, f"invalid label {raw_label!r}"))
            continue
        label_value = label or None

        try:
            score = float(cells.get("score", "0") or 0)
            lat = float(cells.get("lat", "0") or 0)
            lon = float(cells.get("lon", "0") or 0)
            tier = int(cells.get("tier", "0") or 0)
            signal_names = [
                name for name in header if name not in (*BASE_COLUMNS, "label")
            ]
            signals = {
                name: _parse_optional_float(cells.get(name, "")) for name in signal_names
            }
            active_raw = cells.get("active", "true").strip().lower()
            if active_raw in {"", "true", "1", "yes"}:
                active = True
            elif active_raw in {"false", "0", "no"}:
                active = False
            else:
                raise ValueError(f"invalid active value {cells.get('active')!r}")
        except ValueError as exc:
            skipped.append((place_id, f"invalid numeric field: {exc}"))
            continue

        existing = rows.get(place_id)
        if existing is not None:
            if existing.label and label_value and existing.label != label_value:
                skipped.append((place_id, "conflicting duplicate non-blank label"))
            if label_value is None:
                continue
        else:
            order.append(place_id)

        rows[place_id] = GoldenRow(
            place_id=place_id,
            area=cells.get("area", ""),
            name=cells.get("name", ""),
            lat=lat,
            lon=lon,
            category=cells.get("category", ""),
            tier=tier,
            score=score,
            signals=signals,
            label=label_value,
            data_version=cells.get("data_version", "") or data_version or "",
            active=active,
        )
        parsed += 1 if existing is None else 0

    if header is None:
        skipped.append(("header", "missing header"))

    parsed_rows = [rows[place_id] for place_id in order if place_id in rows]
    return ParseResult(
        rows=parsed_rows,
        parsed=len(parsed_rows),
        labeled=sum(1 for row in parsed_rows if row.label is not None),
        skipped=skipped,
        data_version=data_version,
    )


def merge_labels(
    new_rows: Sequence[GoldenRow],
    existing_labeled: Sequence[GoldenRow],
) -> tuple[list[GoldenRow], list[GoldenRow]]:
    existing_by_id = {row.place_id: row for row in existing_labeled}
    old_ids = set(existing_by_id)
    new_ids = {row.place_id for row in new_rows}

    new_versions = {row.data_version for row in new_rows}
    old_versions = {row.data_version for row in existing_labeled}
    if len(new_versions) == 1 and new_versions == old_versions and old_ids != new_ids:
        raise ValueError("candidate set changed without data_version changing")

    merged = []
    for row in new_rows:
        label = existing_by_id.get(row.place_id).label if row.place_id in existing_by_id else None
        merged.append(replace(row, label=label, active=True))

    retired = []
    for place_id in sorted(old_ids - new_ids):
        old = existing_by_id[place_id]
        if old.label is not None:
            retired.append(replace(old, active=False))
    return merged, retired


def dump_area(conn, area: str, bbox: Sequence[float], *, data_version: str) -> list[GoldenRow]:
    if len(bbox) != 4:
        raise ValueError("bbox must be [minlon, minlat, maxlon, maxlat]")
    minlon, minlat, maxlon, maxlat = bbox
    query = """
        SELECT p.place_id, p.name, p.lat, p.lon, c.category, s.tier, s.score, s.signals_json
        FROM places AS p
        JOIN place_categories AS c ON c.place_id = p.place_id
        JOIN place_scores AS s ON s.place_id = p.place_id
        WHERE p.lon >= ? AND p.lon <= ? AND p.lat >= ? AND p.lat <= ?
        ORDER BY s.score DESC, p.place_id ASC
    """
    try:
        records = conn.execute(query, (minlon, maxlon, minlat, maxlat)).fetchall()
    except sqlite3.Error as exc:
        raise RuntimeError(
            "BLOCKED-ON A2/A3/A4 tables: places, place_categories, place_scores"
        ) from exc

    rows = []
    for place_id, name, lat, lon, category, tier, score, signals_json in records:
        signals = _validate_signals_json(signals_json)
        rows.append(
            GoldenRow(
                place_id=place_id,
                area=area,
                name=name,
                lat=lat,
                lon=lon,
                category=category,
                tier=tier,
                score=score,
                signals=signals,
                label=None,
                data_version=data_version,
                active=True,
            )
        )
    return rows
