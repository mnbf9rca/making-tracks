"""Cut a single region basemap and enforce pack budgets."""

from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from mt_contracts.caps import BASEMAP_MAXZOOM, PACK_BUDGET_CEILING_BYTES

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


class BasemapOverBudget(ValueError):
    """Raised when a region basemap exceeds its configured pack budget."""


class BasemapMeasurementMismatch(ValueError):
    """Raised when a cut basemap differs from its exact measured contract size."""


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
    try:
        result = subprocess.run(
            [path, "version"],
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

    bbox = [float(value) for value in cfg["bbox"]]
    bbox_arg = ",".join(str(value) for value in bbox)
    out_path = Path(out_path)
    pmtiles = require_pmtiles()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            pmtiles,
            "extract",
            str(cfg["source_pmtiles"]),
            str(out_path),
            f"--maxzoom={BASEMAP_MAXZOOM}",
            f"--bbox={bbox_arg}",
        ],
        check=True,
    )

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


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
