# Simulator Seat CLI Design

## Context

Gate commands currently select a simulator through an inline
`MT_RELEASE_GATE_DESTINATION` assignment. The assignment changes whenever a simulator is rebuilt and
prevents command-prefix policy from recognizing an otherwise routine invocation. Agents therefore send
the same safe gate shape to the autoclassifier repeatedly.

The host gate already has four stable logical seats in `docs/ios-gate-ledger.md`. The simulator names and
UDIDs behind those seats are operational state; the seat names are the public interface.

## Decision

`scripts/sim-lock.sh` takes a required logical seat before the wrapped command:

```bash
./scripts/sim-lock.sh --seat codex4 xcodebuild test -project ios/App/MakingTracks.xcodeproj -scheme MakingTracks
./scripts/sim-lock.sh --seat codex4 ./scripts/release-gate.sh
./scripts/sim-lock.sh --seat codex4 --status
```

The accepted public seat values are `codex1`, `codex2`, `codex3`, and `codex4`. The fixed argument order
lets command policy match the wrapper, the bounded seat set, and the allowed operation without approving
arbitrary commands.

The Host Gate Seats table in `docs/ios-gate-ledger.md` remains the only seat-to-destination registry.
`sim-lock.sh` reads the selected row directly and fails closed if the row is missing, duplicated, or
malformed. Simulator replacement changes only that table.

There is no compatibility path for callers that set `MT_RELEASE_GATE_DESTINATION`. Fleet rollout is a
coordinated contract replacement: merge, pull into every agent harness, and resume only when the planner
opens the window.

## Command behavior

The wrapper resolves the seat before acquiring locks. It derives the lock identity from the selected
destination's UDID exactly as it does today.

For an `xcodebuild` command, the wrapper adds `-destination <resolved destination>` when the caller omits
it. If the caller supplies `-destination`, it must exactly match the selected seat. This removes volatile
UDIDs from the routine agent command while preserving the existing mismatch guard.

For `release-gate.sh`, the wrapper passes the resolved destination across the private lock boundary as
`MT_SIM_LOCK_DESTINATION`. The release gate accepts only that wrapper-owned value and continues to verify
`MT_SIM_LOCK` and `MT_SIM_LOCK_UDID`. It cannot be invoked through the removed public destination
contract.

GitHub Actions is deliberately separate: it creates an ephemeral simulator and invokes the release gate
with the existing Actions-only skip-lock authority. That path uses `MT_RELEASE_GATE_CI_DESTINATION`, which
is read only when both `GITHUB_ACTIONS=true` and `MT_RELEASE_GATE_SKIP_LOCK=1`. Local runs cannot use the CI
variable to bypass seat selection.

For allowed target-taking `simctl` verbs, the wrapper inserts the selected seat UUID immediately after
the verb. Callers omit the positional simulator target; supplying a UUID, `booted`, or `all` there is
rejected. Device-less `simctl list` keeps its existing arguments. This makes the positional target and the
acquired lock one decision rather than two caller-controlled values.

Unrecognized direct `simctl` verbs pass through unchanged, so the enumerated injection list must remain
exhaustive for every verb whose first operand is a device target. Adding such a verb requires matching
injection and explicit-target rejection tests. Commands using an explicit `simctl --set` select a separate
simulator set and remain outside seat-target injection.

Resolved destination identifiers must have CoreSimulator UUID shape. Fleet selectors such as `all` and
`booted` can never become a seat lock identity, even if the ledger is malformed.

## Policy

Project command policy matches these exact prefixes:

- `sim-lock.sh --seat <bounded seat> xcodebuild`
- `sim-lock.sh --seat <bounded seat> ./scripts/release-gate.sh`
- `sim-lock.sh --seat <bounded seat> xcrun simctl <bounded operation>`
- `sim-lock.sh --seat <bounded seat> <bounded wrapper operation>`

The policy does not match an unknown seat, a missing seat, or an inline environment assignment. Fleet-wide
maintenance controls such as `MT_GATE_MAX_CONCURRENT=1` remain separately reviewed because they change
admission behavior rather than merely selecting an assigned simulator.

## Verification and rollout

Behavior tests cover seat parsing, fail-closed ledger errors, removal of the old caller contract,
xcodebuild injection and mismatch rejection, private release-gate propagation, and the isolated CI
destination path. Exec-policy checks cover accepted and rejected argv shapes.

The implementation can be reviewed and merged independently of the rollout window. No active harness is
switched until the planner confirms all in-flight gates are clear and calls the coordinated reload.
