"""A4 score-stage wiring over reconciled places."""

from __future__ import annotations

import json
import math
import pathlib
from collections import Counter
from collections.abc import Mapping, Sequence

from . import SIGNAL_NAMES
from . import composite, rarity, signals, tiers
from .. import progress, source_record

_CONFIG_PATH = pathlib.Path(__file__).resolve().parents[3] / "config" / "scoring.json"
_HEARTBEAT_EVERY_RECORDS = 10_000
_HEARTBEAT_EVERY_SECONDS = progress.HEARTBEAT_EVERY_SECONDS
_MAX_SIGNALS_JSON_BYTES = 65_536


class ScoreStageError(RuntimeError):
    pass


def load_config(path: str | pathlib.Path = _CONFIG_PATH) -> dict:
    return json.loads(pathlib.Path(path).read_text())


def run(conn, region: str, *, run_id: str, cfg: dict | None = None) -> dict[int, int]:
    cfg = cfg or load_config()
    source_records = _source_records_by_ref(conn, region)
    tag_frequency = rarity.tag_value_frequency(
        conn,
        region,
        rarity_keys=cfg.get("rarity_keys", rarity.RARITY_KEYS),
    )

    total_places = conn.execute(
        """
        SELECT COUNT(*)
        FROM places
        WHERE region = ? AND status = 'live'
        """,
        (region,),
    ).fetchone()[0]
    if total_places == 0:
        raise ScoreStageError(
            "cannot run score: reconcile completed but no places are available "
            "(no live places)"
        )

    phase = progress.PhaseProgress(
        "score.run",
        region=region,
        total=total_places,
        total_label="places",
        heartbeat_every_records=_HEARTBEAT_EVERY_RECORDS,
        heartbeat_every_seconds=_HEARTBEAT_EVERY_SECONDS,
    )
    phase.start()

    histogram: Counter[int] = Counter()
    scored_rows: list[tuple[str, str, float, int, str, str]] = []
    rows = conn.execute(
        """
        SELECT place_id, member_refs_json
        FROM places
        WHERE region = ? AND status = 'live'
        ORDER BY place_id
        """,
        (region,),
    )
    processed = 0
    for place_id, member_refs_json in rows:
        processed += 1
        phase.tick(processed)
        member_refs = _load_json_list(
            member_refs_json,
            context=f"places.member_refs_json for {place_id}",
        )
        if not member_refs:
            raise ScoreStageError(f"place {place_id} has no member refs")
        signal_values = _signal_values(member_refs, source_records, tag_frequency, cfg)
        score = composite.score(signal_values, cfg)
        tier = tiers.tier_for(score, cfg)
        signals_json = _signals_json(signal_values)
        scored_rows.append((place_id, region, score, tier, signals_json, run_id))
        histogram[tier] += 1
    conn.execute("DELETE FROM place_scores WHERE region = ?", (region,))
    conn.executemany(
        """
        INSERT INTO place_scores
            (place_id, region, score, tier, signals_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(place_id) DO UPDATE SET
            region = excluded.region,
            score = excluded.score,
            tier = excluded.tier,
            signals_json = excluded.signals_json,
            run_id = excluded.run_id
        """,
        scored_rows,
    )
    phase.done(processed)
    return dict(sorted(histogram.items()))


def _source_records_by_ref(conn, region: str) -> dict[str, tuple[str, dict]]:
    rows = conn.execute(
        """
        SELECT source, source_ref, props_json
        FROM source_records
        WHERE region = ?
        ORDER BY source_ref
        """,
        (region,),
    )
    records: dict[str, tuple[str, dict]] = {}
    for source, source_ref, props_json in rows:
        records[source_ref] = (
            source,
            _load_json_dict(
                props_json,
                context=f"source_records.props_json for {source_ref}",
            ),
        )
    return records


def _signal_values(
    member_refs: list[str],
    source_records: Mapping[str, tuple[str, dict]],
    tag_frequency: Mapping[str, int],
    cfg: Mapping[str, object],
) -> dict[str, float | None]:
    raw = _raw_signals(member_refs, source_records)
    return {
        "article": signals.article(raw),
        "sitelinks": signals.sitelinks(raw),
        "heritage": signals.heritage(raw, grades=_mapping(cfg.get("heritage_grades"))),
        "plaque": signals.plaque(raw),
        "image": signals.image(raw),
        "tag_rarity": rarity.rarity_score(
            raw.get("osm_tags", set()),
            tag_frequency,
            rarity_keys=cfg.get("rarity_keys", rarity.RARITY_KEYS),
        ),
        "pageviews": signals.pageviews(raw),
        "llm_curiosity": signals.llm_curiosity(raw),
        "class_penalty": signals.class_penalty(
            raw,
            penalties=_mapping(cfg.get("class_penalties")),
        ),
    }


def _raw_signals(
    member_refs: list[str],
    source_records: Mapping[str, tuple[str, dict]],
) -> dict[str, object]:
    raw: dict[str, object] = {
        "wd": {"classes": []},
        "osm_tags": set(),
        "pageviews": None,
        "llm_curiosity": None,
    }
    classes: set[str] = set()
    longest_extract = ""
    max_sitelinks = 0.0
    image: object = None
    best_grade: str | None = None
    best_pageviews_signal: float | None = None

    for source_ref in sorted(member_refs):
        record = source_records.get(source_ref)
        if record is None:
            raise ScoreStageError(f"missing source record for place member {source_ref}")
        source, props = record
        if source == "wd":
            max_sitelinks = max(max_sitelinks, _number(props.get("sitelinks")))
            if image is None and isinstance(props.get("image"), str) and props["image"]:
                image = props["image"]
            classes.update(_wd_classes(props))
        elif source == "wp":
            extract = props.get("extract")
            if isinstance(extract, str) and len(extract) > len(longest_extract):
                longest_extract = extract
            if "pageviews" in props:
                pageviews_signal = signals.pageviews({"pageviews": props["pageviews"]})
                if pageviews_signal is not None and (
                    best_pageviews_signal is None
                    or pageviews_signal > best_pageviews_signal
                ):
                    best_pageviews_signal = pageviews_signal
                    raw["pageviews"] = props["pageviews"]
        elif source == "osm":
            raw["osm_tags"].update(_osm_tags(props))
        elif source in {"hehle", "historic_england"}:
            grade = props.get("grade")
            if isinstance(grade, str):
                best_grade = _best_grade(best_grade, grade)
        elif source in {"plaque", "open_plaques"}:
            raw["plaque"] = True
        if raw["llm_curiosity"] is None and "llm_curiosity" in props:
            raw["llm_curiosity"] = props["llm_curiosity"]
        raw["resolved_members"] = int(raw.get("resolved_members", 0)) + 1

    wd = raw["wd"]
    assert isinstance(wd, dict)
    wd["sitelinks"] = max_sitelinks
    wd["classes"] = sorted(classes)
    if image is not None:
        wd["image"] = image
    if longest_extract:
        raw["wp"] = {"extract": longest_extract}
    if best_grade is not None:
        raw["hehle"] = {"grade": best_grade}
    if raw.get("resolved_members", 0) == 0:
        raise ScoreStageError("place has no resolved member source records")
    return raw


def _wd_classes(props: Mapping[str, object]) -> set[str]:
    classes: set[str] = set()
    for key in ("classes", "p31s"):
        value = props.get(key)
        if isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
            classes.update(str(item) for item in value if item)
    for key in ("p31", "P31", "matched_p31"):
        value = props.get(key)
        if isinstance(value, str) and value:
            classes.add(value)
    return classes


def _osm_tags(props: Mapping[str, object]) -> set[str]:
    tags = props.get("tags")
    if not isinstance(tags, Mapping):
        tags = props
    out: set[str] = set()
    for key in sorted(tags):
        value = tags[key]
        if value is None or (
            isinstance(value, (Mapping, Sequence)) and not isinstance(value, str)
        ):
            continue
        out.add(f"{key}={value}")
    return out


def _best_grade(current: str | None, candidate: str) -> str:
    rank = {"I": 0, "II*": 1, "II": 2}
    if current is None:
        return candidate
    return min((current, candidate), key=lambda grade: rank.get(grade, 99))


def _signals_json(signal_values: Mapping[str, float | None]) -> str:
    values = {name: signal_values.get(name) for name in SIGNAL_NAMES}
    for key, value in values.items():
        if value is not None and not _finite_number(value):
            raise ScoreStageError(f"signal {key!r} is not finite")
    encoded = json.dumps(
        values,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )
    if len(encoded.encode("utf-8")) > _MAX_SIGNALS_JSON_BYTES:
        raise ScoreStageError("signals_json exceeds maximum size")
    return encoded


def _load_json_dict(value: str, *, context: str) -> dict:
    if len(value.encode("utf-8")) > source_record.PROPS_JSON_MAX:
        raise ScoreStageError(f"{context} exceeds maximum size")
    try:
        data = json.loads(value)
    except (ValueError, RecursionError):
        raise ScoreStageError(f"{context} is malformed JSON") from None
    if not isinstance(data, dict):
        raise ScoreStageError(f"{context} must be a JSON object")
    return data


def _load_json_list(value: str, *, context: str) -> list[str]:
    if len(value.encode("utf-8")) > source_record.PROPS_JSON_MAX:
        raise ScoreStageError(f"{context} exceeds maximum size")
    try:
        data = json.loads(value)
    except (ValueError, RecursionError):
        raise ScoreStageError(f"{context} is malformed JSON") from None
    if not isinstance(data, list):
        raise ScoreStageError(f"{context} must be a JSON list")
    if any(not isinstance(item, str) for item in data):
        raise ScoreStageError(f"{context} must contain only strings")
    return data


def _mapping(value) -> Mapping[str, object]:
    return value if isinstance(value, Mapping) else {}


def _number(value) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0.0
    if not math.isfinite(number):
        return 0.0
    return number


def _finite_number(value) -> bool:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return False
    return math.isfinite(number)
