"""Cut a single region basemap and enforce pack budgets."""

from __future__ import annotations

import hashlib
import math
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from mt_contracts.caps import BASEMAP_MAXZOOM, PACK_BUDGET_CEILING_BYTES
from mt_pipeline import acquire, fetch

PMTILES_TOOL = "pmtiles"
PMTILES_REQUIRED_VERSION = "v1.31.1"
PMTILES_INSTALL_SOURCE = (
    "https://github.com/protomaps/go-pmtiles/releases/tag/v1.31.1"
)
PMTILES_LINUX_X86_64_URL = (
    "https://github.com/protomaps/go-pmtiles/releases/download/v1.31.1/"
    "go-pmtiles_1.31.1_Linux_x86_64.tar.gz"
)
PMTILES_LINUX_X86_64_SHA256 = (
    "71b2212d6796e172b8ba27c21e662c25ec93cacdb88adc35e508617e720f6292"
)
_BASEMAP_FILENAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,123}\.pmtiles$")
_HTTPS_URL_RE = re.compile(r"^https://[^\x00-\x1f\x7f-\x9f\s]+$")


class BasemapOverBudget(ValueError):
    """Raised when a region basemap exceeds its configured pack budget."""


class BasemapMeasurementMismatch(ValueError):
    """Raised when a cut basemap differs from its exact measured contract size."""


class BasemapRetainedCutMismatch(ValueError):
    """Raised when a retained basemap cut differs from its pinned contract."""


class PmtilesUnavailable(RuntimeError):
    """Raised when the pmtiles CLI is missing from PATH."""


@dataclass(frozen=True)
class BasemapArtifact:
    filename: str
    maxzoom: int
    sha256: str
    bytes: int
    bbox: list[float]


def require_pmtiles() -> str:
    path = shutil.which(PMTILES_TOOL)
    if path is None:
        raise PmtilesUnavailable(_pmtiles_install_message("Missing required tool 'pmtiles'."))
    path = _validate_pmtiles_executable(path)
    try:
        # Audit note: list-form argv, shell=False; dynamic executable is name/file
        # validated here and version-pinned below before any extract command runs.
        result = subprocess.run(  # nosemgrep: python.lang.security.audit.dangerous-subprocess-use-audit -- shell=False list argv; executable is _validate_pmtiles_executable-checked and v1.31.1-pinned.
            _pmtiles_version_argv(path),
            capture_output=True,
            check=False,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise PmtilesUnavailable(
            _pmtiles_install_message(f"Could not run '{path} version': {exc}.")
        ) from exc

    version_output = (result.stdout + "\n" + result.stderr).strip()
    if result.returncode != 0 or not _pmtiles_version_matches(version_output):
        observed = version_output[:500] if version_output else "<empty>"
        raise PmtilesUnavailable(
            _pmtiles_install_message(
                f"Found '{path}', but it did not report go-pmtiles "
                f"{PMTILES_REQUIRED_VERSION}; `pmtiles version` output was: {observed}"
            )
        )
    return path


def _validate_pmtiles_executable(path: str) -> str:
    resolved = Path(path).resolve()
    if resolved.name != PMTILES_TOOL:
        raise PmtilesUnavailable(
            _pmtiles_install_message(f"Found unexpected executable for pmtiles: {path}.")
        )
    if not resolved.is_file():
        raise PmtilesUnavailable(
            _pmtiles_install_message(f"pmtiles executable is not a file: {path}.")
        )
    return str(resolved)


def _pmtiles_version_argv(pmtiles: str) -> list[str]:
    return [_validate_pmtiles_executable(pmtiles), "version"]


def _pmtiles_version_matches(version_output: str) -> bool:
    required = PMTILES_REQUIRED_VERSION.removeprefix("v")
    return any(
        token.lstrip("v") == required
        for token in re.findall(r"v?\d+(?:\.\d+){2}", version_output)
    )


def _pmtiles_install_message(reason: str) -> str:
    return (
        f"{reason} Required: go-pmtiles {PMTILES_REQUIRED_VERSION}. Install it from "
        f"{PMTILES_INSTALL_SOURCE}; no-sudo Linux x86_64 example: "
        "mkdir -p ~/.local/bin && "
        f"curl -fL {PMTILES_LINUX_X86_64_URL} -o /tmp/go-pmtiles.tar.gz && "
        f"echo '{PMTILES_LINUX_X86_64_SHA256}  /tmp/go-pmtiles.tar.gz' | sha256sum -c - && "
        "tar -xzf /tmp/go-pmtiles.tar.gz -C ~/.local/bin pmtiles && "
        "chmod +x ~/.local/bin/pmtiles && "
        "export PATH=~/.local/bin:$PATH && pmtiles version"
    )


def cut_basemap(region_config: dict[str, Any], out_path: Path) -> BasemapArtifact:
    region = region_config["region"]
    cfg = region_config["basemap"]
    maxzoom = int(cfg["maxzoom"])
    if maxzoom != BASEMAP_MAXZOOM:
        raise ValueError(f"{region} basemap maxzoom must be {BASEMAP_MAXZOOM}")

    out_path = Path(out_path)
    if "retained_cut_pmtiles" in cfg:
        return _reuse_retained_cut(region, cfg, out_path)

    pmtiles = require_pmtiles()
    argv, bbox = _pmtiles_extract_argv(
        pmtiles,
        source_pmtiles=str(cfg["source_pmtiles"]),
        out_path=out_path,
        bbox_values=cfg["bbox"],
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    # Audit note: list-form argv, shell=False; executable, HTTPS source, safe
    # output filename, and finite bbox are validated by _pmtiles_extract_argv.
    subprocess.run(argv, check=True)  # nosemgrep: python.lang.security.audit.dangerous-subprocess-use-audit -- shell=False list argv from _pmtiles_extract_argv validators: pinned executable, HTTPS source, safe output name, finite bbox.

    size = out_path.stat().st_size
    budget = min(int(cfg["size_budget_bytes"]), PACK_BUDGET_CEILING_BYTES)
    if size > budget:
        raise BasemapOverBudget(
            f"{region} basemap is {size} bytes, over budget {budget}; define sub-region configs"
        )
    measured_size = int(cfg["measured_archive_bytes"])
    if size != measured_size:
        raise BasemapMeasurementMismatch(
            f"{region} basemap is {size} bytes, expected exact measured size "
            f"{measured_size} from region config; verify source_pmtiles and pmtiles version"
        )
    return BasemapArtifact(
        filename=out_path.name,
        maxzoom=BASEMAP_MAXZOOM,
        sha256=_sha256_file(out_path),
        bytes=size,
        bbox=bbox,
    )


def _reuse_retained_cut(region: str, cfg: dict[str, Any], out_path: Path) -> BasemapArtifact:
    output = Path(_validate_output_path(out_path))
    source = _validate_retained_cut_url(str(cfg["retained_cut_pmtiles"]))
    expected_sha = _validate_sha256(str(cfg.get("retained_cut_sha256", "")))
    bbox = _validate_bbox(cfg["bbox"])
    budget = min(int(cfg["size_budget_bytes"]), PACK_BUDGET_CEILING_BYTES)
    measured_size = int(cfg["measured_archive_bytes"])

    output.parent.mkdir(parents=True, exist_ok=True)
    fetch.get_to_file(
        source,
        output,
        expected_hosts={"tiles.making-tracks.app"},
        max_bytes=budget,
        headers={"User-Agent": acquire.USER_AGENT},
    )

    size = output.stat().st_size
    if size > budget:
        output.unlink(missing_ok=True)
        raise BasemapOverBudget(
            f"{region} retained basemap is {size} bytes, over budget {budget}"
        )
    if size != measured_size:
        output.unlink(missing_ok=True)
        raise BasemapRetainedCutMismatch(
            f"{region} retained basemap is {size} bytes, expected exact measured size "
            f"{measured_size}"
        )
    observed_sha = _sha256_file(output)
    if observed_sha != expected_sha:
        output.unlink(missing_ok=True)
        raise BasemapRetainedCutMismatch(
            f"{region} retained basemap sha256 {observed_sha}, expected {expected_sha}"
        )
    return BasemapArtifact(
        filename=output.name,
        maxzoom=BASEMAP_MAXZOOM,
        sha256=observed_sha,
        bytes=size,
        bbox=bbox,
    )


def _pmtiles_extract_argv(
    pmtiles: str,
    *,
    source_pmtiles: str,
    out_path: Path,
    bbox_values: Any,
) -> tuple[list[str], list[float]]:
    source = _validate_source_pmtiles(source_pmtiles)
    output = _validate_output_path(out_path)
    bbox = _validate_bbox(bbox_values)
    bbox_arg = ",".join(str(value) for value in bbox)
    return (
        [
            _validate_pmtiles_executable(pmtiles),
            "extract",
            source,
            output,
            f"--maxzoom={BASEMAP_MAXZOOM}",
            f"--bbox={bbox_arg}",
        ],
        bbox,
    )


def _validate_source_pmtiles(value: str) -> str:
    if len(value) > 2048 or not _HTTPS_URL_RE.fullmatch(value):
        raise ValueError("source_pmtiles must be an https URL without whitespace/control chars")
    return value


def _validate_retained_cut_url(value: str) -> str:
    if len(value) > 2048 or not _HTTPS_URL_RE.fullmatch(value):
        raise ValueError(
            "retained_cut_pmtiles must be an https URL without whitespace/control chars"
        )
    parsed = urlparse(value)
    if parsed.hostname != "tiles.making-tracks.app" or not parsed.path.endswith(".pmtiles"):
        raise ValueError("retained_cut_pmtiles must point at controlled PMTiles storage")
    return value


def _validate_sha256(value: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{64}", value):
        raise ValueError("retained_cut_sha256 must be a lowercase hex sha256")
    return value


def _validate_output_path(path: Path) -> str:
    path = Path(path)
    if not _BASEMAP_FILENAME_RE.fullmatch(path.name):
        raise ValueError(f"unsafe basemap output filename: {path.name}")
    return str(path)


def _validate_bbox(values: Any) -> list[float]:
    try:
        bbox = [float(value) for value in values]
    except (TypeError, ValueError) as exc:
        raise ValueError("basemap bbox must contain four finite numbers") from exc
    if len(bbox) != 4 or not all(math.isfinite(value) for value in bbox):
        raise ValueError("basemap bbox must contain four finite numbers")
    if not all(-180.0 <= value <= 180.0 for value in bbox):
        raise ValueError("basemap bbox values must be between -180 and 180")
    return bbox


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
