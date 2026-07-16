import subprocess

import pytest

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
