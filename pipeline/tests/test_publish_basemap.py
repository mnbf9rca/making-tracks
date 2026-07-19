import subprocess

import pytest

from mt_contracts.caps import PACK_BUDGET_CEILING_BYTES
from mt_pipeline.publish import basemap as B


def _cfg(source, size_budget_bytes=3_000_000_000, measured_archive_bytes=3):
    return {
        "region": "united-kingdom",
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
    source = "https://example.com/source.pmtiles"

    def fake_run(args, check):
        assert args[:3] == ["pmtiles", "extract", str(source)]
        assert "--maxzoom=14" in args
        assert "--bbox=-8.6,49.8,1.8,60.9" in args
        (tmp_path / "uk.pmtiles").write_bytes(b"cut")
        return subprocess.CompletedProcess(args=args, returncode=0)

    monkeypatch.setattr(B.subprocess, "run", fake_run)
    monkeypatch.setattr(B, "require_pmtiles", lambda: "pmtiles", raising=False)
    monkeypatch.setattr(B, "_validate_pmtiles_executable", lambda path: path)

    art = B.cut_basemap(_cfg(source), tmp_path / "uk.pmtiles")

    assert art.maxzoom == 14
    assert art.filename == "uk.pmtiles"
    assert art.bytes == 3
    assert art.bbox == [-8.6, 49.8, 1.8, 60.9]


def test_over_budget_region_fails_loud_directing_ops_to_subregion_configs(
    tmp_path, monkeypatch
):
    source = "https://example.com/source.pmtiles"

    def fake_run(args, check):
        (tmp_path / "uk.pmtiles").write_bytes(b"cut")
        return subprocess.CompletedProcess(args=args, returncode=0)

    monkeypatch.setattr(B.subprocess, "run", fake_run)
    monkeypatch.setattr(B, "require_pmtiles", lambda: "pmtiles", raising=False)
    monkeypatch.setattr(B, "_validate_pmtiles_executable", lambda path: path)

    with pytest.raises(B.BasemapOverBudget):
        B.cut_basemap(
            _cfg(source, size_budget_bytes=1, measured_archive_bytes=5_000_000_000),
            tmp_path / "uk.pmtiles",
        )


def test_hard_pack_budget_ceiling_is_enforced_even_when_config_is_higher(
    tmp_path, monkeypatch
):
    source = "https://example.com/source.pmtiles"
    out = tmp_path / "uk.pmtiles"

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
    monkeypatch.setattr(B, "require_pmtiles", lambda: "pmtiles", raising=False)
    monkeypatch.setattr(B, "_validate_pmtiles_executable", lambda path: path)

    with pytest.raises(B.BasemapOverBudget):
        B.cut_basemap(
            _cfg(source, size_budget_bytes=PACK_BUDGET_CEILING_BYTES + 100),
            out,
        )


def test_pmtiles_dependency_check_fails_actionably_when_missing(monkeypatch):
    monkeypatch.setenv("PATH", "")

    with pytest.raises(B.PmtilesUnavailable) as excinfo:
        B.require_pmtiles()

    message = str(excinfo.value)
    assert "pmtiles" in message
    assert "v1.31.1" in message
    assert "protomaps/go-pmtiles" in message
    assert "~/.local/bin" in message
    assert "71b2212d6796e172b8ba27c21e662c25ec93cacdb88adc35e508617e720f6292" in message


def test_pmtiles_dependency_check_accepts_binary_on_path(tmp_path, monkeypatch):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    exe = bin_dir / "pmtiles"
    exe.write_text("#!/bin/sh\nprintf 'pmtiles version 1.31.1\\n'\n")
    exe.chmod(0o755)
    monkeypatch.setenv("PATH", str(bin_dir))

    assert B.require_pmtiles() == str(exe)


def test_pmtiles_dependency_check_rejects_wrong_version(tmp_path, monkeypatch):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    exe = bin_dir / "pmtiles"
    exe.write_text("#!/bin/sh\nprintf 'pmtiles version 1.30.0\\n'\n")
    exe.chmod(0o755)
    monkeypatch.setenv("PATH", str(bin_dir))

    with pytest.raises(B.PmtilesUnavailable) as excinfo:
        B.require_pmtiles()

    assert "v1.31.1" in str(excinfo.value)
    assert "1.30.0" in str(excinfo.value)


def test_pmtiles_dependency_check_rejects_substring_version(tmp_path, monkeypatch):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    exe = bin_dir / "pmtiles"
    exe.write_text("#!/bin/sh\nprintf 'pmtiles version 1.31.10\\n'\n")
    exe.chmod(0o755)
    monkeypatch.setenv("PATH", str(bin_dir))

    with pytest.raises(B.PmtilesUnavailable):
        B.require_pmtiles()


def test_pmtiles_dependency_check_rejects_unexpected_executable_name(
    tmp_path, monkeypatch
):
    exe = tmp_path / "not-pmtiles"
    exe.write_text("#!/bin/sh\nprintf 'pmtiles version 1.31.1\\n'\n")
    exe.chmod(0o755)
    monkeypatch.setattr(B.shutil, "which", lambda _tool: str(exe))

    with pytest.raises(B.PmtilesUnavailable) as excinfo:
        B.require_pmtiles()

    assert "unexpected executable" in str(excinfo.value)


def test_cut_basemap_checks_pmtiles_before_creating_output_dir(tmp_path, monkeypatch):
    source = tmp_path / "source.pmtiles"
    source.write_bytes(b"source")
    out = tmp_path / "missing-parent" / "uk.pmtiles"
    monkeypatch.setenv("PATH", "")

    with pytest.raises(B.PmtilesUnavailable):
        B.cut_basemap(_cfg(source), out)

    assert not out.parent.exists()


def test_cut_basemap_rejects_non_https_source_before_subprocess(tmp_path, monkeypatch):
    called = False

    def fake_run(*_args, **_kwargs):
        nonlocal called
        called = True
        raise AssertionError("subprocess should not run")

    monkeypatch.setattr(B.subprocess, "run", fake_run)
    monkeypatch.setattr(B, "require_pmtiles", lambda: "pmtiles", raising=False)

    with pytest.raises(ValueError, match="source_pmtiles"):
        B.cut_basemap(_cfg("http://example.com/source.pmtiles"), tmp_path / "uk.pmtiles")

    assert called is False


def test_cut_basemap_rejects_unsafe_output_name_before_subprocess(tmp_path, monkeypatch):
    called = False

    def fake_run(*_args, **_kwargs):
        nonlocal called
        called = True
        raise AssertionError("subprocess should not run")

    monkeypatch.setattr(B.subprocess, "run", fake_run)
    monkeypatch.setattr(B, "require_pmtiles", lambda: "pmtiles", raising=False)

    with pytest.raises(ValueError, match="output filename"):
        B.cut_basemap(_cfg("https://example.com/source.pmtiles"), tmp_path / "../UK.pmtiles")

    assert called is False


def test_cut_basemap_rejects_non_finite_bbox_before_subprocess(tmp_path, monkeypatch):
    called = False

    def fake_run(*_args, **_kwargs):
        nonlocal called
        called = True
        raise AssertionError("subprocess should not run")

    cfg = _cfg("https://example.com/source.pmtiles")
    cfg["basemap"]["bbox"] = [-8.6, 49.8, float("nan"), 60.9]
    monkeypatch.setattr(B.subprocess, "run", fake_run)
    monkeypatch.setattr(B, "require_pmtiles", lambda: "pmtiles", raising=False)

    with pytest.raises(ValueError, match="bbox"):
        B.cut_basemap(cfg, tmp_path / "uk.pmtiles")

    assert called is False


def test_cut_basemap_requires_exact_measured_archive_size(tmp_path, monkeypatch):
    source = "https://example.com/source.pmtiles"
    out = tmp_path / "uk.pmtiles"

    def fake_run(args, check):
        out.write_bytes(b"cut")
        return subprocess.CompletedProcess(args=args, returncode=0)

    monkeypatch.setattr(B.subprocess, "run", fake_run)
    monkeypatch.setattr(B, "require_pmtiles", lambda: "pmtiles", raising=False)
    monkeypatch.setattr(B, "_validate_pmtiles_executable", lambda path: path)

    with pytest.raises(B.BasemapMeasurementMismatch) as excinfo:
        B.cut_basemap(_cfg(source, measured_archive_bytes=4), out)

    assert "expected exact measured size" in str(excinfo.value)
