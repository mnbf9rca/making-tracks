"""Crash-safe Wikipedia extractor over a complete geosearch/extract snapshot."""

from __future__ import annotations

import re

from .. import source_record
from .wikidata import MAX_RECORDS_PER_SNAPSHOT, _load_snapshot

MAX_EXTRACT_LEN = 300
MAX_TITLE_LEN = 300
MAX_QID_LEN = 24
MAX_LANG_LEN = 16
_QID_RE = re.compile(r"Q[0-9]+")


class WikipediaExtractor:
    def __init__(self, languages: set[str]) -> None:
        self.languages = languages

    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int:
        snapshot = _load_snapshot(snapshot_path)
        lang = str(snapshot.get("lang", ""))[:MAX_LANG_LEN]
        if lang not in self.languages:
            return 0

        pages = snapshot.get("pages", [])[:MAX_RECORDS_PER_SNAPSHOT]
        projected: dict[int, dict] = {}
        for page in pages:
            try:
                pageid = int(page["pageid"])
                if pageid in projected:
                    continue
                lat = float(page["lat"])
                lon = float(page["lon"])
                title = str(page.get("title", ""))[:MAX_TITLE_LEN]
                props = {
                    "lang": lang,
                    "title": title,
                    "extract": str(page.get("extract", ""))[:MAX_EXTRACT_LEN],
                }
                qid = page.get("wikidata")
                if (
                    isinstance(qid, str)
                    and len(qid) <= MAX_QID_LEN
                    and _QID_RE.fullmatch(qid)
                ):
                    props["wikidata"] = qid
                projected[pageid] = {
                    "lat": lat,
                    "lon": lon,
                    "title": title,
                    "props": props,
                }
            except (KeyError, ValueError, TypeError):
                continue

        count = 0
        for pageid in sorted(projected):
            item = projected[pageid]
            try:
                record = source_record.parse(
                    region=region,
                    source="wp",
                    source_ref=f"wp:{pageid}",
                    name=item["title"],
                    lat=item["lat"],
                    lon=item["lon"],
                    props=item["props"],
                )
            except source_record.SourceRecordError:
                continue
            source_record.persist(conn, record, run_id=run_id)
            count += 1
        return count
