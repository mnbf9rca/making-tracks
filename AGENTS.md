# Agent instructions — Making Tracks (`ios` branch)

**Two files exist because app work never checks out `develop`.** iOS branches are cut from `ios`, so
`develop`'s tree — and the agent law in it — is not on disk here. This file exists to point at that law and
to carry the few iOS-specific deltas. It is not a second copy; a delta below takes precedence only where it
explicitly differs.

**The law is `develop`'s `AGENTS.md`.** Read it first:

```bash
git fetch origin develop && git show origin/develop:AGENTS.md
```

All of it applies on this branch: grounding, hard rules, secrets, workflow, authoring law, reporting and
labels, worktree discipline, the iOS Simulator runbook, disk hygiene, the review gates, and the
finishing-a-branch checklist.

**The docs it links to are not all on this branch.** `docs/process/`, `docs/INFRA.md`,
`docs/threat-model.md` and `docs/architecture/` live on `develop` and have not been merged here. Read them
the same way — `git show origin/develop:<path>` — rather than assuming a missing file means a missing rule.

## What differs on `ios`

The app-specific facts an agent needs are stated in `develop`'s file, in these sections:

- **Workflow** → the iOS branch paragraph: anything under `ios/` branches from a freshly-fetched `ios` and
  PRs into `ios`, never `develop`. Same gates, same labels.
- **Workflow** → *Ground in the current tree*: ground app-code citations against `ios`. `develop` carries a
  lagging copy of `ios/`, so a `file:line` grounded against `develop` points at code that is not here.
- **Review gates**, point 3: run the Release build and simulator test gate as
  `./scripts/sim-lock.sh --seat codexN ./scripts/release-gate.sh`, replacing `codexN` with the assigned
  seat. Warnings-as-errors is set on the app target in
  `ios/App/project.yml`, which lives on this branch.
- **iOS simulator** and `docs/process/ios-simulator.md`: their single `agent-ios-tests` identity, retired
  global lock, and commands containing its hardcoded UDID are superseded on this branch by *The simulators
  have one entry point* below and the seat table in `docs/ios-gate-ledger.md`. Their unaffected simulator
  safety and disk-hygiene rules still apply. The inherited weekly-cleanup procedure is also superseded;
  fleet-wide maintenance uses the exclusive protocol in the iOS gate ledger. The iOS reusable seat
  DerivedData root is `$HOME/Library/Caches/making-tracks-gates/<seat>`; a root that canonically resolves
  under `/tmp`, `/private/tmp`, `/var/tmp`, or macOS's per-user temporary `.../T/` tree is refused because
  of #612. Result bundles retain the inherited temporary-storage cleanup rule. Stable coordination lock
  files live under `$HOME/Library/Application Support/making-tracks-gates/locks`, outside automatic
  temporary and cache cleanup jurisdictions; never delete, replace, or relocate one as recovery.

## CI on this branch

`.github/workflows/ios-gate.yml` runs the build and unit tests on every PR; the UI shards run only on
`workflow_dispatch`. The check name `ios-release-gate` therefore means different things per trigger — the
mapping, the count and classification rules, and the run ledger are in
[`docs/ios-gate-ledger.md`](docs/ios-gate-ledger.md), which lives only on this branch. CI never replaces
the host gate.

## The simulators have one entry point

`scripts/sim-lock.sh` is the only thing that touches a gate simulator. Build, test, boot, shutdown, erase,
delete — all of it goes through the script. Each builder passes its assigned logical seat from
[`docs/ios-gate-ledger.md`](docs/ios-gate-ledger.md) → *Host Gate Seats*. The wrapper resolves the current
destination; callers never copy or export its UDID.

For target-taking `xcrun simctl` commands, omit the simulator argument as well: the wrapper inserts the
assigned seat's UUID after the verb. `simctl list` remains targetless.

```bash
./scripts/sim-lock.sh --seat codexN <command> # run under the assigned lock
./scripts/sim-lock.sh --seat codexN --status  # HELD or FREE, checked two ways
./scripts/sim-lock.sh --seat codexN --erase   # destructive ops, under the lock
```

The script takes a stable per-simulator lock derived from the destination UDID, so two gates aimed at the
same simulator serialize. A stable global counting semaphore caps aggregate gate concurrency at
`MT_GATE_MAX_CONCURRENT` (default `2`); different simulators may run together only within that cap. The
host ceiling is `3`; callers may select `1`, `2`, or `3` but cannot exceed it. The evidence and ruling
provenance for this ceiling are recorded in [`docs/ios-gate-ledger.md`](docs/ios-gate-ledger.md) →
*Host Concurrency Ceiling Evidence (#600)*.
Cap `1` takes an exclusive admission lock, so it waits for all ordinary gates and prevents new ones; use
it for fleet-wide maintenance.
`MT_SIM_LOCK_WAIT` is a per-stage timeout for the simulator lock, admission policy, and global slot; a
command blocked at all three stages can therefore wait up to three times that value.

**Never read a lock file by hand to decide whether a simulator is free.** The file tells you who holds one
inode, not who is using the simulator, and those differ. `--status` checks both and reports HELD if either
fires; it fails closed if the process table cannot be inspected. A bare `lsof` on a lock can report FREE
while a build is mid-flight without it. This applies to coordinators as much as builders. Running
`simctl erase` because the lock looked free is the incident this exists to prevent (incidents → *A
hand-checked lock erased a running gate*).

`scripts/release-gate.sh` no longer takes the lock and refuses local runs outside
`sim-lock.sh --seat codexN`. Two lock-takers is how the paths drifted apart.

The wrapper's lock descriptors intentionally pass to every descendant. If `--status` still names a holder
after the wrapper exits, a surviving background descendant owns the locks: stop that process before
retrying, and never delete or replace a lock file as recovery.

## Adding to this file

Only a genuine `ios`-specific delta belongs here — a rule that is true on this branch and false on
`develop`. Everything else goes in `develop`'s `AGENTS.md` and reaches this branch by inheritance.

Do not restate a rule from `develop`'s file. Two copies of a rule means one of them is silently wrong. This
file's previous incarnation was a partial copy that had drifted: it had lost disk hygiene, the
finishing-a-branch checklist, the authoring law, and the threat-model hook. What drift costs is recorded in
`develop`'s `docs/process/incidents.md` → *Stale law disabled two gates*.
