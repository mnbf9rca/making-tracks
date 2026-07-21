"""Crash-safe Wikipedia extractor over a complete geosearch/extract snapshot."""

from __future__ import annotations

import re
import urllib.parse

from .. import source_record
from . import pageviews
from .wikidata import MAX_RECORDS_PER_SNAPSHOT, _load_snapshot

MAX_EXTRACT_LEN = 300
DESCRIPTION_EXTRACT_LEN = source_record.DESCRIPTION_EXTRACT_MAX
MAX_TITLE_LEN = 300
MAX_QID_LEN = 24
MAX_LANG_LEN = 16
_QID_RE = re.compile(r"Q[0-9]+")


def _commons_upload_url(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    parsed = urllib.parse.urlparse(value)
    if (
        parsed.scheme == "https"
        and parsed.hostname == "upload.wikimedia.org"
        and parsed.path.startswith("/wikipedia/commons/")
        and parsed.path.rsplit("/", 1)[-1]
    ):
        return value
    return None


class WikipediaExtractor:
    def __init__(self, languages: set[str]) -> None:
        self.languages = languages

    def extract(
        self,
        region: str,
        snapshot_path,
        conn,
        *,
        run_id: str,
        pageview_cache_dir=None,
        pageview_window: tuple[str, str] | None = None,
    ) -> int:
        snapshot = _load_snapshot(snapshot_path)
        lang = str(snapshot.get("lang", ""))[:MAX_LANG_LEN]
        if lang not in self.languages:
            return 0

        pages = snapshot.get("pages", [])
        if not isinstance(pages, list):
            return 0
        pages = pages[:MAX_RECORDS_PER_SNAPSHOT]
        projected: dict[int, dict] = {}
        for page in pages:
            try:
                pageid = int(page["pageid"])
                if pageid in projected:
                    continue
                lat = float(page["lat"])
                lon = float(page["lon"])
                title = str(page.get("title", ""))[:MAX_TITLE_LEN]
                raw_extract = str(page.get("extract", ""))
                props = {
                    "lang": lang,
                    "title": title,
                    "extract": raw_extract[:MAX_EXTRACT_LEN],
                    "description_extract": raw_extract[:DESCRIPTION_EXTRACT_LEN],
                }
                if pageview_cache_dir is not None and pageview_window is not None:
                    daily = pageviews.read(pageview_cache_dir, title, pageview_window)
                    if daily is not None:
                        props["pageviews"] = daily
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

        qid_pages = snapshot.get("qid_pages", [])
        if isinstance(qid_pages, list):
            for page in qid_pages[:MAX_RECORDS_PER_SNAPSHOT]:
                try:
                    qid = page["qid"]
                    wikibase_item = page["wikibase_item"]
                    if (
                        not isinstance(qid, str)
                        or len(qid) > MAX_QID_LEN
                        or _QID_RE.fullmatch(qid) is None
                        or wikibase_item != qid
                    ):
                        continue
                    pageid = int(page["pageid"])
                    if pageid in projected:
                        props = projected[pageid]["props"]
                        props["wikidata"] = qid
                        image = _commons_upload_url(page.get("image"))
                        if image:
                            props["image"] = image
                        continue
                    lat = float(page["owner_lat"])
                    lon = float(page["owner_lon"])
                    title = str(page.get("title", ""))[:MAX_TITLE_LEN]
                    raw_extract = str(page.get("extract", ""))
                    props = {
                        "lang": lang,
                        "title": title,
                        "extract": raw_extract[:MAX_EXTRACT_LEN],
                        "description_extract": raw_extract[:DESCRIPTION_EXTRACT_LEN],
                        "wikidata": qid,
                    }
                    image = _commons_upload_url(page.get("image"))
                    if image:
                        props["image"] = image
                    if pageview_cache_dir is not None and pageview_window is not None:
                        daily = pageviews.read(pageview_cache_dir, title, pageview_window)
                        if daily is not None:
                            props["pageviews"] = daily
                    projected[pageid] = {
                        "lat": lat,
                        "lon": lon,
                        "title": title,
                        "props": props,
                    }
                except (KeyError, ValueError, TypeError):
                    continue

        count = 0
        for pageid in sorted(projected, key=lambda pid: f"wp:{pid}"):
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
