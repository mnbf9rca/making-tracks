# Agent instructions — Making Tracks

You are working on **Making Tracks** (making-tracks.app), an iOS map app for discovering interesting places — history, architecture, oddities — built from open data. The map is fresh snow; moving through the world marks it.

## Amending this file

Three constraints on anything written here. `scripts/lint_agent_law.py` runs in CI and catches the known bad shapes of the first and third — dates, narrative openers, line-number citations. It cannot tell narrative from rule, so a green lint means "no known bad shape", not "correct". The constraints bind you, not the linter.

1. **Rule text is timeless.** No dates, no `this morning`, no `as of`. A rule states what to do and why it is true, not what happened. Incident rationale goes in [`docs/process/incidents.md`](docs/process/incidents.md) and the rule cites it by name. A dated fact inside a rule eventually goes false, and a false fact reads as permission to skip the rule — see incidents → *Stale law disabled two gates*.
2. **One rule, one home.** Principles live in `docs/PRINCIPLES.md`. Operational law lives here. Cross-reference; never restate.
3. **Cross-references name a section**, never a line number. Line numbers rot on the next edit.

Every command in this file must be runnable as written — no placeholders you cannot fill.

## Grounding — read before doing anything

1. `docs/PRINCIPLES.md` — the project's non-negotiables. Every change is checked against these.
2. `docs/superpowers/specs/2026-07-14-making-tracks-design.md` — the approved design: architecture, data model, decisions and their rationale, work-package decomposition.
3. `brief.md` — the original product brief (context for *why*; the spec supersedes it where they differ).
4. The work-package design doc for your assigned WP (in `docs/superpowers/plans/` once written). Do not improvise scope beyond your WP.

## Repo layout

- `/pipeline` — Python data pipeline (extract → reconcile → score → categorize → publish). Plain CLI, laptop-first, deterministic, SQLite between stages, publishes static files to Cloudflare R2 (`tiles.making-tracks.app`).
- `/ios` — SwiftUI app. iOS 18+ minimum, Swift 6 language mode with strict concurrency. GRDB for user data. MapLibre Native + PMTiles for the map.
- `/contracts` — frozen cross-boundary schemas, fixtures and the `mt_contracts` package.
- `/docs` — principles, specs, plans, process.

## Hard rules

The non-negotiables are in [`docs/PRINCIPLES.md`](docs/PRINCIPLES.md) and that is their only home. Read it. Amending a principle is an argued amendment to that file, ratified by Rob — never an edit here.

The ones that bite most often, by their number there: `place_id` is forever (7), all source data is polluted until proven otherwise (10), everything crossing a boundary is versioned (11), the pipeline is deterministic (12), "interesting" is measured not asserted (13), privacy is structural (14–15). Beyond principle 15, any network write of user-derived data must also satisfy the unlinkability rules in the spec's §9. If a change could reassign or reformat shipped `place_id`s, stop and flag it rather than proceeding.

These operational rules are not in `PRINCIPLES.md` and live here:

- **Untrusted input, concretely.** Principle 10 states the posture; in practice it means validate schemas, bound sizes, sanitize strings, https-only URLs — and never interpolate source content unescaped into shell, SQL, or LLM prompts.
- **Determinism, concretely.** No wall-clock and no randomness in outputs, except via cached, versioned LLM calls.
- **Constants that shape output are earned, not baked.** A threshold, weight, or cap that affects output quality or behaviour is either swept by the eval harness or flagged tunable in a comment — never a silent magic number the next person fears to touch.
- **No silent long-running work.** Any process expected to run beyond ~30 seconds emits greppable progress: per-phase START/DONE lines with counts and durations, plus heartbeats (every ~10k records or 30s) with count/rate/elapsed. Detached runs always report their log path at launch. A human tailing the log must be able to answer "is it working and how far along?" at any moment.
- **Test-first, with teeth.** Where a behaviour can be expressed as a test, write it first; the ID-stability and reconciliation invariants must have regression tests. A test has teeth only if neutering the code it guards makes it fail — verify that. A test that stays green when the implementation is broken, or that exercises a value/path the product never actually produces, is a false green. The worked checklist is [`docs/process/gate-lessons.md`](docs/process/gate-lessons.md).

## Secrets

All secrets via 1Password: `op run --env-file=.env.tpl -- <command>` (masking stays ON; never `--no-masking`, never render secrets to disk). See [`docs/SECRETS.md`](docs/SECRETS.md). STANDING RULE: any compromised secret (logged, printed unmasked, read into context, committed) gets IMMEDIATELY appended to `TO-ROTATE.log` — reference/name + timestamp + vector, never the value. Logging an exposure is mandatory and blame-free. Access topology — ssh, commit signing, and where heavy work runs — is in [`docs/INFRA.md`](docs/INFRA.md).

## Workflow

Work packages (spec §8) are designed one at a time (design agent) and built one at a time (build agent) on feature branches. **All production code is written by build agents.** A design agent produces plans and never spawns a code-writing subagent; read-only research and review subagents are fine. fable coordinates, reviews and merges. Keep to your package's scope; if you discover a cross-package contract problem, surface it in your report rather than unilaterally changing the contract. Commit messages: imperative, plain, no attribution boilerplate.

**Fold or file.** A new finding may be folded into an in-flight work package only if all of these hold:

- same surface and same owner;
- the WP is not yet in review;
- it introduces no design fork, no schema or contract change, and no new dependency;
- at most one addition has already been absorbed — a third means file it;
- it is recorded as an explicit scope addition in the PR body.

Otherwise file an issue first, then route it to its own PR if it is an urgent live bug, or to the next planned WP. Regardless of route, anything not fixed the same day gets a tracker issue — routing messages are not project memory. (Incidents → *Three riders on one work package*.)

Never invoke **interactive git**: always `git commit -m` (never a bare `commit`), `git commit --amend --no-edit`, and never `rebase -i`. Rob's environment has `EDITOR`/`VISUAL` set to VS Code `--wait`, so any git command that opens an editor **pops a window at the human and hangs the agent** until he closes it (incidents → *Editor-open hangs the agent*). Export `GIT_EDITOR=true` defensively so any accidental editor-open returns immediately instead of blocking.

Branch discipline: feature branches (`wp-<id>-plan` / `wp-<id>-impl`) are cut from `develop` and PR back to `develop` — a PR is the only path onto `develop`; never push to it directly. `main` is human-gated — only Rob promotes `develop` to `main`. No agent self-merges its own PR; the design lead (fable) reviews, and merges happen only with human-sanctioned authority (overnight, PRs queue for Rob's morning review).

Push early, push often: an unpushed branch is invisible — indistinguishable from a dead agent — and unmergeable. Push a WIP commit within minutes of starting; force-with-lease later rather than staying local.

Promotions to `main` are merge commits (ruleset-enforced); squash is for feature PRs into `develop`/`ios` only.

iOS branch: app work (anything under `ios/`) branches from a freshly-fetched `ios` and PRs into `ios`, not `develop` — same gates. The long-lived `ios` branch lives in the main repo checkout as Rob's Xcode surface: never touch that working tree or switch its branch; Rob pulls when he chooses. fable merges `ios` ↔ `develop` at milestones. Pipeline/contracts/docs work targets `develop` as before.

Ground in the current tree: branch from a freshly-fetched target branch (`develop`, or `ios` for app work), and re-ground a long-lived doc — its `file:line` citations and its "not built yet" claims — against that same branch before the PR; with several agents merging, the tree moves under you. `develop`'s `ios/` tree lags `ios`, so a doc citing app code grounded against the wrong branch cites lines that do not exist. Where a brief and the code disagree, the code is authoritative — reconcile or flag it, never design around the discrepancy. **A mutation is a bare single call.** Never put `&&` between a mutation — commit, push, merge, resolve, `gh` write, file move — and anything else, least of all its own verification or a success echo. A failed step earlier in the chain does not stop the rest, and a trailing `echo DONE` prints whether or not the thing happened. Issue the mutation alone, then verify in the **next** call by reading the artifact back: the pushed file, the live issue body, the branch head. An exit code from a step before the one you care about proves nothing. (Incidents → *A chained commit reached the main checkout*.)

## Authoring law (design docs and policy docs)

**Plan-language law: a design doc contains NO unowned deferrals.** "Plan to fix X", "to be addressed later", "TODO", and any bare gesture at future work are banned — they hide dependencies and let designed-but-unbuilt behavior read as current. Every deferred item must be exactly one of: (a) a **scoped fix in this doc**; (b) a **named WP row** in the decomposition with an owner and its dependency; or (c) an **explicit Open Flag addressed to Rob**. Likewise, never state target/aspirational behavior in the present tense — mark it *target* with its owning WP, and mark what exists today against the tree. (Incidents → *Unbuilt behavior stated as current*.)

**A plan applies the principles; it never changes them.** A design doc must not assert a new privacy rule, policy, floor or threshold and cite an existing principle as if it sanctioned it — that launders a real change past review, and downstream work packages inherit a claim nothing ratified. `docs/PRINCIPLES.md` says so directly: *"the principle needs an explicit, argued amendment to this file — never a silent exception."* When a design needs something the principles do not cover, mark the section PENDING, surface the tension with options, and escalate to Rob via fable. Then apply what he rules.

**Policy-document law** (`privacy.md`, `docs/PRINCIPLES.md`, `docs/threat-model.md` and their kin): a policy doc states **commitments that constrain what future features may do**, not a snapshot of what the app does today. Write the ground rules that hold regardless of features, then what they mean for each known roadmap item — accounts, sharing, feedback — with the hard lines drawn now. A doc that only describes today is obsolete at the next feature. Never add a disclaimer demoting the document ("this isn't the real policy yet"); its authority is the whole point. Rob ratifies these before they land.

## Reporting, issues and labels

Blocked ≠ done reporting: a `gh`/connector 403 in an agent harness is a sandbox denial, not expired auth. Escalate the exact command in your harness or relay the exact operation (base/head/title/labels) to fable as an action request; never report blocked and wait. Relays confirm back: whoever unblocks an agent (PR opened for it, command run) confirms on the agent's thread — an agent that does not know it has been unblocked is still effectively blocked.

Issue-closing discipline: GitHub's `closes #N` keywords only fire on merges to the DEFAULT branch (`main`) — our PRs merge to `develop`, so they never auto-close anything. When a WP's implementation PR merges, the merger closes the issue explicitly (`gh issue close N --comment ...`) and ticks the tracker (#25) checkbox; never report an issue as closed without verifying its actual state (`gh issue view N`).

Keep the issue **body** current. When a decision is put to Rob, or a ruling lands, edit the body to reflect it (`gh issue edit N`) — Request / Status / Open questions. Comments carry point-in-time evidence: findings, measurements, test output. The body carries current state, and it is where Rob looks. Never let a work package's state accumulate only as a stack of appended comments.

Issue labels: a **track** label (`track-a-pipeline` / `track-b-ios` / `track-c-services`) plus a **type** label (`bug` / `enhancement` / `design` / `question`). `sourcery-review` and `greptile-review` are PR review triggers — never put them on an issue.

## Worktree discipline

**One git worktree per agent, always.** Never work in the repo root checkout and never switch its branch — multiple agents share this machine, and an uncommitted edit in a shared checkout gets stranded (or destroyed) when another agent switches branches. Start every assignment by setting up your isolated workspace — use the `superpowers:using-git-worktrees` skill if your harness has it (the project-standard mechanism), otherwise fall back per that skill's convention: `git worktree add .worktrees/<branch> -b <branch>` inside the repo (the `.worktrees/` directory is gitignored; verify with `git check-ignore .worktrees/` — the trailing slash matters, without it the check fails until the directory exists) — and do all work there. Do not create sibling directories outside the repo.

Removing the worktree is part of finishing the branch, not a later sweep — see **Finishing a branch**.

## iOS Simulator runbook (agents)

Host-only package tests do not use the simulator. For `/ios` Swift package work that is covered by host tests, run `cd ios && swift test` on the macOS host. These tests never touch CoreSimulator and must not take the fleet lock.

Simulator-backed `xcodebuild` runs are shared-machine resources and must use one designated simulator plus a file lock. The designated simulator is:

- Name: `agent-ios-tests`
- Device type: `iPhone 17`
- Runtime: `com.apple.CoreSimulator.SimRuntime.iOS-26-2`
- UDID: `C4A64D49-24A2-4429-B6E2-AD9A14142A99`
- Creation command: `xcrun simctl create agent-ios-tests "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-26-2`

Every `xcodebuild` invocation — **build OR test** — must hold `flock` on `/private/tmp/making-tracks-ios-tests.lock` around the whole boot-and-run sequence. This is **one fleet-wide lock**: it serializes all simulator-backed work across every agent (a Release-configuration build contends for the same simulator/`testmanagerd`/derived-data state as a test run, so builds take the lock too — not just tests). `swift test` (host package tests, no simulator) does not take it. `flock` is at `/opt/homebrew/bin/flock`. Two runs against one simulator collide in `testmanagerd` and app install state. Boot with `xcrun simctl bootstatus "$UDID" -b`; this is idempotent and blocking. Do not use `simctl boot` in agent scripts.

Use exactly one destination, by UDID, and disable parallel/concurrent destination testing:

```bash
flock /private/tmp/making-tracks-ios-tests.lock sh -ec '
  UDID=C4A64D49-24A2-4429-B6E2-AD9A14142A99
  xcrun simctl bootstatus "$UDID" -b
  xcodebuild \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme MakingTracks \
    -destination "platform=iOS Simulator,id=$UDID" \
    -parallel-testing-enabled NO \
    -disable-concurrent-destination-testing \
    test
'
```

The `/ios` Swift package still has host tests — run those with `cd ios && swift test`, no lock. Simulator-backed work uses the app project above (`ios/App/MakingTracks.xcodeproj`, scheme `MakingTracks`), from the repo root.

### Disk hygiene (mandatory)

Derived data and result bundles are the biggest disk producers on this shared host. A full disk kills CoreSimulator fleet-wide and every failure then looks like a flaky test (incidents → *Disk exhaustion killed the simulator fleet*). Two laws, both non-negotiable:

1. **One reusable derived-data path per agent — never per-run numbered dirs.** Point every `xcodebuild` run at a single stable path `-derivedDataPath /private/tmp/dd-<agent-name>` (e.g. `/private/tmp/dd-codex4`). Reusing one path lets each build overwrite the last; per-run paths (`dd-1`, `dd-run-2`, timestamped dirs) accumulate without bound.
2. **Delete result bundles after extracting counts.** If a run uses `-resultBundlePath <path>.xcresult`, parse the pass/fail counts you need, then `rm -rf` the bundle in the same script — never leave `.xcresult` bundles on disk between runs.

```bash
# Idiom: stable derived-data path + result bundle deleted after counts are read
DD=/private/tmp/dd-<agent-name>
RB=/private/tmp/<agent-name>.xcresult
rm -rf "$RB"
xcodebuild ... -derivedDataPath "$DD" -resultBundlePath "$RB" test
# ... extract counts from "$RB" ...
rm -rf "$RB"
```

Parallel testing and multi-destination runs are the normal paths that spawn simulator clones. The single-destination command above, with `-parallel-testing-enabled NO` and `-disable-concurrent-destination-testing`, is the required defense against clone creation. If a run leaks clones, they hide in XCTest's separate device set; inspect it with:

```bash
xcrun simctl --set testing list
```

Weekly simulator cleanup for agents also takes the fleet lock, so cleanup cannot race an active simulator run:

```bash
flock /private/tmp/making-tracks-ios-tests.lock sh -ec '
  xcrun simctl --set testing delete all
  xcrun simctl delete unavailable
  find ~/Library/Developer/Xcode/DerivedData -mindepth 1 -maxdepth 1 -type d -mtime +14 \
    \( -name "MakingTracks-*" -o -name "MakingTracksData-*" -o -name "agent-ios-tests-*" \) \
    -prune -print -exec rm -rf {} +
'
```

Never put `simctl delete all` or `simctl shutdown all` in shared scripts. Those commands destroy or disrupt other agents' and Rob's simulators. One simulator plus `flock` is the policy; add a simulator pool only if lock waits become a measured bottleneck.

## Review gates (mandatory before declaring anything complete)

Nothing is "done" on the author's say-so. **Every gate below is yours to execute on the host — do not assume CI runs it.** CI does not run the test suite; check `.github/workflows/` for what it does cover. A green PR is not a tested PR.

Before you declare a plan complete, open a PR, or report a build finished:

1. **Adversarial self-review by subagents.** If your harness can spawn subagents or workflows, you MUST run an adversarial review pass over your own output before declaring it complete: several independent critics with distinct lenses (spec fidelity; internal coherence; feasibility/correctness; security + untrusted-data posture per the spec's §5.5; test quality — do the tests actually pin the invariants?). Have findings cross-examined (a critic's claim must survive a genuine refutation attempt), fix what survives, and for every fix prove **teeth** — neutering the fix turns a test red — and include a short review summary (findings raised / survived / fixed) in your completion message. The worked checklist for that pass — how to prove teeth, the traps that produce green-but-wrong, and what to verify on bridged native code — is [`docs/process/gate-lessons.md`](docs/process/gate-lessons.md).
2. **No subagent capability?** Then request the review explicitly: message fable on AMQ (kind: review_request) with the artifact path and wait for the response before declaring completion.
3. **Builders additionally:** full test suite green is a precondition, not evidence of review. Paste the actual test output (counts, not adjectives) in the PR description. A PR whose description says "tests pass" without output is incomplete. One build requirement on top: **for iOS app-target work, a one-time RELEASE-configuration build before any PR** — the Debug build and `swift test` do not exercise Release, so a Debug-only gate lets a Release-only break through (incidents → *Debug-only gate let a Release break through*). Run it under the fleet lock:

   ```bash
   flock /private/tmp/making-tracks-ios-tests.lock sh -ec '
     UDID=C4A64D49-24A2-4429-B6E2-AD9A14142A99
     xcrun simctl bootstatus "$UDID" -b
     xcodebuild build \
       -configuration Release \
       -project ios/App/MakingTracks.xcodeproj \
       -scheme MakingTracks \
       -destination "platform=iOS Simulator,id=$UDID"
   '
   ```
4. **Zero new warnings, on any branch.** A clean build introduces no new warnings. A warning is a defect that has not been triggered yet. On the app target this is enforced — `ios/App/project.yml` (on the `ios` branch) sets warnings-as-errors, so a warning fails the Release build outright. Everywhere else it is on you.
5. **Automated review comments are part of the gate.** Sourcery reviews a PR only when the `sourcery-review` label is applied — apply it yourself the moment you open the PR (`gh pr edit <n> --add-label sourcery-review`); an unlabelled PR is silently skipped, and absence of comments then means nothing. Before a PR is merge-eligible, its author processes every review comment — use the `pr-tools:process-review` skill where available, otherwise apply the same discipline manually: triage each comment with technical rigor (verify against plan/spec — neither performative agreement nor reflexive dismissal), fix-and-reply or rebut-with-evidence, and resolve the thread. **Nothing merges with unresolved review comments — and the automated review can take time to arrive, so its absence is not cleanliness.** A PR is merge-eligible only after the automated reviewer has actually posted its review (check the PR's reviews list for it) AND every resulting thread is resolved.
6. **Greptile is explicit-spend only.** Greptile (`greptile-review` label) costs $1/review and is applied only on fable's explicit instruction: `develop`→`main` promotions, security-surface PRs, and escalations. Sourcery remains the default automated layer; never apply `greptile-review` by default.
7. **Independent review still happens — and your self-review is unconditional.** The adversarial self-review (point 1) does not replace the design lead's review, and the automated bots (Sourcery/Greptile) never substitute for it: run your own critic pass regardless of which bot layers are configured or whether their credit is available. Those layers raise the floor; they are not the floor.

**Threat-model discipline (the spec's §5.5 security-posture hook).** Every security or privacy review finding — whether from the adversarial self-review (point 1) or a human/bot reviewer — must **cite a specific in-scope vector from [`docs/threat-model.md`](docs/threat-model.md)**, or **explicitly propose an amendment to that model**. A finding that names no vector, or that assumes an out-of-scope adversary (a compromised/jailbroken device, physical seizure, a nation-state, our own infra turning hostile, enterprise-MITM), is **rejected as overreach** — do not action it, and say why. The threat model's calibration tests (its §5) are the screening rubric; apply them mechanically. **Untrusted-data / content-validation findings** (defensive parsing, size caps, `SAFE_TEXT`, plain-text rendering, URL allowlists, no unescaped SQL/shell/LLM interpolation) cite the **hostile-upstream-content vector** (threat-model §2 / the spec's §5.5 / PRINCIPLES 10) and are **always in scope** — never "overreach"; the overreach rule targets out-of-scope *adversaries*, not the handling of hostile content we publish. The model is not frozen: a genuine new vector is argued into `docs/threat-model.md` (ratified as project policy, like `privacy.md`), never smuggled in as a one-off review comment. This governs the "security + untrusted-data posture" lens in point 1.

The one standing exception: trivial mechanical changes (typo fixes, comment corrections) need tests green but not the adversarial pass. When unsure whether something is trivial, it isn't.

## Finishing a branch (the pre-PR checklist)

Before opening any PR, run this sequence top to bottom. Each step is stated in full in the section it names — this is the index, not a second copy. The irreversible-action rule (**Workflow**) applies throughout.

1. **Re-ground on a fresh target** (Workflow). `git fetch origin <target>` (`<target>` = `develop`, or `ios` for app work), then `git merge-base --is-ancestor origin/<target> HEAD` must succeed. If it fails, merge the fresh target in as its own step and re-run your gates.
2. **Adversarial gate** (Review gates, point 1). Record the accounting — raised / survived / fixed — for the PR description.
3. **Full test gate under the fleet lock** (iOS Simulator runbook). Capture actual pass/fail counts.
4. **Release-configuration build** for iOS app-target work, under the fleet lock (Review gates, point 3).
5. **Zero new warnings** (Review gates, point 4).
6. **Stale-base diff review.** `git diff --stat origin/<target>..HEAD` (two-dot) must show **only your additions**. Deletions or edits to other agents' merged work mean your base is stale and you are about to clobber it — stop and re-ground (step 1).
7. **Artifact cleanup** (Disk hygiene). No `.xcresult` bundles left; one reusable derived-data dir.
8. **Push before requesting review** (Workflow). A review request against unpushed work is a no-op. Confirm the remote branch exists.
9. **Open the PR** into `<target>` with labels applied immediately — `sourcery-review` (always) + the **track** label + the **wp** label — and cross-link the issue(s) it delivers in the body (Review gates, point 5; Reporting, issues and labels).
10. **Process every review comment** (Review gates, point 5). Nothing merges with an unresolved thread.
11. **After merge, the merger (fable) closes delivered issues explicitly** and ticks the #25 tracker (Reporting, issues and labels).
12. **Remove the worktree as the FINAL step, immediately after the PR merges** — `git worktree remove <path>` and delete the local branch. Do not leave it for a weekly sweep (Worktree discipline; incidents → *Dead worktrees accumulated 25 G*).
