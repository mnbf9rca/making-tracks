"""Acquisition helpers for durable source snapshots."""

from __future__ import annotations

import datetime
import concurrent.futures
import hashlib
import json
import pathlib
import re
import shutil
import threading
import time
import urllib.parse

from . import fetch, stages
from .extractors import _snapshot

DEFAULT_CONFIG = pathlib.Path(__file__).resolve().parents[2] / "config/acquire_sources.json"
DEFAULT_ALLOWLIST = (
    pathlib.Path(__file__).resolve().parents[2] / "config/wikidata_class_allowlist.json"
)
DEFAULT_REGISTER_CONFIG = (
    pathlib.Path(__file__).resolve().parents[2] / "config/a1d_sources.json"
)
USER_AGENT = "MakingTracksBot/0.1 (https://making-tracks.app; data-acquisition)"
RETRY_STATUSES = {429, 500, 502, 503, 504}
_QID_RE = re.compile(r"Q[0-9]+")
_POINT_RE = re.compile(r"Point\(([-0-9.]+) ([-0-9.]+)\)")


class AcquireError(RuntimeError):
    pass


class RetryableAcquireError(AcquireError):
    def __init__(self, message: str, *, status: int | None = None) -> None:
        super().__init__(message)
        self.status = status


class SharedBackoff:
    def __init__(self, sleep_fn) -> None:
        self._sleep = sleep_fn
        self._lock = threading.Lock()

    def before_request(self) -> None:
        with self._lock:
            pass

    def pause(self, seconds: float) -> None:
        with self._lock:
            self._sleep(seconds)


def load_config(path=DEFAULT_CONFIG) -> dict:
    return json.loads(pathlib.Path(path).read_text())


def load_class_qids(path=DEFAULT_ALLOWLIST) -> list[str]:
    data = json.loads(pathlib.Path(path).read_text())
    return sorted(qid for qid in data["allow"] if _QID_RE.fullmatch(qid))


def snapshot_paths(dest_dir) -> dict[str, pathlib.Path]:
    base = pathlib.Path(dest_dir)
    return {
        "wikidata": base / "wikidata.snapshot.json",
        "wikipedia": base / "wikipedia.snapshot.json",
        "osm": base / "osm.osm.pbf",
        "historic_england": base / "historic_england.snapshot",
        "open_plaques": base / "open_plaques.snapshot",
    }


def redirect_map_path(dest_dir) -> pathlib.Path:
    return pathlib.Path(dest_dir) / "wikidata_redirects.snapshot.json"


def _now() -> str:
    return stages._completed_at()


def _parse_time(value: str) -> datetime.datetime:
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))


def _ensure_dir(path) -> pathlib.Path:
    dest = pathlib.Path(path)
    dest.mkdir(parents=True, exist_ok=True)
    return dest


def _atomic_write_json(path, data: dict) -> pathlib.Path:
    out = pathlib.Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(f".{out.name}.tmp")
    tmp.write_text(json.dumps(data, sort_keys=True))
    tmp.replace(out)
    return out


def bbox_tiles(bbox, *, tile_degrees: float = 1.0) -> list[tuple[float, float, float, float]]:
    if tile_degrees <= 0:
        raise AcquireError("tile_degrees must be positive")
    west, south, east, north = [float(value) for value in bbox]
    tiles: list[tuple[float, float, float, float]] = []
    x = west
    while x < east:
        next_x = min(x + tile_degrees, east)
        y = south
        while y < north:
            next_y = min(y + tile_degrees, north)
            tiles.append((x, y, next_x, next_y))
            y = next_y
        x = next_x
    return tiles


def _chunks(items: list[str], size: int) -> list[list[str]]:
    if size <= 0:
        raise AcquireError("chunk size must be positive")
    return [items[index : index + size] for index in range(0, len(items), size)]


def _headers() -> dict[str, str]:
    return {"User-Agent": USER_AGENT, "Accept": "application/json"}


def _is_retryable(exc: Exception) -> bool:
    if isinstance(exc, RetryableAcquireError):
        return exc.status in RETRY_STATUSES or exc.status is None
    if isinstance(exc, fetch.FetchError):
        message = str(exc)
        return "timed out" in message.lower() or any(
            f"http {status}" in message for status in RETRY_STATUSES
        )
    return False


def _retry_json(
    url: str,
    *,
    expected_hosts: set[str],
    max_bytes: int,
    fetch_json,
    retries: int,
    sleep,
    backoff: SharedBackoff | None = None,
) -> dict:
    for attempt in range(retries + 1):
        try:
            if backoff is not None:
                backoff.before_request()
            return fetch_json(
                url,
                expected_hosts=expected_hosts,
                max_bytes=max_bytes,
                headers=_headers(),
            )
        except Exception as exc:
            if attempt >= retries or not _is_retryable(exc):
                raise AcquireError(str(exc)) from exc
            delay = float(2**attempt)
            if backoff is None:
                sleep(delay)
            else:
                backoff.pause(delay)
    raise AcquireError("unreachable retry state")


def _endpoint_url(endpoint: str, params: dict[str, str]) -> str:
    return f"{endpoint}?{urllib.parse.urlencode(params)}"


def _wdqs_query(class_qids: list[str], tile) -> str:
    values = " ".join(f"wd:{qid}" for qid in class_qids)
    west, south, east, north = tile
    return f"""
PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
PREFIX wikibase: <http://wikiba.se/ontology#>
PREFIX bd: <http://www.bigdata.com/rdf#>
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?item ?matched_class ?p31 ?coord ?label ?sitelinks ?image WHERE {{
  VALUES ?wantedClass {{ {values} }}
  ?item wdt:P31 ?p31 ;
        wdt:P31/wdt:P279* ?wantedClass ;
        wikibase:sitelinks ?sitelinks .
  SERVICE wikibase:box {{
    ?item wdt:P625 ?coord .
    bd:serviceParam wikibase:cornerWest "Point({west} {south})"^^geo:wktLiteral .
    bd:serviceParam wikibase:cornerEast "Point({east} {north})"^^geo:wktLiteral .
  }}
  BIND(?wantedClass AS ?matched_class)
  OPTIONAL {{ ?item wdt:P18 ?image . }}
  OPTIONAL {{ ?item rdfs:label ?label FILTER(LANG(?label) = "en") }}
}}
""".strip()


def _binding_qid(binding: dict) -> str:
    return binding.get("item", {}).get("value", "").rsplit("/", 1)[-1]


def _normalize_wdqs_bindings(bindings: list[dict]) -> list[dict]:
    normalized = []
    for binding in bindings:
        out = dict(binding)
        p31s = out.get("p31s", {}).get("value")
        if isinstance(p31s, str):
            first_p31 = next(
                (value for value in p31s.split("|") if value.strip()),
                None,
            )
            if first_p31 is not None:
                out["p31"] = {"type": "uri", "value": first_p31}
        if "lat" in out and "lon" in out:
            normalized.append(out)
            continue
        coord = binding.get("coord", {}).get("value")
        if not isinstance(coord, str):
            normalized.append(out)
            continue
        match = _POINT_RE.fullmatch(coord)
        if match is None:
            normalized.append(out)
            continue
        lon, lat = match.groups()
        out["lat"] = {"type": "literal", "value": lat}
        out["lon"] = {"type": "literal", "value": lon}
        normalized.append(out)
    return normalized


def _merge_wdqs_bindings(bindings: list[dict]) -> list[dict]:
    merged: dict[str, dict] = {}
    actual_by_qid: dict[str, set[str]] = {}
    matched_by_qid: dict[str, set[str]] = {}
    for binding in bindings:
        qid = _binding_qid(binding)
        if not _QID_RE.fullmatch(qid):
            continue
        merged.setdefault(qid, binding)
        p31 = binding.get("p31", {}).get("value")
        if isinstance(p31, str):
            actual_by_qid.setdefault(qid, set()).add(p31)
        matched = binding.get("matched_class", {}).get("value")
        if isinstance(matched, str):
            matched_by_qid.setdefault(qid, set()).add(matched)

    out = []
    for qid in sorted(merged):
        binding = dict(merged[qid])
        actual = sorted(actual_by_qid.get(qid, set()))[:8]
        matched = sorted(matched_by_qid.get(qid, set()))[:8]
        if actual:
            binding["p31"] = {"type": "uri", "value": actual[0]}
            binding["p31s"] = {"type": "literal", "value": "|".join(actual)}
        if matched:
            binding["matched_class"] = {"type": "uri", "value": matched[0]}
            binding["matched_classes"] = {"type": "literal", "value": "|".join(matched)}
        out.append(binding)
    return out


def acquire_wikidata(
    dest_dir,
    *,
    bbox,
    class_qids: list[str],
    config: dict,
    fetch_json=fetch.get_json,
    class_chunk_size: int = 25,
    tile_degrees: float = 1.0,
    retries: int = 6,
    sleep=time.sleep,
    retrieved_at: str | None = None,
) -> pathlib.Path:
    dest = _ensure_dir(dest_dir)
    out = snapshot_paths(dest)["wikidata"]
    endpoint = config["endpoint"]
    expected_hosts = set(config["allowed_hosts"])
    max_bytes = int(config.get("max_bytes", fetch.MAX_RESPONSE_BYTES))
    bindings = []
    segments = []

    try:
        for qid_chunk in _chunks(sorted(class_qids), class_chunk_size):
            for tile in bbox_tiles(bbox, tile_degrees=tile_degrees):
                query = _wdqs_query(qid_chunk, tile)
                url = _endpoint_url(endpoint, {"query": query, "format": "json"})
                data = _retry_json(
                    url,
                    expected_hosts=expected_hosts,
                    max_bytes=max_bytes,
                    fetch_json=fetch_json,
                    retries=retries,
                    sleep=sleep,
                )
                segment_bindings = data.get("results", {}).get("bindings", [])
                if not isinstance(segment_bindings, list):
                    raise AcquireError("WDQS response missing results.bindings list")
                segment_bindings = _merge_wdqs_bindings(
                    _normalize_wdqs_bindings(segment_bindings)
                )
                bindings.extend(segment_bindings)
                segments.append(
                    {
                        "bbox": list(tile),
                        "classes": qid_chunk,
                        "count": len(segment_bindings),
                        "query": query,
                    }
                )
    except Exception:
        out.unlink(missing_ok=True)
        out.with_name(f".{out.name}.tmp").unlink(missing_ok=True)
        raise

    return _atomic_write_json(
        out,
        {
            "_meta": {
                "complete": True,
                "endpoint": endpoint,
                "retrieved_at": retrieved_at or _now(),
                "segments": segments,
            },
            "head": {
                "vars": [
                    "item",
                    "p31",
                    "p31s",
                    "matched_class",
                    "lat",
                    "lon",
                    "label",
                    "sitelinks",
                    "image",
                ]
            },
            "results": {"bindings": bindings},
        },
    )


def _wiki_geosearch_url(endpoint: str, tile) -> str:
    west, south, east, north = tile
    return _endpoint_url(
        endpoint,
        {
            "action": "query",
            "format": "json",
            "list": "geosearch",
            "gsbbox": f"{north}|{west}|{south}|{east}",
            "gslimit": "500",
        },
    )


def _fetch_wikipedia_segment(
    *,
    index: int,
    tile,
    endpoint: str,
    expected_hosts: set[str],
    max_bytes: int,
    fetch_json,
    retries: int,
    sleep,
    backoff: SharedBackoff | None,
    segment_dir: pathlib.Path,
) -> pathlib.Path:
    data = _retry_json(
        _wiki_geosearch_url(endpoint, tile),
        expected_hosts=expected_hosts,
        max_bytes=max_bytes,
        fetch_json=fetch_json,
        retries=retries,
        sleep=sleep,
        backoff=backoff,
    )
    if "error" in data:
        error = data["error"]
        code = error.get("code", "unknown") if isinstance(error, dict) else "unknown"
        info = error.get("info", "") if isinstance(error, dict) else ""
        raise AcquireError(f"Wikipedia geosearch error {code}: {info}")
    rows = data.get("query", {}).get("geosearch", [])
    if not isinstance(rows, list):
        raise AcquireError("Wikipedia geosearch response missing list")
    return _atomic_write_json(
        segment_dir / f"{index:06d}.json",
        {"bbox": list(tile), "count": len(rows), "index": index, "rows": rows},
    )


def _merge_wikipedia_segments(segment_paths: list[pathlib.Path]) -> tuple[list[int], list[dict]]:
    pageids: set[int] = set()
    segments = []
    for path in sorted(segment_paths, key=lambda item: item.name):
        data = json.loads(path.read_text())
        rows = data.get("rows", [])
        if not isinstance(rows, list):
            raise AcquireError(f"Wikipedia segment {path} rows must be a list")
        for row in rows:
            try:
                pageids.add(int(row["pageid"]))
            except (KeyError, TypeError, ValueError):
                continue
        segments.append(
            {
                "bbox": data["bbox"],
                "count": int(data["count"]),
                "index": int(data["index"]),
            }
        )
    return sorted(pageids), segments


def _wiki_pages_url(endpoint: str, pageids: list[int]) -> str:
    return _endpoint_url(
        endpoint,
        {
            "action": "query",
            "format": "json",
            "prop": "extracts|pageprops|coordinates",
            "exintro": "1",
            "explaintext": "1",
            "pageids": "|".join(str(pageid) for pageid in pageids),
        },
    )


def acquire_wikipedia(
    dest_dir,
    *,
    bbox,
    language: str,
    config: dict,
    fetch_json=fetch.get_json,
    tile_degrees: float = 1.0,
    page_batch_size: int = 50,
    retries: int = 6,
    sleep=time.sleep,
    retrieved_at: str | None = None,
    geosearch_workers: int = 4,
) -> pathlib.Path:
    dest = _ensure_dir(dest_dir)
    out = snapshot_paths(dest)["wikipedia"]
    endpoint = config["endpoint"]
    expected_hosts = set(config["allowed_hosts"])
    max_bytes = int(config.get("max_bytes", fetch.MAX_RESPONSE_BYTES))
    segment_dir = dest / ".wikipedia-geosearch-segments.tmp"
    if segment_dir.exists():
        shutil.rmtree(segment_dir)
    segment_dir.mkdir(parents=True)

    try:
        tiles = bbox_tiles(bbox, tile_degrees=tile_degrees)
        segment_paths = []
        workers = max(1, min(int(geosearch_workers), 8))
        backoff = SharedBackoff(sleep) if workers > 1 else None
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
            futures = [
                executor.submit(
                    _fetch_wikipedia_segment,
                    index=index,
                    tile=tile,
                    endpoint=endpoint,
                    expected_hosts=expected_hosts,
                    max_bytes=max_bytes,
                    fetch_json=fetch_json,
                    retries=retries,
                    sleep=sleep,
                    backoff=backoff,
                    segment_dir=segment_dir,
                )
                for index, tile in enumerate(tiles)
            ]
            for future in concurrent.futures.as_completed(futures):
                segment_paths.append(future.result())
        pageids, segments = _merge_wikipedia_segments(segment_paths)

        pages = []
        for batch in _chunks([str(pageid) for pageid in pageids], page_batch_size):
            ids = [int(pageid) for pageid in batch]
            data = _retry_json(
                _wiki_pages_url(endpoint, ids),
                expected_hosts=expected_hosts,
                max_bytes=max_bytes,
                fetch_json=fetch_json,
                retries=retries,
                sleep=sleep,
            )
            page_map = data.get("query", {}).get("pages", {})
            if not isinstance(page_map, dict):
                raise AcquireError("Wikipedia pages response missing pages object")
            for pageid in sorted(page_map, key=lambda key: int(key)):
                page = page_map[pageid]
                coords = page.get("coordinates") or [{}]
                first_coord = coords[0] if isinstance(coords, list) and coords else {}
                pages.append(
                    {
                        "extract": page.get("extract", ""),
                        "lat": first_coord.get("lat"),
                        "lon": first_coord.get("lon"),
                        "pageid": int(page["pageid"]),
                        "title": page.get("title", ""),
                        "wikidata": page.get("pageprops", {}).get("wikibase_item"),
                    }
                )
    except Exception:
        out.unlink(missing_ok=True)
        out.with_name(f".{out.name}.tmp").unlink(missing_ok=True)
        raise
    finally:
        shutil.rmtree(segment_dir, ignore_errors=True)

    return _atomic_write_json(
        out,
        {
            "_meta": {
                "complete": True,
                "endpoint": endpoint,
                "retrieved_at": retrieved_at or _now(),
                "segments": segments,
            },
            "lang": language,
            "pages": pages,
        },
    )


def _sha256_file(path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _md5_file(path) -> str:
    digest = hashlib.md5(usedforsecurity=False)
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _parse_md5(text: str) -> str:
    match = re.search(r"\b[0-9a-fA-F]{32}\b", text)
    if not match:
        raise AcquireError("Geofabrik md5 response did not contain an md5 digest")
    return match.group(0).lower()


def acquire_osm(
    dest_dir,
    *,
    region_id: str,
    config: dict,
    download_file=fetch.get_to_file,
    fetch_text=None,
    retrieved_at: str | None = None,
) -> pathlib.Path:
    dest = _ensure_dir(dest_dir)
    out = snapshot_paths(dest)["osm"]
    entry = config[region_id]
    expected_hosts = set(entry["allowed_hosts"])
    max_bytes = int(entry.get("max_bytes", fetch.MAX_RESPONSE_BYTES))

    try:
        size = download_file(
            entry["url"],
            out,
            expected_hosts=expected_hosts,
            max_bytes=max_bytes,
        )
        if fetch_text is None:
            md5_path = out.with_name(f"{out.name}.md5")
            fetch.get_to_file(
                entry["md5_url"],
                md5_path,
                expected_hosts=expected_hosts,
                max_bytes=4096,
            )
            md5_text = md5_path.read_text()
            md5_path.unlink(missing_ok=True)
        else:
            md5_text = fetch_text(
                entry["md5_url"],
                expected_hosts=expected_hosts,
                max_bytes=4096,
            )
        expected_md5 = _parse_md5(md5_text)
        actual_md5 = _md5_file(out)
        if actual_md5 != expected_md5:
            raise AcquireError(f"Geofabrik md5 mismatch: {actual_md5} != {expected_md5}")
        sidecar = {
            "geofabrik_date": entry.get("geofabrik_date") or (retrieved_at or _now())[:10],
            "sha256": _sha256_file(out),
            "size": size,
            "source_url": entry["url"],
        }
        pathlib.Path(str(out) + ".meta.json").write_text(json.dumps(sidecar, sort_keys=True))
    except Exception:
        out.unlink(missing_ok=True)
        pathlib.Path(str(out) + ".meta.json").unlink(missing_ok=True)
        raise

    return out


def acquire_registers(dest_dir, *, region_config, config_path=DEFAULT_REGISTER_CONFIG) -> dict:
    config = json.loads(pathlib.Path(config_path).read_text())
    paths = {}
    for source in ("historic_england", "open_plaques"):
        if region_config.sources.get(source) is True:
            paths[source] = _snapshot.download_snapshot(
                source,
                dest_dir,
                config=config,
                enabled=True,
            )
    return paths


def _qid_from_uri(uri: str) -> str:
    return uri.rsplit("/", 1)[-1]


def _redirect_query(qids: list[str]) -> str:
    values = " ".join(f"wd:{qid}" for qid in qids)
    return f"""
PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX schema: <http://schema.org/>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
SELECT ?from ?to WHERE {{
  VALUES ?from {{ {values} }}
  ?from owl:sameAs ?to .
  OPTIONAL {{ ?article schema:about ?from . }}
}}
""".strip()


def acquire_wikidata_redirect_map(
    dest_dir,
    *,
    qids: list[str],
    config: dict,
    wikidata_retrieved_at: str,
    fetch_json=fetch.get_json,
    qid_chunk_size: int = 100,
    retries: int = 3,
    sleep=time.sleep,
    retrieved_at: str | None = None,
) -> pathlib.Path:
    retrieved_at = retrieved_at or _now()
    if _parse_time(retrieved_at) < _parse_time(wikidata_retrieved_at):
        raise AcquireError("redirect map snapshot is older than wikidata snapshot")

    dest = _ensure_dir(dest_dir)
    out = redirect_map_path(dest)
    endpoint = config["endpoint"]
    expected_hosts = set(config["allowed_hosts"])
    max_bytes = int(config.get("max_bytes", fetch.MAX_RESPONSE_BYTES))
    redirects: dict[str, str] = {}
    segments = []

    try:
        known_qids = sorted({qid for qid in qids if _QID_RE.fullmatch(qid)})
        for qid_chunk in _chunks(known_qids, qid_chunk_size):
            query = _redirect_query(qid_chunk)
            data = _retry_json(
                _endpoint_url(endpoint, {"query": query, "format": "json"}),
                expected_hosts=expected_hosts,
                max_bytes=max_bytes,
                fetch_json=fetch_json,
                retries=retries,
                sleep=sleep,
            )
            rows = data.get("results", {}).get("bindings", [])
            if not isinstance(rows, list):
                raise AcquireError("WDQS redirect response missing results.bindings list")
            for row in rows:
                try:
                    source = _qid_from_uri(row["from"]["value"])
                    target = _qid_from_uri(row["to"]["value"])
                except (KeyError, TypeError):
                    continue
                if _QID_RE.fullmatch(source) and _QID_RE.fullmatch(target):
                    redirects[source] = target
            segments.append({"qids": qid_chunk, "count": len(rows), "query": query})
    except Exception:
        out.unlink(missing_ok=True)
        out.with_name(f".{out.name}.tmp").unlink(missing_ok=True)
        raise

    return _atomic_write_json(
        out,
        {
            "_meta": {
                "complete": True,
                "endpoint": endpoint,
                "retrieved_at": retrieved_at,
                "segments": segments,
                "wikidata_retrieved_at": wikidata_retrieved_at,
            },
            "redirects": dict(sorted(redirects.items())),
        },
    )


def wikidata_snapshot_retrieved_at(snapshot_path) -> str:
    data = json.loads(pathlib.Path(snapshot_path).read_text())
    meta = data.get("_meta", {})
    value = meta.get("retrieved_at")
    if not isinstance(value, str):
        raise AcquireError("wikidata snapshot missing _meta.retrieved_at")
    return value


def qids_from_store(conn, *, region: str) -> list[str]:
    qids: set[str] = set()
    rows = conn.execute(
        "SELECT source_ref, props_json FROM source_records WHERE region = ?",
        (region,),
    ).fetchall()
    for source_ref, props_json in rows:
        if isinstance(source_ref, str) and source_ref.startswith("wd:"):
            qids.add(source_ref.split(":", 1)[1])
        try:
            props = json.loads(props_json)
        except (TypeError, ValueError, RecursionError):
            continue
        value = props.get("wikidata") if isinstance(props, dict) else None
        if isinstance(value, str) and _QID_RE.fullmatch(value):
            qids.add(value)
    return sorted(qids)


def acquire_all(dest_dir, *, region_config, config_path=DEFAULT_CONFIG) -> dict[str, pathlib.Path]:
    config = load_config(config_path)
    dest = _ensure_dir(dest_dir)
    paths = {}
    if region_config.sources.get("wikidata") is True:
        paths["wikidata"] = acquire_wikidata(
            dest,
            bbox=region_config.bbox,
            class_qids=load_class_qids(),
            config=config["wikidata"],
        )
    if region_config.sources.get("wikipedia") is True:
        language = region_config.languages[0]
        paths["wikipedia"] = acquire_wikipedia(
            dest,
            bbox=region_config.bbox,
            language=language,
            config=config["wikipedia"],
            tile_degrees=0.15,
        )
    if region_config.sources.get("osm") is True:
        paths["osm"] = acquire_osm(
            dest,
            region_id=region_config.region_id,
            config=config["osm"],
        )
    paths.update(acquire_registers(dest, region_config=region_config))
    return paths
