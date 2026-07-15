"""Deterministic source-record distribution audit for taxonomy derivation."""

from __future__ import annotations

import json
import pathlib
from collections import Counter
from dataclasses import asdict, dataclass

from . import source_record
from .extractors import osm

_OSM_CANDIDATE_TAGS = (
    pathlib.Path(__file__).resolve().parents[2] / "config/osm_candidate_tags.json"
)


@dataclass(frozen=True)
class AuditReport:
    region: str
    n_records: int
    by_source: dict[str, int]
    p31_counts: list[tuple[str, int]]
    osm_tag_counts: list[tuple[str, int]]
    grade_counts: list[tuple[str, int]]
    plaque_count: int


def audit_region(conn, region: str) -> AuditReport:
    candidate_tags = osm.load_tag_config(_OSM_CANDIDATE_TAGS)
    by_source: Counter[str] = Counter()
    p31_counts: Counter[str] = Counter()
    osm_tag_counts: Counter[str] = Counter()
    grade_counts: Counter[str] = Counter()
    plaque_count = 0
    n_records = 0

    rows = conn.execute(
        """
        SELECT source, props_json
        FROM source_records
        WHERE region = ?
        ORDER BY source, source_ref
        """,
        (region,),
    )
    for source, props_json in rows:
        n_records += 1
        by_source[source] += 1
        props = _load_props(props_json)
        if source == "wd":
            p31 = props.get("p31")
            if isinstance(p31, str) and p31:
                p31_counts[p31] += 1
        elif source == "osm":
            for key in sorted(props):
                value = props[key]
                if isinstance(key, str) and isinstance(value, str):
                    tag = {key: value}
                    if osm.is_candidate(tag, candidate_tags):
                        osm_tag_counts[f"{key}={value}"] += 1
        elif source == "hehle":
            grade = props.get("grade")
            if isinstance(grade, str) and grade:
                grade_counts[grade] += 1
        elif source == "plaque":
            plaque_count += 1

    return AuditReport(
        region=region,
        n_records=n_records,
        by_source=dict(sorted(by_source.items())),
        p31_counts=_sorted_counts(p31_counts),
        osm_tag_counts=_sorted_counts(osm_tag_counts),
        grade_counts=_sorted_counts(grade_counts),
        plaque_count=plaque_count,
    )


def render_json(report: AuditReport) -> str:
    return json.dumps(asdict(report), indent=2, sort_keys=True) + "\n"


def render_markdown(report: AuditReport) -> str:
    lines = [
        f"# A3 Audit: {report.region}",
        "",
        f"- records: {report.n_records}",
        f"- plaque records: {report.plaque_count}",
        "",
        "## By Source",
        *_table(report.by_source.items()),
        "",
        "## Wikidata P31",
        *_table(report.p31_counts),
        "",
        "## OSM Candidate Tags",
        *_table(report.osm_tag_counts),
        "",
        "## Heritage Grades",
        *_table(report.grade_counts),
        "",
    ]
    return "\n".join(lines)


def _load_props(props_json: str) -> dict:
    if len(props_json.encode("utf-8")) > source_record.PROPS_JSON_MAX:
        return {}
    try:
        data = json.loads(props_json)
    except (ValueError, RecursionError):
        return {}
    return data if isinstance(data, dict) else {}


def _sorted_counts(counter: Counter[str]) -> list[tuple[str, int]]:
    return sorted(counter.items(), key=lambda item: (-item[1], item[0]))


def _table(rows) -> list[str]:
    out = ["| key | count |", "|---|---:|"]
    out.extend(f"| {_markdown_cell(str(key))} | {count} |" for key, count in rows)
    return out


def _markdown_cell(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", " ").replace("|", "\\|")
