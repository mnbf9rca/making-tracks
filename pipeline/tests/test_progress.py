from io import StringIO

import pytest

from mt_pipeline import progress


class _StepClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


class _FlushingStream(StringIO):
    def __init__(self) -> None:
        super().__init__()
        self.flushes = 0

    def flush(self) -> None:
        self.flushes += 1
        super().flush()


def test_phase_progress_flushes_and_accepts_injected_clock_and_stream():
    clock = _StepClock()
    stream = _FlushingStream()
    phase = progress.PhaseProgress(
        "blank_extract.batch_refresh",
        region="en",
        total=2,
        total_label="pages",
        heartbeat_every_records=2,
        heartbeat_every_seconds=999,
        clock=clock,
        stream=stream,
    )

    phase.start()
    clock.now = 2.0
    phase.tick(1)
    phase.tick(2, extra=" recovered=1 skipped_mismatch=0 fallback_count=0")
    phase.done(2, extra=" recovered=1 skipped_mismatch=0 fallback_count=0")

    out = stream.getvalue()
    assert "PHASE START blank_extract.batch_refresh region=en pages=2\n" in out
    assert (
        "PHASE HEARTBEAT blank_extract.batch_refresh region=en processed=2/2 "
        "rate=1.0/s elapsed=2.0s recovered=1 skipped_mismatch=0 fallback_count=0\n"
    ) in out
    assert (
        "PHASE DONE blank_extract.batch_refresh region=en processed=2/2 "
        "elapsed=2.0s recovered=1 skipped_mismatch=0 fallback_count=0\n"
    ) in out
    assert stream.flushes == 3


def test_phase_progress_can_adopt_a_known_total_after_start():
    clock = _StepClock()
    stream = _FlushingStream()
    phase = progress.PhaseProgress(
        "acquire.osm.download",
        region="united-kingdom",
        total=None,
        total_label="bytes",
        heartbeat_every_records=1,
        heartbeat_every_seconds=999,
        clock=clock,
        stream=stream,
    )

    phase.start()
    phase.set_total(9)
    clock.now = 3.0
    phase.tick(9)
    phase.done(9)

    out = stream.getvalue()
    assert "PHASE START acquire.osm.download region=united-kingdom bytes=unknown" in out
    assert "processed=9/9 rate=3.0/s" in out
    assert "PHASE DONE acquire.osm.download region=united-kingdom processed=9/9" in out


@pytest.mark.parametrize("bad_total", [-1, True, 1.5, "9"])
def test_phase_progress_rejects_invalid_late_totals(bad_total):
    phase = progress.PhaseProgress(
        "acquire.osm.download",
        region="united-kingdom",
        total=None,
        total_label="bytes",
    )

    with pytest.raises(ValueError, match="total"):
        phase.set_total(bad_total)


def test_upload_progress_emits_pinned_publish_upload_shape_with_flush():
    clock = _StepClock()
    stream = _FlushingStream()
    upload = progress.UploadProgress(
        phase="publish.r2_upload_data",
        region="united-kingdom",
        total_objects=2,
        total_bytes=9,
        workers=3,
        heartbeat_every_objects=2,
        heartbeat_every_seconds=999,
        clock=clock,
        stream=stream,
    )

    upload.start()
    clock.now = 3.0
    upload.tick(object_bytes=4, kind="tile", key_class="tiles")
    upload.tick(object_bytes=5, kind="manifest", key_class="manifest")
    upload.done()

    out = stream.getvalue()
    assert (
        "PUBLISH_UPLOAD START phase=publish.r2_upload_data region=united-kingdom "
        "objects_total=2 bytes_total=9 workers=3\n"
    ) in out
    assert (
        "PUBLISH_UPLOAD HEARTBEAT phase=publish.r2_upload_data region=united-kingdom "
        "objects_done=2/2 bytes_done=9/9 objects_rate=0.7/s bytes_rate=3.0/s "
        "elapsed=3.0s workers=3 current_kind=manifest current_key_class=manifest "
        "kind_counts=manifest:1,tile:1\n"
    ) in out
    assert (
        "PUBLISH_UPLOAD DONE phase=publish.r2_upload_data region=united-kingdom "
        "objects_done=2/2 bytes_done=9/9"
    ) in out
    assert stream.flushes == 3
