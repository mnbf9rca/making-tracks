# Eval dump label survival

**Status:** approved by planner for issue #94
**Target:** `develop`

## Problem

`golden.merge_labels` already preserves hand labels across refreshed candidate sets, including
retiring vanished labeled rows and restoring their labels if they later return. The
`mt-pipeline eval dump` command never calls it. Every dump therefore writes a fresh unlabeled
TSV and JSONL pair, forcing the operator to compose the merge by hand.

## Command contract

`eval dump` gains one optional argument:

```text
--merge-existing PATH
```

`PATH` is the exact prior hand-labeled TSV whose active and retired rows form the label history.
The option is explicit-only. The command never searches the output directory or chooses a prior
dump from ambient filesystem state. Without the option, the command produces the same bytes and
messages it produces today.

## Data flow

1. Validate the area, run identifier, and area configuration as today.
2. Open the database and produce the fresh rows with `golden.dump_area` as today.
3. If `--merge-existing` is present, before creating the output directory or either output file:
   - read the named TSV with the existing 10 MB bounded text reader;
   - parse it with `golden.parse_labeled_tsv`;
   - reject the artifact if any row is skipped;
   - reject a header-only artifact with a specific empty-artifact error; a first fresh dump omits the
     merge option;
   - reject the artifact unless every parsed row belongs to the requested area;
   - pass the fresh rows and every parsed active or retired row to `golden.merge_labels`;
   - use `merged + retired` as the row set for both output formats.
4. Render the same final row set to TSV and JSONL using the existing deterministic renderers.

`golden.merge_labels` remains the only owner of carry-forward semantics. Surviving place IDs
inherit only `label`, `labeled_by`, and `evidence`; their fresh candidate facts, score, signals,
data version, and sample weight win. New candidates stay blank. Vanished labeled candidates remain
in the artifact with `active=false`. A later return restores their prior annotation. The existing
same-version candidate-change rejection continues to apply.

## Errors and observability

A missing, unreadable, empty, oversized, malformed, partially skipped, or wrong-area merge artifact
returns a non-zero status before any output is created. The error identifies the merge artifact
contract rather than presenting the failure as a database dump error.

On a successful merge, the command prints counts for:

- `carried`: fresh candidates whose annotation history was found;
- `new`: fresh candidates with no prior row;
- `retired`: labeled prior candidates absent from the fresh dump.

These counts make the explicit invocation auditable without inspecting the files. The ordinary
two `wrote ...` lines remain.

## Testing

The CLI regression uses the production parser, merge function, and both renderers. It proves that
a refreshed dump:

- preserves `label`, `labeled_by`, and `evidence` for surviving place IDs;
- keeps the fresh row's score, signals, data version, and sample weight;
- leaves a new place blank;
- emits a vanished labeled place as inactive in both TSV and JSONL;
- reports the carried, new, and retired counts.

Boundary tests prove that missing, empty, malformed/skipped, and valid-but-wrong-area artifacts fail
before the output directory or files exist. A no-option regression pins current fresh-unlabeled output.
Test teeth are demonstrated by bypassing the production merge call: the end-to-end survival test
must fail.

## Rejected alternatives

- **Auto-discover the latest area dump:** rejected because output would depend on invisible ambient
  filesystem state and the meaning of “latest” becomes ambiguous when several labeled generations
  exist.
- **Explicit path with auto-discovery fallback:** rejected because it retains the unsafe contract
  while adding a second behavior to document and test.
- **Reimplement carry-forward logic in the CLI:** rejected because it would create a second owner for
  semantics already pinned by `golden.merge_labels` and its resurrection tests.
