# Phase 1 — Task Graph

Phase spec: [`docs/superpowers/specs/2026-07-25-design-system-and-ia-design.md`](../../specs/2026-07-25-design-system-and-ia-design.md) (ratified, merged as PR #465).
Epic: #466. Scope ruled by Rob: **DS-1 (#467), DS-2 (#468), DS-4 (#470) in scope; DS-5 (#471) stretch.** Nothing else from the epic this phase.
Frozen renders: [`docs/design/design-system/`](../../../design/design-system/). No new wireframes are authored mid-build.

Stall threshold: **45 min** without a status change (phase-cycle spec §2.3 default, unchanged for this phase).
Status vocabulary: `claimed → branch → tests green → PR open → review clean → ready-to-merge` (plus `blocked: <reason>` / `released`).
Builder pool: **codex1, codex2, codex3** (codex4 stood down). Builders write their own status line here; fable reads this file on the supervision loop, and per coordination.md → *Dual channel* also announce each transition to fable over AMQ.

Greptile allocation (spec §7, 50/month): **one slot, on T1.6.** Reasoning under *Review budget* below.

---

## How to read this file

1. **Operating rules — every task** applies to all ten tasks, stated once. It is not repeated per task, deliberately: ten verbatim copies of the same rules is how one copy silently goes stale (AGENTS.md → *Amending this file*, one rule one home). Read it as part of your brief.
2. **Acceptance criteria** are numbered AC1–AC33 there and referenced by number in each task.
3. **Where the issue text is wrong** lists the places the epic's issue bodies did not match the tree. Trust this file and the tree, not the counts in the issues. fable is folding these corrections into the issue bodies (*Rulings* → R6), so an issue you read may already be fixed — the tree is still the arbiter.
4. Your task's section carries only what is specific to it.
5. **The `Owner` and `Status` lines in this file lag reality, structurally.** A builder writes their status line on their own branch, and it only reaches `ios` when their PR merges — so a task reading `unclaimed` here may already be claimed and branched. **Never infer claim state from this file.** Claim state is authoritative only with fable over AMQ; ask, rather than reading. See `docs/process/coordination.md` → *Supervision-loop contract*.

---

## Acceptance criteria

The ratified spec states its requirements as prose, not as a numbered acceptance list. This graph numbers them so tasks can own subsets and so the acceptance pass has something to grade against. **Every AC below traces to a spec section or an issue's "Done when" clause — none is invented.** Traces are given in brackets.

Several spec statements are app-wide absolutes that *cannot* be true when Phase 1 ends, because DS-3 (#469) and DS-6 through DS-12 (#472–#478) are all out of phase. Those carry **[phase-scoped]**: graded over the `DesignSystem` module plus the surfaces this phase actually adopts, not the whole app. This was a decomposition judgment and Rob has ruled it stands — see *Rulings* → R5.

### Foundation — issue #467, spec §3–§6, §8

- **AC1** A single material token sheet is the only colour source for map style, app surfaces and accents. The snow column matches the spec §3 table exactly, **plus the four map rows Rob ratified** (see *Rulings* → R4): `background`, `labels`, `labelHalo`, `boundaries`, initialised from `ground`, `muted`, `ground` and `hairline` respectively. No map-style colour lives outside the sheet. [§3, §8, R4]
- **AC2** Every text/background pair in a shipped material meets WCAG AA (4.5:1 body, 3:1 large/UI), proven by a test **in the token sheet** — an illegible material cannot ship. **The gate extends to the map `labels` token at map-label sizes, per material** (R4's rider). If a material's `labels` value fails the gate, that material's label token escalates toward `ink` until it passes: that is a **gate outcome, not a re-ratification**, and needs no new ruling. [§3 gates, R4]
- **AC3** `pin` `#E4572E` and `pinFaded` (35%) are identical across every material, and the **pin** layer constants read from the sheet's constant pin block rather than their own literals. The constant block is **pins only**: spec §8 says "pin layer constants come from the same sheet's constant pin block", §1 law 2 makes "the pins — the places, the subject" the thing that never themes, and the §3 table's constant row is `pin`/`pinFaded` alone. **The track line is not a pin.** It is the user's trace *through* the material, it is one of the four scattered teals §3 says "collapse into the token sheet", and collapsing into a per-material sheet means becoming a themed row — so `trackLine` is a normal token with a per-material value, not a constant. [§1 law 2, §3, §8, §5]
- **AC4** Newsreader ships as static named instances (3–4 cuts), scaled via `UIFontMetrics(forTextStyle:)` with the text style matched to the design size. No variable font file. [§4]
- **AC5** Story roles (display lines, sheet titles, place names, list-row titles) use Newsreader; machinery roles (buttons, labels, metadata, body, data) use SF; on-map labels stay sans. [§4]
- **AC6** Newsreader's SIL OFL 1.1 text is present in About → Software licences. [§4, §2]
- **AC7** Exactly three button styles exist — filled (accent bg, one per screen max), tonal (12% accent tint), quiet (muted text). No `.bordered` or `.borderedProminent`. **[phase-scoped]** [§5]
- **AC8** One sheet pattern: grabber, 22pt top radius, `surface` token background, medium/large detents, one close-affordance convention. No mixed `.material` backgrounds. **[phase-scoped]** [§5]
- **AC9** Two row types only: raised card-row (`surfaceRaised`, 14pt radius) and hairline row. **[phase-scoped]** [§5]
- **AC10** One chip capsule family: filled = active, tonal = available. **[phase-scoped]** [§5]
- **AC11** One toast/pill family carries download progress, location notice, nearby prompt and undo. [§5]
- **AC12** One progress language — thin accent bar on hairline track. Spec §5 names **three** consumers of it: list progress, download progress, **and the ruled #359 map-fetch hairline**. The component must be able to express all three; adopting it at the #359 call site belongs to whichever task owns that surface, and if #359 is unbuilt that adoption is out of phase (see *Explicit non-goals*). [§5]
- **AC13** `Color.accentColor` resolves to a real `AccentColor` asset (snow accent); no site relies on the stock system accent. **Not phase-scoped** — spec §5 requires this to hold "even before full adoption", which is the whole point of doing it as an asset rather than per-call-site. [§5]
- **AC14** SF Symbols only, one weight `.medium`, monochrome, tinted `ink`/`muted`/`accent`. No multicolor, no emoji. Bespoke glyphs only for pin category glyphs and the footprints motif. **[phase-scoped]** [§6]
- **AC15** No view outside `DesignSystem` defines a colour or font literal. **[phase-scoped]** [§8]
- **AC16** Each surface's extraction from `MapScreen.swift` happens with that surface's adoption — no big-bang rewrite, no adoption without extraction. [§8]
- **AC17** The map theme type consumes the material sheet, so map and UI have a single colour source. [§8]
- **AC34** Pins visibly pop against `ground` in every shipped material — spec §3 states "the render is the check", so this is graded on a render, not a ratio. [§3 gates]
- **AC35** Components **inside** `DesignSystem` resolve their type through the typography role API rather than defining their own font literals, so there is exactly one answer to what type a control uses. [§4 two voices, §8 single source. Added with T1.11 by fable's ruling: AC15 binds views *outside* the module and so does not reach a literal written inside it, which is the gap T1.11 closes.]

### IA shell — issue #468, spec §2

- **AC18** The map is the only home: full-bleed, always. No tab bar, no hamburger. [§2]
- **AC19** Persistent chrome is exactly: compass, locate button, the two doors, and bare-text attribution (`© OpenStreetMap`, 11pt, muted ink, **no pill**). [§2]
- **AC20** The World door presents a Scope row, a reserved Search slot, and quiet Settings + About bottom rows. [§2]
- **AC22** Every destination reachable before the change is still reachable — deep links intact, including the map's contextual deep links into Offline maps (download-progress pill, empty-region card's download action). The old menu stack is removed. [§2, #468 Done-when]
- **AC23** Contextual chrome appears only when it has something to say. [§2]

### Tracks door — issue #470, spec §2

- **AC21** The Tracks door presents: My tracks hero (the #266 unified surface — list-detail landing, Retrace one tap away), Lists with per-list progress (n of m seen, thin accent bar), a Loved places virtual row, and a quiet Hidden places virtual row. [§2]
- **AC24** #266's definition of done still holds: one surface, list-detail landing, verdict edits fold in, membership protected. [§2 *existing rulings honoured*, #470 Done-when]
- **AC25** Hidden-place management round-trips with the include-hidden filter. [#470 Done-when]

### Standing a11y gates — spec §7, every task, scoped to the surfaces it touches

- **AC26** Reduced Motion honoured for motion the task's surfaces own (pin pulse, shimmer, arc-glide, autoplay); Reduce Transparency swaps material blur for solid `surface`. **[phase-scoped: per-surface; the app-wide sweep is DS-10 #476]** [§7]
- **AC27** Dynamic Type through AX5 with no clipping, Newsreader included via `UIFontMetrics`. Fixed-height frames that clip at AX5 are defects. **[phase-scoped: per-surface]** [§7]
- **AC28** Never colour-alone: seen-state is fade **plus** label; progress bars carry counts. [§7, #130]
- **AC29** VoiceOver labels and values on all interactive elements; custom controls get real accessibility actions. **[phase-scoped: per-surface]** [§7]

### Place card — issue #471, spec §5 — **STRETCH**

- **AC30** The card's bottom-fade gradient uses the card surface token at both stops; the cream→white seam is gone. [#471]
- **AC31** The action bar uses the three DS styles: Save tonal, Seen filled, Hide quiet. [#471]
- **AC32** The photo slot uses the ruled #376 adaptive height: **the frame height adapts to fit the photo, the subject is not cropped, and odd crops are not filled with letterbox bars**, within a min/max clamp. The fixed 132pt frame and the dead missing-photo slot are retired. [#471, §5, and the ruling itself in `docs/design/2026-07-23-design-session/RULINGS.md` → *#376 — Place card photo aspect ratios*]
- **AC33** `PlaceCardVisualSpec`'s colour literals are gone and the card drops its forced `.preferredColorScheme(.light)` in favour of material tokens. [#471]

---

## Explicit non-goals — do not build these

Scope creep here is expensive, because each of these is someone else's issue in a later phase.

| Out of scope | Issue | What that means for you |
|---|---|---|
| Scope surface (Layers + filter-chip merge) | DS-3 #469 | The World door's Scope row routes to the **existing** Layers sheet, unchanged. Do not merge Layers with the list-mode filter chips. |
| Settings & About rebuild | DS-6 #472 | The World door's Settings/About rows route to the **existing** screens. The only About change this phase is adding Newsreader's OFL entry (AC6). |
| Mud material, Appearance picker, `map.theme.id` migration | DS-7 #473 | Snow only. The token schema must **admit** a second material column without redesign, but no mud values ship and the theme picker is not touched. |
| Onboarding re-skin | DS-8 #474 | Leave `OnboardingFlow.swift` alone except where AC13 forces an accent fix. |
| Diagnostics / blocking surfaces re-skin | DS-9 #475 | — |
| App-wide a11y sweep | DS-10 #476 | You own AC26/27/29 **for the surfaces your task touches**, not app-wide. |
| Search | DS-11 #477 | The World door reserves the slot. Search does not exist. |
| Future materials (forest, sand, petals) | DS-12 #478 | — |
| Adopting the progress component at the #359 map-fetch hairline | #359 | Spec §5 names that hairline as the third consumer of the one progress language, so T1.4's component must be able to express it (AC12). Wiring it at the map-fetch site is #359's own work and is not in this phase — if you find that surface already built and one line from adopting, that is a fold-or-file call, not licence to build it. |

---

## Where the issue text is wrong

Grounded against `ios` at 42c556f3. These are corrections to the epic's issue bodies — build against this file and the tree, not against the counts in the issues.

| Issue says | Tree says |
|---|---|
| `PaperStyle` consumes the material sheet | **No type named `PaperStyle` exists.** The file is `ios/Sources/MakingTracksMapStyle/PaperStyle.swift` but the type inside is `public struct MapTheme` (line 51). The string "PaperStyle" survives only as a filename, a test filename (`ios/Tests/MakingTracksMapStyleTests/PaperStyleTests.swift`) and a test method name (`ios/App/Tests/NativeClusteringSpikeTests.swift:20`) — never as a symbol you can call. |
| "seven per-surface spec enums" in `MapScreen.swift` | **Nine** `*Spec` types exist, and only **four** carry colour/font literals: `PlaceCardVisualSpec` (:24, 13 literals), `TrackVisitEditorVisualSpec` (:851, 10), `TrackReplayTimelineControlSpec` (:1799, 3), `DiagnosticsVisualSpec` (:7651, 1). The other five (`MapHomeChromeSpec` :12, `MapOverlayChromeSpec` :101, `TrackVisitRowDensitySpec` :843, `TrackVisitDragVisualSpec` :1251, `TrackReplayArcGlideSpec` :1813) are pure layout/timing constants. |
| "13 stock-blue `Color.accentColor` sites" | **10** literal `Color.accentColor` references (all `MapScreen.swift`: 3557, 3960, 4956, 5001, 5454, 5930, 7171, 7909, 8501, 8507), plus **9** `.buttonStyle(.borderedProminent)` sites with no `.tint()` override that also render in the stock accent (`MapScreen.swift` 4131, 4975, 5020, 5783, 8477; `OnboardingFlow.swift` 700, 865, 880, 887). So 10 narrow, 19 broad — not 13. Re-derive the list; do not trust the number. |
| "four scattered teal definitions" | Four distinct **values** across **six** sites in **two** modules: `#057563` (`MapScreen.swift:44`), `#006e5e` (:50), `#0a6b5c` (:859 and again :7652), `#2d8c83` (:1808 as RGB floats and again `ios/Sources/MakingTracksMapStyle/TrackLayers.swift:9` as a hex string). Plus `accentSoft` `#e3f0eb` (:860). The scattering is worse than "four definitions" implies. |
| "the #266 unified surface" (DS-4) | **#266 is unbuilt app-side** (`docs/superpowers/phases/phase-1/design-session-input.md:24` says so). What exists is two `MenuDestination` cases (`.lists`, `.tracks`, `MapScreen.swift:740`) that both render the same `ListDetailView` for the system track list — component reuse, not unified navigation. UITest `testTracksMenuAndListsMyTracksReachSameScreenIdentity` (`ios/App/UITests/MakingTracksCoreLoopUITests.swift:1406`) currently **pins that drift**. Rob's framing: the mockups are ratified (#295, `68d1b38`), the app side is unbuilt, and DS-2 and DS-4 deliver it. T1.8 delivers the unification; it is not a restyle. |
| "Retrace one tap away" | **"Retrace" is not a code symbol** — zero occurrences in `ios/`. The real control is a "Map" button in the track summary card (`MapScreen.swift:5866`) and "Show on map" in plain list detail (:5781), both accessibility id `lists.detail.show-map`. |
| Loved / Hidden become "manageable" rows | **Neither collection surface exists.** No menu row, no view, no accessibility ids. Loved exists only as per-card state plus a filter chip; Hidden only as per-card state plus the "Include hidden places" toggle. Both need **new read helpers** — but **no new schema or migration** (see T1.9). |
| Hidden management "round-trips with the include-hidden filter" | The filter (`LayersSheet`, `MapScreen.swift:8527`, id `map.layers.show-hidden`) affects **map pin rendering only**, via `PinFeatureFilter.discoveryFeatures`. It does **not** gate `trackVisits`, `trackGeometryContext` or `listProgress`, which unconditionally exclude hidden places (`ios/Sources/MakingTracksData/Derivations.swift:160, 182, 380`). AC25 must be satisfied against that asymmetry, not in ignorance of it. |
| "the ruled #376 adaptive photo height" | The ruling **is** in the tree, just not in code: `docs/design/2026-07-23-design-session/RULINGS.md` → *#376 — Place card photo aspect ratios* records it verbatim ("Adaptive height - frame fits photo"), and no code, comment or partial implementation exists yet. AC32 states the ruled behaviour; only the min/max clamp values are open, and those are a taste guess for T1.10, not a blocker. |
| — | **There is no snapshot / visual-regression framework in the repo.** The only "visual" coverage is exact-value constant assertions in `ios/App/Tests/AppShellTests.swift:11` plus behavioural XCUITests by accessibility id. Do not assume pixel coverage exists to catch a styling regression. |

---

## Operating rules — every task

**Branch and PR.** App work branches from a freshly-fetched `ios` and PRs into `ios`, never `develop`. Branch name `wp-<issue>-<slug>`. One git worktree per agent: `git worktree add .worktrees/<branch> -b <branch> origin/ios`. Push a WIP commit within minutes of starting — an unpushed branch is indistinguishable from a dead agent. Remove the worktree as the final step after your PR merges.

**Labels, immediately on opening the PR.** `sourcery-review` + `track-b-ios` + `wp`. An unlabelled PR is silently skipped by Sourcery, and absence of comments then means nothing. Add `greptile-review` only if your task's review tier says so.

**PR body must contain:** the issue it serves (`#467`/`#468`/`#470`/`#471`) and this task's id; actual test output with **counts, not adjectives**; the adversarial-review accounting (raised / survived / fixed); a `## Taste guesses` heading if you made any; and the renders for any surface whose appearance changes.

**Gates, all yours to run on the host — CI does not replace them.**

```bash
# Host-only package tests (DesignSystem and the other ios/ SwiftPM targets).
# Never takes the fleet lock, never touches the simulator.
cd ios && swift test

# Full gate: Release build + build-for-testing + app unit/UI tests. Takes the fleet lock.
./scripts/sim-lock.sh ./scripts/release-gate.sh

# Release-configuration build only (does NOT run tests):
MT_RELEASE_GATE_MODE=build ./scripts/sim-lock.sh ./scripts/release-gate.sh
```

`release-gate.sh` refuses to run unless `HEAD` is a descendant of the current `origin/ios` and the lock is held, so re-ground before you gate. Nothing touches the designated simulator except through `sim-lock.sh` — never `simctl` by hand, never read the lock file to decide it is free (`./scripts/sim-lock.sh --status`).

**Disk hygiene.** One stable reused derived-data path per agent, never per-run directories: `/private/tmp/dd-<your-handle>`. Delete any `.xcresult` bundle immediately after extracting counts.

**Zero new warnings.** Warnings-as-errors is set on the app target in `ios/App/project.yml` on the `ios` branch, so a warning fails the Release build outright.

**Adversarial self-review is unconditional.** Before declaring complete, run independent critics with distinct lenses — spec fidelity, internal coherence, correctness, untrusted-data posture, test quality. For every fix, prove **teeth**: neutering the fix must turn a test red. Report the accounting in the PR body. Any security or privacy finding must cite a specific in-scope vector from the threat model (`git show origin/develop:docs/threat-model.md`) or explicitly propose an amendment; a finding assuming an out-of-scope adversary is rejected as overreach.

**Checkpoint protocol.** Update your task's **Status** line here at every transition — `claimed → branch → tests green → PR open → review clean → ready-to-merge` — and announce the same transition to fable over AMQ (`amq send --to fable --session collab`). An event in only one channel is half-delivered. No status essays on GitHub issues: the ledger is here.

**Taste-call protocol.** When this file and the spec do not settle a judgment call: build the most defensible interpretation and flag it in the PR body under `## Taste guesses`, stating the alternative you considered. Ping Rob only when a wrong guess would be expensive to rework **and** waiting blocks nothing downstream. If waiting would block downstream work, best-guess and flag regardless, noting the risk. **Never stall the pipeline on a taste question.**

**Fold or file.** On finding a defect in a pre-existing component: **always log a tracker issue at the moment of discovery.** If the fix is small and cleanly encapsulated in your PR, fix it there, note it in the PR body, and close the issue on merge. Otherwise file and continue — never expand PR scope to chase it.

**Standing gates for every PR under epic #466.** Reduced Motion and Reduce Transparency honoured; Dynamic Type including Newsreader via `UIFontMetrics`; AA contrast proven in the token sheet; never colour-alone; no colour or font literal outside the `DesignSystem` module. Scoped to the surfaces your task touches.

**Two mechanical traps specific to this phase.**

1. **`xcodegen` is not automated.** `ios/App/MakingTracks.xcodeproj` is a committed artifact and `release-gate.sh` builds it directly. If you edit `ios/App/project.yml`, you must run `cd ios/App && xcodegen generate` **by hand** and commit the regenerated project, or your change silently will not exist in the built product.
2. **A docs-only PR does not run the iOS gate.** `ios-gate.yml` and `ios-logging-privacy.yml` are path-filtered and are simply omitted (not red). `agent-law-lint.yml`, `attribution.yml` and `shellcheck.yml` have no path filter and run on every PR. Do not read a green PR as a tested PR.

---

## Review budget

- **Sourcery** on every PR, no cap tracking.
- **opus design review** on all ten tasks. Every task in this phase either defines or changes a user-facing surface, and per fable's budget note this is deliberately preferred over additional Codex passes.
- **Greptile: one slot, T1.6.** T1.6 deletes the entire menu navigation stack while ~70 XCUITests are pinned to its accessibility identifiers and five deep-link entry points must survive. It is the one task in this phase where a silent regression is both likely and expensive, which is what the "highest-risk" allocation is for.
- **A second slot is fable's call, not mine.** T1.9 introduces new read queries over hidden/loved user state against a documented filter asymmetry. It is not a migration or a state machine, so I have not spent a slot on it — flagging it instead of quietly consuming budget.
- **codex-r appears in no review tier.** Its remaining XHIGH pass this phase is the acceptance pass.
- This graph itself is a docs-only PR and consumes neither budget.

---

## Dependency graph

Edges are "must have merged before this starts". Read them as a list, not as the picture's vertical alignment.

| Task | Depends on |
|---|---|
| T1.1 tokens + module | — (critical path) |
| T1.2 fonts + OFL | T1.1 |
| T1.3 buttons + chips | T1.1 |
| T1.4 sheet / rows / toasts / progress | T1.1 |
| T1.5 map theme consumes sheet | T1.1 |
| T1.6 IA shell — doors, chrome, attribution | T1.1, T1.3, T1.4 |
| T1.7 contextual chrome → toast family | T1.6 |
| T1.8 Tracks door contents, #266 unification | T1.6, T1.4, **T1.2** |
| T1.9 Loved + Hidden surfaces | T1.8, **T1.2** |
| T1.10 place card *(stretch)* | T1.1, T1.3, **T1.2** (title only) |
| T1.11 components adopt the typography role API *(follow-up)* | **T1.2 and T1.3, both merged**, and only once T1.2's API has settled |

T1.2 is easy to under-read as a leaf: three later tasks render story-voice titles, so the font-role API is a real upstream dependency for T1.8, T1.9 and T1.10, and it is **not** transitively supplied by T1.6 or T1.4.

Suggested waves for a three-builder pool. **Wave 1 is intentionally serial** — T1.1 blocks everything, so keep it small and land it fast; the other two builders should claim T1.2 and T1.3 the moment it merges.

| Wave | Tasks | Builders busy |
|---|---|---|
| 1 | T1.1 | 1 of 3 |
| 2 | T1.2, T1.3, T1.4 | 3 of 3 |
| 3 | T1.5, T1.6, T1.10 | 3 of 3 |
| 4 | T1.7, T1.8 | 2 of 3 |
| 5 | T1.9 | 1 of 3 |

---

## Tasks

### T1.1 — DesignSystem module, material token schema, snow sheet, AccentColor asset

- **Issue:** #467 · **Spec section:** §3, §8
- **Acceptance criteria:** AC1, AC2, AC3 (constant pin block only), AC13, AC34 (snow)
- **Depends on:** none — **this is the critical path; everything else waits on it**
- **Owner:** codex1
- **Review tier:** `sourcery` + `opus`
- **Status:** ready-to-merge
- **Contracts produced:** the material token sheet API — the type that names the semantic tokens, the accessor other modules call, and the constant pin block. **T1.2 through T1.10 all consume this**, so its shape is a cross-task contract: fix it in this PR and name it in the PR body, because four builders start against it the moment this merges (PRINCIPLES Engineering 18, contracts before parallelism).
- **Contracts consumed:** none.

**Builder brief.** Create the `DesignSystem` module and the token foundation. No surface re-skins in this task.

Mechanics, grounded. `ios/Package.swift` is the local SPM manifest (name `MakingTracksData`, swift-tools 6.0). Copy the `MakingTracksMapStyle` shape: its `.library` product is declared at `ios/Package.swift:10`, its `.target` at `:29`, and its `.testTarget` at `:49`–`:50`. Add the same triplet for `DesignSystem` — `.library` product, `.target`, and `.testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])` — with sources under `ios/Sources/DesignSystem/` and tests under `ios/Tests/DesignSystemTests/`.

Then wire it into the app. In `ios/App/project.yml`, the `packages:` block is at `:20` and already points at `path: ..`, so **no new package entry is needed**; the `MakingTracks` app target's `dependencies:` list is at `:36`, where the existing four products are declared as `- package: MakingTracksData` / `product: <name>` pairs at `:37`–`:44`. Add a fifth pair for `DesignSystem` in the same form. Then run `cd ios/App && xcodegen generate` by hand and commit the regenerated project — nothing automates this.

The token sheet: semantic names, **one value column per material**, snow values exactly as the spec §3 table gives them. The schema must admit a second column (mud) without redesign, but **no mud values ship this phase** — that is DS-7 #473. Include the constant pin block (`pin` `#E4572E`, `pinFaded` 35%) as values that are *by construction* shared across material columns, so AC3 is a property of the schema rather than a convention someone can break.

**Four map rows join the sheet as ratified rows** (*Rulings* → R4): `background`, `labels`, `labelHalo`, `boundaries`, taking snow's `ground`, `muted`, `ground` and `hairline` values. They are **rows with their own per-material values, not compile-time aliases of the tokens they start from.** That distinction is load-bearing: R4's rider lets the AA gate escalate one material's `labels` toward `ink` when `muted` fails at map-label sizes, and an alias would make that impossible without also moving `muted` everywhere it is used. Initialise from those tokens, keep them independently settable.

This is additive to the schema, not a reshape — four more rows in the same name-to-per-material-value structure. The one genuine addition to your deliverable is AC2's extended gate: the contrast test must also cover `labels` at map-label sizes for each material.

**Tokens resolve statically, not dynamically.** Spec §3's mode model is theme-locked: snow *is* light, mud *is* dark, and the app renders the pinned material "regardless of system light/dark". So token values must not be dynamic or appearance-adaptive colours — a token that resolves differently under system dark appearance breaks theme-locking the moment T1.10 removes the place card's forced light mode. Assert it: the snow column resolves to identical values under both system appearances.

AC2 is a **test**, not a review step: assert every text/background pair in the snow column meets 4.5:1 for body and 3:1 for large/UI. Write it so adding a material with an illegible pair fails the suite. This runs host-only — `cd ios && swift test` — no simulator, no fleet lock. Prove teeth: perturb one token to a failing contrast and confirm the test goes red.

AC34 is graded on a **render**, not a ratio — spec §3 says "the render is the check". Ship a render showing pins over `ground` so the pop is visible.

`AccentColor` (AC13, **not** phase-scoped — spec §5 wants no stock-blue site surviving "even before full adoption"). `ios/App/Assets.xcassets` contains only `AppIcon.appiconset` today, so add an `AccentColor` colorset set to the snow accent `#0A6B5C`. **An asset named `AccentColor` is not automatically the app's accent** — the app target must point at it via the `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` build setting in `ios/App/project.yml`, or the 10 literal `Color.accentColor` sites keep resolving to stock blue. Set it, regenerate, and verify on a real screen rather than trusting the asset's presence. You do not need to rewrite those 10 call sites. The nine unstyled `.borderedProminent` sites are AC7's problem and belong to the surfaces that adopt buttons.

Do **not** migrate the four colour-carrying `*Spec` enums in this task — extraction accompanies adoption (AC16). Leave them; T1.10 and later phases dissolve them.

You changed `project.yml`, so the Release build must run even though your logic is host-tested: `MT_RELEASE_GATE_MODE=build ./scripts/sim-lock.sh ./scripts/release-gate.sh`.

---

### T1.2 — Newsreader font provider and OFL licence entry

- **Issue:** #467 · **Spec section:** §4
- **Acceptance criteria:** AC4, AC6, AC27 (Newsreader scaling). **AC5 is shared**: this task owns the *role API* that makes the story/machinery split expressible; the tasks that render text own applying it (T1.6, T1.8, T1.9, T1.10).
- **Depends on:** T1.1
- **Owner:** codex2
- **Review tier:** `sourcery` + `opus`
- **Status:** ready-to-merge
- **Contracts produced:** the font-role API. **T1.6, T1.8, T1.9 and T1.10 all consume it** for titles and place names, so fix its shape here and name it in the PR body: callers ask for a *role* (display, sheet title, place name, list-row title, evocative sub-line, and the SF machinery roles), never for a font or a point size.
- **Contracts consumed:** T1.1's token sheet.

**Builder brief.** Ship the story voice.

The tree has **no custom fonts at all** today: no `.ttf`/`.otf` anywhere in the repo, no `UIAppFonts` key in `ios/App/Sources/Info.plist`, no font registration calls, and `UIFontMetrics` appears exactly once (`MapScreen.swift:8303`, scaling a hand-built `UIFont` for `.caption2`). You are establishing this path, not extending one.

**Acquisition, concretely.** Newsreader is by Production Type, licensed SIL OFL 1.1, and is published on Google Fonts (`https://fonts.google.com/specimen/Newsreader`) with source at `https://github.com/productiontype/Newsreader`. Take the **static** instances, not the variable file — spec §4 rules the variable file out because iOS variable-font APIs are unreliable. Ship 3–4 cuts spanning the optical range plus the italic the spec calls for on evocative sub-lines.

**Where the files go and how they bundle.** There is no precedent in this repo, so establish one: put the font files under `ios/App/Resources/Fonts/`, add that directory to the `MakingTracks` target's `sources:` in `ios/App/project.yml` (the app target's `sources:` list sits above its `dependencies:` at `:36`) so XcodeGen copies them into the bundle, then declare each filename under a `UIAppFonts` array in `ios/App/Sources/Info.plist`. Run `cd ios/App && xcodegen generate` and commit the regenerated project. Verify the fonts actually registered at runtime rather than assuming — a misnamed `UIAppFonts` entry fails silently and falls back to the system font, which looks like nothing happened.

**Do not rename the font files.** The OFL's Reserved Font Name clause makes a rename a licence violation, and renaming is also how the `UIAppFonts` entry silently stops matching.

Every cut is scaled through `UIFontMetrics(forTextStyle:)` with the text style matched to the design size — a raw point size that does not scale is a defect (AC27). The provider must also express the machinery voice (SF) so AC5 becomes an API distinction rather than a convention. On-map labels stay sans and are not your concern — they are MapLibre style layers, not SwiftUI text.

**Fallback.** Spec §4 retains New York as a runtime `design: .serif` fallback (its licence forbids bundling, so it is only ever a fallback). Make the provider degrade to `design: .serif` if a Newsreader cut is missing at runtime, rather than silently rendering SF where the story voice was specified — a silent fall back to the machinery voice is invisible in review and wrong on every card.

AC6 needs **no About-screen code change**. `AboutView` (`MapScreen.swift:7968`) loads `ios/App/Sources/OSSCredits.json` (`:8002`) and renders each entry; that file already contains a full OFL-1.1 entry for the Noto Sans glyph mirror with the complete licence body inlined in `notice_text`. Add a Newsreader entry following that exact pattern (`license_spdx: "OFL-1.1"`, licence text in `notice_text`).

`Info.plist` and bundled resources changed, so run the full gate, not just host tests.

**Licence discipline:** ship the OFL text with the fonts, and do not rename the font files in a way that violates the OFL's Reserved Font Name clause. If the OFL copy you obtain differs from the one already in `OSSCredits.json`, use the one shipped with the font you actually bundle.

---

### T1.3 — Core component styles A: the three buttons and the chip family

- **Issue:** #467 · **Spec section:** §5
- **Acceptance criteria:** AC7 (styles exist), AC10, AC14 (icon convention in these components), AC29
- **Depends on:** T1.1
- **Owner:** codex3
- **Review tier:** `sourcery` + `opus`
- **Status:** ready-to-merge — #486; `swift test`: 404 tests, 0 failures; Opus exact-head review cleared; CI green; Sourcery degradation evidence recorded in PR body per fable ruling
- **Contracts produced:** the three `ButtonStyle`s and the chip family. **T1.6, T1.7, T1.8, T1.9 and T1.10 all consume them** — fix the names and the tone/state API here and name them in the PR body.
- **Contracts consumed:** T1.1's token sheet.
- **Gate:** the components are in a SwiftPM target, so their tests are host-only (`cd ios && swift test`). You changed no app-target file, so no fleet lock and no Release build are needed — **unless** you touch `project.yml`, in which case run `MT_RELEASE_GATE_MODE=build ./scripts/sim-lock.sh ./scripts/release-gate.sh`.

**Builder brief.** Three `ButtonStyle`s and one chip family in `DesignSystem`, all reading tokens.

Exactly three button styles: **filled** (accent background, at most one per screen), **tonal** (12% accent tint), **quiet** (muted text). One chip capsule family: filled means active, tonal means available.

Note how the current code styles buttons, because it shapes what "adoption" will mean later: the place card's action bar does **not** use semantic SwiftUI styles — every button is `.buttonStyle(.plain)` with background, foreground, corner radius and disabled stroke applied manually inside a shared `actionLabel(_:title:)` helper (`MapScreen.swift:8952`). So a "tone" parameter already exists in spirit. Your styles replace that helper's job; do not modify the place card here (that is T1.10).

Chips: the existing list-mode filter chips (`MapScreen.swift:3465`) and the chips inside `TrackFilterPickerSheet` (`:8408`) are the shapes your family must be able to express, but **do not re-skin them in this task** — they belong to DS-3 #469, out of scope. Build the family and prove it with tests plus a render.

AC29 applies to what you build: styles must not swallow accessibility. A disabled state needs a value, not just a colour change (AC28's sibling), and any icon-only button needs a label.

Ship a render of the three buttons and the chip states at 390×844 plus an AX variant, HTML source committed alongside, per the mockup law.

---

### T1.4 — Core component styles B: sheet, rows, toast/pill family, progress bar

- **Issue:** #467 · **Spec section:** §5
- **Acceptance criteria:** AC8, AC9, AC11 (family exists), AC12, AC26 (Reduce Transparency in the sheet/toast surfaces), AC28
- **Depends on:** T1.1
- **Owner:** codex1
- **Review tier:** `sourcery` + `opus`
- **Status:** PR open — #491
- **Contracts produced:** the sheet pattern, the two row types, the toast/pill family and the progress component. **T1.6, T1.7, T1.8 and T1.9 all consume them** — fix the API here and name it in the PR body.
- **Contracts consumed:** T1.1's token sheet.
- **Gate:** host-only (`cd ios && swift test`) unless you touch `project.yml`, as T1.3.

**Builder brief.** The remaining core components in `DesignSystem`.

**Sheet pattern:** grabber, 22pt top radius, `surface` token background, medium/large detents, one close-affordance convention. Today's sheets mix `.ultraThinMaterial` and `.regularMaterial` backgrounds; your pattern replaces both with the token. **Reduce Transparency must swap blur for solid `surface`** (AC26) — build that into the component so no adopting surface can forget it.

**Rows:** exactly two — raised card-row (`surfaceRaised`, 14pt radius) for hero items, and hairline row for lists.

**Toast/pill family:** one component that can express all four of today's bespoke views. They currently disagree on every axis, which is the defect: download-progress pill (`MapScreen.swift:3365`, `.ultraThinMaterial` + `Capsule`, `.caption` semibold), location-off banner (`:4039`, `.ultraThinMaterial` + `Capsule`, `.caption2` semibold), nearby prompt (`:4117`, `.ultraThinMaterial` + `RoundedRectangle(cornerRadius: 10)`, `.caption2`, with an embedded `.borderedProminent` button), undo toast (`:3135`, `.regularMaterial` + `Capsule`, `.callout` medium, with a `.bordered` button). Your family must cover: text-only, text + one action, and text + action + dismiss. **Do not migrate the four call sites here** — that is T1.7.

**Progress:** one language, a thin accent bar on a hairline track. Spec §5 names **three** consumers — list progress, download progress, and the ruled #359 map-fetch hairline — so the component must express all three shapes, including a bare hairline with no count where a map-fetch indicator has no meaningful total. It **carries a count wherever one exists** (AC28): never colour or bar-length alone. Adopting it at the #359 call site is not yours; see *Explicit non-goals*.

Host tests plus renders (390×844 and an AX variant, HTML committed).

---

### T1.5 — The map theme consumes the material sheet

- **Issue:** #467 · **Spec section:** §8
- **Branch:** `wp-467-map-theme-tokens` — cut from a freshly-fetched `ios`
- **Acceptance criteria:** AC3 (pin/track constants), AC17, AC34 (the pin-pop render is this task's evidence)
- **Depends on:** T1.1
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed
- **Contracts consumed:** T1.1's token sheet, including its constant pin block.
- **Contracts produced:** none new, but you change `MapTheme`'s source of values, which `MLNMapViewRepresentable` and the theme picker both read — say so in the PR body.

**Builder brief.** Make map and UI share one colour source.

**Read this first: there is no `PaperStyle` type.** The file is `ios/Sources/MakingTracksMapStyle/PaperStyle.swift`; the type inside is `public struct MapTheme` at line 51, exposing hex-string colours (`background`, `land`, `parks`, `water`, `roads`, `boundaries`, `labels`, `labelHalo`) plus widths and flags, with four static presets (`.snow`, `.definedPaper`, `.streetContrast`, `.verdantKL`), `allCandidates` (`:174`) and `named(_:)`. Consumers: `ios/App/Sources/Map/MLNMapViewRepresentable.swift:166` for layer construction, and `MapScreen.swift:3333` (`selectedTheme`). The theme-**picker** UI is the "Map theme" section of `SettingsView` (`MapScreen.swift:7153`–`7182`); note that `:7849`–`:7890` is `PinSizePreview`, a pin-size swatch, **not** the picker.

Derive **`MapTheme.snow`** from the `DesignSystem` snow material sheet — `ground`→`land`, `water`, `park`→`parks`, `road`/`roadMinor`→`roads` — so the map and the app surfaces read the same tokens (AC17).

**`MapTheme`'s four remaining colour fields are ratified sheet rows, not your judgment call** (*Rulings* → R4). `background`→`ground`, `labels`→`muted`, `labelHalo`→`ground`, `boundaries`→`hairline`. Rob ruled these into the token sheet rather than leaving them as map-only constants, because one sheet feeding both map and surfaces is the system's first law and map-only literals would recreate the very token-island split this epic exists to close. So T1.1 owns adding the rows; you consume them like any other token. **Do not add a proposal note to your PR body about them and do not define them locally.**

If T1.1 has already merged without those four rows, that is a gap in T1.1, not licence to define them here: say so and get T1.1 amended.

**The trap in this task: `MapTheme` colour strings reach two consumers that disagree about what a colour string may be, and the disagreement fails silently.** T1.1's `MaterialColor.mapStyleString` emits `#RRGGBB` when a token is opaque and `rgba(r, g, b, a)` when it is translucent. The **MapLibre style JSON** path — `ios/Sources/MakingTracksMapStyle/PaperStyle.swift:416`, `:420`, `:455`, where the value lands in `fill-color`, `line-color` and `background-color` — accepts CSS colour syntax and handles both. The **app's own parser** does not: `MapThemeColor.uiColor(hex:)` guards on `value.count == 6` and, on anything else, returns a **hardcoded beige `UIColor(red: 0.953, green: 0.937, blue: 0.898, alpha: 1)`** — no throw, no log, no test — and it discards alpha unconditionally. That parser is reached from `ios/App/Sources/Map/MLNMapViewRepresentable.swift:979`, `:989` and `ios/App/Sources/Map/MapScreen.swift:7857`, `:7865`, `:7884`, `:7890`.

**Concretely: `boundaries` is translucent in the ratified snow sheet (alpha `0.14`), so `mapStyleString` gives it the `rgba(…)` form, and `MapScreen.swift:7865` feeds `theme.boundaries` straight into that parser** — `.strokeBorder(MapThemeColor.color(hex: theme.boundaries).opacity(0.55), lineWidth: 1)`. Wire it naively and the swatch renders hardcoded beige at full opacity instead of a dark hairline, **with every test still green** and nothing looking obviously wrong on a light map. Decide deliberately how each field crosses that boundary: the style-JSON fields can take `mapStyleString` as-is, the `uiColor(hex:)` fields need an opaque six-digit value or a fixed parser. The parser defect itself is filed as **#483** — fixing it is not in this task's scope, but if you fix it here instead of working around it, say so in your PR body and close #483 on merge (fold-or-file).

**Leave the other three presets and the theme picker alone — ruled, not guessed** (*Rulings* → R3). The spec says the four existing paper themes "fold into the material system … decided in the material architecture issue with a migration for the stored `map.theme.id`", and Rob confirmed that fold is DS-7 #473's ratified remit: doing it early risks performing the stored-preference migration twice. Deleting or rewiring the presets now would also break the picker and its UITests (`ios/App/UITests/MakingTracksCoreLoopUITests.swift:2427`–`3246`) for no in-phase benefit. No taste flag needed for this — it is settled.

Also collapse the pin and track layer constants onto the sheet (AC3) — but onto **two different parts of it**, and the distinction matters:

- `PinLayers.pinColor` (`ios/Sources/MakingTracksMapStyle/PinLayers.swift:4`) reads from the sheet's **constant pin block**. It must remain `#E4572E` and identical across material columns — pins never theme, so wire it so a future material *cannot* recolour it.
- `TrackLayers.lineColor` (`ios/Sources/MakingTracksMapStyle/TrackLayers.swift:9`, the duplicate of the `#2d8c83` teal typed as RGB floats at `MapScreen.swift:1808`) reads from a **normal per-material token row**. A track is not a place: it is the user's trace *through* the material, and §5 lists this value among the four scattered teals that "collapse into the token sheet". Freezing it as a constant would both overreach §8 — which scopes the constant block to *pin* layer constants — and lock every future material out of tuning it, `#2d8c83` never having been checked against mud's `ground`. Snow's value stays `#2d8c83` for now; whether it should instead become the accent is a taste question with Rob and is not yours to settle.

Fold-or-file note: `TrackLineStyle` (`ios/Sources/MakingTracksMapStyle/TrackLineStyle.swift:3`) has no call sites outside `TrackLayers.swift`. Do not assume the app constructs it.

`MapTheme` is in a SwiftPM target, so its tests are host-only (`cd ios && swift test`), but map rendering changed — run the full gate too.

**This task changes the map's visible palette, so it ships renders.** Today's `MapTheme.snow` is `land #ECE8DD`, `water #DCE3E5`, `roads #E3DED2`; the spec §3 snow column is `ground #F4F1EA`, `water #C9DBE2`, `road #C9BFA8`. That is a visible change to the app's largest surface, and the authoring law is explicit that a PR changing how a surface looks carries the renders that show it — "confirm it still renders" is not evidence. Ship before/after renders of the map home at 390×844 plus an AX variant with HTML sources committed, and make one of them the **AC34 pin-pop check**: pins over the new `ground`, so the pop is visible rather than asserted.

---

### T1.6 — IA shell: two doors replace the hamburger, chrome reduction, bare attribution

- **Issue:** #468 · **Spec section:** §2
- **Branch:** `wp-468-ia-shell-doors` — cut from a freshly-fetched `ios`
- **Acceptance criteria:** AC18, AC19, AC20, AC22, AC23, plus AC14 (the door pill icons and the retired chrome glyphs), AC15/AC16 (the chrome and door code you move out of `MapScreen.swift`), AC5 (any Newsreader text on the door surfaces), AC26/AC27/AC29 for the chrome and door surfaces
- **Depends on:** T1.1, T1.3, T1.4
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `greptile` + `opus` — **the phase's highest-risk task**
- **Status:** unclaimed
- **Contracts consumed:** T1.1 tokens, T1.3 buttons/chips, T1.4 sheet pattern. If any door text uses the story voice you also consume T1.2's font-role API — if T1.2 has not merged, use SF for the door pills (spec §5 specifies SF 600 for doors) and leave story-voice text to T1.8.
- **Ruled render:** `docs/design/design-system/ia-doors.png` — certifies the **door pattern only**, not its row list. The render shows Offline maps and Coverage as World-door rows; spec §2 supersedes that. Implement spec §2's rows, not the render's.

**Doors, per spec §5:** pill buttons on `surface`, hairline border, soft shadow, SF 600 text, accent stroke icon. AC14 binds those icons — SF Symbols only, one weight `.medium`, monochrome, tinted. This task is also where spec §6's "odd-one-out chrome glyphs (filter icon, etc.)" retire structurally, since the chrome cluster they lived in is being rebuilt.

**Builder brief.** Replace the hamburger and its modal menu with two door pills, without losing a single destination.

What you are deleting, in full: the hamburger button in `shellChrome` (`MapScreen.swift:3343`–`3387`, id `map.menu`, glyph `line.3.horizontal` sized by `MapHomeChromeSpec` at `:12`); the sheet presentation at `:2920`; `AppMenuSheet` (`:5058`–`5191`) with its `NavigationStack` and `AppMenuRootView` root rows (`:5280`–`5350`: `menu.row.lists` :5289, `menu.row.tracks` :5297, `menu.row.offline-maps` :5303, `menu.row.settings` :5311, `menu.row.about` :5319) and the per-destination Done button helper (`:5155`, id `menu.done`).

What must survive, because deleting the menu does not delete these destinations. `MenuDestination` (`:740`) has seven cases; each needs a home:

| Destination | Where it goes | Notes |
|---|---|---|
| `.settings` → `SettingsView` (`:7141`) | World door, quiet bottom row | Screen unchanged (DS-6 #472 owns its rebuild) |
| `.about` → `AboutView` (`:7968`) | World door, quiet bottom row | Screen unchanged |
| `.offlineMaps` | **Settings**, not a door | Reachable today from Settings' "Manage offline maps" row (`:7230`, id `settings.storage.manage`, routing to the same `MenuDestination.offlineMaps` at `:7915`). *Target:* spec §2 makes Settings its only menu home, so this task removes the root menu row and adds no door row. Settings' own reorganisation into Offline-maps and Coverage groups is DS-6 #472 — do not restructure Settings here. |
| `.lists` → `ListsView` (`:5352`) | Tracks door | See below |
| `.tracks` → `TrackListDetailDeepLinkView` (`:5237`) | Tracks door | See below |
| `.listDetail(Int64)` | Deep link only | Reached from list-mode "Back" (`:3400`) |
| `.diagnostics` | Inside Settings, unchanged | Never was a root row — reached from `settings.diagnostics.export` (`:7240`) |

**The Tracks door routes to today's surfaces in this task.** Its contents are restructured in T1.8. If you delete the hamburger and leave the Tracks door empty, the app regresses between two merges — so the door opens onto the existing Lists / My-tracks destinations, and T1.8 replaces that content. Say so in your PR body so the reviewer knows the door is deliberately provisional.

**The World door's Scope row routes to the existing Layers sheet, unchanged.** Entry today is `layersButton` (`:3953`, id `map.layers`) opening `LayersSheet` (`:8519`, detents medium/large) which holds the include-hidden toggle (`:8527`), coverage shading (`:8540`) and the category toggles (`:8554`). Merging that sheet's contents with the list-mode filter chips (`:3465`, which open a *different* sheet, `TrackFilterPickerSheet` at `:8408`) is DS-3 #469 and **out of scope** — you route to the sheet as it stands.

**The standalone layers button is deleted, and this is not a taste call.** Spec §9 item 2 reads "two doors replace hamburger **+ Layers entry**", and AC19 — which this task owns — enumerates persistent chrome exhaustively as compass, locate, the two doors and the attribution, with no sixth slot. `layersButton` is unconditional persistent chrome today: it renders in **both** branches of the `if/else` in `shellChrome` (`:3343`–`:3387`) and `shellChrome` itself is an ungated `.overlay` (`:2796`). So the World door's Scope row becomes the only entry to `LayersSheet`, and the `map.layers` UITests get re-pointed once, here. In list-mode, where the button also appears today, the door is still present, so the Scope row remains reachable — confirm that in the simulator rather than assuming it.

**Deep links that must keep working.** `AppShellModel` (`:787`, extended `:2276`) is the source of truth. Five entry points: `openMenu()` (`:794`, dies with the hamburger), `openListDetailDeepLink` (`:801`, called from list-mode Back at `:3400`), `openListsDeepLink` (`:2277` — **no production caller; exercised only by `AppShellTests.swift:83`**), `openTracksDeepLink` (`:2284`, called from the place card's "Manage visits" at `:3047`), `openOfflineMapsDeepLink` (`:2291`, called from **two** places: the empty-region card's action at `:5014`/wired `:2837`, and the download-progress pill at `:3367`). AC22 is graded on all of these still resolving. The dead `openListsDeepLink` is a fold-or-file call: small and encapsulated, so remove it in this PR and log the issue, or keep it and say why.

**Chrome, reduced to four things** (AC19). Today's overlay stack is chained `.overlay(alignment:)` calls at `:2795`–`:2919`.

- **Attribution is currently a pill and must stop being one.** `attributionText` (`:3806`) is `Text(verbatim: "© OpenStreetMap")`, `.caption2` semibold, in a `Capsule()` filled with `.ultraThinMaterial`. Replace with bare muted-ink text at 11pt, no background. Keep it visible — it is an ODbL compliance requirement, not decoration — and keep id `map.openstreetmap-attribution`. MapLibre's own attribution and logo stay hidden (`MLNMapViewRepresentable.swift:230`–`231`).
- **Locate button** (`:4055`, id `map.locate-me`) moves onto the token surface treatment; its three tracking-mode icons and labels (`:4069`–`:4093`) are unchanged.
- **Compass — ruled** (*Rulings* → R1). Adopt and position MapLibre's built-in compass; **do not build a bespoke control.** No compass exists in the Swift sources today and `MLNMapView`'s built-in appears on rotation, which Rob confirmed is the correct iOS grammar — the renders' intent was "a stable home in the quiet chrome cluster", not an always-visible control. Your design work here is **theming and positioning only**: give it a settled place in the reduced cluster and make it read as part of the material.
- **Doors** are pill buttons on `surface` with a hairline border, soft shadow, SF 600 text and an accent stroke icon (spec §5).

**Search slot — ruled** (*Rulings* → R2). The door's layout **accommodates** Search and **nothing renders** until DS-11 #477. No disabled row, no placeholder, no "coming soon" advertising: a visible dead row is a tap that does nothing. No taste flag needed.

**The test migration is the bulk of this task and the reason for the Greptile slot.** `ios/App/UITests/MakingTracksCoreLoopUITests.swift` has roughly 70 tests, many driving the menu through a helper `openAppMenu(in:)` (first call site `:630`) and asserting on ids `map.menu`, `menu.row.lists`, `menu.row.tracks`, `menu.row.settings`, `menu.row.offline-maps`, `menu.row.about`, `menu.done`. Representative cases to re-point rather than delete: `testMenuAboutCarriesCreditsAndMapAttributionIsInert` (`:2203`) and `testOfflineProgressChipDeepLinksToOfflineMaps` (`:2234`). In unit tests, `testMapHomeChromeUsesFilterGlyphAndChiplessMenuSpec` (`ios/App/Tests/AppShellTests.swift:47`) asserts `MapHomeChromeSpec`'s hamburger constants directly and must be rewritten, and the `AppShellModel` routing tests at `:56`, `:71`, `:80`, `:89`, `:99`, `:109` must be re-pointed at the new routing.

**Re-point tests; do not delete them to get green.** A test deleted because its identifier moved is lost coverage of a destination that AC22 says must still work. If a test genuinely no longer describes a behaviour that exists, say so explicitly in the PR body and name what replaces its coverage.

Full gate required, plus renders of the map home with both doors and each door open.

---

### T1.7 — Contextual chrome adopts the toast/pill family

- **Issue:** #468 · **Spec section:** §2, §5
- **Branch:** `wp-468-chrome-toast-family` — cut from a freshly-fetched `ios`
- **Acceptance criteria:** AC11, AC12 (the download-progress consumer), AC23, plus AC15/AC16 (these four views come out of `MapScreen.swift` as they adopt), AC26, AC29
- **Depends on:** T1.6
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed
- **Contracts consumed:** T1.1 tokens, T1.3 buttons (the nearby prompt's embedded action), T1.4 toast/pill family and progress component.

**Two acceptance additions inherited from T1.4.** T1.4 built the family but mounts nothing — its diff touches no file under `ios/App/` — so two obligations that can only be proved at a real call site land here, on the task that does the mounting. They are anchored in this row rather than left in a review thread, which is what makes the deferral compliant rather than an unowned one:

1. **44×44 proof at the concrete call sites.** T1.4 proved its own built-in controls meet the target in both dimensions. Prove it again for every control that is *injected* at adoption — `LocationSettingsButton` inside the location-off banner, any T1.3-styled action passed as custom content, and the nearby prompt's two controls — because an injected view carries its own frame and the family cannot enforce one it does not own.
2. **Mounted download-progress accessibility *value*.** AC29's value clause is proved on the **live pill**, not on the component in isolation. T1.4's tests assert the value the component derives; this task asserts the value VoiceOver actually reads from the mounted surface with real progress state behind it.

**Builder brief.** Migrate the four bespoke contextual views onto T1.4's family.

Depends on T1.6 rather than running beside it **on purpose**: the download-progress pill lives inside `shellChrome` (`MapScreen.swift:3365`), which T1.6 rewrites wholesale. Two builders editing that region of a 10k-line file concurrently is a merge conflict that costs more than the lost parallelism, and the Codex budget this phase does not have room for avoidable rework.

The four call sites and their current inconsistencies are inventoried in T1.4's brief. Migrate each to the family, preserving behaviour and every accessibility identifier: `map.download-progress` (`:3365`, taps into `openOfflineMapsDeepLink`), the location-off banner (`:4039`, with its embedded `LocationSettingsButton`), `map.nearby-prompt` with `.seen` and `.dismiss` (`:4117` — its embedded `.borderedProminent` becomes a DS filled button, killing two of the nine stock-accent sites), and the undo toast with `place-card.hide.undo` (`:3135`, whose `.bordered` button becomes quiet or tonal).

AC23 is behavioural: each must appear only when it has something to say. Preserve the existing auto-dismiss semantics — `testHiddenToastAutoDismissesWithoutUnhidingPlace` (`ios/App/UITests/MakingTracksCoreLoopUITests.swift:2044`) and `testHiddenToastUndoRestoresHiddenPlace` (`:2059`) pin them, and an undo toast that dismisses differently is a data-loss-adjacent regression, not a styling nit.

Reduce Transparency: these are the surfaces most likely to be blur-backed today (three use `.ultraThinMaterial`, one `.regularMaterial`), so AC26 lands here concretely.

Full gate plus renders of each of the four states.

---

### T1.8 — Tracks door contents: unify #266, My tracks hero, Lists with progress

- **Issue:** #470 · **Spec section:** §2
- **Branch:** `wp-470-tracks-door-unify-266` — cut from a freshly-fetched `ios`
- **Acceptance criteria:** AC21 (My tracks and Lists parts), AC22 (**you inherit it**: T1.6 wired this door provisionally, so you are the task that can silently drop a destination), AC24, AC28, plus AC5 (Newsreader titles), AC12 (the progress bar), AC15/AC16 (what you extract from `MapScreen.swift` as this surface adopts), AC26/AC27/AC29
- **Depends on:** T1.6, T1.4, **T1.2** — the hero and list-row titles are story-voice text, so this task needs the font-role API, which is not a transitive dependency of T1.6 or T1.4
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed
- **Contracts consumed:** T1.1 tokens, T1.2 font roles, T1.4 rows + progress component, T1.6's door surface.
- **Ruled renders:** `coherence.png` frame 4, `ia-doors.png` frame 3

**Builder brief.** Build the Tracks door's real contents, and actually deliver #266's unification.

**#266 is unbuilt — this is not a restyle.** Today `.lists` and `.tracks` are two distinct `MenuDestination` cases (`MapScreen.swift:740`) reaching the same `ListDetailView` for the system track list by two paths: `.tracks` → `TrackListDetailDeepLinkView` (`:5237`), which fetches the list where `isSystem && kind == PlaceList.trackKind` (`:5275`, `trackKind` defined at `ios/Sources/MakingTracksData/Models/PlaceList.swift:6`, the `kind` property at `:11`); and `.lists` → `ListsView` (`:5352`), whose row for that same system list navigates to the same detail view (`:5390`). `ListDetailView` (`:5508`) then branches on `isTrackListDetail` (`:5562`) into `trackListPage` versus `collectionListBody`. **UITest `testTracksMenuAndListsMyTracksReachSameScreenIdentity` (`ios/App/UITests/MakingTracksCoreLoopUITests.swift:1406`) currently asserts the drift** — it must be rewritten to assert the single surface, not two paths agreeing.

The door presents:

- **My tracks hero** — raised card-row (T1.4), Newsreader title, SF metadata. Lands on the list-detail surface with **Retrace one tap away**. "Retrace" is spec vocabulary with no code symbol: the control is the "Map" button in the track summary card (`:5866`) or "Show on map" in plain list detail (`:5781`), both id `lists.detail.show-map`, calling `onShowOnMap` → `showListOnMap` (`:4528`) which sets `activeListMap`. Keep that id.
- **Lists** — hairline rows with per-list progress. **The query already exists:** `AppDatabase.listProgress(listID:)` (`ios/Sources/MakingTracksData/Derivations.swift:315`) returns a bare tuple `(visited: Int, total: Int)` — **not** the `ListProgress` struct, which is declared at `Models/PlaceList.swift:37` and built one layer up. There is an async wrapper `MapScreenModel.listProgress(listID:)` (`MapScreen.swift:9947`) and existing UI use in `ListsView.listRow` (`:5449`). No new query needed. Render it with T1.4's progress bar **and its counts** — AC28 forbids bar-length alone.
- **New list** — the ratified render's Lists block carries a "New list" row (`docs/design/design-system/ia-doors.html:786`) and the affordance exists today as a `TextField("New list", …)` inside `ListsView` (`MapScreen.swift:5369`; a second one lives in the add-to-list sheet at `:8130`, which is not yours). **Carry it across.** It is the one row in the ruled render that no other task owns, and AC22 means losing it is a regression, not a simplification.
- **Loved places** and **Hidden places** rows are **T1.9**, not this task. Do **not** ship a visible row that does nothing — same reasoning as the Search slot ruling (*Rulings* → R2). Reserve the positions in the layout and render no rows, and say so in your PR body.

AC24 is a regression gate, not new work: one surface, list-detail landing, verdict edits fold in, membership protected. The system "My tracks" list is protected in the data layer (`ios/Tests/MakingTracksDataTests/InteractionsTests.swift:99` `testMyTracksSystemListIsProtectedAndUsesTrackKind`; `ListsView` already gates delete on `!list.isSystem` at `:5404`) — do not weaken that.

Existing coverage to keep green or consciously re-point: `testTracksMenuOpensUnifiedMyTracksVisitEditor` (`UITests:977`), `testMyTracksListDerivesDistinctVisitedPlacesWithoutStoredMembership` (`ios/Tests/MakingTracksDataTests/DerivationsTests.swift:290`), `testMyTracksProgressCountsOnlyValidatedRenderedRows` (`:341`), `testListProgressCountsSnapshotBackedRowsShownByTheList` (`:52`).

Full gate plus renders of the door and the hero landing.

---

### T1.9 — Loved and Hidden places become browsable surfaces

- **Issue:** #470 · **Spec section:** §2
- **Branch:** `wp-470-loved-hidden-surfaces` — cut from a freshly-fetched `ios`
- **Acceptance criteria:** AC21 (Loved and Hidden parts), AC22 (the door keeps every destination it had), AC25, plus AC5 (Newsreader titles on the new surfaces), AC15/AC16, AC26/AC27/AC29
- **Depends on:** T1.8, and **T1.2** for story-voice titles on the two new surfaces
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus` (a Greptile slot here is fable's call — see *Review budget*)
- **Status:** unclaimed
- **Contracts consumed:** T1.1 tokens, T1.2 font roles, T1.4 rows, T1.8's door structure.
- **Contracts produced:** two new read helpers on `AppDatabase` — an all-loved-places query and a hidden-places-with-snapshot-data query. Name their signatures in the PR body; nothing else in the phase consumes them, but DS-6 and later phases will.
- **Ruled renders:** `coherence.png` frame 4 and `ia-doors.png` frame 3 both show the Tracks door's row set — the Loved and Hidden rows you build are two of the four rows those renders certify, so they are graded against them. The list surfaces *behind* those rows are new and have no ruled render: specify them against the DS row and sheet patterns, and ship your own renders.

**Builder brief.** This is **new UI over new read queries** — not a rewire of an existing screen. Neither surface exists today.

**Loved.** There is no `loved` table: loved is the `verdict` column on `visits` (`Verdict` enum with the single case `.loved`, `ios/Sources/MakingTracksData/Models/Visit.swift:4`; record at `:8`, table created in migration v1). Mutators exist — `AppDatabase.setLoved(placeID:_:)` (`ios/Sources/MakingTracksData/Interactions.swift:193`) and `setVisitVerdict(id:_:)` (`:210`). **No "all loved places" read helper exists at all**; lovedness is only ever computed per-place-ID-set via `viewportState` or folded into `TrackVisit` rows (`Derivations.swift:171`). You will write that query.

**Hidden.** Table `hidden_places` (`place_id` PK, `hidden_at`) created in migration v2 (`ios/Sources/MakingTracksData/Migrations.swift:58`). **It has no GRDB record type** — every access is raw SQL across `Derivations.swift` and `Interactions.swift`. `AppDatabase.hiddenPlaceIDs()` (`Derivations.swift:299`) returns a bare `Set<String>` of ids, so a browsable list needs a new read joining `place_snapshots` for names, categories and types. The mutator is `setHidden(_:_:)` (`Interactions.swift:309`); note `unhide(placeID:)` (`:330`) is explicitly commented as test/maintenance-only — **live UI must route through `CoreLoopController.setHidden`**.

**No new schema and no migration.** Both are derivable from existing tables. If you find yourself writing a migration, stop and re-read this paragraph — a migration here would be out of scope and would need Rob's ruling.

**AC25 has a trap you must handle explicitly.** The include-hidden filter (`LayersSheet`, `MapScreen.swift:8527`, id `map.layers.show-hidden`, bound to `MapLayerVisibility.showHiddenPlaces` at `ios/App/Sources/Map/MapLayerVisibility.swift:13`) is threaded only through `PinFeatureFilter.discoveryFeatures(_:showHidden:)` and therefore affects **map pin rendering only**. It does **not** gate `trackVisits`, `trackGeometryContext` or `listProgress`, which unconditionally exclude hidden places (`Derivations.swift:160`, `:182`, `:380`). So "round-trips with the include-hidden filter" cannot mean "the toggle changes these counts". Build the defensible reading — unhiding from your surface makes the place reappear in discovery exactly as the toggle would, and hidden places stay excluded from track and list progress regardless — and **state which reading you built** under `## Taste guesses`, naming the alternative. Do not silently change what track or list progress counts; that is user-visible data semantics and needs a ruling, not a guess.

The Hidden row is **quiet** by design (spec §2): hiding becomes reversible in the open, without advertising itself.

Reuse `showHiddenMode` if it fits — `PlaceCard(showHiddenMode:)` (`MapScreen.swift:8601`) already exposes an unhide affordance without normal hide ownership, pinned by `testShowHiddenModeExposesUnhideAffordanceWithoutNormalHideOwnership` (`UITests:2176`).

Existing coverage to keep green: `testSetHiddenIsIdempotentReversibleAndSnapshotsOnFirstInteraction` (`ios/Tests/MakingTracksDataTests/InteractionsTests.swift:545`), `testHiddenIsOrthogonalToSavedAndVisitState` (`:563`), `testSetLovedTrueMarksLatestVisitAndFalseClearsEveryLovedVisitForPlace` (`:358`), `testVerdictLovedIsRecordedAndReversible` (`:63`), `testHiddenAndListScopeOmissionsBridgeSilently` (`DerivationsTests.swift:418`).

Write host-level tests for the two new queries (`cd ios && swift test`) before the UI, then the full gate. Renders for both surfaces and the two door rows.

---

### T1.10 — Place card adopts the design system — **STRETCH**

- **Issue:** #471 · **Spec section:** §5
- **Branch:** `wp-471-place-card-tokens` — cut from a freshly-fetched `ios`
- **Acceptance criteria:** AC30, AC31, AC32, AC33, plus AC5 (the place name is story voice), AC15/AC16 for this surface, AC26/AC27/AC29
- **Depends on:** T1.1, T1.3, and **T1.2** if you move the card's title onto the story voice (the place name is one of spec §4's named Newsreader roles). If T1.2 has not merged, do the token and action-bar work and leave the title to a follow-up, saying so in the PR body.
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed — **stretch: claim only when no in-scope task is *claimable*.** "Claimable" means unclaimed *and* unblocked: a task still waiting on its dependencies does not hold this one back. That is why the wave table places T1.10 in wave 3 alongside T1.5 and T1.6 while T1.7-T1.9 are still blocked.
- **Contracts consumed:** T1.1 tokens, T1.3 button styles, T1.2 font roles (title only).
- **Ruled renders:** `coherence.png` frame 3 for the card, and `docs/design/2026-07-23-design-session/RULINGS.md` → *#376* for the photo-height ruling.

**Builder brief.** Move the place card onto tokens. This is the phase's first real *adoption*, so AC16 applies: extraction accompanies adoption.

**`PlaceCardVisualSpec`** (`MapScreen.swift:24`–`99`) holds exactly **13** `Color(red:green:blue:)` literals at `:41`–`:53` — the one count in the issue text that is accurate: `cardBackground` (:41), `mediaBackground` (:42), `neutralActionBackground` (:43), `primaryActionBackground` (:44), `loveActionBackground` (:45), `warningActionBackground` (:46), `disabledActionBackground` (:47), `primaryText` (:48), `secondaryText` (:49), `linkText` (:50), `loveText` (:51), `warningText` (:52), `disabledText` (:53). Map each onto a token. **The love and warning tones have no token in the spec §3 table**, which is the same shape of gap as the map-colour fields, and R4 settled how that gets resolved: a missing token becomes a **ratified row in the sheet**, not a local literal and not a colour invented in a view. So raise the two tones for a ruling through fable rather than defining them yourself — AC15 forbids the literal and the sheet is the only legal home. Do the rest of the task meanwhile; this does not block the fade, the action-bar styles or the photo height.

**The fade seam (AC30) is worse than the issue says.** `placeCardBottomFade` (`:8735`) uses `Color(.systemBackground)` at **both** stops (`:8738`, `:8739`) — there is no cream stop at all. Because the card is force-lit (see below), `systemBackground` resolves to opaque white against the cream `cardBackground` used at `:8644` and `:8849`. Both stops become the card surface token.

**Action bar (AC31).** `actionBar(_:)` (`:8821`) dispatches through `actionButton(_:card:)` (`:8855`) to `saveButton` (`:8912`), an inline `.seen` case (`:8860`), `hideButton` (`:8930`), plus `unhideButton` (`:8941`), love/unlove (`:8869`), unsee (`:8889`) and `seenDisabled` (`:8899`). Every one is `.buttonStyle(.plain)` with styling applied manually in `actionLabel(_:title:)` (`:8952`), keyed off `PlaceCardVisualSpec.tone(for:)`. Replace with the T1.3 styles: **Save tonal, Seen filled, Hide quiet.** The spec allows at most one filled button per screen — Seen is it, so check no other filled control coexists on the card.

**Photo slot (AC32).** `mediaSlotHeight = 132` (`:37`) is applied at both `PlaceCardMissingPhotoSlot.body` (`:9148`) and `PlaceCardPhotoSlot.body` (`:9191`). The dead slot is `PlaceCardMissingPhotoSlot` (`:9135`), reachable only through `photoSlot(_:)` (`:8778`) behind `PlaceCardVisualSpec.showsMediaSlotWhenPhotoMissing`, which is a `static let false` (`:34`) never written anywhere — so the branch is **unreachable dead code**, and the type has no other call site. Retire the flag, the branch and the type together.

**The #376 ruling exists — read it, do not re-derive it.** `docs/design/2026-07-23-design-session/RULINGS.md` → *#376 — Place card photo aspect ratios* records Rob's decision verbatim: "Adaptive height - frame fits photo". Concretely: the photo frame height adapts to fit the photo; the card does **not** crop the subject; odd crops are **not** filled with letterbox bars. That file also notes the packet mislabelled its options and shifted Rob's letters by one, so ignore any lettered option you find elsewhere and treat adaptive height as the ruling. Issue #376's own body adds that the image fills the frame edge to edge within a min/max clamp.

The **clamp values are the only open part** and they are yours as a taste guess, not a blocker: pick a minimum that keeps a very wide photo from becoming a sliver and a maximum that keeps a very tall photo from pushing the action bar off the first detent, state both values and your reasoning under `## Taste guesses`, and note that the fixed 132pt height is the value they replace.

**`.preferredColorScheme(.light)` (AC33)** appears exactly once in the whole tree, `:8646`, on the card sheet's modifier chain — so it forces the card *and everything inside it, including the fade* into light appearance. Removing it is what makes the card able to render in mud later; verify the card in dark system appearance after removal, since nothing else was protecting it.

**The test that will fail, and must be rewritten rather than deleted.** `testPlaceCardVisualSpecMatchesApprovedCardLayout` (`ios/App/Tests/AppShellTests.swift:11`) asserts every one of the 13 colour literals by exact value, plus the geometry constants including `showsMediaSlotWhenPhotoMissing` and `mediaSlotHeight`. Rewrite it to assert the card resolves its colours **from tokens** — that is the invariant worth pinning now. `testPlaceCardActionTonesFollowRuledSlotsWithoutDestructiveHide` (`:35`) asserts the tone mapping and needs re-pointing at the new styles. **There is no snapshot framework in this repo**, so nothing else will catch a visual regression: your renders are the evidence.

Full gate plus renders of the card in snow, default and AX sizes.

---

### T1.11 — DesignSystem components adopt the typography role API — **follow-up**

- **Issue:** #467 · **Spec section:** §4, §8
- **Acceptance criteria:** AC35, plus AC5 for the components it touches
- **Depends on:** **T1.2 and T1.3, both merged** — and see the sequencing rule below, which is stricter than the edge
- **Owner:** codex3
- **Review tier:** `sourcery` + `opus`
- **Status:** `blocked: reserved for codex3 after T1.5` — reserved rather than open, so it is **not** "claimable" for the purposes of T1.10's stretch clause. codex3 wrote `ControlStyles` and the 15pt correction that makes this collapse rename-level, so the context fit is real; a builder who frees up first should take other work rather than this.
- **Branch:** `wp-467-component-typography-adoption` — cut from a freshly-fetched `ios`
- **Contracts consumed:** T1.2's font-role API, T1.3's control styles.
- **Contracts produced:** none. This task **removes** a second source of truth rather than adding one.

**Builder brief.** T1.3 shipped its components with font literals because the graph gave it a dependency on T1.1 only, so T1.2's role API did not exist to consume — a decomposition omission, not a builder error. The result is two answers to "what type does a control use", with nothing failing when they drift. This task collapses that to one.

**Scope: rename-level, no visual change.** Two kinds of site, and they need different treatment:

**(a) Literals to replace — `ios/Sources/DesignSystem/ControlStyles.swift` (T1.3).** `Typography.font(for: .button)` for the action text in `MaterialButtonStyleBody` and `MaterialControlLabelStyle`, and `Typography.font(for: .label)` for the chip's text and icon. **If you find yourself changing a rendered size or weight, stop.** That is a design change, not an adoption, and it needs a ruling rather than a commit.

**(b) Roles to *supply* — T1.4's components, which have no literals to replace.** `MaterialToast.swift`, `MaterialProgress.swift` and `MaterialSheetRows.swift` contain **zero** `.font(` calls: they inherit whatever the adopting surface happens to set, so every adopter must remember the right voice and any one of them can silently get it wrong. Give each component the role for the text it owns:

- `MaterialToast` — the message, and the built-in action's title.
- `MaterialProgress` — the count text. The `leadingHeader` is caller-supplied and stays the caller's choice.
- `MaterialSheetRows` — owns no text of its own; its content is caller-supplied. Nothing to do unless the close affordance gains a label.

These are all **machinery voice** under spec §4, so they take SF roles, not Newsreader. The obvious mapping is `.body` for the toast message, `.button` for its action title and `.metadata` for the progress count — but confirm each against §4's machinery list rather than taking that from this row, and flag under `## Taste guesses` if you land somewhere else. **Supplying a role where a component previously inherited is still not a licence to change a rendered size**: if adopting a role visibly changes any component, that is a finding to raise, not a change to absorb.

**Why the values already line up.** T1.3's review corrected its action text from `.body` (17pt) to 15pt semibold, matching both the frozen coherence render (`.coh .act { font-size:15px; font-weight:600 }`) and T1.2's `.button` role (15pt, `.subheadline`, semibold). That correction is what makes this a rename. If T1.3 merged without it, this task is no longer rename-level and you should say so rather than absorbing a redesign.

**Sequencing rule — stricter than the dependency edge.** Do not start when T1.2 merely merges; start when **T1.2's API has settled**. T1.2's SwiftUI path is under review because `Font(uiFont:)` returns a resolved fixed-size font that does not honour `.dynamicTypeSize` on a subtree, so the role API's shape is expected to move. Adopting against the pre-fix API buys the rework twice.

**Add a divergence test if the API admits one cheaply.** The point of this task is that the two cannot silently disagree again: assert a control's resolved size and weight equal `Typography`'s for that role. If the API makes that awkward, say so in the PR body rather than shipping an assertion that cannot fail.

**Note on what this does *not* gate.** T1.3 merges on its own gate and does **not** block on T1.2. T1.6 needs T1.3 and T1.4 and must not inherit T1.2's fix latency; the door pills are SF 600 by spec §5 and need no role API. This row exists so that deferral is owned and tracked rather than loose (AGENTS.md → *Authoring law*, no unowned deferrals).

Host tests only (`cd ios && swift test`) unless you touch `project.yml`. No render needed if nothing visual changes — and nothing visual should change.

---

## Rulings

Decomposition raised six judgment calls the ratified spec did not settle. **Rob has ruled on all six.** Nothing here is a taste guess any more, so a builder who finds one of these questions in front of them should follow the ruling rather than flagging it again. Numbering is kept from the original flags so earlier threads still resolve.

- **R1 — The compass is MapLibre's built-in.** Adopt and position it; do not build a bespoke control. Appear-on-rotation is the correct iOS grammar, and the renders' intent was a stable home in the quiet chrome cluster rather than an always-visible control. Theming and positioning are the only design requirements. → T1.6, AC19.
- **R2 — The reserved Search slot renders nothing.** The World door's layout accommodates Search; no row, no placeholder, no "coming soon" advertising appears until DS-11 #477. A visible dead row is a tap that does nothing. → T1.6, AC20.
- **R3 — The four existing paper themes and the picker are untouched this phase.** Derive `MapTheme.snow` from the sheet and stop there. The fold into the material system is DS-7 #473's ratified remit; doing it early risks performing the stored-preference migration twice. → T1.5, AC17.
- **R4 — The four remaining `MapTheme` colour fields join the token sheet as ratified rows.** `background`→`ground`, `labels`→`muted`, `labelHalo`→`ground`, `boundaries`→`hairline`. They are **not** map-only constants and **not** proposals for a builder to raise in a PR body. Rationale: one sheet feeding map and surfaces is the system's first law, and map-only literals would recreate exactly the token-island split this epic exists to close.
  - **Rider:** the sheet's standing AA gate applies to `labels` at map-label sizes, per material. If `muted` fails there on any material — mud is the likely one — the gate escalates that material's label token toward `ink`. That is a **gate outcome, not a re-ratification**, and needs no further ruling.
  - Consequence for the graph: the rows are owned by **T1.1** (AC1) and the extended gate by **T1.1** (AC2); T1.5 consumes them like any other token. They must be independently valued rows rather than compile-time aliases, or the rider's escalation cannot be performed without dragging `muted` with it.
  - A builder already working on T1.1 when this ruling lands receives it as a **scope note relayed by fable**, not by re-reading this file. Claim state is not discoverable here — see *How to read this file*, point 5.
- **R5 — Phase-scoped grading stands, including the AC13 exception.** Grading the app-wide absolutes over the module plus the surfaces this phase adopts is the ratified migration design; grading them app-wide now would manufacture known-failing noise and burn the acceptance pass's signal. AC13 remains app-wide, because "even before full adoption" is explicit in spec §5.
- **R6 — The epic's issue bodies are corrected by fable, not here.** The counts and claims this graph records under *Where the issue text is wrong* are being folded into the issue bodies by fable, with the inventory re-verified against the current tree and the corrected bodies reviewed by the original planner. Rob's framing for #470: the mockups are ratified (#295, `68d1b38`), the app side is unbuilt, and DS-2 and DS-4 deliver it.
