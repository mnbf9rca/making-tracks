# iOS Gate Ledger

This ledger records iOS gate count-watch decisions that affect whether a run counts, resets, or consumes the infra budget.

## Classification Rule

A red run is infra only when all of the following hold:

1. Every failure is a harness operation, such as a snapshot-query timeout or app launch/terminate failure, with no app assertion failure.
2. Non-UI is green.
3. There is positive environmental evidence: prior green on byte-identical tree and/or duration materially above the tree's established baseline.

Absent condition 3, a harness timeout is a real red. Infra classifications are budgeted and auditable. The budget is at most 1 infra-classified red per rolling window of 5 runs. If infra-classified reds exceed that budget, the gate is not ready to be authoritative and the response is to reduce harness sensitivity.

Each entry records gate duration and the runner benchmark score (`runner_benchmark_ops_per_sec`) so classifications can be checked against measured runner performance rather than duration alone. Use `not measured` only for legacy runs whose workflow did not emit the runner benchmark.

## Current Count

The infra budget is at 1 of 5. Run 29933454122 is exhausted: both attempts are classified infra, the rerun-once allowance is spent, and no third attempt is dispatched.

The next qualifying count-watch run starts a new rolling window from the first tree that contains both runner instrumentation from PR #410 and the harness hardening from PR #409.

## Entries

| Run | Attempt | Ref | Head | Duration | Runner Score | Result | Classification | Evidence | Action |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 29933454122 | 1 | ios | c6e0285444dbe0df8c41ecda1e050ffd1c6eb238 | 65m53s | not measured | failure | infra | Host/unit suites passed 154/154. UI suite ran 48 tests with 2 harness failures: `testCardVisitStateSuppressesNearbyPromptWithoutViewportRefresh` timed out evaluating a UI snapshot query, and `testCoverageEdgeScreenshotsAcrossThemes` failed in app termination. No app assertion failure. Duration was materially above the two green baselines on equivalent content at about 39m. | Rerun once; neither counts nor resets. |
| 29933454122 | 2 | ios | c6e0285444dbe0df8c41ecda1e050ffd1c6eb238 | 46m57s | not measured | failure | infra | Host/unit suite passed 154/154. UI suite ran 48 tests with 1 harness failure: `testCardVisitStateSuppressesNearbyPromptWithoutViewportRefresh` timed out evaluating a UI snapshot query. No app assertion failure. The release-gate test phase ran for 2219s, materially above the tree's established baseline. | Rerun-once exhausted; no candidate produced; budget is now 1 of 5. |
