import subprocess

import pytest

from mt_contracts.caps import PACK_BUDGET_CEILING_BYTES
from mt_pipeline.publish import basemap as B


def _cfg(source, size_budget_bytes=3_000_000_000, measured_archive_bytes=1_400_000_000):
    return {
        "region": "uk",
        "basemap": {
            "source_pmtiles": str(source),
            "maxzoom": 14,
            "size_budget_bytes": size_budget_bytes,
            "measured_archive_bytes": measured_archive_bytes,
            "bbox": [-8.6, 49.8, 1.8, 60.9],
        },
    }


def test_within_budget_produces_one_basemap_matching_the_manifest_shape(
    tmp_path, monkeypatch
):
    source = tmp_path / "source.pmtiles"
    source.write_bytes(b"source")

    def fake_run(args, check):
        assert args[:3] == ["pmtiles", "extract", str(source)]
        assert "--maxzoom=14" in args
        assert "--bbox=-8.6,49.8,1.8,60.9" in args
        (tmp_path / "uk.pmtiles").write_bytes(b"cut")
        return subprocess.CompletedProcess(args=args, returncode=0)

    monkeypatch.setattr(B.subprocess, "run", fake_run)

    art = B.cut_basemap(_cfg(source), tmp_path / "uk.pmtiles")

    assert art.maxzoom == 14
    assert art.filename == "uk.pmtiles"
    assert art.bytes == 3
    assert art.bbox == [-8.6, 49.8, 1.8, 60.9]


def test_over_budget_region_fails_loud_directing_ops_to_subregion_configs(
    tmp_path, monkeypatch
):
    source = tmp_path / "source.pmtiles"
    source.write_bytes(b"source")

    def fake_run(args, check):
        (tmp_path / "uk.pmtiles").write_bytes(b"cut")
        return subprocess.CompletedProcess(args=args, returncode=0)

    monkeypatch.setattr(B.subprocess, "run", fake_run)

    with pytest.raises(B.BasemapOverBudget):
        B.cut_basemap(
            _cfg(source, size_budget_bytes=1, measured_archive_bytes=5_000_000_000),
            tmp_path / "uk.pmtiles",
        )


def test_hard_pack_budget_ceiling_is_enforced_even_when_config_is_higher(
    tmp_path, monkeypatch
):
    source = tmp_path / "source.pmtiles"
    out = tmp_path / "uk.pmtiles"
    source.write_bytes(b"source")

    def fake_run(args, check):
        out.write_bytes(b"x")
        return subprocess.CompletedProcess(args=args, returncode=0)

    real_stat = B.Path.stat

    def fake_stat(self, *args, **kwargs):
        if self == out:
            return type("S", (), {"st_size": PACK_BUDGET_CEILING_BYTES + 1})()
        return real_stat(self, *args, **kwargs)

    monkeypatch.setattr(B.subprocess, "run", fake_run)
    monkeypatch.setattr(B.Path, "stat", fake_stat)

    with pytest.raises(B.BasemapOverBudget):
        B.cut_basemap(
            _cfg(source, size_budget_bytes=PACK_BUDGET_CEILING_BYTES + 100),
            out,
        )
