"""Cut a single region basemap and enforce pack budgets."""

from __future__ import annotations

import hashlib
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from mt_contracts.caps import BASEMAP_MAXZOOM, PACK_BUDGET_CEILING_BYTES


class BasemapOverBudget(ValueError):
    """Raised when a region basemap exceeds its configured pack budget."""


@dataclass(frozen=True)
class BasemapArtifact:
    filename: str
    maxzoom: int
    sha256: str
    bytes: int
    bbox: list[float]


def cut_basemap(region_config: dict[str, Any], out_path: Path) -> BasemapArtifact:
    region = region_config["region"]
    cfg = region_config["basemap"]
    maxzoom = int(cfg["maxzoom"])
    if maxzoom != BASEMAP_MAXZOOM:
        raise ValueError(f"{region} basemap maxzoom must be {BASEMAP_MAXZOOM}")

    bbox = [float(value) for value in cfg["bbox"]]
    bbox_arg = ",".join(str(value) for value in bbox)
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "pmtiles",
            "extract",
            str(cfg["source_pmtiles"]),
            str(out_path),
            f"--maxzoom={BASEMAP_MAXZOOM}",
            f"--bbox={bbox_arg}",
        ],
        check=True,
    )

    data = out_path.read_bytes()
    size = len(data)
    budget = min(int(cfg["size_budget_bytes"]), PACK_BUDGET_CEILING_BYTES)
    if size > budget:
        raise BasemapOverBudget(
            f"{region} basemap is {size} bytes, over budget {budget}; define sub-region configs"
        )
    return BasemapArtifact(
        filename=out_path.name,
        maxzoom=BASEMAP_MAXZOOM,
        sha256=hashlib.sha256(data).hexdigest(),
        bytes=size,
        bbox=bbox,
    )
