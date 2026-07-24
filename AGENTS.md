# Agent instructions — Making Tracks

You are working on **Making Tracks** (making-tracks.app), an iOS map app for discovering interesting places — history, architecture, oddities — built from open data. The map is fresh snow; moving through the world marks it.

## Amending this file

1. **Rule text is timeless.** No dates, no `as of`. A rule states what to do and why it is true, not what happened. Incident rationale goes in [`docs/process/incidents.md`](docs/process/incidents.md) and the rule cites it by name. A dated fact eventually goes false, and a false fact reads as permission to skip the rule (incidents → *Stale law disabled two gates*).
2. **One rule, one home.** Principles live in `docs/PRINCIPLES.md`. Operational law lives here, stated once. Worked detail, command blocks and examples live in the process docs cited below. Cross-reference; never restate.
3. **Cross-references name a section**, never a line number. Line numbers rot on the next edit. Principle citations name the section and number (`Data 7`, `Product 7`) — bare numbers are ambiguous across sections.

Every command in this file must be runnable as written — no placeholders you cannot fill. `scripts/lint_agent_law.py` runs in CI on every PR and catches the known bad shapes of the first and third constraints — dates, narrative openers, line-number citations. Run it yourself before committing. It cannot tell narrative from rule, so a green lint means "no known bad shape", not "correct". The constraints bind you, not the linter.

## Grounding — read before doing anything

1. `docs/PRINCIPLES.md` — the project's non-negotiables. Every change is checked against these.
2. `docs/superpowers/specs/2026-07-14-making-tracks-design.md` — the approved design: architecture, data model, decisions and their rationale, work-package decomposition.
3. `brief.md` — the original product brief (context for *why*; the spec supersedes it where they differ).
4. The **current Phase Spec** (`docs/superpowers/specs/YYYY-MM-DD-phase-<n>.md`) and the phase **task graph** (`docs/superpowers/phases/phase-<n>/tasks.md`) — the task's builder brief is the scope; do not improvise beyond it.
5. `docs/process/coordination.md` — the standing fleet reference (roster, AMQ conventions, merge law, supervision-loop contract, taste-call protocol, review budgets, standing items, current-phase pointer).
6. Rob's sibling repos (`gh: mnbf9rca/family-foqos` and kin), when your WP builds or debugs a capability that plausibly exists there. Ground the existing implementation first: read it, port the proven parts, and record in the issue what was reused and what was genuinely non-portable — with evidence, not assumption. Proven beats invented.

A fresh session — including a full fleet restart — boots by reading `AGENTS.md`, `docs/process/coordination.md`, and the current phase's `tasks.md`; nothing load-bearing lives only in a session.

## Repo layout

- `/pipeline` — Python data pipeline (extract → reconcile → score → categorize → publish). Plain CLI, laptop-first, deterministic, SQLite between stages, publishes static files to Cloudflare R2 (`tiles.making-tracks.app`).
- `/ios` — SwiftUI app. iOS 18+ minimum, Swift 6 language mode with strict concurrency. GRDB for user data. MapLibre Native + PMTiles for the map.
- `/contracts` — frozen cross-boundary schemas, fixtures and the `mt_contracts` package.
- `/docs` — principles, specs, plans, process.

## Hard rules

The non-negotiables are in [`docs/PRINCIPLES.md`](docs/PRINCIPLES.md) and that is their only home. Read it. Amending a principle is an argued amendment to that file, ratified by Rob — never an edit here.

The ones that bite most often, by section and number there: `place_id` is forever (Data 7), all source data is polluted until proven otherwise (Data 10), everything crossing a boundary is versioned (Data 11), the pipeline is deterministic (Data 12), "interesting" is measured not asserted (Ranking 13), privacy is structural (Privacy 14–15), the app never editorialises which pins you see (Product 7). Beyond principle 15, any network write of user-derived data must also satisfy the unlinkability rules in the spec's §9. If a change could reassign or reformat shipped `place_id`s, stop and flag it rather than proceeding.

These operational rules are not in `PRINCIPLES.md` and live here:

- **Untrusted input, concretely.** Data 10 states the posture; in practice it means validate schemas, bound sizes, sanitize strings, https-only URLs — and never interpolate source content unescaped into shell, SQL, or LLM prompts.
- **Determinism, concretely.** No wall-clock and no randomness in outputs, except via cached, versioned LLM calls.
- **Constants that shape output are earned, not baked.** A threshold, weight, or cap that affects output quality or behaviour is either swept by the eval harness or flagged tunable in a comment — never a silent magic number the next person fears to touch.
- **No silent long-running work.** Any process expected to run beyond ~30 seconds emits greppable progress through the shared heartbeat helper: per-phase START/DONE lines with counts and durations, plus heartbeats with done/total, rate, elapsed time and phase-specific counters. A human tailing the log must be able to compute the current phase, progress against a known total and an ETA. A long-running phase that is silent, or whose output is not ETA-computable, is a review-blocking defect. Detached runs always report their log path at launch.
- **Test-first, with teeth.** Where a behaviour can be expressed as a test, write it first; the ID-stability and reconciliation invariants must have regression tests. A test has teeth only if neutering the code it guards makes it fail — verify that. A test that stays green when the implementation is broken, or that exercises a value/path the product never actually produces, is a false green. The worked checklist is [`docs/process/gate-lessons.md`](docs/process/gate-lessons.md).

## Secrets

All secrets via 1Password: `op run --env-file=.env.tpl -- <command>` (masking stays ON; never `--no-masking`, never render secrets to disk). See [`docs/SECRETS.md`](docs/SECRETS.md). STANDING RULE: any compromised secret (logged, printed unmasked, read into context, committed) gets IMMEDIATELY appended to `TO-ROTATE.log` — reference/name + timestamp + vector, never the value. Logging an exposure is mandatory and blame-free. Access topology — ssh, commit signing, and where heavy work runs — is in [`docs/INFRA.md`](docs/INFRA.md).

## Workflow

The build runs as a **phase cycle** (spec §2): each phase is a large package defined in one design session (the **Phase Spec**), decomposed into a **task graph** (`tasks.md`), and built autonomously by the builder pool. **All production code is written by build agents.** A design agent produces plans and never spawns a code-writing subagent; read-only research and review subagents are fine. fable coordinates, reviews and merges. Keep to your package's scope; if you discover a cross-package contract problem, surface it in your report rather than unilaterally changing the contract. Commit messages: imperative, plain, no attribution boilerplate.

**Taste-call protocol.** When the spec doesn't settle a judgment call: build the most defensible interpretation and flag it in the PR body under a `## Taste guesses` heading, stating the alternative. Ping Rob (push) only when a wrong guess would be expensive to rework (schema/data migration, system-wide visual change) **and** waiting blocks nothing downstream. If waiting would block downstream work, best-guess and flag regardless, noting the risk. **Never stall the pipeline on a taste question.**

**Fold or file.** On finding a defect in a pre-existing component while building or testing: **always log a tracker issue at the moment of discovery.** If the fix is small and cleanly encapsulated within the current PR, **fix it in the same PR**, note it in the PR body, and close the issue on merge. Otherwise **file and continue — never expand PR scope to chase it.** The acceptance pass grades these judgments as part of "spirit". (Incidents → *Three riders on one work package*.)

**Never invoke interactive git.** Always `git commit -m` (never a bare `commit`), `git commit --amend --no-edit`; never `rebase -i`. Rob's `EDITOR`/`VISUAL` are VS Code `--wait`, so any git command that opens an editor pops a window at the human and hangs the agent until he closes it (incidents → *Editor-open hangs the agent*). Export `GIT_EDITOR=true` defensively.

**A mutation is a bare single call.** Never put `&&` between a mutation — commit, push, merge, resolve, `gh` write, file move — and anything else, least of all its own verification or a success echo. A failed step earlier in the chain does not stop the rest, and a trailing `echo DONE` prints whether or not the thing happened. Issue the mutation alone, then verify in the **next** call by reading the artifact back: the pushed file, the live issue body, the branch head. An exit code from a step before the one you care about proves nothing. (Incidents → *A chained commit reached the main checkout*.)

**Branch discipline.** Feature branches (`wp-<id>-plan` / `wp-<id>-impl`) are cut from `develop` and PR back to `develop` — a PR is the only path onto `develop`; never push to it directly. `main` is human-gated: only Rob promotes `develop` to `main`. No agent self-merges its own PR; the design lead (fable) reviews, and merges happen only with human-sanctioned authority (overnight, PRs queue for Rob's morning review). Promotions to `main` are merge commits (ruleset-enforced); squash is for feature PRs into `develop`/`ios` only.

**Merge execution and announcement.** Merges into long-lived branches are executed by fable unless explicitly delegated per-merge; a reviewer's "cleared to merge" is input to fable's gate, never authorization to merge. Whoever executes a merge announces it as their first act afterwards — peer-to-peer to fable, with the PR number and merge SHA; a copy dropped into a busy thread is not an announcement. GitHub's `mergedBy` always shows the shared-token identity and proves nothing about who executed.

**iOS branch.** App work (anything under `ios/`) branches from a freshly-fetched `ios` and PRs into `ios`, not `develop` — same gates. The long-lived `ios` branch lives in the main repo checkout as Rob's Xcode surface: never touch that working tree or switch its branch; Rob pulls when he chooses. fable merges `ios` ↔ `develop` at milestones. Pipeline/contracts/docs work targets `develop`.

**Push early, push often.** An unpushed branch is invisible — indistinguishable from a dead agent — and unmergeable. Push a WIP commit within minutes of starting; force-with-lease later rather than staying local.

**Ground in the current tree.** Branch from a freshly-fetched target branch (`develop`, or `ios` for app work), and re-ground a long-lived doc — its `file:line` citations and its "not built yet" claims — against that same branch before the PR; with several agents merging, the tree moves under you. `develop`'s `ios/` tree lags `ios`, so a doc citing app code grounded against the wrong branch cites lines that do not exist. Where a brief and the code disagree, the code is authoritative — reconcile or flag it, never design around the discrepancy.

## Authoring law (design docs and policy docs)

**A design doc contains NO unowned deferrals.** "Plan to fix X", "to be addressed later", "TODO" and any bare gesture at future work are banned — they hide dependencies and let designed-but-unbuilt behavior read as current. Every deferred item must be exactly one of: (a) a **scoped fix in this doc**; (b) a **named WP row** in the decomposition with an owner and its dependency; or (c) an **explicit Open Flag addressed to Rob**. Never state target or aspirational behavior in the present tense — mark it *target* with its owning WP, and mark what exists today against the tree. (Incidents → *Unbuilt behavior stated as current*.)

**A plan applies the principles; it never changes them.** A design doc must not assert a new privacy rule, policy, floor or threshold and cite an existing principle as if it sanctioned it — that launders a real change past review, and downstream work packages inherit a claim nothing ratified. `docs/PRINCIPLES.md` says so directly: *"the principle needs an explicit, argued amendment to this file — never a silent exception."* When a design needs something the principles do not cover, mark the section PENDING, surface the tension with options, and escalate to Rob via fable. Then apply what he rules.

**Policy-document law** (`privacy.md`, `docs/PRINCIPLES.md`, `docs/threat-model.md` and their kin): a policy doc states **commitments that constrain what future features may do**, not a snapshot of what the app does today. Write the ground rules that hold regardless of features, then what they mean for each known roadmap item — accounts, sharing, feedback — with the hard lines drawn now. A doc that only describes today is obsolete at the next feature. Never add a disclaimer demoting the document ("this isn't the real policy yet"); its authority is the whole point. Rob ratifies these before they land.

**UI design ships with mockups.** This is a visual app; a UI design doc is not complete as prose. Every work package with a user-facing surface carries **rendered mockups**, and they are authored by a **build agent**, not by the designer.

Under the phase cycle, wireframes are authored and ruled **in the design session**, not during the build. Opus specifies the layout; a build agent authors the HTML and renders (390×844 plus an accessibility variant); opus validates; **Rob rules on them before the spec is ratified.** The build phase implements against ruled wireframes only — **no new wireframes are authored mid-build.** The authorship split (build agent renders, design agent validates, Rob rules on taste) is unchanged; only the timing moves forward.

This binds **amendments as much as new designs**. A PR that changes how a surface looks or behaves carries the renders that show it, in the PR itself — not on a branch a reader would have to go and find. If the renders are not merged yet, the design change waits for them rather than going ahead alone. A reviewer opening a UI change and seeing only prose cannot review it.

**Renders are integrated into the related issue's body, not only the PR.** Edit the body so the renders sit where they belong in its story — beside the decision they settle, not appended at the end and never as a comment. A PR is a moment; the issue body is the record.

The split is the point: the **build agent renders**, the **design agent validates the renders against the design**, and **Rob rules on taste**. A designer validating their own mockup is not a gate. Design-correctness and taste are separate judgements and are made by separate parties.

Renders go to Rob only after design validation. Anything the mockup shows that the design does not specify is either a gap in the design or an invention in the render — name which, rather than letting it pass because it looks fine.

The pipeline is the one from the place-card design: HTML wireframes rendered to PNG, **committed with their sources** so they can be re-rendered rather than redrawn, at the ruled design canvas (390×844) with an accessibility-size variant. Mark the fold. See `docs/design/card/` for the worked example.

## Reporting, issues and labels

**Blocked ≠ done.** A `gh`/connector 403 in an agent harness is a sandbox denial, not expired auth. Escalate the exact command in your harness, or relay the exact operation (base/head/title/labels) to fable as an action request; never report blocked and wait. Relays confirm back: whoever unblocks an agent confirms on that agent's thread — an agent that does not know it has been unblocked is still blocked.

**Issue-closing discipline.** GitHub's `closes #N` keywords only fire on merges to the default branch (`main`), and our PRs merge to `develop`, so they never auto-close anything. When a WP's implementation PR merges, the merger closes the issue explicitly (`gh issue close N --comment ...`) and ticks the tracker (#25) checkbox. Never report an issue as closed without verifying its actual state (`gh issue view N`).

**An issue is a single coherent story, told in its body.** Not a conversation. When a decision is put to Rob, or a ruling lands, edit the body (`gh issue edit N`) so the whole thing still reads as one account of what this work is and where it stands — Request / Status / Open questions. Rewrite rather than append; a body that grew by accretion is a transcript wearing a body's clothes.

Comments carry point-in-time evidence only: findings, measurements, test output, a render that has just been produced. **Comments are never the record.** Anything that changes what the issue *is* goes into the body, and if a comment ends up carrying state, move it and delete it.

The body is where Rob looks. A stack of appended comments makes him reconstruct the story himself, which is the thing he is asking us not to do.

**Labels.** Issues get a **track** label (`track-a-pipeline` / `track-b-ios` / `track-c-services`) plus a **type** label (`bug` / `enhancement` / `design` / `question`). `wp` is the work-package label, applied to any PR delivering a tracked work package. `sourcery-review` and `greptile-review` are PR review triggers — never put them on an issue.

An issue whose work touches a user-facing surface also gets **`requires-mockups`**. That label is how the mockup rule is found: it turns "UI design ships with mockups" from something an agent has to remember into something the tracker can be queried for.

**Every PR body names the issue or issues it serves.** A PR that names none orphans its own rationale — the issue is the record, so a change that does not point at one leaves a reader with the diff and nothing else. If a PR genuinely has no owning issue, name what prompted it: the PR, incident or ruling it came from.

## Worktree discipline

**One git worktree per agent, always.** Never work in the repo root checkout and never switch its branch — multiple agents share this machine, and an uncommitted edit in a shared checkout gets stranded or destroyed when another agent switches branches. Start every assignment by setting up your isolated workspace: use the `superpowers:using-git-worktrees` skill if your harness has it (the project-standard mechanism), otherwise `git worktree add .worktrees/<branch> -b <branch>` inside the repo (`.worktrees/` is gitignored; verify with `git check-ignore .worktrees/` — the trailing slash matters, without it the check fails until the directory exists). Do all work there. Never create sibling directories outside the repo.

Removing the worktree is part of finishing the branch, not a later sweep — see **Finishing a branch**.

## iOS simulator

Host-only package tests do not use the simulator: for `/ios` Swift package work covered by host tests, run `cd ios && swift test` on the macOS host. These never touch CoreSimulator and **must not** take the fleet lock.

Simulator-backed work is a shared-machine resource and uses **one designated simulator**, `agent-ios-tests` (UDID `C4A64D49-24A2-4429-B6E2-AD9A14142A99`), driving the app project `ios/App/MakingTracks.xcodeproj`, scheme `MakingTracks`.

**Nothing touches the designated simulator except through `scripts/sim-lock.sh`.** It owns the fleet lock and is the only thing that takes it — build, test, boot, shutdown, erase, delete. This binds coordinators exactly as it binds builders: a maintenance command run by hand is still a second thing touching the simulator. A Release build contends for the same simulator state as a test run, so builds go through it too. Use exactly one destination, by UDID, with parallel and concurrent-destination testing disabled — those are the paths that spawn simulator clones.

**Never read the lock file to decide whether the simulator is free.** It records who holds the lock, not who is using the simulator, and work that never took the lock leaves it looking idle. Use `sim-lock.sh --status`, which checks the lock and the process table and reports HELD if either fires. Acting on a bare `lsof` reading is how a running gate lost its simulator (incidents → *A hand-checked lock erased a running gate*).

Boot with `xcrun simctl bootstatus "$UDID" -b` — idempotent and blocking. **Never use `simctl boot` in agent scripts**, and **never put `simctl delete all` or `simctl shutdown all` in a shared script** — unscoped, those destroy or disrupt Rob's simulators and every other agent's.

Commands, cleanup, clone detection and the simulator's full identity: [`docs/process/ios-simulator.md`](docs/process/ios-simulator.md).

### Disk hygiene (mandatory)

Derived data and result bundles are the biggest disk producers on this shared host. A full disk kills CoreSimulator fleet-wide and every failure then looks like a flaky test (incidents → *Disk exhaustion killed the simulator fleet*). Two laws, both non-negotiable:

1. **One reusable derived-data path per agent — never per-run numbered dirs.** Point every `xcodebuild` run at a single stable `-derivedDataPath /private/tmp/dd-<agent-name>`. Per-run paths accumulate without bound.
2. **Delete result bundles after extracting counts.** If a run uses `-resultBundlePath <path>.xcresult`, parse the counts you need, then `rm -rf` the bundle in the same script — never leave `.xcresult` bundles on disk between runs.

The idiom for both is in [`docs/process/ios-simulator.md`](docs/process/ios-simulator.md) → *Disk hygiene idiom*.

## Review gates (mandatory before declaring anything complete)

Nothing is "done" on the author's say-so. **Every gate below is yours to execute on the host — CI never replaces it.** What CI covers varies by branch and by trigger: on `ios`, the per-PR check builds and runs unit tests only, and the UI suite runs on manual dispatch alone ([`docs/ios-gate-ledger.md`](docs/ios-gate-ledger.md) on `ios` → *Check Name Mapping*); check `.github/workflows/` on your target branch for what actually ran. A green PR is not a tested PR.

Before you declare a plan complete, open a PR, or report a build finished:

1. **Adversarial self-review by subagents.** If your harness can spawn subagents or workflows, you MUST run an adversarial review pass over your own output before declaring it complete: several independent critics with distinct lenses (spec fidelity; internal coherence; feasibility/correctness; security + untrusted-data posture per the spec's §5.5; test quality — do the tests actually pin the invariants?). Have findings cross-examined (a critic's claim must survive a genuine refutation attempt), fix what survives, and for every fix prove **teeth** — neutering the fix turns a test red. Include a review summary (findings raised / survived / fixed) in your completion message. The worked checklist — how to prove teeth, the traps that produce green-but-wrong, what to verify on bridged native code — is [`docs/process/gate-lessons.md`](docs/process/gate-lessons.md).
2. **No subagent capability?** Request the review explicitly: message fable on AMQ (kind: review_request) with the artifact path, and wait for the response before declaring completion.
3. **Builders additionally:** full test suite green is a precondition, not evidence of review. Paste the actual test output (counts, not adjectives) in the PR description — a PR whose description says "tests pass" without output is incomplete. On top of that, **iOS app-target work needs a one-time RELEASE-configuration build before any PR**, run under the fleet lock ([`docs/process/ios-simulator.md`](docs/process/ios-simulator.md) → *The Release-configuration build*). Debug builds and `swift test` do not exercise Release, so a Debug-only gate lets a Release-only break through (incidents → *Debug-only gate let a Release break through*).
4. **Zero new warnings, on any branch.** A clean build introduces no new warnings. A warning is a defect that has not been triggered yet. On the app target this is enforced — warnings-as-errors is set in `ios/App/project.yml` **on the `ios` branch only**, so a warning fails the Release build outright. Build app-target work from an `ios`-based branch or the setting is simply absent. Everywhere else it is on you.
5. **Automated review comments are part of the gate.** Sourcery reviews a PR only when the `sourcery-review` label is applied — apply it yourself the moment you open the PR (`gh pr edit <n> --add-label sourcery-review`); an unlabelled PR is silently skipped, and absence of comments then means nothing. Before a PR is merge-eligible its author processes every review comment — use the `pr-tools:process-review` skill where available, otherwise apply the same discipline manually: triage each comment with technical rigor (verify against plan/spec — neither performative agreement nor reflexive dismissal), fix-and-reply or rebut-with-evidence, and resolve the thread. **Nothing merges with unresolved review comments, and the automated review can take time to arrive, so its absence is not cleanliness.** A PR is merge-eligible only once the automated reviewer has actually posted its review (check the PR's reviews list) AND every resulting thread is resolved.
6. **Greptile is explicit-spend only.** Greptile (`greptile-review` label) costs $1/review and is applied only on fable's explicit instruction: `develop`→`main` promotions, security-surface PRs, and escalations. Sourcery remains the default automated layer; never apply `greptile-review` by default.
7. **Your self-review is unconditional.** The adversarial pass (point 1) does not replace the design lead's review, and the automated bots never substitute for it: run your own critic pass regardless of which bot layers are configured or whether their credit is available. Those layers raise the floor; they are not the floor.

**Threat-model discipline** (the spec's §5.5 security-posture hook). Every security or privacy review finding — from the adversarial self-review or from a human/bot reviewer — must **cite a specific in-scope vector from [`docs/threat-model.md`](docs/threat-model.md)** or **explicitly propose an amendment to that model**. A finding that names no vector, or that assumes an out-of-scope adversary (a compromised/jailbroken device, physical seizure, a nation-state, our own infra turning hostile, enterprise-MITM), is **rejected as overreach** — do not action it, and say why. The threat model's calibration tests (its §5) are the screening rubric; apply them mechanically. **Untrusted-data and content-validation findings** (defensive parsing, size caps, `SAFE_TEXT`, plain-text rendering, URL allowlists, no unescaped SQL/shell/LLM interpolation) cite the **hostile-upstream-content vector** (threat-model §2 / the spec's §5.5 / PRINCIPLES Data 10) and are **always in scope** — never "overreach"; that rule targets out-of-scope *adversaries*, not the handling of hostile content we publish. The model is not frozen: a genuine new vector is argued into `docs/threat-model.md` and ratified as project policy, never smuggled in as a one-off review comment. This governs the "security + untrusted-data posture" lens in point 1.

The one standing exception: trivial mechanical changes (typo fixes, comment corrections) need tests green but not the adversarial pass. When unsure whether something is trivial, it isn't.

## Finishing a branch (the pre-PR checklist)

Before opening any PR, run this sequence top to bottom. Each step is stated in full in the section it names — this is the index, not a second copy. The bare-single-call rule (**Workflow**) applies throughout.

1. **Re-ground on a fresh target** (Workflow). `git fetch origin <target>` (`<target>` = `develop`, or `ios` for app work), then `git merge-base --is-ancestor origin/<target> HEAD` must succeed. If it fails, merge the fresh target in as its own step and re-run your gates.
2. **Adversarial gate** (Review gates, point 1). Record the accounting — raised / survived / fixed — for the PR description.
3. **Full test gate under the fleet lock** (iOS simulator). Capture actual pass/fail counts.
4. **Release-configuration build** for iOS app-target work, under the fleet lock (Review gates, point 3).
5. **Zero new warnings** (Review gates, point 4).
6. **Stale-base diff review.** `git diff --stat origin/<target>..HEAD` (two-dot) must show **only your additions**. Deletions or edits to other agents' merged work mean your base is stale and you are about to clobber it — stop and re-ground (step 1).
7. **Artifact cleanup** (Disk hygiene). No `.xcresult` bundles left; one reusable derived-data dir.
8. **Push before requesting review** (Workflow). A review request against unpushed work is a no-op. Confirm the remote branch exists.
9. **Open the PR** into `<target>` with labels applied immediately — `sourcery-review` (always) + the **track** label + the **wp** label — and cross-link the issue(s) it delivers in the body (Review gates, point 5; Reporting, issues and labels).
10. **Process every review comment** (Review gates, point 5). Nothing merges with an unresolved thread.
11. **After merge, the merger (fable) closes delivered issues explicitly** and ticks the #25 tracker (Reporting, issues and labels), **and announces the merge** (Workflow → Merge execution and announcement).
12. **Remove the worktree as the FINAL step, immediately after the PR merges** — `git worktree remove <path>` and delete the local branch. Do not leave it for a weekly sweep (Worktree discipline; incidents → *Dead worktrees accumulated 25 G*).
