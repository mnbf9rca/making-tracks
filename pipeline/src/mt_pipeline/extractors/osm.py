"""OSM extractor helpers for candidate tags and provenance sidecars."""

from __future__ import annotations

import hashlib
import json
import logging
import pathlib
import re

import osmium

from .. import source_record

MAX_TAGS_PER_FEATURE = 200
MAX_TAG_KEY_LEN = 100
MAX_TAG_VAL_LEN = 300
MAX_NAME_LEN = 300
MAX_QID_LEN = 24
MAX_CANDIDATE_RECORDS = 5_000_000
MAX_SIDECAR_BYTES = 64 * 1024

_log = logging.getLogger(__name__)


class ProvenanceError(Exception):
    pass


class OsmParseError(Exception):
    """The file could not be parsed by pyosmium."""


class TooManyCandidatesError(Exception):
    """Candidate count exceeded the extractor's bounded-memory ceiling."""


def load_tag_config(path) -> dict:
    return json.loads(pathlib.Path(path).read_text())["tags"]


def is_candidate(tags: dict, config: dict) -> bool:
    for key, allowed in config.items():
        if key in tags and (
            allowed is True or (isinstance(allowed, list) and tags[key] in allowed)
        ):
            return True
    return False


def _sha256_file(path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_provenance(pbf_path) -> None:
    meta_path = pathlib.Path(str(pbf_path) + ".meta.json")
    if not meta_path.exists():
        _log.warning(
            "no provenance sidecar for %s; proceeding with hand-placed dev file",
            pbf_path,
        )
        return

    if meta_path.stat().st_size > MAX_SIDECAR_BYTES:
        raise ProvenanceError(
            f"provenance sidecar for {pbf_path} exceeds {MAX_SIDECAR_BYTES} bytes"
        )
    try:
        meta = json.loads(meta_path.read_text())
    except (ValueError, RecursionError) as exc:
        raise ProvenanceError(
            f"unparseable provenance sidecar for {pbf_path}: {exc}"
        ) from exc
    if not isinstance(meta, dict) or not isinstance(meta.get("sha256"), str):
        raise ProvenanceError(f"provenance sidecar for {pbf_path} lacks sha256")

    actual = _sha256_file(pbf_path)
    if actual != meta["sha256"]:
        raise ProvenanceError(
            f"sha256 mismatch for {pbf_path}: {actual} != {meta['sha256']}"
        )


def _validate_qid(value) -> bool:
    return (
        isinstance(value, str)
        and len(value) <= MAX_QID_LEN
        and re.fullmatch(r"Q[0-9]+", value) is not None
    )


def _bounded_props(osm_object) -> dict:
    props: dict = {}
    for index, tag in enumerate(osm_object.tags):
        if index >= MAX_TAGS_PER_FEATURE:
            break
        props[tag.k[:MAX_TAG_KEY_LEN]] = tag.v[:MAX_TAG_VAL_LEN]
    wikidata = props.pop("wikidata", None)
    if _validate_qid(wikidata):
        props["wikidata"] = wikidata
    return props


class _CandidateHandler(osmium.SimpleHandler):
    def __init__(self, config: dict) -> None:
        super().__init__()
        self.config = config
        self.records: dict[str, dict] = {}
        self.dropped = 0

    def _consider(self, typ: str, object_id: int, lat: float, lon: float, obj) -> None:
        props = _bounded_props(obj)
        if not is_candidate(props, self.config):
            return
        source_ref = f"osm:{typ}/{object_id}"
        if source_ref in self.records:
            return
        if len(self.records) >= MAX_CANDIDATE_RECORDS:
            raise TooManyCandidatesError(f"exceeded {MAX_CANDIDATE_RECORDS} candidates")
        self.records[source_ref] = {
            "lat": lat,
            "lon": lon,
            "name": (props.get("name") or "")[:MAX_NAME_LEN],
            "props": props,
        }

    def node(self, obj) -> None:
        try:
            if obj.location.valid():
                self._consider("node", obj.id, obj.location.lat, obj.location.lon, obj)
        except TooManyCandidatesError:
            raise
        except Exception as exc:
            self.dropped += 1
            _log.debug(
                "skipped node %s: %s: %s",
                getattr(obj, "id", "?"),
                type(exc).__name__,
                exc,
            )

    def way(self, obj) -> None:
        try:
            nodes = list(obj.nodes)
            if len(nodes) >= 2 and nodes[0].ref == nodes[-1].ref:
                nodes = nodes[:-1]
            locations = [
                (node.location.lat, node.location.lon)
                for node in nodes
                if node.location.valid()
            ]
            if locations:
                lat = sum(item[0] for item in locations) / len(locations)
                lon = sum(item[1] for item in locations) / len(locations)
                self._consider("way", obj.id, lat, lon, obj)
        except TooManyCandidatesError:
            raise
        except Exception as exc:
            self.dropped += 1
            _log.debug(
                "skipped way %s: %s: %s",
                getattr(obj, "id", "?"),
                type(exc).__name__,
                exc,
            )


class OsmExtractor:
    def __init__(self, tag_config: dict) -> None:
        self.tag_config = tag_config

    def extract(
        self,
        region: str,
        snapshot_path,
        conn,
        *,
        run_id: str,
        index_type: str = "flex_mem",
    ) -> int:
        verify_provenance(snapshot_path)
        handler = _CandidateHandler(self.tag_config)
        try:
            handler.apply_file(str(snapshot_path), locations=True, idx=index_type)
        except TooManyCandidatesError:
            raise
        except (ValueError, RuntimeError) as exc:
            raise OsmParseError(f"pyosmium could not parse {snapshot_path}: {exc}") from exc

        if handler.dropped:
            _log.warning(
                "osm extract %s: skipped %d malformed feature(s)",
                snapshot_path,
                handler.dropped,
            )

        count = 0
        for source_ref in sorted(handler.records):
            item = handler.records[source_ref]
            try:
                record = source_record.parse(
                    region=region,
                    source="osm",
                    source_ref=source_ref,
                    name=item["name"],
                    lat=item["lat"],
                    lon=item["lon"],
                    props=item["props"],
                )
            except source_record.SourceRecordError:
                continue
            source_record.persist(conn, record, run_id=run_id)
            count += 1
        return count


def make_extractor(tag_config_path) -> OsmExtractor:
    return OsmExtractor(load_tag_config(tag_config_path))
