# iOS Gate Ledger

This ledger records iOS gate count-watch decisions that affect whether a run counts, resets, or consumes the infra budget.

## Classification Rule

A red run is infra only when all of the following hold:

- Every failure is an XCUITest harness operation, such as a snapshot-query timeout or app launch/terminate failure, with no app assertion failure.
- Non-UI suites are green.
- There is positive environmental evidence: a prior green on a byte-identical tree and/or a duration materially above that tree's established baseline.

Absent positive environmental evidence, a harness timeout is a real red. Infra classifications consume a rerun budget; if infra-classified reds exceed the budget for the rolling window, the gate is not ready to be authoritative and the response is to reduce harness sensitivity.

## Entries

| Run | Attempt | Ref | Head | Result | Classification | Evidence | Action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 29933454122 | 1 | ios | c6e0285444dbe0df8c41ecda1e050ffd1c6eb238 | failure | infra | Host/unit suites passed 154/154. UI suite ran 48 tests with 2 harness failures: `testCardVisitStateSuppressesNearbyPromptWithoutViewportRefresh` timed out evaluating a UI snapshot query, and `testCoverageEdgeScreenshotsAcrossThemes` failed in app termination. No app assertion failure. Release-gate step ran from 2026-07-22T15:28:25Z to 2026-07-22T16:34:18Z, about 65m53s, materially above the two green baselines on equivalent content at about 39m. | Rerun once; neither counts nor resets. |
