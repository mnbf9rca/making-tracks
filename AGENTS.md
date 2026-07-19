# Agent instructions — Making Tracks (`ios` branch)

**Two files exist because app work never checks out `develop`.** iOS branches are cut from `ios`, so
`develop`'s tree — and the agent law in it — is not on disk here. This file exists to point at that law and
to carry the few iOS-specific deltas. It is not a second copy, and nothing here overrides it.

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
- **Review gates**, point 3: run `scripts/release-gate.sh` for the Release build and simulator test gate.
  Warnings-as-errors is set on the app target in `ios/App/project.yml`, which lives on this branch.

## Adding to this file

Only a genuine `ios`-specific delta belongs here — a rule that is true on this branch and false on
`develop`. Everything else goes in `develop`'s `AGENTS.md` and reaches this branch by inheritance.

Do not restate a rule from `develop`'s file. Two copies of a rule means one of them is silently wrong. This
file's previous incarnation was a partial copy that had drifted: it had lost disk hygiene, the
finishing-a-branch checklist, the authoring law, and the threat-model hook. What drift costs is recorded in
`develop`'s `docs/process/incidents.md` → *Stale law disabled two gates*.
