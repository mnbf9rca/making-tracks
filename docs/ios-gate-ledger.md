# iOS Gate Ledger

This ledger records iOS gate count-watch decisions that affect whether a run counts, resets, or consumes the infra budget.

## Host Gate Seats

Every builder seat has one gate simulator. Callers pass the stable logical seat to
`scripts/sim-lock.sh --seat codexN`; the wrapper resolves the destination by reading this table. The
planner updates only the affected row when a simulator is replaced. Callers never copy or export the
destination UDID.

`sim-lock.sh` derives a stable per-simulator lock from the resolved UDID. Different simulators may run
concurrently, but the global counting semaphore admits at most `MT_GATE_MAX_CONCURRENT` gates at once.
The default is `2` and the host-wide ceiling is `3`; operators may select `1`, `2`, or `3`, but callers
cannot exceed the ceiling. GitHub Actions creates ephemeral simulators outside this seat table and supplies its
destination and explicit non-temporary DerivedData override through the Actions-only release-gate path.

| Seat | Simulator | Destination |
| --- | --- | --- |
| `codex1` | `mt-gate-codex1` | `platform=iOS Simulator,id=8749271C-95FD-4270-A754-401F77E7AEB6` |
| `codex2` | `mt-gate-codex2` | `platform=iOS Simulator,id=BACC2CF8-C1F8-4C92-B058-47B0AC0B128D` |
| `codex3` | `mt-gate-codex3` | `platform=iOS Simulator,id=AC60FA71-9449-4F15-A259-5E4A3E832839` |
| `codex4` | `mt-gate-codex4` | `platform=iOS Simulator,id=42D1482C-DE04-49AA-990D-1884ED9B855D` |

## Per-seat DerivedData roots

| Seat | Cache-root DerivedData |
| --- | --- |
| `codex1` | `$HOME/Library/Caches/making-tracks-gates/codex1` |
| `codex2` | `$HOME/Library/Caches/making-tracks-gates/codex2` |
| `codex3` | `$HOME/Library/Caches/making-tracks-gates/codex3` |
| `codex4` | `$HOME/Library/Caches/making-tracks-gates/codex4` |

DerivedData never belongs under `/tmp`, `/private/tmp`, `/var/tmp`, or macOS's per-user temporary
`/private/var/folders/*/T/` trees; #612 guards both entry points before Xcode runs.

### Local result-artifact retention

App Store `.xcarchive` retention is governed by [`docs/app-store-release.md`](app-store-release.md).
Those archives live in caller-owned Application Support and private R2, never carry release-gate
markers, and are never eligible for the gate's 24-hour pruning.

Default local `full`, `test`, and `enumerate` runs place their artifacts in unique owned directories below
`/private/tmp/release-gate-<validated simulator UUID>/runs/`. The gate writes an ownership marker before
Xcode and a success marker only after every requested phase succeeds. A later successful, fully default
`full` gate for the same simulator may remove a marked owned success only when its success marker is
strictly older than 24 hours (`age > 86400` seconds). The cleanup examines canonical direct children with
exact run names and exact ownership identities; it does not scan another simulator root or use a wildcard
as a deletion target.

Failed and interrupted runs have no success marker and are never deleted by the gate. Local paths named
through `MT_RELEASE_GATE_RUN_DIR`, `MT_RELEASE_GATE_RESULT_BUNDLE`, or another artifact override are
caller-owned and remain outside automatic cleanup. GitHub Actions keeps its existing explicit artifact
replacement and upload lifecycle.

If a caller override resolves inside a previously owned run, the gate writes `.release-gate-preserve`
before Xcode; that marker permanently disqualifies the whole containing run from cleanup. Eligible
successes are moved to a unique quarantine pathname and their device/inode, boundary, markers, and age
are revalidated there before deletion. A mismatch or deletion failure is preserved and warned, never
treated as cleanup success.

Failure evidence is temporary even though the gate preserves it. The macOS `com.apple.tmp_cleaner`
service can remove files beneath `/private/tmp` after their access, modification, and change times are all
older than roughly three days. Operators therefore extract or copy needed evidence within that OS window
to `$HOME/Library/Application Support/making-tracks-gates/evidence/<issue>`; that deadline is an operator
SLA, not gate behavior. After extraction, manually delete only the exact released failure directory.
`~/Library/Caches` is suitable only for bounded transient holdings with a named cleanup trigger, not
durable evidence.

The 24-hour success window bounds accumulation from repeated result bundles recently measured at roughly
168–178 MiB each. Two old-machine ENOSPC incidents required manual Phase 1 sweeps; the durable incident
record quantifies one as roughly 35 GB of DerivedData and result-bundle litter filling the shared host.
The second incident has no retained byte measurement, so this ledger does not invent one.

Stable coordination files live under
`$HOME/Library/Application Support/making-tracks-gates/locks`, outside automatic temporary and cache
cleanup jurisdictions. That location is the lock-stability invariant: lock files are never deleted or
replaced. Opening an existing file for append and applying `flock` does not refresh its timestamps. Host
verification after a healthy 53-minute gate found the simulator, admission-policy, and occupied slot
inodes still carrying the same access/modify/change time from almost three days earlier. A `/tmp`
janitor could therefore unlink a normally held old inode and let a second acquirer flock a replacement;
gate duration provides no protection. Same-simulator serialization and the global cap are separate
gates: acquiring one never substitutes for the other.

Legacy `/private/tmp/making-tracks-*.lock` pathnames on this host are compatibility symlinks to those
Application Support targets. Pre-cutover and current wrappers therefore flock the same inodes; never
turn an alias back into a regular file. A lock-root transition on any replacement host requires a
planner-announced fleet-quiet window, proof that every old inode is unheld, and post-cutover proof that
each legacy pathname and target resolve to the same inode before wrapper operation resumes. Changing the
code default without that one-namespace cutover creates two independent lock fleets and is prohibited.

### Fleet-exclusive maintenance

`MT_GATE_MAX_CONCURRENT=1` takes an exclusive policy lock. It waits for every ordinary gate to exit,
and ordinary gates cannot enter until the maintenance command finishes. This supersedes the single-fleet-
lock weekly-cleanup claim in `develop`'s simulator runbook.
The admission lock does not promise fairness; run fleet-exclusive maintenance in a quiet window so a
steady stream of ordinary shared admissions cannot starve it until the timeout.

Choose the operator's assigned seat, then wrap each maintenance operation through the same entry point.
Do not embed a different or retired UDID inside a nested shell command.

```bash
MT_GATE_MAX_CONCURRENT=1 ./scripts/sim-lock.sh --seat codex1 xcrun simctl --set testing delete all
```

## Host Concurrency Ceiling Evidence (#600)

Issue #600 measured equal-cold full release gates on isolated simulators. The cap-3 first repetition ran
at signed head `95bc330f2ce50f0b179b0ee853a359f70def78a4` (iOS tree
`036da507de143493ca065a2372412d342c20949b`). The remaining repetitions ran at signed head
`a9dd8f4a71d3a337ebac42186b8dd9f85d38d3ba` (tree
`a59de7ec83ff6e4f8f031086ff79d36eb29df575`). The dominance rule retired the cap-2 cell after cap 3
qualified twice. The closeout ruling (planner decision AMQ ID
`2026-08-06T06-37-06.832Z_pid74852_fd027872`) accepted R2's current signed workload as the second
qualification even though the inventory had gained one UI test since R1; the 371/372 difference is
disclosed below. The capacity claim covers the full current suite rather than byte-identical workload
replay: #618's seam repair added 0.27% to the inventory, the same suite-change class the dominance
amendment accepted for cap-2 subsumption, and R2 qualified independently at the larger inventory. Carried
R1 is therefore the weaker member of the pair. Each repetition kept one equal workload
across all of its concurrent lanes, but the workload was not identical between R1 and R2. The issue-body
closeout remains planner-owned and occurs only after both ceiling-law PRs land.

| Cap | Rep | UTC date | Actual START epochs by seat | Max skew | Test counts by lane | Elapsed evidence by lane | Power endpoints | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 3 | R1 | 2026-08-05 | c3 `1785940725`; c2 `1785940740`; c1 `1785940742` | 17s | 3 × 371/371 | wrapper c1 3,276s; wrapper c2/c3 unavailable; xcresult intervals c1 3,155.866s, c2 3,195.307s, c3 3,156.159s | START preflight AC/100%; no authoritative per-lane END capture | qualified |
| 3 | R2 | 2026-08-06 | c2 `1785977409`; c1/c3 `1785977414` | 5s | 3 × 372/372 | c2 3,276s; c3 3,271s; c1 3,279s | START preflight AC/100%; no authoritative per-lane END capture | qualified; cap 3 = 2/2 |
| 4 | R1 | 2026-08-06 | c1/c3 `1785981607`; c2 `1785981608`; c4 `1785981610` | 3s | 4 × 372/372 | c2 3,424s; c1/c3 3,426s; c4 3,423s | START AC/100%; END uncaptured; power history records Battery from epoch `1785982861` | qualified with mixed-power caveat |
| 4 | R2 | 2026-08-06 | c2 `1785985922`; c1/c3/c4 `1785985926` | 4s | c1/c2/c4 372/372; c3 371/372 | c2 3,733s; c1/c3 3,729s; c4 3,728s | AC/73% charging → AC/75% charging | clean failure one |
| 4 | R3 | 2026-08-06 | c1 `1785990629`; c3 `1785990630`; c2 `1785990631`; c4 `1785990635` | 6s | c1/c3 372/372; c2/c4 371/372 | c1 3,847s; c3 3,846s; c2 3,845s; c4 3,841s | AC/78% charging → AC/55% charging | two failing lanes; stop rule fired |

Pressure telemetry was host-wide, so same-repetition lane samples converge except for snapshots taken a
few seconds apart. The runner's thermal probe reported no recorded thermal, performance, or CPU-power
warning at either endpoint for every repetition where it ran.

| Cap | Rep | Free-memory endpoints | Swap-in endpoints | One-minute load endpoints | Thermal record |
| --- | --- | --- | --- | --- | --- |
| 3 | R1 | captured samples: c1 54% → 50%; c2 52% → 50%; c3 consolidated sample unavailable | all lanes no increase | c1 7.15 → 9.24; c2 7.58 → 12.12; c3 3.41 → 7.43 | endpoint probe not retained |
| 3 | R2 | all lanes 59% → 48% | 18,301 → 18,305 | 2.53–2.56 → 7.77–8.07 | no warning recorded |
| 4 | R1 | all lanes 50% → 45–48% | 18,305 → 18,305 | 2.49 → 66.05 | no warning recorded |
| 4 | R2 | lanes 49–50% → 48% | 18,331 → 18,339 | 2.25 → 62.97 | no warning recorded |
| 4 | R3 | all lanes 52% → 48% | 18,347 → 18,351 | 2.25–2.31 → 87.61 | no warning recorded |

R1 remains a qualifying pass under the protocol that governed its launch: AC was a launch precondition,
and all four lanes started on AC. Power history later showed that the host switched to Battery at epoch
`1785982861`, so the final approximately 36 minutes ran on battery. Its elapsed values therefore carry a
mixed-power caveat. From R2 onward the measurement runner captured both endpoints and classified any
battery endpoint as environment-invalid.

The three clean cap-4 failure modes were distinct:

- R2, codex3: `testFixturePinTapUsesNamedPinAfterMapRepositionAtAX5` lost the named pin from the
  accessibility snapshot after its second drag. The full bundle is held transiently at
  `$HOME/Library/Caches/making-tracks-gates/evidence/issue-600-cap4-r2-codex3/`; its 2,320-file
  aggregate SHA-256 is `f571c24e0a34b48fe28410dc46f770ccdd7d1dc9622f974e485796019981f388`, and the
  four-file permanent failure export at
  `$HOME/Library/Application Support/making-tracks-gates/evidence/issue-600-cap4-r2-codex3/failure-evidence/`
  has aggregate
  `d53e66cb1bfe7d1138eec3e039d7b30e564cc729c2f916bc4223bab9dd344617`.
- R3, codex2: `testTrackReplaySliderAndAutoplayDriveMapPins` expected `Visit 2 of 6` after autoplay
  but observed the final `Visit 6 of 6`. The full bundle is held transiently at
  `$HOME/Library/Caches/making-tracks-gates/evidence/issue-600-cap4-r3-codex2/`; its 2,256-file
  aggregate SHA-256 is `5d39ff88f62b7e62f18711cae61225b17573449a04648aea34f5e582a76ab9a4`, and the
  one-file permanent failure export at
  `$HOME/Library/Application Support/making-tracks-gates/evidence/issue-600-cap4-r3-codex2/failure-evidence/`
  has aggregate
  `13bb3830ee8bb6bf1983b5ad4c872a2a22948ee65b78e37806f670e5936422d2`.
- R3, codex4: `testExploreSavedVisibilityFiltersOnlySavedDiscoveryPinsAndKeepsCategoryScope` tapped
  the hittable Show saved switch, but its value remained `0` instead of returning to `1`. The full bundle
  is held transiently at `$HOME/Library/Caches/making-tracks-gates/evidence/issue-600-cap4-r3-codex4/`; its
  2,324-file aggregate SHA-256 is `ae64ee48391633758f86b8a32d65433aceb271af04077eebfb5f947f1e240072`,
  and the two-file permanent failure export at
  `$HOME/Library/Application Support/making-tracks-gates/evidence/issue-600-cap4-r3-codex4/failure-evidence/`
  has aggregate
  `6142f0ebd0d0814d5135499ad5510f3313e017aa3cce448521d7b65cdee2cb6c`.

Each aggregate is reproducible independently inside the named `MakingTracksTests.xcresult` or
`failure-evidence` directory. It hashes the SHA-256 manifest in byte-sorted relative-path order:

```bash
find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256
```

Recomputing all three bundle/export pairs with that command produced all six recorded digests.
These three full bundles are the bounded failed-evidence exception to normal result hygiene. The planner
owns their cleanup trigger: after both ceiling-law PRs land, the planner closes #600 and deletes each
`MakingTracksTests.xcresult` from its transient cache directory. The non-purgeable Application Support
exports, aggregate digests and file counts remain as the permanent record.

The cap-4 physics independently supports the stop-rule result. Mean wrapper elapsed increased across
its three repetitions from 3,425s to 3,730s to 3,845s. During R3 the battery fell 23 percentage points,
from 78% to 55%, while macOS reported AC power and charging: four full gates drew more power than the
adapter delivered. End load averages reached 87–97. Cap 4 therefore sits outside this host's sustainable
power and scheduling envelope. Cap 3 qualified 2/2, cap 4 produced one passing and two failed
repetitions, and the evidence-based production ceiling is **3**. The default remains `2`; selecting `3`
is permitted, while `4` is rejected.

## Classification Rule

A red run is infra only when all of the following hold:

1. Every failure is a harness operation, such as a snapshot-query timeout or app launch/terminate failure, with no app assertion failure.
2. Non-UI is green.
3. There is positive environmental evidence: prior green on byte-identical tree and/or duration materially above the tree's established baseline.

Absent condition 3, a harness timeout is a real red. Infra classifications are budgeted and auditable. The budget is at most 1 infra-classified red per rolling window of 5 runs. If infra-classified reds exceed that budget, the gate is not ready to be authoritative and the response is to reduce harness sensitivity.

Each entry records gate duration and the runner benchmark score (`runner_benchmark_ops_per_sec`) so classifications can be checked against measured runner performance rather than duration alone. Use `not measured` only for legacy runs whose workflow did not emit the runner benchmark.

## Retired CI-Authority Count Rules

The historical experiment counted a run only when the full `workflow_dispatch` UI-shard fan-in was green
on a tree matching a green host gate. A real red reset the count; an infra-classified red neither counted
nor reset and consumed the classification budget above. Its proposed flip-at-2 criterion, CI-authority
change, optional-host-gate outcome, and self-hosted-runner path were retired without activation by Rob's
PR #403 ruling. These entries remain measurement history, not a standing authorization or merge rule.

## Suite Inventory

At `ios` head `79a8a19c2974e5f915796a4dc1449ee02e401f32` on 2026-08-06, the Xcode `MakingTracks`
scheme inventory was 372 tests: 251 app/unit and 121 UI. The distinct SwiftPM inventory executed by
`swift test` was 518 tests. `release-gate.sh` exercises the Xcode inventory only. These are grounded
snapshots, not timeless constants; refresh this section when either suite changes, and always report the
suite name with its count. Reproduce the Xcode snapshot from the per-suite summaries emitted by
`./scripts/sim-lock.sh --seat codexN ./scripts/release-gate.sh`; reproduce the SwiftPM snapshot with
`swift test` from `ios/`.

## Check Name Mapping

After the sharded gate change, `ios-release-gate` has two trigger-dependent meanings. On `pull_request`, it is the per-PR build+unit fan-in and the UI shards are expected to be skipped. On `workflow_dispatch`, it is the full UI-shard fan-in and also validates executed UI coverage against the built test enumeration. Any CI evidence claim must pin this trigger-dependent meaning, not just the check name.

## Entries

| Run | Attempt | Ref | Head | Duration | Runner Score | Result | Classification | Evidence | Action |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 29933454122 | 1 | ios | c6e0285444dbe0df8c41ecda1e050ffd1c6eb238 | 65m53s | not measured | failure | infra | Host/unit suites passed 154/154. UI suite ran 48 tests with 2 harness failures: `testCardVisitStateSuppressesNearbyPromptWithoutViewportRefresh` timed out evaluating a UI snapshot query, and `testCoverageEdgeScreenshotsAcrossThemes` failed in app termination. No app assertion failure. Duration was materially above the two green baselines on equivalent content at about 39m. | Rerun once; neither counts nor resets. |
| 29952317663 | 1 | wp-ios-gate-shards | f241c6a1225ceef34283e3eb879f715915463a9f | 43m57s | not emitted by sharded workflow | failure | real | Build-once sharding plumbing ran: one build job passed, unit shard passed, all three UI shards executed and uploaded artifacts, and fan-in failed closed on the red matrix. UI shards contained app assertion failures: `testPinSizeSliderUpdatesLiveMapLayers` missed the 160% slider value and `testTrackReplaySliderAndAutoplayDriveMapPins` observed Play instead of Pause. `vm_stat` confirmed steady-state pressure: each shard reached near-monolith compressor pressure while running about one third of the UI tests. | Count resets to zero. Runner-capacity work is parked pending the self-hosted-runner decision; app assertion failures route as product bugs. |
