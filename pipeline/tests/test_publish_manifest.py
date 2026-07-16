from types import SimpleNamespace

import pytest

from mt_pipeline.publish import manifest as M
from mt_pipeline.publish.tiles import PublishCounts, TileArtifact


def _tiles():
    return [
        TileArtifact(x=2, y=1, gz_bytes=b"b", sha256="b" * 64, byte_len=20),
        TileArtifact(x=1, y=1, gz_bytes=b"a", sha256="a" * 64, byte_len=10),
    ]


def _counts():
    return PublishCounts(
        total_published=3,
        by_tier=(1, 2, 0, 0),
        uncategorized_excluded=1,
        invalid_excluded=0,
        non_winner_excluded=0,
        overflow_dropped=0,
    )


def _basemap():
    return SimpleNamespace(
        filename="uk.pmtiles",
        maxzoom=14,
        sha256="0" * 64,
        bytes=1,
        bbox=[-8.6, 49.8, 1.8, 60.9],
    )


def test_no_LLM_publish_still_gets_a_valid_manifest_with_score_provenance():
    man = M.assemble_manifest(
        region="uk",
        publish_version="20260715T120000Z",
        generated_at="2026-07-15T12:00:00Z",
        tiles=_tiles(),
        counts=_counts(),
        basemap=_basemap(),
        scoring_config_version="scoring-v1",
        llm_provenance=(),
        attribution=(),
    )
    assert man["provenance"][0] == {
        "task_id": "score",
        "model": "heuristic",
        "prompt_version": "scoring-v1",
    }
    assert man["tiles"] == sorted(man["tiles"], key=lambda tile: (tile["x"], tile["y"]))
    assert man["counts"]["total"] == sum(man["counts"]["by_tier"])
    assert man["min_reader_version"] == 1


def test_attribution_bumps_min_reader_version():
    man = M.assemble_manifest(
        region="uk",
        publish_version="20260715T120000Z",
        generated_at="2026-07-15T12:00:00Z",
        tiles=_tiles(),
        counts=_counts(),
        basemap=_basemap(),
        scoring_config_version="scoring-v1",
        attribution=[
            {
                "source": "historic_england",
                "license": "OGL-3.0",
                "text": "Contains HE data...",
            }
        ],
    )
    assert man["min_reader_version"] == 2


def test_manifest_rejects_an_oversize_tile():
    bad = [{"x": 0, "y": 0, "sha256": "0" * 64, "bytes": 2 * 1024 * 1024}]
    with pytest.raises(M.ManifestInvalid):
        M.assemble_manifest(
            region="uk",
            publish_version="20260715T120000Z",
            generated_at="2026-07-15T12:00:00Z",
            tiles=bad,
            counts=_counts(),
            basemap=_basemap(),
            scoring_config_version="scoring-v1",
        )
