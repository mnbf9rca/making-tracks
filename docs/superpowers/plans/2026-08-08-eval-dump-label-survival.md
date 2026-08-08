# Eval Dump Label Survival Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit `--merge-existing PATH` option to `mt-pipeline eval dump` that preserves annotation history and retired labeled rows across refreshed dumps.

**Architecture:** Keep `golden.merge_labels` as the sole owner of carry-forward semantics. The CLI owns only bounded artifact loading, parse/area validation, audit counts, and sequencing the merge after the database dump but before any output path is created.

**Tech Stack:** Python 3.11, stdlib `argparse`/`pathlib`/`sqlite3`, existing `mt_pipeline.eval.golden` APIs, pytest.

## Global Constraints

- The option is explicit-only: no filesystem discovery and no fallback to ambient prior dumps.
- Without `--merge-existing`, output bytes and console behavior remain unchanged.
- Read the merge artifact with `_read_text_limited(..., max_bytes=_MAX_TSV_BYTES)`.
- Reject every parser skip and every artifact whose rows do not all match the requested area.
- Finish validation before creating the output directory or either output file.
- Render the same `merged + retired` row set to TSV and JSONL.
- Do not duplicate or modify `golden.merge_labels` semantics.
- No new dependency.

---

## File map

- `pipeline/tests/test_cli.py` — end-to-end command contract, fail-before-output boundaries, no-option regression, and merge-call teeth.
- `pipeline/src/mt_pipeline/cli.py` — parser option, bounded load/validation helper, audit counts, and dump-path integration.
- `pipeline/README.md` — operator invocation for refreshing an existing labeled set.

### Task 1: Wire the existing label-survival model into `eval dump`

**Files:**
- Modify: `pipeline/tests/test_cli.py:1-15,1480-1540`
- Modify: `pipeline/src/mt_pipeline/cli.py:288-309,1600-1690`
- Modify: `pipeline/README.md:30-45`

**Interfaces:**
- Consumes: `golden.parse_labeled_tsv(text: str) -> golden.ParseResult`
- Consumes: `golden.merge_labels(new_rows, existing_labeled) -> tuple[list[GoldenRow], list[GoldenRow]]`
- Produces: `_merge_existing_golden_rows(new_rows: list[golden.GoldenRow], *, path: pathlib.Path, area: str) -> tuple[list[golden.GoldenRow], tuple[int, int, int]]`
- Produces: CLI argument `--merge-existing PATH`
- Produces: success line `merge carried=<n> new=<n> retired=<n>` when the option is present

- [ ] **Step 1: Add a focused database fixture helper to the CLI tests**

Import the production golden module:

```python
from mt_pipeline.eval import golden, report as eval_report
```

Add a helper near the eval tests that initializes a real working store and inserts deterministic candidate rows:

```python
def _seed_eval_dump_db(db: Path, candidates: list[tuple[str, str, float, float]]) -> None:
    conn = store.connect(db)
    store.init_schema(conn)
    store.replace_places(
        conn,
        region="united-kingdom",
        places=[
            {
                "place_id": place_id,
                "name": name,
                "lat": 51.51,
                "lon": -0.11,
                "refs": [f"wd:{index}"],
                "member_refs": [f"wd:{index}"],
                "status": "active",
            }
            for index, (place_id, name, _, _) in enumerate(candidates, start=1)
        ],
    )
    for place_id, _, score, sample_signal in candidates:
        conn.execute(
            "INSERT INTO place_categories (place_id, region, category, run_id) VALUES (?, ?, ?, ?)",
            (place_id, "united-kingdom", "history", "cat-v2"),
        )
        conn.execute(
            "INSERT INTO place_scores (place_id, region, score, tier, signals_json, run_id) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                place_id,
                "united-kingdom",
                score,
                2,
                json.dumps({"article": sample_signal}),
                "score-v2",
            ),
        )
    conn.commit()
    conn.close()
```

- [ ] **Step 2: Write the failing end-to-end survival test**

Use three valid fixed place IDs. Put `A` and vanished `B` in the prior TSV, and `A` plus new `C` in the fresh DB. Give `A` a prior label, provenance, evidence, old score/signal/data-version/sample-weight; give `B` a prior label. Invoke:

```python
rc = cli.main(
    [
        "eval", "dump", "london",
        "--db", str(db),
        "--run-id", "v2",
        "--out-dir", str(out_dir),
        "--merge-existing", str(existing_tsv),
    ]
)
```

Parse the emitted TSV through `golden.parse_labeled_tsv`, parse each JSONL line with `json.loads`, and assert:

```python
assert rc == 0
assert captured.out.splitlines()[0] == "merge carried=1 new=1 retired=1"
assert by_id[A].label == "yes"
assert by_id[A].labeled_by == "rob-confirmed"
assert by_id[A].evidence == "manual evidence"
assert by_id[A].score == 0.95
assert by_id[A].signals == {"article": 0.75}
assert by_id[A].data_version == "v2"
assert by_id[A].sample_weight == 1.0
assert by_id[C].label is None and by_id[C].active
assert by_id[B].label == "no" and not by_id[B].active
assert set(json_by_id) == {A, B, C}
assert json_by_id[B]["active"] is False
```

- [ ] **Step 3: Run the survival test and verify RED**

Run:

```bash
PYTHONPATH=contracts/src:pipeline/src /Users/rob/git/making-tracks/.venv/bin/pytest pipeline/tests/test_cli.py::test_cli_eval_dump_merges_existing_annotation_history -v
```

Expected: argparse exits because `--merge-existing` is unrecognized.

- [ ] **Step 4: Add fail-before-output boundary tests**

Parameterize three artifacts against a seeded DB and a nonexistent `out_dir`:

1. a missing path;
2. a TSV with a valid header and an invalid `place_id`, producing a parser skip;
3. a valid TSV whose rows have `area="kl"` while the invocation requests `london`.

For every case assert `rc == 1`, `"eval dump merge error:"` is in stderr, and `not out_dir.exists()`.

Add a fourth test for the bounded reader without writing a 10 MB fixture: use `monkeypatch` to set
`cli._MAX_TSV_BYTES = 8`, write a nine-byte merge file, invoke the command, and assert the error names
the byte limit while the output directory still does not exist.

- [ ] **Step 5: Add the no-option compatibility regression**

Invoke the same seeded DB without `--merge-existing`. Open the DB after the command and compute:

```python
expected_rows = golden.dump_area(
    conn,
    "london",
    [-0.2, 51.5, -0.1, 51.6],
    data_version="v2",
)
```

Assert the emitted TSV equals `golden.render_tsv(expected_rows)`, the JSONL equals
`golden.render_jsonl(expected_rows)`, all rows are active and unlabeled, stdout contains only the two
existing `wrote ...` lines, and no `merge carried=` line appears.

- [ ] **Step 6: Run the new tests and confirm they are RED for the intended reasons**

Run:

```bash
PYTHONPATH=contracts/src:pipeline/src /Users/rob/git/making-tracks/.venv/bin/pytest pipeline/tests/test_cli.py -k 'eval_dump' -v
```

Expected: existing dump tests and the no-option test pass; merge-option tests fail only because the parser and integration do not exist.

- [ ] **Step 7: Add the parser argument and the validation/count helper**

Add the optional parser argument:

```python
dump.add_argument(
    "--merge-existing",
    help="prior hand-labeled golden TSV whose active and retired rows carry forward",
)
```

Add the helper immediately above `_run_eval`:

```python
def _merge_existing_golden_rows(
    new_rows: list[golden.GoldenRow],
    *,
    path: pathlib.Path,
    area: str,
) -> tuple[list[golden.GoldenRow], tuple[int, int, int]]:
    text = _read_text_limited(path, max_bytes=_MAX_TSV_BYTES)
    parsed = golden.parse_labeled_tsv(text)
    if parsed.skipped:
        details = "; ".join(f"{ident}: {reason}" for ident, reason in parsed.skipped)
        raise ValueError(f"merge-existing parse skipped rows: {details}")
    artifact_areas = {row.area for row in parsed.rows}
    if artifact_areas != {area}:
        raise ValueError(
            f"merge-existing areas {sorted(artifact_areas)!r} do not match requested area {area!r}"
        )

    existing_ids = {row.place_id for row in parsed.rows}
    carried = sum(row.place_id in existing_ids for row in new_rows)
    new = len(new_rows) - carried
    merged, retired = golden.merge_labels(new_rows, parsed.rows)
    return merged + retired, (carried, new, len(retired))
```

- [ ] **Step 8: Integrate the merge between DB dump and output creation**

Immediately after the existing `golden.dump_area` try/except and before `out_dir.mkdir`, add:

```python
merge_counts: tuple[int, int, int] | None = None
if args.merge_existing:
    try:
        rows, merge_counts = _merge_existing_golden_rows(
            rows,
            path=pathlib.Path(args.merge_existing),
            area=args.area,
        )
    except (OSError, ValueError) as exc:
        print(f"eval dump merge error: {exc}", file=sys.stderr)
        return 1
```

After both output writes and before the existing `wrote` lines, print only when counts exist:

```python
if merge_counts is not None:
    carried, new, retired = merge_counts
    print(f"merge carried={carried} new={new} retired={retired}")
```

- [ ] **Step 9: Run the focused tests and verify GREEN**

Run:

```bash
PYTHONPATH=contracts/src:pipeline/src /Users/rob/git/making-tracks/.venv/bin/pytest pipeline/tests/test_eval_golden.py pipeline/tests/test_cli.py -q
```

Expected: 105 existing tests plus the new CLI tests pass with zero failures.

- [ ] **Step 10: Prove test teeth by bypassing the merge call**

Temporarily replace:

```python
merged, retired = golden.merge_labels(new_rows, parsed.rows)
```

with:

```python
merged, retired = new_rows, []
```

Run the single end-to-end survival test and verify it fails on carried annotations and the retired
row. Restore the production call with `apply_patch`, rerun the test, and verify it passes.

- [ ] **Step 11: Document the operator command**

Add this example and explanation to `pipeline/README.md` under **CLI**:

```bash
uv run mt-pipeline eval dump london \
  --db work.db \
  --run-id refresh-v2 \
  --merge-existing docs/superpowers/eval/refresh-v1-golden-london.tsv
```

State that the explicit file supplies active and retired annotation history, bad artifacts fail
before outputs are created, and omitting the flag creates an ordinary fresh unlabeled dump.

- [ ] **Step 12: Run the pipeline gate and static checks**

Run:

```bash
PYTHONPATH=contracts/src:pipeline/src /Users/rob/git/making-tracks/.venv/bin/pytest pipeline/tests -q
python3 scripts/lint_agent_law.py
git diff --check
```

Expected: full pipeline suite passes with zero failures; agent-law lint and diff check are clean.

- [ ] **Step 13: Commit the implementation**

```bash
git add pipeline/src/mt_pipeline/cli.py pipeline/tests/test_cli.py pipeline/README.md
git commit -m "Preserve labels across eval dumps"
```

- [ ] **Step 14: Update the issue record and begin the repository review gates**

Rewrite issue #94's body into one coherent Request / Design / Acceptance account. Link the design
spec, name the explicit-only ruling and rejected auto-discovery behavior, and record test counts only
after fresh verification. Then run the mandatory independent adversarial review, push the exact reviewed
head, and open a draft PR to `develop` with `sourcery-review`, `track-a-pipeline`, and `wp` labels.
