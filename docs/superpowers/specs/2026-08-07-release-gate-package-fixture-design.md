# Release-gate Package.resolved fixture repair

## Problem and root cause

PR #627 correctly made `scripts/release-gate.sh` refuse a checkout whose tracked
`ios/Package.resolved` differs from `HEAD`. The disposable repositories built by
`pipeline/tests/test_release_gate_script.py::_init_repo` predate that invariant: they commit a fake
Xcode project but never create `ios/Package.resolved`. Fourteen successful-path tests therefore stop at
the new entry guard rather than exercising their intended gate behavior.

Once that guard is satisfied, four previously masked stale assumptions remain:

- the fake Xcode executable recognizes a controlled `test-without-building` failure only when the action
  is the first argument, but #523 correctly prepends `-disableAutomaticPackageResolution`;
- the full/build/test-mode assertions likewise assume each Xcode action is the first logged argument;
- the general build/test sequencing case seeds an existing caller-owned result bundle and expects the
  gate to delete it, but #546 correctly made caller-owned artifacts preserve-and-refuse inputs.

The fixture also inherits the host's `commit.gpgsign` setting. On a host whose signing key is provided by
1Password, temporary-repository commits fail when that agent is unavailable. A hermetic test fixture must
not depend on the operator's signing configuration.

## Approved repair

The fixture writes and commits a minimal valid SwiftPM v3 resolution document at
`ios/Package.resolved` in every branch shape it creates. Its local repository config sets
`commit.gpgsign=false` before the first disposable commit. These are test-fixture inputs only; production
repository commits remain signed and the release gate's package-resolution check is unchanged.

The minimal resolution contains `version: 3`, an empty `pins` array, and a fixed 64-character lowercase
hexadecimal `originHash`. The gate needs a real regular tracked file matching `HEAD`; using a structurally
valid SwiftPM document also keeps the fixture honest if a later test invokes package tooling.

For the normal `ios`-derived branch, the resolution is present in the base commit inherited by `work`.
For the deliberately unrelated orphan branch, the fixture writes and commits the same resolution so the
test reaches the ancestry guard it is designed to exercise rather than failing on an incidental missing
file.

The fake Xcode executable scans its complete space-delimited argument vector for the exact
`test-without-building` token before applying the controlled failure. Tests parse each logged Xcode
invocation into tokens and assert action presence and ordering without assuming an action occupies argv
position zero. The full ordered argument log remains intact for flag and destination assertions.

The general sequencing test no longer creates or expects deletion of an existing caller-owned result.
Dedicated tests continue to cover result preservation after success, after failure, and at an explicitly
named caller-owned path. Removing the dead deletion premise restores current ownership law without losing
lifecycle coverage.

## Rejected alternatives

- A test-mode bypass in `release-gate.sh` would weaken the exact production invariant under test and let
  stale fixtures accumulate more hidden prerequisites.
- Excluding `test_release_gate_script.py` from the baseline would turn a caused regression into permanent
  noise.
- Applying a process-wide Git override only in the invoking shell would leave the fixture non-hermetic for
  CI, other agents, and direct pytest runs.
- Restoring argv-zero assumptions by moving the package-resolution flag in production would couple command
  semantics to a test double and weaken #523.
- Teaching the sequencing case to delete its caller-owned fixture would reintroduce the destructive
  behavior #546 removed.

## Verification and scope

The existing successful-path cases are the behavioral regression: before the repair they fail at the
signing and package-resolution boundaries; after those repairs, the four masked cases fail at their stale
argv/result-ownership premises. The complete repair must pass all 26 focused release-gate tests. Run the
full pipeline suite without external Git config overrides and require 695 passed plus the existing single
live-provider skip (696 collected total). Run `git diff --check` and agent-law lint. Review only the fixture
and its test semantics. No simulator gate is required unless repository law or historical evidence shows
test-only release-gate harness changes have used one.
