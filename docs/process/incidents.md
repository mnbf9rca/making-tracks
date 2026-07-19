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
