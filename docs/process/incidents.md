# Incidents — why the rules exist

Dated record of defects that produced a standing rule. **This is the only place dated narrative belongs.**

`AGENTS.md` states rules timelessly. It never explains itself with a story. When a rule needs a "because
this happened", the story lands here and the rule cites the incident by name.

Rules that stop being true get fixed. Incidents never do — they are history, so they are safe to date.

Adding an entry: give it a stable anchor name, state what happened, name the rule it produced, and link
back to the rule's **section name** in `AGENTS.md` (never a line number — line numbers rot).

---

## Editor-open hangs the agent

**2026-07-18.** Three agent worktrees ran a git command that opens `EDITOR`. Rob's `EDITOR`/`VISUAL` are
set to VS Code `--wait`, so each one popped a `COMMIT_EDITMSG` window at him and blocked the agent until he
closed it.

Rule: `AGENTS.md` → **Workflow**, the never-invoke-interactive-git paragraph.

---

## Unbuilt behavior stated as current

**2026-07-17/18.** A night of design reviews repeatedly caught two failures in the same class: behavior that
did not exist yet written in the present tense, and bare deferrals ("plan to fix X", "TODO") that hid real
cross-package dependencies. Downstream work packages inherited both as fact.

Rule: `AGENTS.md` → **Authoring law (design docs and policy docs)**, the plan-language law.

---

## Disk exhaustion killed the simulator fleet

**2026-07-18.** Roughly 35 GB of derived-data and result-bundle litter filled the shared Mac's disk to 100%.
CoreSimulator died fleet-wide. Every "flaky simulator" failure that night was disk suffocation, not a flaky
test — a full disk masquerades as flakiness.

Rule: `AGENTS.md` → **Disk hygiene (mandatory)**, both laws.

---

## Poisoned simulator state looked like branch failures

**2026-07-19.** Several iOS branches saw batches of UI tests fail with `Test crashed with signal kill`.
The failures moved between tests, and isolated reruns alternated between accessibility snapshot errors and
signal kills. A clean `origin/ios` baseline reproduced the same failure on the designated simulator, while
the same baseline and same test passed on a freshly-created simulator of the same device type/runtime.

The actual kill signature was not an app crash, jetsam, or watchdog: no fresh `.ips` appeared, and simulator
unified logs showed `SIGTERM(15)` sent by `xcodebuild`. Erasing the single designated simulator under the
fleet lock restored the baseline repro and the blocked app gate.

The same response window exposed a second failure mode: two agents independently used the retired
`/tmp/agent-ios-sim.lock` path while the canonical `/private/tmp/making-tracks-ios-tests.lock` was empty.
That made the device appear free to any agent using the correct script. Muscle memory beat the written law;
the script and explicit lock-holder checks are the durable carrier.

Rule: `AGENTS.md` → **iOS simulator**, and `docs/process/ios-simulator.md` → **Device poisoning**.

---

## Dead worktrees accumulated 25 G

**2026-07-18.** Merged branches' worktrees were left in `.worktrees/` for a later sweep. They reached 25 G on
the shared disk.

Rule: `AGENTS.md` → **Finishing a branch (the pre-PR checklist)**, the worktree-removal step, and **Worktree discipline**.

---

## Debug-only gate let a Release break through

**2026-07-18, PR #181.** A `#if DEBUG` fence with an incomplete `#else` compiled clean under Debug and broke
the Release compile. The Debug build and `swift test` do not exercise Release, and warnings-as-errors applies
to Release too, so the pre-PR gate passed on a broken build. The standing fix landed in PR #192.

Rule: `AGENTS.md` → **Review gates (mandatory before declaring anything complete)**, the builders' Release-configuration requirement.

---

## Three riders on one work package

**2026-07-19.** A status-honesty work package absorbed three follow-on findings before it reached review.
Rob asked where the line was. The threshold below is the answer.

Rule: `AGENTS.md` → **Workflow**, *Fold or file*.

---

## Lock misdiagnosed from the symptom

**Undated — recurring.** A transient 1Password agent fault under concurrent load
(`failed to fill whole buffer`) produces the same simultaneous ssh/push/signing failure as a locked Mac.
Agents asserted the lock without probing the socket and parked themselves for hours waiting for an unlock
that was not the cause.

Rule: `docs/INFRA.md` → **Do not diagnose a lock from the symptom alone**.

---

## Stale law disabled two gates

**2026-07-16/18, fixed in PR #223.** Two gates in `AGENTS.md` were found disabled by facts that were true
when written and later became false:

- A note reading "as of 2026-07-16 `flock` is not in PATH" was read as permission to run simulator work
  unlocked. `flock` is at `/opt/homebrew/bin/flock`.
- The mandated Release-build command carried unfilled `<scheme>` placeholders, so it could not be run as
  written.

Rule: this file, and `AGENTS.md` → **Amending this file**. Dated facts inside rule text are the failure mode
that produced the incidents/rule split.

## A chained commit reached the main checkout

**2026-07-19.** An agent ran `cd <worktree> && git add -A && git commit && git push && echo PUSHED` as one
command. The `git worktree add` before it had failed — the branch was already checked out elsewhere — so the
`cd` failed and the rest ran in the **main checkout**, on the `ios` branch, which is Rob's Xcode surface.

`git add -A` swept up two files that happened to be sitting untracked in that working tree: a
`.claude/settings.json` enabling a third-party plugin, and a regenerated `Package.resolved`. The plugin
setting would have been a supply-chain trust change travelling under a documentation commit message. The
push then failed non-fast-forward, and `echo PUSHED` printed anyway, so the agent reported success and moved
on.

Contained: the commit never reached a remote, a mixed reset restored the working tree byte-for-byte, and the
containment was independently verified before the checkout was fast-forwarded.

Three rules already existed and all three were broken by one command: never commit in the main checkout,
never chain an irreversible action past a check, and verify from the artifact rather than the step before it.
The agent had re-stated the second of those in the same pull request it was writing at the time.

→ *A mutation is a bare single call* (Workflow); *Worktree discipline* (Workflow).

## A hand-checked lock erased a running gate

**2026-07-20.** A coordinator checked the simulator lock file by hand to see whether the designated device
was free. The check reported idle, so the simulator was erased. A gate was running against it at the time
and lost its device mid-run.

The reading was not wrong about the lock. It was wrong about the question. The holder was working through
the retired lock path, so nothing appeared against the canonical file — and a lock file records who holds
the lock, not who is using the simulator. Those are different facts and only one of them was being checked.

This was the fourth failure in the same family. Three earlier regressions came from the lock path itself
splitting between a canonical and a retired name; this one came from reading the surviving path correctly
and drawing the wrong conclusion.

The fix removes the hand-check rather than improving it: `scripts/sim-lock.sh` is the only thing that
touches the simulator, `--status` consults the process table as well as the lock, destructive operations
refuse when the device is in use, and the retired path is asserted as a symlink on every invocation so it
cannot silently split again after a reboot clears it.

The runbook had told agents to `lsof` the lock file when in doubt. That instruction is gone.

→ *iOS simulator* (AGENTS.md); *docs/process/ios-simulator.md*.
