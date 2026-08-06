# Release-gate Package.resolved fixture repair

## Problem and root cause

PR #627 correctly made `scripts/release-gate.sh` refuse a checkout whose tracked
`ios/Package.resolved` differs from `HEAD`. The disposable repositories built by
`pipeline/tests/test_release_gate_script.py::_init_repo` predate that invariant: they commit a fake
Xcode project but never create `ios/Package.resolved`. Fourteen successful-path tests therefore stop at
the new entry guard rather than exercising their intended gate behavior.

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

## Rejected alternatives

- A test-mode bypass in `release-gate.sh` would weaken the exact production invariant under test and let
  stale fixtures accumulate more hidden prerequisites.
- Excluding `test_release_gate_script.py` from the baseline would turn a caused regression into permanent
  noise.
- Applying a process-wide Git override only in the invoking shell would leave the fixture non-hermetic for
  CI, other agents, and direct pytest runs.

## Verification and scope

The existing successful-path cases are the behavioral regression: before the repair they fail at the
package-resolution guard; afterward they reach and assert their original build/test/result behavior.
Run the full pipeline suite without external Git config overrides and require the 695-passed class plus
the existing live-provider skip. Run the focused release-gate Python file, `git diff --check`, and agent-law
lint. Review only the fixture and its test semantics. No simulator gate is required unless repository law
or historical evidence shows test-only release-gate harness changes have used one.
