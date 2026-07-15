"""Crash-safe Wikidata extractor over a complete dated SPARQL snapshot."""

from __future__ import annotations

import json
import pathlib

from .. import source_record

MAX_SNAPSHOT_BYTES = 256 * 1024 * 1024
MAX_RECORDS_PER_SNAPSHOT = 2_000_000
MAX_LABEL_LEN = 300
MAX_SITELINKS = 100_000


class SnapshotTooLargeError(Exception):
    pass


class SnapshotIncompleteError(Exception):
    pass


def load_allowlist(path) -> set[str]:
    data = json.loads(pathlib.Path(path).read_text())
    return set(data["allow"])


def _load_snapshot(snapshot_path) -> dict:
    path = pathlib.Path(snapshot_path)
    if path.stat().st_size > MAX_SNAPSHOT_BYTES:
        raise SnapshotTooLargeError(f"{path} exceeds {MAX_SNAPSHOT_BYTES} bytes")
    try:
        data = json.loads(path.read_text())
    except (ValueError, RecursionError) as exc:
        raise SnapshotTooLargeError(f"unparseable snapshot: {exc}") from exc

    meta = data.get("_meta")
    if not isinstance(meta, dict) or meta.get("complete") is not True:
        raise SnapshotIncompleteError(f"{path} is not marked _meta.complete=true")
    return data


def _qid(uri: str) -> str:
    return uri.rsplit("/", 1)[-1]


def _https(url: str) -> str | None:
    if isinstance(url, str) and url.startswith("http://"):
        url = "https://" + url[len("http://") :]
    if isinstance(url, str) and url.startswith("https://"):
        return url
    return None


class WikidataExtractor:
    def __init__(self, allowlist: set[str]) -> None:
        self.allowlist = allowlist

    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int:
        snapshot = _load_snapshot(snapshot_path)
        bindings = snapshot.get("results", {}).get("bindings", [])
        if len(bindings) > MAX_RECORDS_PER_SNAPSHOT:
            bindings = bindings[:MAX_RECORDS_PER_SNAPSHOT]

        projected: dict[str, dict] = {}
        for binding in bindings:
            try:
                qid = _qid(binding["item"]["value"])
                p31 = _qid(binding["p31"]["value"])
                if p31 not in self.allowlist or qid in projected:
                    continue
                lat = float(binding["lat"]["value"])
                lon = float(binding["lon"]["value"])
                label = str(binding.get("label", {}).get("value", ""))[:MAX_LABEL_LEN]
                sitelinks = min(
                    int(binding.get("sitelinks", {}).get("value", 0) or 0),
                    MAX_SITELINKS,
                )
                props = {"p31": p31, "label": label, "sitelinks": sitelinks}
                image = _https(binding.get("image", {}).get("value"))
                if image:
                    props["image"] = image
                projected[qid] = {"lat": lat, "lon": lon, "label": label, "props": props}
            except (KeyError, ValueError, TypeError):
                continue

        count = 0
        for qid in sorted(projected):
            item = projected[qid]
            try:
                record = source_record.parse(
                    region=region,
                    source="wd",
                    source_ref=f"wd:{qid}",
                    name=item["label"],
                    lat=item["lat"],
                    lon=item["lon"],
                    props=item["props"],
                )
            except source_record.SourceRecordError:
                continue
            source_record.persist(conn, record, run_id=run_id)
            count += 1
        return count


def make_extractor(allowlist_path) -> WikidataExtractor:
    return WikidataExtractor(load_allowlist(allowlist_path))
