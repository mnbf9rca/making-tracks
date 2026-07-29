# iOS Gate Ledger

This ledger records iOS gate count-watch decisions that affect whether a run counts, resets, or consumes the infra budget.

## Host Gate Seats

Every builder seat has one gate simulator. The seat exports the literal destination below as
`MT_RELEASE_GATE_DESTINATION` before any `scripts/sim-lock.sh` or `scripts/release-gate.sh` invocation.
`sim-lock.sh` derives a stable per-simulator lock from its UDID. Different simulators may run concurrently,
but the global counting semaphore admits at most `MT_GATE_MAX_CONCURRENT` gates at once. The default and
host-wide ceiling are `2`; operators may lower the setting to `1`, but callers cannot enlarge it.

| Seat | Simulator | `MT_RELEASE_GATE_DESTINATION` |
| --- | --- | --- |
| `codex1` | `mt-gate-codex1` | `platform=iOS Simulator,id=8749271C-95FD-4270-A754-401F77E7AEB6` |
| `codex2` | `mt-gate-codex2` | `platform=iOS Simulator,id=BACC2CF8-C1F8-4C92-B058-47B0AC0B128D` |
| `codex3` | `mt-gate-codex3` | `platform=iOS Simulator,id=AC60FA71-9449-4F15-A259-5E4A3E832839` |
| `codex4` | `mt-gate-codex4` | `platform=iOS Simulator,id=42D1482C-DE04-49AA-990D-1884ED9B855D` |

Lock files are stable `/private/tmp` files and are never deleted or replaced. Same-simulator serialization
and the global cap are separate gates: acquiring one never substitutes for the other.

### Fleet-exclusive maintenance

`MT_GATE_MAX_CONCURRENT=1` takes an exclusive policy lock. It waits for every ordinary cap-2 gate to exit,
and ordinary gates cannot enter until the maintenance command finishes. This supersedes the single-fleet-
lock weekly-cleanup claim in `develop`'s simulator runbook.

Export one seat destination from the table, then wrap each maintenance operation through the same entry
point. Do not embed a different or retired UDID inside a nested shell command.

```bash
MT_GATE_MAX_CONCURRENT=1 ./scripts/sim-lock.sh xcrun simctl --set testing delete all
```

## Classification Rule

A red run is infra only when all of the following hold:

1. Every failure is a harness operation, such as a snapshot-query timeout or app launch/terminate failure, with no app assertion failure.
2. Non-UI is green.
3. There is positive environmental evidence: prior green on byte-identical tree and/or duration materially above the tree's established baseline.

Absent condition 3, a harness timeout is a real red. Infra classifications are budgeted and auditable. The budget is at most 1 infra-classified red per rolling window of 5 runs. If infra-classified reds exceed that budget, the gate is not ready to be authoritative and the response is to reduce harness sensitivity.

Each entry records gate duration and the runner benchmark score (`runner_benchmark_ops_per_sec`) so classifications can be checked against measured runner performance rather than duration alone. Use `not measured` only for legacy runs whose workflow did not emit the runner benchmark.

## Count Rules

1. A run counts toward the flip only when it is green on the full UI-shard fan-in — the
   `workflow_dispatch` meaning of `ios-release-gate` (see Check Name Mapping) — on a tree that matches a
   green local gate.
2. Flip criterion: 2 consecutive counting greens. Rob pre-authorized the flip at that point (2026-07-22):
   make `ios-release-gate` a required check, and amend the law so CI is the merge authority with local
   full gates optional.
3. A real red resets the count to zero. An infra-classified red neither counts nor resets, and consumes
   the infra budget above.
4. Status: the flip is parked pending the runner-capacity decision (self-hosted runner on real hardware).
   Entries continue to be recorded while parked.

## Check Name Mapping

After the sharded gate change, `ios-release-gate` has two trigger-dependent meanings. On `pull_request`, it is the per-PR build+unit fan-in and the UI shards are expected to be skipped. On `workflow_dispatch`, it is the full UI-shard fan-in and also validates executed UI coverage against the built test enumeration. The parked flip plan must pin the meaning, not just the check name.

## Entries

| Run | Attempt | Ref | Head | Duration | Runner Score | Result | Classification | Evidence | Action |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 29933454122 | 1 | ios | c6e0285444dbe0df8c41ecda1e050ffd1c6eb238 | 65m53s | not measured | failure | infra | Host/unit suites passed 154/154. UI suite ran 48 tests with 2 harness failures: `testCardVisitStateSuppressesNearbyPromptWithoutViewportRefresh` timed out evaluating a UI snapshot query, and `testCoverageEdgeScreenshotsAcrossThemes` failed in app termination. No app assertion failure. Duration was materially above the two green baselines on equivalent content at about 39m. | Rerun once; neither counts nor resets. |
| 29952317663 | 1 | wp-ios-gate-shards | f241c6a1225ceef34283e3eb879f715915463a9f | 43m57s | not emitted by sharded workflow | failure | real | Build-once sharding plumbing ran: one build job passed, unit shard passed, all three UI shards executed and uploaded artifacts, and fan-in failed closed on the red matrix. UI shards contained app assertion failures: `testPinSizeSliderUpdatesLiveMapLayers` missed the 160% slider value and `testTrackReplaySliderAndAutoplayDriveMapPins` observed Play instead of Pause. `vm_stat` confirmed steady-state pressure: each shard reached near-monolith compressor pressure while running about one third of the UI tests. | Count resets to zero. Runner-capacity work is parked pending the self-hosted-runner decision; app assertion failures route as product bugs. |
