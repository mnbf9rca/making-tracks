"""OSM extractor helpers for candidate tags and provenance sidecars."""

from __future__ import annotations

import hashlib
import json
import logging
import pathlib

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
