# Release Gate Committed Resolution Design

Issue: #523

## Purpose

The mandatory iOS release gate must verify the dependency graph committed in
`ios/Package.resolved`. It must not silently select a newer compatible
dependency, bless a local lockfile edit, or leave the lockfile changed after a
passing run.

This design is deliberately narrower than #614. Issue #614 owns unifying the
standalone SwiftPM and Xcode dependency declarations, defining the intentional
lockfile-update workflow, and invalidating reusable DerivedData across
dependency-version transitions. Issue #523 changes only release-gate
verification.

## Current state

`ios/App/MakingTracks.xcodeproj` declares MapLibre from `6.27.0`.
`ios/Package.resolved` commits MapLibre `6.27.0` at revision
`84a79bc375a301169390ac110c868f06c857b83f` and GRDB `7.11.1` at revision
`b83108d10f42680d78f23fe4d4d80fc88dab3212`.

`scripts/release-gate.sh` invokes Xcode four ways:

- Release `build`
- Debug `build-for-testing`
- `test-without-building`
- test enumeration

None currently passes Xcode's committed-resolution enforcement flag. The gate
also neither rejects a lockfile that differs from `HEAD` at entry nor checks
the file after an Xcode phase.

Two disposable-clone probes against the installed Xcode establish the required
tool behavior:

1. `-onlyUsePackageVersionsFromResolvedFile` with the committed project and
   lockfile resolved MapLibre `6.27.0` at
   `84a79bc375a301169390ac110c868f06c857b83f` and GRDB `7.11.1`, exited
   successfully, and left `ios/Package.resolved` byte-identical.
2. Raising only the disposable project's MapLibre minimum to `6.28.0` while
   retaining the committed `6.27.0` lock made the same command exit `74`
   with Xcode's out-of-date-resolved-file refusal. The lockfile again remained
   byte-identical.

## Ruled behavior

The release gate verifies the committed graph, so a lockfile that differs from
`HEAD` at entry is already invalid gate input. The gate refuses it instead of
testing or restoring it. The refusal names `ios/Package.resolved` and gives
the two recovery choices: commit an intentional update, or restore the file
from `HEAD`.

An intentional dependency update is not a release-gate mode. It follows the
separate workflow owned by #614.

## Design

### Committed-resolution preflight

`scripts/release-gate.sh` owns one package-resolution path constant and one
central Xcode argument:

- lockfile: `ios/Package.resolved`
- Xcode argument: `-onlyUsePackageVersionsFromResolvedFile`

After repository and ancestry validation, but before artifact creation,
simulator boot, or Xcode, the gate requires the lockfile to:

1. exist as a regular non-symlink file;
2. be tracked by Git; and
3. be byte-identical to `HEAD`.

The gate records the file's SHA-256 digest and emits it as greppable provenance.
An absent, symlinked, untracked, staged, or unstaged replacement fails closed.

### Every Xcode phase uses the committed graph

The central Xcode argument is passed exactly once to every invocation routed
through `run_xcodebuild`. This covers Release build, Debug
build-for-testing, test-without-building, and enumeration without four
independent policy copies.

The flag tells Xcode that the versions in `Package.resolved` are the only
permitted versions. If a project requirement and the committed graph disagree,
Xcode fails rather than rewriting the lockfile or selecting another compatible
version.

### Post-phase invariant

`run_xcodebuild` captures Xcode's status, then checks the lockfile before
returning. The check runs after every Xcode invocation even when Xcode itself
failed. It requires both:

- the path remains byte-identical to `HEAD`; and
- its SHA-256 remains equal to the preflight digest.

If resolution drift occurred, the drift diagnostic wins and the wrapper
returns failure. If the invariant still holds, the wrapper preserves Xcode's
original status. The verifier never restores the file: it reports changed
state instead of concealing it.

CI already runs `scripts/release-gate.sh`, so the same invariant covers host
and CI gates without a second implementation.

## Error handling

All invalid input and drift cases fail closed with the exact lockfile path.
Dirty-at-entry diagnostics tell the operator to commit the intentional update
or restore from `HEAD`. Post-phase diagnostics state that Xcode changed the
committed resolution and that the gate refused the result.

A package-resolution failure must not create a successful result-artifact
marker. Existing failed-run retention remains unchanged.

## Host-test design

`scripts/sim-lock-tests.sh` remains the host regression seam. Its release-gate
fixture uses a disposable repository tree so deliberate lockfile mutations
never touch the builder's working tree.

The regression cases prove:

1. absent, symlinked, untracked, staged, and unstaged lockfiles refuse before
   simulator boot or Xcode;
2. all three full-mode Xcode calls and the enumeration call contain exactly one
   `-onlyUsePackageVersionsFromResolvedFile`;
3. a fake Xcode process that exits successfully after changing the fixture
   lockfile makes the gate fail immediately, prevents later Xcode phases, and
   never creates a success marker; and
4. a fake Xcode failure without drift preserves the original nonzero phase
   status.

The teeth checks are bidirectional:

- removing the central Xcode argument makes the logged-argument invariant fail;
- removing the post-phase check makes the successful-mutator case pass
  incorrectly.

The existing controller harness baseline is `126 passed, 0 failed`.

## Verification

After implementation:

1. run the complete controller harness;
2. run Bash syntax, ShellCheck, agent-law lint, and diff checks;
3. prove both mutations turn the intended regression red and restore the
   production sources;
4. obtain independent adversarial review of the exact signed head; and
5. run one fresh codex1 host release gate with
   `MT_GATE_MAX_CONCURRENT=3`, recording package-resolution provenance,
   Release/build-for-testing status, exact test counts, artifact lifecycle, and
   final seat status.

The change does not alter app behavior or dependency declarations, so it needs
no mockups and makes no product taste call.
