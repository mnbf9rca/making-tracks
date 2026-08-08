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
uv run mt-pipeline --region united-kingdom extract
```

No-uv fallback for a Python 3.11 environment:

```bash
python -m pip install -e ./contracts -e "./pipeline[dev]"
python -m pytest pipeline/tests -q
```

## CLI

```bash
uv run mt-pipeline --region united-kingdom extract --db work.db
uv run mt-pipeline --region united-kingdom reconcile --db work.db
uv run mt-pipeline --region united-kingdom score --db work.db
uv run mt-pipeline --region united-kingdom categorize --db work.db
uv run mt-pipeline --region united-kingdom publish --db work.db
```

Every stage after `extract` requires its immediate predecessor to have completed for the same region. A skipped predecessor fails loudly and names the stage to run first.

To refresh a golden-area dump without losing its hand labels, name the exact prior TSV explicitly:

```bash
uv run mt-pipeline eval dump london \
  --db work.db \
  --run-id refresh-v2 \
  --merge-existing docs/superpowers/eval/refresh-v1-golden-london.tsv
```

The named file supplies both active and retired annotation history. A missing, malformed, oversized,
or wrong-area artifact fails before either output is created. Omitting `--merge-existing` produces an
ordinary fresh unlabeled dump; the command never auto-discovers a prior file.

## Source Records

`mt_pipeline.source_record.parse()` is the single defensive boundary every extractor will call. It delegates source-ref grammar and unsafe-text stripping to `mt_contracts`, bounds finite coordinates, and bounds plus cleans opaque `props`. `props` is intentionally opaque here: URL validation belongs to extractors when they map a known URL field, and A0 remains the final publish gate.

## Wikipedia Blurb Coverage QA

When a shipped place has a Wikipedia sitelink but no card blurb, trace one QID end to end before changing the pipeline:

1. Retained refs: find the shipped `place_id`, `refs_json`, and `member_refs_json`; confirm the expected `wd:Q...` is retained.
2. Sitelink acquisition: find the matching `wp:` source row by `props.wikidata`; confirm title, pageid/source_ref, run id, and coordinates.
3. Snapshot content: inspect `wikipedia.snapshot.json` for the page in `pages` and `qid_pages`; record `extract_len`, image, and `wikibase_item`.
4. Extracted DB props: confirm `extract` and `description_extract` in `source_records.props_json`; distinguish blank upstream text from sanitizer or persist failures.
5. Description publish bridge: verify retained `wd:` refs can bridge to `wp:` rows by QID, then identify the specific drop reason.
6. Published artifacts: inspect the z10 tile plus matching `images/` and `descriptions/` sidecars; compare live CDN and staged SHA when serving behavior matters.

Use `acquire-wikipedia-sitelinks --refresh-blank-extracts-only` to refetch only accepted sitelink pages whose extract fields are blank, then re-extract Wikipedia rows into the working DB.

## Working Store

The SQLite working store is ephemeral between-stage state, recreated per run. It has a `meta(schema_version)` row so stale-shaped databases fail loudly, but it is not a published cross-boundary artifact. All source-derived values are written with parameterized SQL.

## Determinism

No wall-clock or randomness feeds output values. `run_id` and `completed_at` are metadata only. The test suite scans for wall-clock and random APIs, allowing only the single timestamp helper used to record stage-completion metadata.
