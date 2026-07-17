# Making Tracks Pipeline

`making-tracks-pipeline` is the Python scaffold for the region-parameterised data pipeline:

`extract -> reconcile -> score -> categorize -> publish`

WP-A1 intentionally makes those stages dispatchable no-ops. They enforce stage order and record completion in the working store; domain logic lands later in A1b/A1c/A1d, A2, A3, A4, and A7.

## Setup

From the repo root:

```bash
uv sync
```

Run commands and tests with `uv run` so the workspace `mt-contracts` dependency is installed:

```bash
cd pipeline
uv run --extra dev python -m pytest -q
uv run mt-pipeline --region uk extract
```

No-uv fallback for a Python 3.11 environment:

```bash
python -m pip install -e ./contracts -e "./pipeline[dev]"
python -m pytest pipeline/tests -q
```

## CLI

```bash
uv run mt-pipeline --region uk extract --db work.db
uv run mt-pipeline --region uk reconcile --db work.db
uv run mt-pipeline --region uk score --db work.db
uv run mt-pipeline --region uk categorize --db work.db
uv run mt-pipeline --region uk publish --db work.db
```

Every stage after `extract` requires its immediate predecessor to have completed for the same region. A skipped predecessor fails loudly and names the stage to run first.

## Source Records

`mt_pipeline.source_record.parse()` is the single defensive boundary every extractor will call. It delegates source-ref grammar and unsafe-text stripping to `mt_contracts`, bounds finite coordinates, and bounds plus cleans opaque `props`. `props` is intentionally opaque here: URL validation belongs to extractors when they map a known URL field, and A0 remains the final publish gate.

## Working Store

The SQLite working store is ephemeral between-stage state, recreated per run. It has a `meta(schema_version)` row so stale-shaped databases fail loudly, but it is not a published cross-boundary artifact. All source-derived values are written with parameterized SQL.

## Determinism

No wall-clock or randomness feeds output values. `run_id` and `completed_at` are metadata only. The test suite scans for wall-clock and random APIs, allowing only the single timestamp helper used to record stage-completion metadata.
