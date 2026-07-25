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
3. **Where the issue text is wrong** lists the places the epic's issue bodies do not match the tree. Trust this file and the tree, not the counts in the issues.
4. Your task's section carries only what is specific to it.

---

## Acceptance criteria

The ratified spec states its requirements as prose, not as a numbered acceptance list. This graph numbers them so tasks can own subsets and so the acceptance pass has something to grade against. **Every AC below traces to a spec section or an issue's "Done when" clause — none is invented.** Traces are given in brackets.

Several spec statements are app-wide absolutes that *cannot* be true when Phase 1 ends, because DS-3 (#469) and DS-6 through DS-12 (#472–#478) are all out of phase. Those carry **[phase-scoped]**: graded over the `DesignSystem` module plus the surfaces this phase actually adopts, not the whole app. This is a decomposition judgment, flagged to Rob — see *Open flags*.

### Foundation — issue #467, spec §3–§6, §8

- **AC1** A single material token sheet is the only colour source for map style, app surfaces and accents; the snow column matches the spec §3 table exactly. [§3, §8]
- **AC2** Every text/background pair in a shipped material meets WCAG AA (4.5:1 body, 3:1 large/UI), proven by a test **in the token sheet** — an illegible material cannot ship. [§3 gates]
- **AC3** `pin` `#E4572E` and `pinFaded` (35%) are identical across every material, and the pin/track layer constants read from the sheet's constant pin block rather than their own literals. [§1 law 2, §3, §8]
- **AC4** Newsreader ships as static named instances (3–4 cuts), scaled via `UIFontMetrics(forTextStyle:)` with the text style matched to the design size. No variable font file. [§4]
- **AC5** Story roles (display lines, sheet titles, place names, list-row titles) use Newsreader; machinery roles (buttons, labels, metadata, body, data) use SF; on-map labels stay sans. [§4]
- **AC6** Newsreader's SIL OFL 1.1 text is present in About → Software licences. [§4, §2]
- **AC7** Exactly three button styles exist — filled (accent bg, one per screen max), tonal (12% accent tint), quiet (muted text). No `.bordered` or `.borderedProminent`. **[phase-scoped]** [§5]
- **AC8** One sheet pattern: grabber, 22pt top radius, `surface` token background, medium/large detents, one close-affordance convention. No mixed `.material` backgrounds. **[phase-scoped]** [§5]
- **AC9** Two row types only: raised card-row (`surfaceRaised`, 14pt radius) and hairline row. **[phase-scoped]** [§5]
- **AC10** One chip capsule family: filled = active, tonal = available. **[phase-scoped]** [§5]
- **AC11** One toast/pill family carries download progress, location notice, nearby prompt and undo. [§5]
- **AC12** One progress language — thin accent bar on hairline track — shared by list progress and download progress. [§5]
- **AC13** `Color.accentColor` resolves to a real `AccentColor` asset (snow accent); no site relies on the stock system accent. **[phase-scoped]** [§5]
- **AC14** SF Symbols only, one weight `.medium`, monochrome, tinted `ink`/`muted`/`accent`. No multicolor, no emoji. Bespoke glyphs only for pin category glyphs and the footprints motif. **[phase-scoped]** [§6]
- **AC15** No view outside `DesignSystem` defines a colour or font literal. **[phase-scoped]** [§8]
- **AC16** Each surface's extraction from `MapScreen.swift` happens with that surface's adoption — no big-bang rewrite, no adoption without extraction. [§8]
- **AC17** The map theme type consumes the material sheet, so map and UI have a single colour source. [§8]

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
- **AC32** The photo slot uses the ruled #376 adaptive height; the fixed 132pt frame and the dead missing-photo slot are retired. [#471, §5]
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

---

## Where the issue text is wrong

Grounded against `ios` at 42c556f3. These are corrections to the epic's issue bodies — build against this file and the tree, not against the counts in the issues.

| Issue says | Tree says |
|---|---|
| `PaperStyle` consumes the material sheet | **No type named `PaperStyle` exists.** The file is `ios/Sources/MakingTracksMapStyle/PaperStyle.swift` but the type inside is `public struct MapTheme` (line 51). The only occurrence of the string "PaperStyle" is inside a test method name at `ios/App/Tests/NativeClusteringSpikeTests.swift:20`. |
| "seven per-surface spec enums" in `MapScreen.swift` | **Nine** `*Spec` types exist, and only **four** carry colour/font literals: `PlaceCardVisualSpec` (:24, 13 literals), `TrackVisitEditorVisualSpec` (:851, 10), `TrackReplayTimelineControlSpec` (:1799, 3), `DiagnosticsVisualSpec` (:7651, 1). The other five (`MapHomeChromeSpec` :12, `MapOverlayChromeSpec` :101, `TrackVisitRowDensitySpec` :843, `TrackVisitDragVisualSpec` :1251, `TrackReplayArcGlideSpec` :1813) are pure layout/timing constants. |
| "13 stock-blue `Color.accentColor` sites" | **10** literal `Color.accentColor` references (all `MapScreen.swift`: 3557, 3960, 4956, 5001, 5454, 5930, 7171, 7909, 8501, 8507), plus **9** `.buttonStyle(.borderedProminent)` sites with no `.tint()` override that also render in the stock accent (`MapScreen.swift` 4131, 4975, 5020, 5783, 8477; `OnboardingFlow.swift` 700, 865, 880, 887). So 10 narrow, 19 broad — not 13. Re-derive the list; do not trust the number. |
| "four scattered teal definitions" | Four distinct **values** across **six** sites in **two** modules: `#057563` (`MapScreen.swift:44`), `#006e5e` (:50), `#0a6b5c` (:859 and again :7652), `#2d8c83` (:1808 as RGB floats and again `ios/Sources/MakingTracksMapStyle/TrackLayers.swift:9` as a hex string). Plus `accentSoft` `#e3f0eb` (:860). The scattering is worse than "four definitions" implies. |
| "the #266 unified surface" (DS-4) | **#266 is unbuilt app-side** (`docs/superpowers/phases/phase-1/design-session-input.md:24` says so). What exists is two `MenuDestination` cases (`.lists`, `.tracks`, `MapScreen.swift:740`) that both render the same `ListDetailView` for the system track list — component reuse, not unified navigation. UITest `testTracksMenuAndListsMyTracksReachSameScreenIdentity` (`ios/App/UITests/MakingTracksCoreLoopUITests.swift:1406`) currently **pins that drift**. T1.8 delivers the unification; it is not a restyle. |
| "Retrace one tap away" | **"Retrace" is not a code symbol** — zero occurrences in `ios/`. The real control is a "Map" button in the track summary card (`MapScreen.swift:5866`) and "Show on map" in plain list detail (:5781), both accessibility id `lists.detail.show-map`. |
| Loved / Hidden become "manageable" rows | **Neither collection surface exists.** No menu row, no view, no accessibility ids. Loved exists only as per-card state plus a filter chip; Hidden only as per-card state plus the "Include hidden places" toggle. Both need **new read helpers** — but **no new schema or migration** (see T1.9). |
| Hidden management "round-trips with the include-hidden filter" | The filter (`LayersSheet`, `MapScreen.swift:8527`, id `map.layers.show-hidden`) affects **map pin rendering only**, via `PinFeatureFilter.discoveryFeatures`. It does **not** gate `trackVisits`, `trackGeometryContext` or `listProgress`, which unconditionally exclude hidden places (`ios/Sources/MakingTracksData/Derivations.swift:160, 182, 380`). AC25 must be satisfied against that asymmetry, not in ignorance of it. |
| "the ruled #376 adaptive photo height" | **No reference to #376 exists anywhere in the tree** — no comment, no TODO, no partial implementation. See Open flag OF4. |
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

```
T1.1 tokens + module
 ├── T1.2 fonts + OFL
 ├── T1.3 buttons + chips ──┐
 ├── T1.4 sheet/rows/toasts/progress ──┤
 └── T1.5 MapTheme consumes sheet      │
                                       ├── T1.6 IA shell (doors, chrome, attribution)
                                       │    ├── T1.7 contextual chrome → toast family
                                       │    └── T1.8 Tracks door contents (#266 unification)
                                       │         └── T1.9 Loved + Hidden surfaces
                                       └── T1.10 place card (STRETCH)
```

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
- **Acceptance criteria:** AC1, AC2, AC3 (constant pin block only), AC13
- **Depends on:** none — **this is the critical path; everything else waits on it**
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed

**Builder brief.** Create the `DesignSystem` module and the token foundation. No surface re-skins in this task.

Mechanics, grounded: `ios/Package.swift` is the local SPM manifest (name `MakingTracksData`, swift-tools 6.0) declaring four library targets each with a sibling `.testTarget` — follow the `MakingTracksMapStyle` / `MakingTracksMapStyleTests` pattern at `ios/Package.swift:40`. Add a `.target(name: "DesignSystem")`, a matching `.library` product, and a `.testTarget(name: "DesignSystemTests")`, with sources under `ios/Sources/DesignSystem/` and tests under `ios/Tests/DesignSystemTests/`. Then add the `DesignSystem` product to the `MakingTracks` app target's dependency list in `ios/App/project.yml:25` — the `packages:` block at `:19` already points at `path: ..`, so no new package entry is needed. Then run `cd ios/App && xcodegen generate` by hand and commit the regenerated project.

The token sheet: semantic names, **one value column per material**, snow values exactly as the spec §3 table gives them. The schema must admit a second column (mud) without redesign, but **no mud values ship this phase** — that is DS-7 #473. Include the constant pin block (`pin` `#E4572E`, `pinFaded` 35%) as values that are *by construction* shared across material columns, so AC3 is a property of the schema rather than a convention someone can break.

AC2 is a **test**, not a review step: assert every text/background pair in the snow column meets 4.5:1 for body and 3:1 for large/UI. Write it so adding a material with an illegible pair fails the suite. This runs host-only — `cd ios && swift test` — no simulator, no fleet lock. Prove teeth: perturb one token to a failing contrast and confirm the test goes red.

`AccentColor`: `ios/App/Assets.xcassets` currently contains only `AppIcon.appiconset` and has no `AccentColor` entry, so create one set to the snow accent (`#0A6B5C`). That alone fixes the stock-blue default at the 10 literal `Color.accentColor` sites; you do not need to rewrite those call sites in this task. The nine unstyled `.borderedProminent` sites are AC7's problem and belong to the surfaces that adopt buttons, not here.

Do **not** migrate the four colour-carrying `*Spec` enums in this task — extraction accompanies adoption (AC16). Leave them; T1.10 and later phases dissolve them.

You changed `project.yml`, so the Release build must run even though your logic is host-tested: `MT_RELEASE_GATE_MODE=build ./scripts/sim-lock.sh ./scripts/release-gate.sh`.

---

### T1.2 — Newsreader font provider and OFL licence entry

- **Issue:** #467 · **Spec section:** §4
- **Acceptance criteria:** AC4, AC5 (provider API only), AC6, AC27 (Newsreader scaling)
- **Depends on:** T1.1
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed

**Builder brief.** Ship the story voice.

The tree has **no custom fonts at all** today: no `.ttf`/`.otf` in the repo, no `UIAppFonts` key in `ios/App/Sources/Info.plist`, no font registration calls, and `UIFontMetrics` appears exactly once (`MapScreen.swift:8303`, scaling a hand-built `UIFont` for `.caption2`). You are establishing this path, not extending one.

Acquire Newsreader (Production Type, SIL OFL 1.1) and ship **static named instances, 3–4 cuts spanning the optical range — not the variable font file**; iOS variable-font APIs are unreliable and the spec rules them out. Register via `UIAppFonts`. The provider lives in `DesignSystem` and exposes the story roles by name (display lines, sheet titles, place names, list-row titles) plus italic for evocative sub-lines. Every cut is scaled through `UIFontMetrics(forTextStyle:)` with the text style matched to the design size — a raw point size that does not scale is a defect (AC27).

The provider must also express the machinery voice (SF) so that AC5 is expressible as an API distinction rather than a convention: a caller picks a *role*, not a font. On-map labels stay sans and are not your concern — they are MapLibre style layers, not SwiftUI text.

AC6 needs **no About-screen code change**. `AboutView` (`MapScreen.swift:7968`) loads `ios/App/Sources/OSSCredits.json` (`:8002`) and renders each entry; that file already contains a full OFL-1.1 entry for the Noto Sans glyph mirror with the complete licence body inlined in `notice_text`. Add a Newsreader entry following that exact pattern (`license_spdx: "OFL-1.1"`, licence text in `notice_text`).

`Info.plist` and bundled resources changed, so run the full gate, not just host tests.

**Licence discipline:** ship the OFL text with the fonts, and do not rename the font files in a way that violates the OFL's Reserved Font Name clause. If the OFL copy you obtain differs from the one already in `OSSCredits.json`, use the one shipped with the font you actually bundle.

---

### T1.3 — Core component styles A: the three buttons and the chip family

- **Issue:** #467 · **Spec section:** §5
- **Acceptance criteria:** AC7 (styles exist), AC10, AC14 (icon convention in these components), AC29
- **Depends on:** T1.1
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed

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
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed

**Builder brief.** The remaining core components in `DesignSystem`.

**Sheet pattern:** grabber, 22pt top radius, `surface` token background, medium/large detents, one close-affordance convention. Today's sheets mix `.ultraThinMaterial` and `.regularMaterial` backgrounds; your pattern replaces both with the token. **Reduce Transparency must swap blur for solid `surface`** (AC26) — build that into the component so no adopting surface can forget it.

**Rows:** exactly two — raised card-row (`surfaceRaised`, 14pt radius) for hero items, and hairline row for lists.

**Toast/pill family:** one component that can express all four of today's bespoke views. They currently disagree on every axis, which is the defect: download-progress pill (`MapScreen.swift:3365`, `.ultraThinMaterial` + `Capsule`, `.caption` semibold), location-off banner (`:4039`, `.ultraThinMaterial` + `Capsule`, `.caption2` semibold), nearby prompt (`:4117`, `.ultraThinMaterial` + `RoundedRectangle(cornerRadius: 10)`, `.caption2`, with an embedded `.borderedProminent` button), undo toast (`:3135`, `.regularMaterial` + `Capsule`, `.callout` medium, with a `.bordered` button). Your family must cover: text-only, text + one action, and text + action + dismiss. **Do not migrate the four call sites here** — that is T1.7.

**Progress:** one language, a thin accent bar on a hairline track, used by both list progress and download progress. It **carries a count** (AC28): never colour or bar-length alone.

Host tests plus renders (390×844 and an AX variant, HTML committed).

---

### T1.5 — The map theme consumes the material sheet

- **Issue:** #467 · **Spec section:** §8
- **Acceptance criteria:** AC3 (pin/track constants), AC17
- **Depends on:** T1.1
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed

**Builder brief.** Make map and UI share one colour source.

**Read this first: there is no `PaperStyle` type.** The file is `ios/Sources/MakingTracksMapStyle/PaperStyle.swift`; the type inside is `public struct MapTheme` at line 51, exposing hex-string colours (`background`, `land`, `parks`, `water`, `roads`, `boundaries`, `labels`, `labelHalo`) plus widths and flags, with four static presets (`.snow`, `.definedPaper`, `.streetContrast`, `.verdantKL`), `allCandidates` (`:174`) and `named(_:)`. Consumers: `ios/App/Sources/Map/MLNMapViewRepresentable.swift:166` for layer construction, and `MapScreen.swift:3333` (`selectedTheme`) plus the theme-picker UI around `:7849`–`:7890`.

Derive **`MapTheme.snow`** from the `DesignSystem` snow material sheet — `ground`→land, `water`, `park`, `road`/`roadMinor`, and the label colours — so the map and the app surfaces read the same tokens (AC17).

**Leave the other three presets and the theme picker alone.** The spec says the four existing paper themes "fold into the material system … decided in the material architecture issue with a migration for the stored `map.theme.id`", and that migration is DS-7 #473, out of this phase. Deleting or rewiring the presets now would break the picker and its UITests (`ios/App/UITests/MakingTracksCoreLoopUITests.swift:2427`–`3246`) for no in-phase benefit. This is a taste guess — flag it in your PR body with that alternative stated.

Also collapse the pin and track constants onto the sheet's constant block (AC3): `PinLayers.pinColor` (`ios/Sources/MakingTracksMapStyle/PinLayers.swift:4`) and `TrackLayers.lineColor` (`ios/Sources/MakingTracksMapStyle/TrackLayers.swift:9`, which is the duplicate of the `#2d8c83` teal typed as RGB floats at `MapScreen.swift:1808`). Pin colour must remain `#E4572E` and must stay identical across material columns — pins never theme, so wire it so a future material *cannot* recolour it.

Fold-or-file note: `TrackLineStyle` (`ios/Sources/MakingTracksMapStyle/TrackLineStyle.swift:3`) has no call sites outside `TrackLayers.swift`. Do not assume the app constructs it.

`MapTheme` is in a SwiftPM target, so its tests are host-only (`cd ios && swift test`), but map rendering changed — run the full gate and confirm the map still renders in the simulator.

---

### T1.6 — IA shell: two doors replace the hamburger, chrome reduction, bare attribution

- **Issue:** #468 · **Spec section:** §2
- **Acceptance criteria:** AC18, AC19, AC20, AC22, AC23, AC26/AC27/AC29 for the chrome and door surfaces
- **Depends on:** T1.1, T1.3, T1.4
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `greptile` + `opus` — **the phase's highest-risk task**
- **Status:** unclaimed
- **Ruled render:** `docs/design/design-system/ia-doors.png` — certifies the **door pattern only**. Its row list predates a ruling: Offline maps and Coverage live in **Settings**, and a Search slot joins the World door. Spec §2 is canonical.

**Builder brief.** Replace the hamburger and its modal menu with two door pills, without losing a single destination.

What you are deleting, in full: the hamburger button in `shellChrome` (`MapScreen.swift:3343`–`3387`, id `map.menu`, glyph `line.3.horizontal` sized by `MapHomeChromeSpec` at `:12`); the sheet presentation at `:2920`; `AppMenuSheet` (`:5058`–`5191`) with its `NavigationStack` and `AppMenuRootView` root rows (`:5280`–`5350`: `menu.row.lists` :5289, `menu.row.tracks` :5297, `menu.row.offline-maps` :5303, `menu.row.settings` :5311, `menu.row.about` :5319) and the per-destination Done button helper (`:5155`, id `menu.done`).

What must survive, because deleting the menu does not delete these destinations. `MenuDestination` (`:740`) has seven cases; each needs a home:

| Destination | Where it goes | Notes |
|---|---|---|
| `.settings` → `SettingsView` (`:7141`) | World door, quiet bottom row | Screen unchanged (DS-6 #472 owns its rebuild) |
| `.about` → `AboutView` (`:7968`) | World door, quiet bottom row | Screen unchanged |
| `.offlineMaps` | **Settings**, not a door | Already reachable from Settings' "Manage offline maps" row (`:7230`, id `settings.storage.manage`, routing to the same `MenuDestination.offlineMaps` at `:7915`). Per spec §2 this is now its only menu home. |
| `.lists` → `ListsView` (`:5352`) | Tracks door | See below |
| `.tracks` → `TrackListDetailDeepLinkView` (`:5237`) | Tracks door | See below |
| `.listDetail(Int64)` | Deep link only | Reached from list-mode "Back" (`:3400`) |
| `.diagnostics` | Inside Settings, unchanged | Never was a root row — reached from `settings.diagnostics.export` (`:7240`) |

**The Tracks door routes to today's surfaces in this task.** Its contents are restructured in T1.8. If you delete the hamburger and leave the Tracks door empty, the app regresses between two merges — so the door opens onto the existing Lists / My-tracks destinations, and T1.8 replaces that content. Say so in your PR body so the reviewer knows the door is deliberately provisional.

**The World door's Scope row routes to the existing Layers sheet, unchanged.** Entry today is `layersButton` (`:3953`, id `map.layers`) opening `LayersSheet` (`:8519`, detents medium/large) which holds the include-hidden toggle (`:8527`), coverage shading (`:8540`) and the category toggles (`:8554`). Merging that with the list-mode filter chips (`:3465`, which open a *different* sheet, `TrackFilterPickerSheet` at `:8408`) is DS-3 #469 and **out of scope**. Whether the standalone layers button survives alongside the door's Scope row is a taste call — flag your choice.

**Deep links that must keep working.** `AppShellModel` (`:787`, extended `:2276`) is the source of truth. Five entry points: `openMenu()` (`:794`, dies with the hamburger), `openListDetailDeepLink` (`:801`, called from list-mode Back at `:3400`), `openListsDeepLink` (`:2277` — **no production caller; exercised only by `AppShellTests.swift:83`**), `openTracksDeepLink` (`:2284`, called from the place card's "Manage visits" at `:3047`), `openOfflineMapsDeepLink` (`:2291`, called from **two** places: the empty-region card's action at `:5014`/wired `:2837`, and the download-progress pill at `:3367`). AC22 is graded on all of these still resolving. The dead `openListsDeepLink` is a fold-or-file call: small and encapsulated, so remove it in this PR and log the issue, or keep it and say why.

**Chrome, reduced to four things** (AC19). Today's overlay stack is chained `.overlay(alignment:)` calls at `:2795`–`:2919`.

- **Attribution is currently a pill and must stop being one.** `attributionText` (`:3806`) is `Text(verbatim: "© OpenStreetMap")`, `.caption2` semibold, in a `Capsule()` filled with `.ultraThinMaterial`. Replace with bare muted-ink text at 11pt, no background. Keep it visible — it is an ODbL compliance requirement, not decoration — and keep id `map.openstreetmap-attribution`. MapLibre's own attribution and logo stay hidden (`MLNMapViewRepresentable.swift:230`–`231`).
- **Locate button** (`:4055`, id `map.locate-me`) moves onto the token surface treatment; its three tracking-mode icons and labels (`:4069`–`:4093`) are unchanged.
- **Compass — see Open flag OF1.** No compass exists in the Swift sources. MapLibre's `MLNMapView` has a built-in one that appears on rotation and is never configured. Best guess: adopt the built-in and configure its position to sit in the reduced chrome cluster, rather than building a bespoke control. Flag it.
- **Doors** are pill buttons on `surface` with a hairline border, soft shadow, SF 600 text and an accent stroke icon (spec §5).

**Search slot — see Open flag OF2.** Best guess: the door's layout reserves the position but renders no row until DS-11 #477, because a visible dead row invites taps that do nothing. Flag it with the alternative (a disabled row) stated.

**The test migration is the bulk of this task and the reason for the Greptile slot.** `ios/App/UITests/MakingTracksCoreLoopUITests.swift` has roughly 70 tests, many driving the menu through a helper `openAppMenu(in:)` (first use around `:850`) and asserting on ids `map.menu`, `menu.row.lists`, `menu.row.tracks`, `menu.row.settings`, `menu.row.offline-maps`, `menu.row.about`, `menu.done`. Representative cases to re-point rather than delete: `testMenuAboutCarriesCreditsAndMapAttributionIsInert` (`:2203`) and `testOfflineProgressChipDeepLinksToOfflineMaps` (`:2234`). In unit tests, `testMapHomeChromeUsesFilterGlyphAndChiplessMenuSpec` (`ios/App/Tests/AppShellTests.swift:47`) asserts `MapHomeChromeSpec`'s hamburger constants directly and must be rewritten, and the `AppShellModel` routing tests at `:56`, `:71`, `:80`, `:89`, `:99`, `:109` must be re-pointed at the new routing.

**Re-point tests; do not delete them to get green.** A test deleted because its identifier moved is lost coverage of a destination that AC22 says must still work. If a test genuinely no longer describes a behaviour that exists, say so explicitly in the PR body and name what replaces its coverage.

Full gate required, plus renders of the map home with both doors and each door open.

---

### T1.7 — Contextual chrome adopts the toast/pill family

- **Issue:** #468 · **Spec section:** §2, §5
- **Acceptance criteria:** AC11, AC23, AC26, AC29
- **Depends on:** T1.6
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed

**Builder brief.** Migrate the four bespoke contextual views onto T1.4's family.

Depends on T1.6 rather than running beside it **on purpose**: the download-progress pill lives inside `shellChrome` (`MapScreen.swift:3365`), which T1.6 rewrites wholesale. Two builders editing that region of a 10k-line file concurrently is a merge conflict that costs more than the lost parallelism, and the Codex budget this phase does not have room for avoidable rework.

The four call sites and their current inconsistencies are inventoried in T1.4's brief. Migrate each to the family, preserving behaviour and every accessibility identifier: `map.download-progress` (`:3365`, taps into `openOfflineMapsDeepLink`), the location-off banner (`:4039`, with its embedded `LocationSettingsButton`), `map.nearby-prompt` with `.seen` and `.dismiss` (`:4117` — its embedded `.borderedProminent` becomes a DS filled button, killing two of the nine stock-accent sites), and the undo toast with `place-card.hide.undo` (`:3135`, whose `.bordered` button becomes quiet or tonal).

AC23 is behavioural: each must appear only when it has something to say. Preserve the existing auto-dismiss semantics — `testHiddenToastAutoDismissesWithoutUnhidingPlace` (`ios/App/UITests/MakingTracksCoreLoopUITests.swift:2044`) and `testHiddenToastUndoRestoresHiddenPlace` (`:2059`) pin them, and an undo toast that dismisses differently is a data-loss-adjacent regression, not a styling nit.

Reduce Transparency: these are the surfaces most likely to be blur-backed today (three use `.ultraThinMaterial`, one `.regularMaterial`), so AC26 lands here concretely.

Full gate plus renders of each of the four states.

---

### T1.8 — Tracks door contents: unify #266, My tracks hero, Lists with progress

- **Issue:** #470 · **Spec section:** §2
- **Acceptance criteria:** AC21 (My tracks and Lists parts), AC24, AC28, AC26/AC27/AC29
- **Depends on:** T1.6, T1.4
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed
- **Ruled renders:** `coherence.png` frame 4, `ia-doors.png` frame 3

**Builder brief.** Build the Tracks door's real contents, and actually deliver #266's unification.

**#266 is unbuilt — this is not a restyle.** Today `.lists` and `.tracks` are two distinct `MenuDestination` cases (`MapScreen.swift:740`) reaching the same `ListDetailView` for the system track list by two paths: `.tracks` → `TrackListDetailDeepLinkView` (`:5237`), which fetches the list where `isSystem && kind == PlaceList.trackKind` (`:5275`, kind defined at `ios/Sources/MakingTracksData/Models/PlaceList.swift:7`); and `.lists` → `ListsView` (`:5352`), whose row for that same system list navigates to the same detail view (`:5390`). `ListDetailView` (`:5508`) then branches on `isTrackListDetail` (`:5562`) into `trackListPage` versus `collectionListBody`. **UITest `testTracksMenuAndListsMyTracksReachSameScreenIdentity` (`ios/App/UITests/MakingTracksCoreLoopUITests.swift:1406`) currently asserts the drift** — it must be rewritten to assert the single surface, not two paths agreeing.

The door presents:

- **My tracks hero** — raised card-row (T1.4), Newsreader title, SF metadata. Lands on the list-detail surface with **Retrace one tap away**. "Retrace" is spec vocabulary with no code symbol: the control is the "Map" button in the track summary card (`:5866`) or "Show on map" in plain list detail (`:5781`), both id `lists.detail.show-map`, calling `onShowOnMap` → `showListOnMap` (`:4528`) which sets `activeListMap`. Keep that id.
- **Lists** — hairline rows with per-list progress. **The query already exists:** `AppDatabase.listProgress(listID:)` (`ios/Sources/MakingTracksData/Derivations.swift:315`) returns `ListProgress(visited:total:)` (`Models/PlaceList.swift:37`), with an async wrapper `MapScreenModel.listProgress(listID:)` (`MapScreen.swift:9947`) and existing UI use in `ListsView.listRow` (`:5449`). No new query needed. Render it with T1.4's progress bar **and its counts** — AC28 forbids bar-length alone.
- **Loved places** and **Hidden places** rows are **T1.9**, not this task. Leave their positions out or inert, and say which in your PR body.

AC24 is a regression gate, not new work: one surface, list-detail landing, verdict edits fold in, membership protected. The system "My tracks" list is protected in the data layer (`ios/Tests/MakingTracksDataTests/InteractionsTests.swift:99` `testMyTracksSystemListIsProtectedAndUsesTrackKind`; `ListsView` already gates delete on `!list.isSystem` at `:5404`) — do not weaken that.

Existing coverage to keep green or consciously re-point: `testTracksMenuOpensUnifiedMyTracksVisitEditor` (`UITests:977`), `testMyTracksListDerivesDistinctVisitedPlacesWithoutStoredMembership` (`ios/Tests/MakingTracksDataTests/DerivationsTests.swift:290`), `testMyTracksProgressCountsOnlyValidatedRenderedRows` (`:341`), `testListProgressCountsSnapshotBackedRowsShownByTheList` (`:52`).

Full gate plus renders of the door and the hero landing.

---

### T1.9 — Loved and Hidden places become browsable surfaces

- **Issue:** #470 · **Spec section:** §2
- **Acceptance criteria:** AC21 (Loved and Hidden parts), AC25, AC26/AC27/AC29
- **Depends on:** T1.8
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus` (a Greptile slot here is fable's call — see *Review budget*)
- **Status:** unclaimed

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
- **Acceptance criteria:** AC30, AC31, AC32, AC33, plus AC15/AC16 for this surface and AC26/AC27/AC29
- **Depends on:** T1.1, T1.3
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `opus`
- **Status:** unclaimed — **stretch: claim only when no in-scope task is unclaimed**
- **Ruled render:** `coherence.png` frame 3

**Builder brief.** Move the place card onto tokens. This is the phase's first real *adoption*, so AC16 applies: extraction accompanies adoption.

**`PlaceCardVisualSpec`** (`MapScreen.swift:24`–`99`) holds exactly **13** `Color(red:green:blue:)` literals at `:41`–`:53` — the one count in the issue text that is accurate: `cardBackground` (:41), `mediaBackground` (:42), `neutralActionBackground` (:43), `primaryActionBackground` (:44), `loveActionBackground` (:45), `warningActionBackground` (:46), `disabledActionBackground` (:47), `primaryText` (:48), `secondaryText` (:49), `linkText` (:50), `loveText` (:51), `warningText` (:52), `disabledText` (:53). Map each onto a token; where no token exists (love and warning tones), that is a genuine gap — flag it rather than inventing a colour outside the sheet, because AC15 forbids a literal and the sheet is the only legal home.

**The fade seam (AC30) is worse than the issue says.** `placeCardBottomFade` (`:8735`) uses `Color(.systemBackground)` at **both** stops (`:8738`, `:8739`) — there is no cream stop at all. Because the card is force-lit (see below), `systemBackground` resolves to opaque white against the cream `cardBackground` used at `:8644` and `:8849`. Both stops become the card surface token.

**Action bar (AC31).** `actionBar(_:)` (`:8821`) dispatches through `actionButton(_:card:)` (`:8855`) to `saveButton` (`:8912`), an inline `.seen` case (`:8860`), `hideButton` (`:8930`), plus `unhideButton` (`:8941`), love/unlove (`:8869`), unsee (`:8889`) and `seenDisabled` (`:8899`). Every one is `.buttonStyle(.plain)` with styling applied manually in `actionLabel(_:title:)` (`:8952`), keyed off `PlaceCardVisualSpec.tone(for:)`. Replace with the T1.3 styles: **Save tonal, Seen filled, Hide quiet.** The spec allows at most one filled button per screen — Seen is it, so check no other filled control coexists on the card.

**Photo slot (AC32).** `mediaSlotHeight = 132` (`:37`) is applied at both `PlaceCardMissingPhotoSlot.body` (`:9148`) and `PlaceCardPhotoSlot.body` (`:9191`). The dead slot is `PlaceCardMissingPhotoSlot` (`:9135`), reachable only through `photoSlot(_:)` (`:8778`) behind `PlaceCardVisualSpec.showsMediaSlotWhenPhotoMissing`, which is a `static let false` (`:34`) never written anywhere — so the branch is **unreachable dead code**, and the type has no other call site. Retire the flag, the branch and the type together.

**Open flag OF4 gates the rest of AC32.** There is **no reference to #376 anywhere in the tree** — no comment, no TODO, no partial work — so the "ruled adaptive height" is not recorded where you can read it. Read issue #376 itself for the ruling. If #376 does not state a concrete rule, do **not** guess a layout algorithm: adaptive photo height is a system-wide visual change and a wrong guess is expensive to rework, which is exactly the taste-call case that escalates. Deliver the rest of the task and flag AC32's height rule as blocked on a ruling.

**`.preferredColorScheme(.light)` (AC33)** appears exactly once in the whole tree, `:8646`, on the card sheet's modifier chain — so it forces the card *and everything inside it, including the fade* into light appearance. Removing it is what makes the card able to render in mud later; verify the card in dark system appearance after removal, since nothing else was protecting it.

**The test that will fail, and must be rewritten rather than deleted.** `testPlaceCardVisualSpecMatchesApprovedCardLayout` (`ios/App/Tests/AppShellTests.swift:11`) asserts every one of the 13 colour literals by exact value, plus the geometry constants including `showsMediaSlotWhenPhotoMissing` and `mediaSlotHeight`. Rewrite it to assert the card resolves its colours **from tokens** — that is the invariant worth pinning now. `testPlaceCardActionTonesFollowRuledSlotsWithoutDestructiveHide` (`:35`) asserts the tone mapping and needs re-pointing at the new styles. **There is no snapshot framework in this repo**, so nothing else will catch a visual regression: your renders are the evidence.

Full gate plus renders of the card in snow, default and AX sizes.

---

## Open flags — Rob's, raised by decomposition

These are judgment calls the ratified spec does not settle. Per the taste-call protocol each has a best-guess so nothing blocks, but a ruling would be cheaper than rework.

- **OF1 — Is there a compass?** Spec §2 lists a compass in persistent chrome (AC19), but no compass control exists in the Swift sources; MapLibre's `MLNMapView` has a built-in one that appears on rotation and is never configured or hidden. Best guess in T1.6: adopt and position the built-in rather than building a bespoke control. A bespoke themed compass would be new work nobody has scoped.
- **OF2 — What does a "reserved" Search slot look like?** Spec §2 says the World door "reserves its place" for Search. Best guess in T1.6: the layout reserves the position and renders no row until DS-11 #477, on the grounds that a visible dead row invites taps that do nothing. Alternative: a visibly disabled row that advertises Search is coming.
- **OF3 — What happens to the four existing paper themes this phase?** Spec §3 says they "fold into the material system … decided in the material architecture issue with a migration for the stored `map.theme.id`" — but that migration is DS-7 #473, out of phase. Best guess in T1.5: derive `MapTheme.snow` from the snow sheet and leave `.definedPaper`, `.streetContrast`, `.verdantKL` and the picker untouched, so nothing breaks for no in-phase gain.
- **OF4 — #376's adaptive photo height is not written down anywhere reachable.** AC32 depends on it and the tree has no trace of the ruling. If issue #376 does not state a concrete rule, T1.10 delivers everything else and AC32's height rule waits for a ruling rather than being guessed.
- **OF5 — App-wide criteria are graded phase-scoped.** Spec §5, §6, §7 and §8 state absolutes ("no `.bordered` anywhere", "no colour or font literal outside the module", "Reduced Motion app-wide") that cannot hold while DS-3 and DS-6 through DS-12 are unbuilt. This graph grades them over the module plus the surfaces this phase adopts, marked **[phase-scoped]**. If the acceptance pass should instead grade them app-wide and record the remainder as known-failing, that is a different call and worth making now rather than at the acceptance pass.
- **OF6 — The epic's issue bodies carry several counts and claims the tree contradicts** (see *Where the issue text is wrong*), most consequentially that #266 is described as built when it is not. The issues are the record, so they should be corrected. Not done in this PR — flagged for fable.
