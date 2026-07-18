# Agent instructions — Making Tracks

You are working on **Making Tracks** (making-tracks.app), an iOS map app for discovering interesting places — history, architecture, oddities — built from open data. The map is fresh snow; moving through the world marks it.

## Grounding — read before doing anything

1. `docs/PRINCIPLES.md` — the project's non-negotiables. Every change is checked against these.
2. `docs/superpowers/specs/2026-07-14-making-tracks-design.md` — the approved design: architecture, data model, decisions and their rationale, work-package decomposition.
3. `brief.md` — the original product brief (context for *why*; the spec supersedes it where they differ).
4. The work-package design doc for your assigned WP (in `docs/superpowers/plans/` once written). Do not improvise scope beyond your WP.

## Repo layout

- `/pipeline` — Python data pipeline (extract → reconcile → score → categorize → publish). Plain CLI, laptop-first, deterministic, SQLite between stages, publishes static files to Cloudflare R2 (`tiles.making-tracks.app`).
- `/ios` — SwiftUI app. iOS 18+ minimum, Swift 6 language mode with strict concurrency. GRDB for user data. MapLibre Native + PMTiles for the map.
- `/docs` — principles, specs, plans.

## Hard rules

- **Never break the `place_id` contract.** IDs are never reassigned; upstream disappearances are tombstoned. If your change could reassign or reformat shipped IDs, stop and flag it.
- **All external data is untrusted** — sources, LLM outputs, and even our own published tiles. Validate schemas, bound sizes, sanitize strings, https-only URLs. Never interpolate source content unescaped into shell, SQL, or LLM prompts.
- **Version everything that crosses a boundary** (manifest, tile format, DB migrations, prompt versions). Readers must detect data newer than they understand and degrade gracefully, never misread.
- **Determinism:** pipeline re-runs must not shuffle IDs or flip outputs. No wall-clock or randomness in outputs except via cached, versioned LLM calls.
- **Privacy is structural:** no identifiers, no analytics SDKs, no accounts, user data on-device. Any network write of user-derived data must satisfy the unlinkability rules in the spec's §9.
- **Ranking changes are judged by the eval harness**, not by argument.
- **Constants that shape output are earned, not baked.** A threshold, weight, or cap that affects output quality or behaviour is either swept by the eval harness or flagged tunable in a comment — never a silent magic number the next person fears to touch.
- **No silent long-running work.** Any process expected to run beyond ~30 seconds emits greppable progress: per-phase START/DONE lines with counts and durations, plus heartbeats (every ~10k records or 30s) with count/rate/elapsed. Detached runs always report their log path at launch. A human tailing the log must be able to answer "is it working and how far along?" at any moment.
- **Test-first, with teeth.** Where a behaviour can be expressed as a test, write it first; the ID-stability and reconciliation invariants must have regression tests. A test has teeth only if neutering the code it guards makes it fail — verify that. A test that stays green when the implementation is broken, or that exercises a value/path the product never actually produces, is a false green.

## Secrets

All secrets via 1Password: `op run --env-file=.env.tpl -- <command>` (masking stays ON; never `--no-masking`, never render secrets to disk). See `docs/SECRETS.md`. STANDING RULE: any compromised secret (logged, printed unmasked, read into context, committed) gets IMMEDIATELY appended to `TO-ROTATE.log` — reference/name + timestamp + vector, never the value. Logging an exposure is mandatory and blame-free.

## Workflow

Work packages (spec §8) are designed one at a time (design agent) and built one at a time (build agent) on feature branches. Keep to your package's scope; if you discover a cross-package contract problem, surface it in your report rather than unilaterally changing the contract. Commit messages: imperative, plain, no attribution boilerplate.

Never invoke **interactive git**: always `git commit -m` (never a bare `commit`), `git commit --amend --no-edit`, and never `rebase -i`. Rob's environment has `EDITOR`/`VISUAL` set to VS Code `--wait`, so any git command that opens an editor **pops a window at the human and hangs the agent** until he closes it (three worktrees popped `COMMIT_EDITMSG` in Rob's VS Code this morning). Export `GIT_EDITOR=true` defensively so any accidental editor-open returns immediately instead of blocking.

Branch discipline: feature branches (`wp-<id>-plan` / `wp-<id>-impl`) are cut from `develop` and PR back to `develop` — a PR is the only path onto `develop`; never push to it directly. `main` is human-gated — only Rob promotes `develop` to `main`. No agent self-merges its own PR; the design lead (fable) reviews, and merges happen only with human-sanctioned authority (overnight, PRs queue for Rob's morning review).

Push early, push often: an unpushed branch is invisible — indistinguishable from a dead agent — and unmergeable. Push a WIP commit within minutes of starting; force-with-lease later rather than staying local.

Promotions to `main` are merge commits (ruleset-enforced); squash is for feature PRs into `develop`/`ios` only.

iOS branch: app work (anything under `ios/`) branches from a freshly-fetched `ios` and PRs into `ios`, not `develop` — same gates. The long-lived `ios` branch lives in the main repo checkout as Rob's Xcode surface: never touch that working tree or switch its branch; Rob pulls when he chooses. fable merges `ios` ↔ `develop` at milestones. Pipeline/contracts/docs work targets `develop` as before.

Ground in the current tree: branch from a freshly-fetched `develop`, and re-ground a long-lived doc — its `file:line` citations and its "not built yet" claims — against `develop` before the PR; with several agents merging, the tree moves under you. Where a brief and the code disagree, the code is authoritative — reconcile or flag it, never design around the discrepancy. Run any merge, push, or resolve as its own step *after* reading the gate or CI result — never chain an irreversible action past a check in a single command.

Plan-language law (design docs): **a design doc contains NO unowned deferrals.** "Plan to fix X", "to be addressed later", "TODO", and any bare gesture at future work are banned — they hide dependencies and let designed-but-unbuilt behavior read as current. Every deferred item must be exactly one of: (a) a **scoped fix in this doc**; (b) a **named WP row** in the decomposition with an owner and its dependency; or (c) an **explicit Open Flag addressed to Rob**. Likewise, never state target/aspirational behavior in the present tense — mark it *target* with its owning WP, and mark what exists today against the tree. (Tonight's reviews repeatedly caught unbuilt behavior stated as current and vague deferrals hiding real dependencies; this law is the standing fix.)

Blocked ≠ done reporting: a `gh`/connector 403 in an agent harness is a sandbox denial, not expired auth. Escalate the exact command in your harness or relay the exact operation (base/head/title/labels) to fable as an action request; never report blocked and wait. Relays confirm back: whoever unblocks an agent (PR opened for it, command run) confirms on the agent's thread — an agent that does not know it has been unblocked is still effectively blocked.

Issue-closing discipline: GitHub's `closes #N` keywords only fire on merges to the DEFAULT branch (`main`) — our PRs merge to `develop`, so they never auto-close anything. When a WP's implementation PR merges, the merger closes the issue explicitly (`gh issue close N --comment ...`) and ticks the tracker (#25) checkbox; never report an issue as closed without verifying its actual state (`gh issue view N`).

Worktree discipline: **one git worktree per agent, always.** Never work in the repo root checkout and never switch its branch — multiple agents share this machine, and an uncommitted edit in a shared checkout gets stranded (or destroyed) when another agent switches branches. Start every assignment by setting up your isolated workspace — use the `superpowers:using-git-worktrees` skill if your harness has it (the project-standard mechanism), otherwise fall back per that skill's convention: `git worktree add .worktrees/<branch> -b <branch>` inside the repo (the `.worktrees/` directory is gitignored; verify with `git check-ignore .worktrees` before creating) — and do all work there. Do not create sibling directories outside the repo.

## iOS Simulator runbook (agents)

Host-only package tests do not use the simulator. For `/ios` Swift package work that is covered by host tests, run `cd ios && swift test` on the macOS host. These tests never touch CoreSimulator and must not take the fleet lock.

Simulator-backed `xcodebuild` runs are shared-machine resources and must use one designated simulator plus a file lock. The designated simulator is:

- Name: `agent-ios-tests`
- Device type: `iPhone 17`
- Runtime: `com.apple.CoreSimulator.SimRuntime.iOS-26-2`
- UDID: `C4A64D49-24A2-4429-B6E2-AD9A14142A99`
- Creation command: `xcrun simctl create agent-ios-tests "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-26-2`

Every `xcodebuild` invocation — **build OR test** — must hold `flock` on `/private/tmp/making-tracks-ios-tests.lock` around the whole boot-and-run sequence. This is **one fleet-wide lock**: it serializes all simulator-backed work across every agent (a Release-configuration build contends for the same simulator/`testmanagerd`/derived-data state as a test run, so builds take the lock too — not just tests). `swift test` (host package tests, no simulator) does not take it. If `flock` is not available in `PATH`, stop and install/provide it; do not run simulator-backed work unlocked. As of 2026-07-16, this host does not expose `flock` in the default agent `PATH`, so `[XCODE/SIM]` work must provision it first. Two runs against one simulator collide in `testmanagerd` and app install state. Boot with `xcrun simctl bootstatus "$UDID" -b`; this is idempotent and blocking. Do not use `simctl boot` in agent scripts.

Use exactly one destination, by UDID, and disable parallel/concurrent destination testing:

```bash
flock /private/tmp/making-tracks-ios-tests.lock sh -ec '
  UDID=C4A64D49-24A2-4429-B6E2-AD9A14142A99
  xcrun simctl bootstatus "$UDID" -b
  xcodebuild \
    <project-or-workspace-args> \
    -scheme <scheme> \
    -destination "platform=iOS Simulator,id=$UDID" \
    -parallel-testing-enabled NO \
    -disable-concurrent-destination-testing \
    test
'
```

Current repo state: `/ios` is a Swift package, so use `swift test` there. When a B-track work package creates the app `.xcodeproj` or `.xcworkspace`, replace `<project-or-workspace-args>` and `<scheme>` with that package's real `xcodebuild` arguments; do not invent paths in shared docs.

### Disk hygiene (mandatory)

Derived data and result bundles are the biggest disk producers on this shared host. Two laws, both non-negotiable:

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

**Why this is a law, not a nicety:** on 2026-07-18 roughly **35 GB** of derived-data and result-bundle litter filled this Mac's disk to **100%**, which killed CoreSimulator **fleet-wide** — every "flaky simulator" failure that night was actually disk suffocation, not a flaky test. A full disk masquerades as flakiness; keep the litter from accumulating in the first place.

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

## Finishing a branch (the pre-PR checklist)

Before opening any PR, run this ordered sequence verbatim. It consolidates the laws detailed elsewhere in this file; follow it top to bottom, and do each irreversible step (push, PR, merge) as its own action after reading the prior check's result.

1. **Re-ground on a fresh target.** `git fetch origin <target>` (`<target>` = `develop`, or `ios` for app work), then verify you are not on a stale base: `git merge-base --is-ancestor origin/<target> HEAD` must succeed. If it fails, the target moved under you — merge/rebase the fresh target in as its own step and re-run your gates. Re-ground any long-lived doc's `file:line` and "not built yet" claims against the fresh tree.
2. **Adversarial gate** (Review gates §1). Run the critic pass; cross-examine findings; fix survivors. For every fix, prove **teeth** — neutering the fix turns a test red. Record the accounting (**raised / survived / fixed**) for the PR description.
3. **Full test gate under THE fleet lock** (iOS Simulator runbook). Serialize the whole suite under `flock /private/tmp/making-tracks-ios-tests.lock`; capture the actual pass/fail **counts** (not adjectives).
4. **Release-configuration build** for iOS app-target work (Review gates §3, #192), also under the fleet lock — Debug + `swift test` do not exercise Release.
5. **Zero-warning build.** Warnings-as-errors applies; a clean build introduces **no new warnings** (they fail Release, and a warning is a defect that hasn't been triggered yet).
6. **Stale-base diff review.** `git diff --stat origin/<target>..HEAD` (two-dot) shows **only your additions** — if it lists deletions or edits to other agents' merged work, your base is stale and you are about to clobber it; stop and re-ground (step 1).
7. **Artifact cleanup** (Disk hygiene). Delete `.xcresult` bundles after extracting counts; one reusable derived-data dir. Leave no litter on the shared disk.
8. **Push BEFORE requesting review.** An unpushed branch is invisible and unmergeable; a review request against unpushed work is a no-op. Push, confirm the remote branch exists, then proceed.
9. **Open the PR** into `<target>` with the labels applied immediately: `sourcery-review` (always) + the **track** label + the **wp** label, and **cross-link the issue(s)** the PR delivers in the body.
10. **Process every review comment** via `pr-tools:process-review` (Review gates §4). Nothing merges with an unresolved thread, and the automated review's absence is not cleanliness — wait for it to post.
11. **After merge, the MERGER (fable) closes delivered issues explicitly** and ticks the #25 tracker — `closes #N` never auto-fires off `develop`/`ios` (only merges to the default branch `main` trigger it; the line-50 issue-closing rule). Never report an issue closed without `gh issue view N`.
12. **Remove the worktree as the FINAL step, immediately after the PR merges** — `git worktree remove <path>` + delete the local branch. A merged branch's worktree is dead weight; `.worktrees/` accumulating dead checkouts caused a **25 G disk incident (2026-07-18)**. Don't leave it for a weekly sweep — clean it as you finish.

## Review gates (mandatory before declaring anything complete)

Nothing is "done" on the author's say-so. Before you declare a plan complete, open a PR, or report a build finished:

1. **Adversarial self-review by subagents.** If your harness can spawn subagents or workflows, you MUST run an adversarial review pass over your own output before declaring it complete: several independent critics with distinct lenses (spec fidelity; internal coherence; feasibility/correctness; security + untrusted-data posture per §5.5; test quality — do the tests actually pin the invariants?). Have findings cross-examined (a critic's claim must survive a genuine refutation attempt), fix what survives, and include a short review summary (findings raised / survived / fixed) in your completion message.
2. **No subagent capability?** Then request the review explicitly: message fable on AMQ (kind: review_request) with the artifact path and wait for the response before declaring completion.
3. **Builders additionally:** full test suite green is a precondition, not evidence of review. Paste the actual test output (counts, not adjectives) in the PR description. A PR whose description says "tests pass" without output is incomplete. **For iOS app-target work, a one-time RELEASE-configuration build is also required before any PR** (`xcodebuild build -configuration Release <project-or-workspace-args> -scheme <scheme> -destination "platform=iOS Simulator,id=$UDID"`) — the Debug build and `swift test` do not exercise Release. Rationale: on 2026-07-18 (#181) a `#if DEBUG` fence with an incomplete `#else` compiled clean under Debug but broke the Release compile; warnings-as-errors applies to Release too, so a Debug-only gate lets a Release-only break through. One green Release build before the PR catches it.
4. **Automated review comments are part of the gate.** Sourcery reviews a PR only when the `sourcery-review` label is applied — apply it yourself the moment you open the PR (`gh pr edit <n> --add-label sourcery-review`); an unlabelled PR is silently skipped, and absence of comments then means nothing. Before a PR is merge-eligible, its author processes every review comment — use the `pr-tools:process-review` skill where available, otherwise apply the same discipline manually: triage each comment with technical rigor (verify against plan/spec — neither performative agreement nor reflexive dismissal), fix-and-reply or rebut-with-evidence, and resolve the thread. **Nothing merges with unresolved review comments — and the automated review can take time to arrive, so its absence is not cleanliness.** A PR is merge-eligible only after the automated reviewer has actually posted its review (check the PR's reviews list for it) AND every resulting thread is resolved.
5. **Greptile is explicit-spend only.** Greptile (`greptile-review` label) costs $1/review and is applied only on fable's explicit instruction: `develop`→`main` promotions, security-surface PRs, and escalations. Sourcery remains the default automated layer; never apply `greptile-review` by default.
6. **Independent review still happens — and your self-review is unconditional.** The adversarial self-review (point 1) does not replace the design lead's review, and the automated bots (Sourcery/Greptile) never substitute for it: run your own critic pass regardless of which bot layers are configured or whether their credit is available. Those layers raise the floor; they are not the floor.

**Threat-model discipline (the §5.5 security-posture hook).** Every security or privacy review finding — whether from the adversarial self-review (point 1) or a human/bot reviewer — must **cite a specific in-scope vector from [`docs/threat-model.md`](docs/threat-model.md)**, or **explicitly propose an amendment to that model**. A finding that names no vector, or that assumes an out-of-scope adversary (a compromised/jailbroken device, physical seizure, a nation-state, our own infra turning hostile, enterprise-MITM), is **rejected as overreach** — do not action it, and say why. The threat model's calibration tests (its §5) are the screening rubric; apply them mechanically. **Untrusted-data / content-validation findings** (defensive parsing, size caps, `SAFE_TEXT`, plain-text rendering, URL allowlists, no unescaped SQL/shell/LLM interpolation) cite the **hostile-upstream-content vector** (threat-model §2 / this §5.5 posture / PRINCIPLES §10) and are **always in scope** — never "overreach"; the overreach rule targets out-of-scope *adversaries*, not the handling of hostile content we publish. The model is not frozen: a genuine new vector is argued into `threat-model.md` (ratified as project policy, like `privacy.md`), never smuggled in as a one-off review comment. This governs the "security + untrusted-data posture per §5.5" lens in point 1.

The one standing exception: trivial mechanical changes (typo fixes, comment corrections) need tests green but not the adversarial pass. When unsure whether something is trivial, it isn't.
