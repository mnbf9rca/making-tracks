# Phase 2 — Task Graph

Phase spec: [`docs/superpowers/specs/2026-07-25-design-system-and-ia-design.md`](../../specs/2026-07-25-design-system-and-ia-design.md) (ratified, merged as PR #465; amended by #524 and the amendment wave).
Epic: #466. Scope: **DS-3 (#469) + DS-6 (#472)** per the epic's phased work-list. Nothing else from the epic this phase.
Session rulings: **P2R-1 … P2R-10**, plus wireframe commissions **W-1** and **W-2**, from the Phase 2 opening design session (2026-07-31). **Canonical text: [`design-session-rulings.md`](design-session-rulings.md) at `9fa91d482f8de857f10e4b82693e55209dd2e0fb`** (PR #563, authored from Rob's in-session text). Every quotation in this graph is from that file at that SHA; no ruling is quoted from a relay. P2R-2 and P2R-5 were flagged to Rob individually and confirmed in his own words — **no ruling here rests on silence.** Session input packet: [`design-session-input.md`](design-session-input.md).
Frozen renders: [`docs/design/design-system/`](../../../design/design-system/) — three files, unchanged. **This phase authors two new wireframes (W-1, W-2) under the mockup gate; they are not frozen renders until Rob rules them.**

Stall threshold: **45 min** (phase-cycle spec §2.3 default).
Builder pool: **codex1–codex4**.
Greptile allocation (spec §7, 50/month): **one slot recommended, on T2.7.** Reasoning under *Review budget*; the second-slot question is flagged there rather than spent.

**Operating rules are not restated here.** Branch/PR mechanics, gates, evidence law, review law, the checkpoint protocol, the taste-call protocol and the status vocabulary live in [`docs/process/coordination.md`](../../../process/coordination.md) and `AGENTS.md`, graduated there from Phase 1 by #560. Read them as part of your brief. Phase-1-specific traps that still bind (`xcodegen` is manual; a docs-only PR does not run the iOS gate; the frozen render set is three files and a claim about "the render" names its file) are in [`phase-1/tasks.md`](../phase-1/tasks.md) → *Operating rules*.

Two additions to the status vocabulary, for wireframe rows only: `claimed → branch → drawn → validated → PR open → awaiting ruling → ruled`. A wireframe row is **not** complete when its PR merges; it completes when Rob rules it, and the rows gated on it unblock at that moment and not before.

---

## Provenance

Every acceptance criterion below carries a **per-row provenance cell**, and it is the cell — not this preamble — that says what each criterion rests on. `ruled` means the rulings file states it at `9fa91d4`; `reviewer-derived` means **this graph proposes it and no ruling states it**, so it is a proposal for planner and Rob rather than law. Check the cell before treating a criterion's wording as binding.

An earlier relay of these rulings arrived with dropped characters and is **superseded and discarded**; nothing in this graph is built on it. Where the ruling's own words decide a question, they are quoted verbatim from the file above; everywhere else the graph states substance and says whose it is.

---

## Planner landing record (2026-07-31)

Drafted by reviewer; landed by planner after independent verification. Every load-bearing tree claim was re-checked against `ios` at `9fa91d4` before landing: the `trail` rename (no `trackLine` symbol survives), `disabledAlpha`/`pressScale` live in sheet and spec, `hiddenPinColor`'s raw literal at `PinLayers.swift:6`, the shipped Explore surface and vestigial LayersSheet plumbing, the five `isDefault` pins, the coverage storage key, the spec's 19×19 door-pill row (OF3 is real), and the 17-beside-15 and `accentDeepContainer` table rows. One figure corrected at landing: the identifier blast radius greps at **36** `map.layers.*` references, not 37 — re-count at claim; it is a blast-radius indicator, not a contract.

Decisions the draft routed to planner, taken at landing:

- **T2.1 item 3 (`disabledAlpha`/`pressScale`): cross-reference, not duplicate rows.** The metrics table gains a pointer to the §3 rows; no figure gets a second home. P2R-9's row list is discharged for these two by the already-landed §3 rows, and the PR body says so.
- **Greptile: one slot, on T2.7, approved.** The **second slot is not spent** — T2.8's rename is mechanical and grep-verifiable; the flag stands and the question reopens only if T2.8's diff grows non-mechanical teeth.
- **codex-r placement approved as recommended**: spec attack on T2.1's amendment text plus this graph before the build rows claim; acceptance pass at closeout.
- **The wireframe status vocabulary is adopted**: `claimed → branch → drawn → validated → PR open → awaiting ruling → ruled`; rows gated on a wireframe unblock at **ruled**, not merge.
- **OF1 is with Rob** (raised in planner's chat, per the gate law); OF2's stated default stands; OF3 carries to the next session; OF4/OF5 are W-1's to draw and Rob's to rule.

---

## Acceptance criteria

Numbered so tasks can own subsets and the acceptance pass has something to grade against. Every AC traces to a session ruling, an issue's Done-when clause, or ratified spec text; traces are in the Source column.

| AC | Criterion | Source | Provenance |
|---|---|---|---|
| **AC2.1** | The component-metrics table carries `rowRaised` = 20 and `rowQuiet` = 18 as **ratified** rows, on `ia-doors`' frozen figures, each paired to its typography role and scaled like every role. Functional names, never size names. | P2R-2(a) | ruled |
| **AC2.2** | `IconRole` expresses exactly **five** roles and the closure test fails on a silently added case. P2R-2(d): *"the set is again closed (now at five); additions only by session ratification against frozen-render evidence."* | P2R-2(a), P2R-2(d), R11 pt 2 | ruled |
| **AC2.3** | The press inset is a **scaled metric anchored to the control's paired typography role**; the shipped `1pt` literal (`ControlStyles.swift:199`, `.textInset(points: 1)`) is retired. Perceptibility is constant across Dynamic Type, not constant in points. | P2R-1; ruling verbatim in phase-1 `tasks.md` § *The component-metrics table's batch* item 1 | ruled |
| **AC2.4** | No `.font(…)` literal survives in the Phase 1 adopted IA-shell surfaces; `MapDoorRowIconGlyph` resolves through `rowRaised`/`rowQuiet`. **#520 closes and Phase 1 acceptance completes at 35/35.** Point-of-use coverage fails if the site bypasses the vocabulary again — a definition-only test is insufficient. | P2R-2(b), #520 Done-when | ruled |
| **AC2.5** | The A8 Explore **Scope-row** metrics carry **ratified** provenance in the spec's component-metrics table — 52pt default / 86pt AX, full geometry as tabled — ratified *"as system law for this row class"*, i.e. binding on the row class wherever it appears, not on this surface alone. A DS-3 deviation from a ratified default *"deviates through its own gate with the delta named — never silently."* | P2R-4 | ruled (residual boundary → **OF2**) |
| **AC2.6** | `hiddenPinColor` is read from the sheet's **constant pin block** rather than defined as a module literal, as `pinColor` already is. The pin-pop gate does not apply to it. | P2R-9 rider; spec §8 ("pin layer constants come from the same sheet's constant pin block") | ruling clean; **code-side reach is reviewer-derived** |
| **AC2.7** | **All four** scope choices persist across launches — category selection, include-hidden, show-saved, coverage shading — as *"one versioned scope record (Data §11 applies)"*, defaults **hidden OFF, saved ON, coverage ON**. Data §11 is load-bearing, not decorative: the reader knows its maximum understood version and **refuses or degrades gracefully — never silently misreads** a newer or older record. | P2R-5; `docs/PRINCIPLES.md` → Data 11 | ruled |
| **AC2.8** | Whenever effective scope differs from default, the Explore door wears a **scope-active indicator** — *"the map may never look mysteriously thin with the reason hidden behind a door."* | P2R-5(a) | ruled |
| **AC2.9** | The picker carries a quiet **Clear-scope row** restoring defaults in one tap — *"persistence with a visible one-tap exit, nothing destroyed."* | P2R-5(b) | ruled |
| **AC2.10** | Ratified general law: *"scope filters govern discovery surfaces; story surfaces (Journal: tracks, lists, loved, hidden management) are exhaustive over their own domain and NAME overlaps instead of filtering them."* `Derivations.swift` stays untouched by this filter, **permanently**. Pinned by test, not by convention. | P2R-8, generalising the pinned `lovedPlaces()` behaviour | ruled |
| **AC2.11** | One Scope surface: the category toggles, the three scope controls and the list-mode floating filter chips are reachable from a single picker. The floating chip overlay and any surviving Layers-sheet plumbing are dismantled. | #469 | issue text; **merge boundary → OF4** |
| **AC2.12** | The relocated Scope rows carry **A1-convention identifiers**, named in W-1's annex, and the contract rename happens **once, in one commit, with nothing in flight**. | P2R-6; A1 convention (`phase-1/amendment-wave.md` § A10 → *Ownership boundary*) | ruled |
| **AC2.13** | Derived hit targets on the picker **tile** per R10 — `min(11pt, gap/2)` per side, every screen point mapping to exactly one control — with R10's rider intact: tiling only for reversible, immediately-legible actions; destructive/navigational/commitment controls keep full 44pt **without exception**. W-1's instruction on the numbers is *"Derive the tiling numbers at the gap the drawn surface actually has"* — the worked ~30pt arithmetic assumes an 8pt gap and is illustrative, not ratified. | R10 + rider; W-1 | ruled |
| **AC2.14** | Settings is regrouped: **Appearance, Offline maps** (moved in; the map's contextual deep links intact), **Coverage, Map & data, Location, Diagnostics, Replay welcome** — on DS-1 rows/sheets, **no system `List` chrome**. | W-2, #472 | ruled |
| **AC2.15** | The map's contextual deep links into Offline maps survive — the download-progress pill and the empty-region card's download action both still resolve. | W-2; #472 Done-when; AC22 lineage | ruled |
| **AC2.16** | About is rebuilt: story + privacy promise up top, then **Software licences** (OSS credits incl. Newsreader OFL text) and **Data licences** (OSM, Wikipedia, per-region sources) as proper sub-areas. | W-2, #472 | ruled |
| **AC2.17** | Each wireframe record carries **measurements beside every frame** and the **constraint structure enumerated before figures are adopted**; a general bound states its qualifier; a clearance states its scope. | W-1/W-2 preamble; Evidence and review law (`coordination.md`) | ruled |
| **AC2.18** | **Both** wireframe records carry this sentence, in these words: ***"this surface does not pair a filled action with a state cluster; the R16 proof obligation travels to the first surface that does."*** The obligation may not lapse in silence. | P2R-7 | ruled — **verbatim requirement** |
| **AC2.19** | Standing a11y gates hold for the surfaces each task touches: Dynamic Type through AX5 without clipping, VoiceOver labels/values and real accessibility actions, Reduced Motion and Reduce Transparency, never colour-alone. **[phase-scoped: per-surface; the app-wide sweep is DS-10 #476]** | spec §7; AC26–AC29 lineage | ruled |

---

## Explicit non-goals — do not build these

| Out of scope | Issue | What that means for you |
|---|---|---|
| Mud material, the Appearance **picker**, `map.theme.id` migration | DS-7 #473 | Settings gains an **Appearance group**; the existing "Map theme" section moves into it **unchanged**. Do not fold the four presets, do not touch the stored theme id, do not delete the picker's UITests (`MakingTracksCoreLoopUITests.swift:2427`–`3246`). |
| Search | DS-11 #477 | The Explore surface reserves the top slot and **renders nothing** (R2). No disabled row, no placeholder. |
| Diagnostics / blocking surfaces re-skin | DS-9 #475 | Settings' Diagnostics **row** is regrouped; the diagnostics screens behind it are not re-skinned. |
| App-wide a11y sweep | DS-10 #476 | AC2.19 binds the surfaces your task touches, not the app. |
| Onboarding re-skin | DS-8 #474 | Settings' "Replay welcome" row routes to the existing flow. |
| Coverage-boundary affordance (covered-but-empty vs no-data-here) | #360 | A Settings **Coverage group** is not the #360 affordance. Do not build map-side coverage semantics here. |
| Map-fetch loading hairline | #359 | Unchanged from Phase 1. |
| Future materials | DS-12 #478 | — |

---

## Where the tree differs from the commission

Grounded against `ios` at `2066dda` (#562); the sole advance to the landing head `9fa91d4` is the rulings file itself (docs-only, verified by diff). **Build against this file and the tree.** These are not corrections to the rulings — the rulings are ruled — they are corrections to what the rulings still leave to do.

| The commission's shape implies | The tree says |
|---|---|
| The one-shot spec §3 amendment is outstanding work. | **Most of it has already landed.** #524 plus amendment-wave rows A3/A4 put `trail` in the sheet **and the code** (`MaterialTokens.swift:98`, `:147`, `:217` — the rename is done, `trackLine` is gone), `disabledAlpha 0.46` and `pressScale 0.98` as §3 rows (spec `:142`–`:143`) **and** as live token-sheet fields (`MaterialTokens.swift:153`–`154`, `:219`–`220`), `hiddenPinColor #767B82` as a §3 constant-pin-block row (spec `:132`), and the 17-beside-15 pairing constant as a §5 metrics row. The Saved-ON inversion is in the table as `accentDeepContainer`, marked **RATIFIED** (ratified by Rob 2026-07-31). **What is actually left** is enumerated in T2.1, and it is smaller than the commission assumes. |
| P2R-4 ratifies "the A8 Explore metrics". | It ratifies a **row class**, and the spec's *Measured A8 Explore frozen-render facts* table carries **seven** MEASURED rows (`:303`–`:309`) sharing one provenance stamp: sheet placement, default Scope control rows, default Scope **block rhythm**, default quiet destination row, AX sheet/labels/chips, AX Scope control rows, AX quiet rows. P2R-4's words are *"RATIFIED WHOLESALE as system law for this row class"* — so **two rows ratify, five stay MEASURED**, and the two that ratify bind wherever that row class appears, not only on this surface. The block-rhythm boundary is genuinely ambiguous — see **OF2**. |
| DS-3 builds a new Scope surface. | **The Explore Scope surface already exists.** A1/A8 shipped `ExploreDoorRootView` (`MapDoorShell.swift:429`–`575`) with the three scope toggle rows, the category chip flow at the ratified 6pt gap with R10 neighbour-gap tiling already wired (`ExploreCategoryChipTopology`, `:92`–`:124`), and the quiet Settings/About destination rows. **`LayersSheet` no longer exists** — only vestigial plumbing names survive (`layersSheetVisibilityBinding`, `updateLayersSheetVisibility`, `MapScreen.swift:3882`–`3890`). DS-3 is a **rebuild in place plus the chip merge**, not a green field. |
| DS-3 "dismantles floating chips". | The floating chips are `ListMapFilterChips` (`MapScreen.swift:1298`, rendered at `:3390`) and they are **list-mode**, scoped to an active list's `TracksVisitFilter` — a **different state object** from discovery's `MapLayerVisibility`. A bridge already exists (`ListMapLayerVisibility.displayed/updating`, `MapLayerVisibility.swift`). Merging them is a **semantic** question, not a move — see **OF4**. |
| The identifier rename is a wireframe annex detail. | It is a 36-reference blast radius. `map.layers.*` appears **36 times** (planner grep at landing) across `ios/App/UITests` and `ios/App/Tests`: `show-hidden` ×9, `show-all-categories` ×8, `coverage-shading` ×7, `show-saved` ×4, `category.*` ×4, plus loose matches. One commit, nothing in flight — exactly as P2R-6 says, and the reason it says so. |
| A scope-active predicate exists to hang AC2.8 on. | `MapLayerVisibility.isDefault` (`MapLayerVisibility.swift:18`) is `!showHiddenPlaces && showSavedPlaces && visibleCategories == nil` — it **ignores `showCoverageShading` entirely**, and it is pinned by five assertions in `MapLayerVisibilityTests.swift`. Under P2R-5 coverage is a persisted scope choice, so `isDefault` cannot serve AC2.8 unchanged. Extending it changes what those five tests assert; that is the task's work, not an accident to discover. |
| Coverage shading is settled. | **It is ruled into two places.** P2R-5 makes it one of four persisted **scope** choices (default ON) living in the picker; #472/W-2 puts a **Coverage** group in Settings. See **OF1** — this is the one flag that can produce two homes for one control, which is the exact inconsistency debt P2R-5 exists to kill. |
| The closed set's pressure is 20 and 18. | There is a **third** figure. The ratified metrics table gives the **door pill icon as 19×19** (`ia-doors`), while the shipped `MapDoorButtonIconGlyph` renders `.iconRole(.inline)` = **15** (`MapDoorShell.swift:1262`–`1272`, landed by #529 and accepted). P2R-2 mints roles for 20 and 18 and closes the set at five; **19 is expressed by none of them.** See **OF3**. |

---

## Open flags

Decisions this graph cannot take. Each names the owner and what is blocked.

- **OF1 — Where does the coverage-shading toggle live? (owner: Rob, via planner. Blocks: T2.8 and T2.9 acceptance, not their claim.)** P2R-5 ratifies coverage shading as one of four persisted **scope** choices, default ON, in the Explore picker. #472 and W-2 give Settings a **Coverage** group. If both ship the same toggle, one control has two homes and they will drift; if the Settings group means coverage **data** (sources, downloaded coverage, the #360 territory) it is not a conflict at all. **Reviewer's reading, offered for correction:** the *shading* toggle is scope and stays in the picker; Settings' Coverage group covers coverage **data and downloads** and carries no shading toggle. Confirm at the W-2 gate, where it becomes visible.
- **OF2 — Does the Scope **block rhythm** travel with the ratified row class? (owner: Rob, via planner. Blocks: nothing — T2.1 has a stated default. Affects: T2.1's edit and T2.8's provenance.)** P2R-4 ratifies *"A8 Explore's measured Scope-row geometry"* — *"RATIFIED WHOLESALE as system law for this row class (52pt default / 86pt AX, full geometry as tabled)"*, That cleanly ratifies the two Scope-control rows (52pt default, 86pt AX) and cleanly leaves sheet placement, the quiet destination rows and the AX sheet/labels/chips row as MEASURED. **The one genuinely ambiguous row is *Explore default Scope block rhythm*** (18/11/14pt) — the rhythm *between* the Scope rows and their neighbours, not the rows themselves — and the ambiguity is not invented: the **AX** Scope-control row already carries its own `14/9/14pt block rhythm` **inside the ratified row**, so the default surface's rhythm sits outside a ratification its AX twin contains. **Reviewer's reading, and T2.1's default absent a ruling:** ratify the two control rows only, leave the rhythm MEASURED, and let T2.8 gate any use of it with the delta named — under-claiming a ratification is recoverable; over-claiming one puts a figure into system law that nobody ruled.
- **OF3 — The door pill's 19×19.** The ratified table says 19; the code says 15; the closed set now has five roles and expresses neither 19 nor a rule for it. Nothing in this phase's rows touches that site, and #520 does not cover it (#529 removed that literal by adopting `inline`). **Not blocking anything** — recorded so the next session meets it as a fact rather than discovering it as a third instance. P2R-2(d)'s anti-creep restatement is the thing it presses against.
- **OF4 — What exactly merges into the Scope surface from list mode?** `ListMapFilterChips` filters an **active list's** visits; the picker scopes **discovery**. Reading A: the picker gains a list-scoped section when a list map is active. Reading B: the floating chips stay, and #469's "merge" means the *category* chips only. **Reviewer's reading: A**, on #469's own words ("merge today's Layers sheet … and the floating filter chips into one Scope surface") — but the two filters are not the same kind of thing and W-1 is where that has to be drawn, so it is the wireframe's question to answer and Rob's to rule.
- **OF5 — Do the scope rows keep switches under R15?** The ratified row-class geometry describes a **44×28 switch with a 22pt knob** per scope control row (AX: 51×31 with a 25pt knob). R15's state morphology is ON = filled pill + filled glyph. P2R-7 describes this surface's controls as *"states and quiet verbs"* — which confirms they are **states**, and still does not say what a state row looks like when it is a row rather than a pill in a cluster. **Reviewer's reading:** ratifying the row-class geometry ratifies the switch as the scope-row control, and R15 governs state clusters rather than switch rows — but ratifying geometry is not the same act as ratifying morphology. W-1 must state which it drew and on what grounds. Not blocking; it is a W-1 requirement, recorded here so the validation pass has something to check against.

---

## Review budget

- **Sourcery** on every PR, no cap tracking.
- **reviewer (opus) design review** on every row that defines or changes a user-facing surface, and on **both wireframe rows** — where the review is the validation step between authoring and Rob's ruling, not an afterthought.
- **Greptile: one slot recommended, on T2.7.** T2.7 introduces a **versioned persisted scope set over stored user state** and migrates an existing shipped key (`map.coverageShading.visible`, `MapScreen.swift:2460`, asserted by `AppShellTests.swift:2888`, and removed on reset in `MakingTracksApp.swift:442`). Stored-state versioning with a migration is exactly the allocation criterion (state machines, migrations), and a silent defect here loses a user's standing statement of intent without an error.
- **A second slot is planner's call, not mine.** T2.8 re-points **36 identifier references** across the UITest and unit suites while dismantling a chip surface. It is mechanical and fully verifiable by grep, so I have not spent a slot on it — flagging it rather than quietly consuming budget.
- **codex-r: one spec attack + one acceptance pass** (spec §5 XHIGH budget). Recommended placement: the spec attack on **T2.1's amendment text plus this graph** before the build rows claim — the amendment is where a wrong figure becomes law — and the acceptance pass at closeout, grading AC2.1–AC2.19 including Phase 1's 35/35 completion.
- This graph is a docs-only PR and consumes neither budget.

---

## Dependency graph

Edges are "must have merged before this starts" — except the two wireframe edges, are **must have been ruled by Rob** — a strictly later moment than merge.

| Task | Depends on |
|---|---|
| T2.1 spec amendment: the metrics batch | — (docs-only; **claimable immediately**) |
| T2.2 `IconRole` gains `rowRaised`/`rowQuiet`; the press inset scales | T2.1 (the table ratifies before the API carries) |
| T2.3 #520: the door row glyph migrates — Phase 1 completes at 35/35 | T2.2 |
| T2.4 `hiddenPinColor` reads the constant pin block | — |
| T2.5 **W-1** — DS-3 Explore picker wireframe | — (**claimable immediately**) |
| T2.6 **W-2** — DS-6 Settings + About wireframes | — (**claimable immediately**) |
| T2.7 DS-3 scope persistence + the derivation-reach law | — (**claimable immediately**; no wireframe gate — nothing visible changes) |
| T2.8 DS-3 picker UI, chip merge, identifier rename | **T2.5 ruled**, T2.7 |
| T2.9 DS-6 Settings rebuild | **T2.6 ruled** |
| T2.10 DS-6 About rebuild | **T2.6 ruled** |

**Conflict pairs, named rather than discovered.**

1. **T2.7 and T2.8 both edit the Explore/scope region of `MapScreen.swift` (~`:2460`–`:3950`) and `MapLayerVisibility.swift`.** The edge is there for that reason, not only for the contract: persistence lands first, the picker consumes it. Do not run them in parallel.
2. **T2.8 and T2.9 both touch `MapDoorShell.swift`.** DS-3 owns `ExploreDoorRootView` and everything inside it, including the two quiet destination rows' presentation; **DS-6 owns what those rows lead to** and must not restructure the Explore root view. They are safe in parallel under that boundary and unsafe without it.
3. **T2.9 and T2.10 both edit `MapScreen.swift`, in different regions** — `SettingsView` at `:6744`–`:6900` and `AboutView` at `:7566`–`:7900`. Safe in parallel; both should land before any further Explore work reopens the file.
4. **T2.3 touches `MapDoorShell.swift`'s glyph block** (`:1215`–`:1230`), which T2.8 later rebuilds around. T2.3 is small and lands early; if it has not merged when T2.8 claims, T2.8 carries the migration instead and says so — never both.

Suggested waves for a four-builder pool. **Wave 1 is where the phase's latency lives**: both wireframes must be authored, validated and ruled before four of the ten rows can start, so they claim first and nothing else waits on them.

| Wave | Tasks | Builders busy |
|---|---|---|
| 1 | T2.5 (W-1), T2.6 (W-2), T2.1, T2.7 | 4 of 4 |
| 2 | T2.2, T2.4 *(wireframes in validation/ruling)* | 2 of 4 |
| 3 | T2.3, T2.8 *(if W-1 ruled)*, T2.9, T2.10 *(if W-2 ruled)* | 4 of 4 |

---

## Tasks

### T2.1 — The metrics batch lands in the spec

- **Serves:** P2R-1, P2R-2(a)(c)(d), P2R-4, P2R-8, P2R-9 · **Spec section:** §3, §5
- **Acceptance criteria:** AC2.1, AC2.5, and the spec-side halves of AC2.2, AC2.3, AC2.10
- **Depends on:** none — docs-only, claimable immediately
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `reviewer` (+ codex-r's spec attack, per *Review budget*)
- **Status:** unclaimed
- **Contracts produced:** the ratified figures T2.2 and T2.8 build against. **Fix them here**; a figure that moves after a builder consumes it is the failure this table exists to prevent.

**Builder brief.** This is the one-shot amendment P2R-9 commissions, and **it is smaller than the commission implies** — most of its riders landed with #524 and the amendment wave. **Verify each of the following is already true before you write anything, and record the verification in your PR body**; if one is not true, it is yours and you say so:

| Already landed — do not redo | Where |
|---|---|
| the `trail` rename, code **and** sheet | `MaterialTokens.swift:98`, `:147`, `:217`; no `trackLine` symbol remains |
| `disabledAlpha 0.46`, `pressScale 0.98` as §3 rows | spec `:142`–`:143`; live at `MaterialTokens.swift:153`–`154`, `:219`–`220` |
| `hiddenPinColor #767B82` in the §3 **constant pin block** | spec `:132`, `:145` |
| the 17-beside-15 pairing constant as a §5 metrics row | spec's component-metrics table, *Control-label icon beside a 15pt label* |
| the Saved-ON inversion (`accentDeepContainer`, RATIFIED) | spec's component-metrics table |

**What this row actually adds.** All of it in the §5 component-metrics table unless stated:

1. **`rowRaised` = 20 and `rowQuiet` = 18** as ratified rows (AC2.1), each naming its `ia-doors` source and its paired typography role. **Functional names, never size names** — the number is the role's current value, not its identity.
2. **The press-inset scaled metric** (AC2.3): the inset is a metric anchored to the control's paired typography role, replacing the builder-proposed `1pt` cited literal. The table is the ratifying home the literal's own comment points at (`ControlStyles.swift:190`–`:194`).
3. **`disabledAlpha` and `pressScale` as metrics-table rows.** They are §3 rows today and the commission lists them as table rows. If planner reads P2R-9 as already discharged by the §3 rows, drop this item and say so — **do not create a second home for the same figure**; a cross-reference from the metrics table to §3 is the defensible middle and is what I would build.
4. **P2R-4's ratification** (AC2.5): the two Scope-control rows (52pt default, 86pt AX) change provenance from *measured, not ratified* to **ratified as system law for this row class**, naming the ruling and its date and **retaining the artifact SHA**. Ratify **the row class, not the surface** — the figures bind wherever that row class appears. **Read OF2 before you edit**: the five remaining MEASURED rows stay MEASURED, and the *Scope block rhythm* row is the ambiguous one. Absent a ruling, restamp the two control rows only and say in your PR body that you did.
   - Carry P2R-4's rider into the text verbatim-in-substance: these are the **ratified defaults**, and a DS-3 deviation *"deviates through its own gate with the delta named — never silently."*
5. **P2R-8's derivation-reach law** (AC2.10), stated where the spec describes scope filters, in the ruling's own words: *"scope filters govern discovery surfaces; story surfaces (Journal: tracks, lists, loved, hidden management) are exhaustive over their own domain and NAME overlaps instead of filtering them."* State it as **general law** — the point of the ruling is that future reach questions answer from the law instead of case-by-case — and record that `Derivations.swift` stays untouched by this filter **permanently**.
6. **P2R-2(d)'s anti-creep restatement**: *"the set is again closed (now at five); additions only by session ratification against frozen-render evidence."*

**Do not touch the frozen renders.** A render certifies what it certifies; this table says which figures bind. That distinction is R10's frozen-render supersession precedent and it applies unchanged.

Docs-only, so the iOS gate does not run — and a green PR is therefore not a tested PR. `agent-law-lint`, `attribution` and `shellcheck` do run.

---

### T2.2 — `IconRole` gains `rowRaised` and `rowQuiet`; the press inset becomes a scaled metric

- **Serves:** P2R-1, P2R-2(a) · **Spec section:** §4, §5
- **Acceptance criteria:** AC2.2, AC2.3
- **Depends on:** **T2.1** — the table ratifies, the API carries
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `reviewer`
- **Status:** unclaimed
- **Contracts produced:** two new `IconRole` cases and the scaled press inset. **T2.3 consumes the first**; name both in the PR body.

**Builder brief.** Two changes in `ios/Sources/DesignSystem/`, both rename-level in spirit: no surface should look different except the one glyph T2.3 migrates afterwards.

**(a) The two row roles.** `IconRole` (`Iconography.swift:26`–`:43`) is three cases — `hero` 22 / `inline` 15 / `accessory` 11 — each with a paired `TypographyRole` and `UIFontMetrics` scaling. Add `rowRaised` = 20 and `rowQuiet` = 18 in the same shape, each paired to its typography role and scaling like every other role. **Pair them deliberately and state your pairing in the PR body** — the pairing is the load-bearing part of R11 point 3, and this row is where two more get chosen.

**The closure test is the point of the closed set.** The existing test pins the three-role property the way `MaterialTokensTests.swift:40` pins the token enum; re-pin it at **five** so a silently added sixth case still fails. An equality assertion against the role's own expression proves nothing.

**(b) The press inset.** `MaterialQuietButtonStyle.textOnly` ships `.textInset(points: 1)` (`ControlStyles.swift:199`) with a doc comment declaring it builder-proposed pending ratification. Replace the literal with a metric anchored to the control's **paired typography role**, the same law icons already follow — `IconRoleModifier` already anchors `@ScaledMetric` to a paired role, which is why P2R-1 calls the migration one line. Retire the comment's pending clause and cite the ratified table row instead.

**Prove the property the ruling is about, not just the code change.** The evidence that produced P2R-1 was that the inset measured **+3 device pixels at both default and AX**, so its perceptibility fell as type grew. Your test asserts the inset **grows with Dynamic Type**; a test that only asserts "it is a scaled metric" cannot see the defect that motivated the ruling.

`testQuietTextOnlyBodyRetainsPressScaleWithoutWeightPulse` and its A9 siblings pin the current behaviour — re-point, do not delete, and say which assertion changed.

Host-only (`cd ios && swift test`) unless you touch `project.yml`. No render: nothing visual changes at default size, and if something does, that is the news and you show it.

---

### T2.3 — #520: the door row glyph migrates — Phase 1 completes at 35/35

- **Serves:** P2R-2(b), #520 · **Spec section:** §4, §8
- **Acceptance criteria:** AC2.4
- **Depends on:** **T2.2**
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `reviewer`
- **Status:** unclaimed
- **Closes:** **#520** on merge, and with it Phase 1's parked acceptance remainder.

**Builder brief.** `MapDoorRowIconGlyph` (`ios/App/Sources/Map/MapDoorShell.swift:1215`–`:1230`) holds `.font(.headline.weight(.medium))` — a **17pt literal declared non-compliant in its own comment**, retained as a way-station pending exactly this ruling. It is the last font literal outside `DesignSystem` in the Phase 1 adopted surfaces (#529 removed the other one by adopting `IconRole.inline`).

Migrate it to `rowRaised` or `rowQuiet` **as appropriate to the row it draws**, and say which and why: `ia-doors` ratifies 20px for **raised** row glyphs and 18px for **quiet** ones, and `MapDoorRowLabel` is consumed by both `MapDoorRaisedRow` (`:1185`) and `MapDoorHairlineRow` (`:1200`). If one glyph view serves both row kinds, that is the design question in this row — solve it by passing the role, not by picking one and living with the other. Delete the pending-ruling comment; the vocabulary now expresses the figure, so the citation belongs in the table, not the call site.

**This is a visible change** — 17 → 20/18 on live door rows. Ship before/after renders at 390×844 plus an AX variant with measurements beside the images, per the evidence law. `AppShellTests.swift` asserts this glyph in five places (`:1119`, `:1202`, `:1275`, `:1293`, and the point-of-use coverage #520 requires) — re-point them, and keep the coverage assertion **point-of-use**: #520's Done-when states in terms that a definition-only `IconRole` test is insufficient.

Your PR body states, in these terms, that **Phase 1 acceptance completes at 35/35**, and closes #520.

Full gate — you changed an app-target surface.

---

### T2.4 — `hiddenPinColor` reads the constant pin block

- **Serves:** P2R-9's second rider; spec §8 · **Spec section:** §3, §8
- **Acceptance criteria:** AC2.6
- **Depends on:** none
- **Owner:** unclaimed
- **Review tier:** `sourcery`
- **Status:** unclaimed

**Builder brief.** The smallest row in the phase, and it exists because the amendment landed the **sheet** side and not the **code** side. `PinLayers.pinColor` reads `PinTokenBlock.constant.pin.mapStyleString` (`ios/Sources/MakingTracksMapStyle/PinLayers.swift:5`); the line below it, `hiddenPinColor`, is still a raw `"#767B82"` string literal (`:6`) even though spec §3 now carries it as a constant-pin-block row and §8 says pin layer constants come from that block. Wire it the way `pinColor` is wired.

**The pin-pop gate does not apply to this colour** — hidden pins are *deliberately* de-emphasised, which is the rider's whole point. `PinLayersTests.swift:319` asserts a ≥3.0 contrast against white and `:348` asserts the emitted style string; both should stay green and are your proof that the value did not move.

**Fold-or-file honesty:** if this turns out to be one line and you are already in the module for another reason, fold it and close the row. It is a named row so it cannot become an unowned deferral, not because it deserves a whole PR.

Host-only unless you touch `project.yml`.

---

### T2.5 — **W-1**: the DS-3 Explore picker wireframe

- **Serves:** W-1, gating #469 · **Spec section:** §2, §5, §7
- **Acceptance criteria:** AC2.13 (drawn), AC2.17, AC2.18, and the drawn form of AC2.8, AC2.9, AC2.11, AC2.12
- **Depends on:** none — claimable immediately
- **Owner:** unclaimed · **Pipeline:** build agent authors → **reviewer validates** → **Rob rules**
- **Review tier:** `sourcery` + `reviewer` (validation is the gate, not a courtesy)
- **Status:** unclaimed
- **Unblocks:** T2.8, **on Rob's ruling — not on merge**

**Builder brief.** Draw the DS-3 Explore picker at **390×844 plus an AX variant**, HTML committed. This is a mockup-gate artifact under the authoring law: it is evidence, and evidence carries its numbers.

**What the drawing must satisfy:**

- **Scope rows at the P2R-4 ratified geometry, "in the ruled order and defaults"** — 52pt minimum at default, 86pt at AX, with the full tabled geometry (label, icon, gap, padding, switch metrics, hairlines). These are the **ratified defaults**: if the drawn picker needs to deviate, that deviation *"deviates through its own gate with the delta named"*, never a silent redraw. **OF2** governs whether the block-rhythm figures come to you ratified or measured; state which you drew to.
- **R10 and its rider, with the numbers derived at the gap the drawn surface actually has.** The only ratified chip container is `ia-doors`' `gap:6px`, non-wrapping; **the wrapped multi-row flow is this design's to set.** State the pitch and the outsets beside the frame. The worked ~30pt arithmetic elsewhere assumes an 8pt gap and is illustrative, not ratified. Reversible, immediately-legible controls may tile; destructive, navigational or commitment-bearing ones keep full 44pt.
- **The scope-active indicator** (P2R-5a) drawn on the **Explore door**, and the quiet **Clear-scope row** (P2R-5b) drawn in the picker. Both are ruled; their form is what you are deciding.
- **The P2R-6 identifier annex**: name the A1-convention identifier for **every relocated row**, so T2.8's rename is a transcription rather than a fresh naming exercise. Today's names are `map.layers.show-hidden`, `map.layers.show-saved`, `map.layers.coverage-shading`, `map.layers.show-all-categories`, `map.layers.category.<id>` — and they belong to a sheet that no longer exists.
- **The P2R-7 proof-absence sentence in the record, in these exact words:** ***"this surface does not pair a filled action with a state cluster; the R16 proof obligation travels to the first surface that does."*** The ruling specifies the sentence, not merely the substance — paraphrasing it is how an obligation lapses in silence.
- **State the morphology you drew and reconcile it with R15** (see **OF5**). The ratified A8 geometry describes switches; R15's ON = filled pill + filled glyph. Whichever you draw, the record says which and on what grounds.
- **Answer OF4 in the drawing**: what, if anything, list-mode filtering contributes to this surface. `ListMapFilterChips` filters an active list's visits; the picker scopes discovery. Draw the answer; do not leave it to the builder who implements you.
- **The grouped-edit state remains the sanctioned fallback if the drawn surface reads mis-tappy — not pre-emptively.** It trades the one-tap loop for a mode.

**Evidence law is the acceptance criterion here, not a formality.** Measurements beside every frame; the full constraint structure enumerated before any figure is adopted; a general bound states its qualifier. A render asserting a state carries the number that proves it.

**Grounding you should not re-derive:** the surface already exists (`MapDoorShell.swift:429`–`575`) with the three scope rows, the 6pt-gap category flow and `ExploreCategoryChipTopology`'s neighbour-gap tiling already wired. Draw the target state, and where you keep what is built, say so — a wireframe that silently redraws working geometry costs a builder a diff they cannot explain.

---

### T2.6 — **W-2**: the DS-6 Settings and About wireframes

- **Serves:** W-2, gating #472 · **Spec section:** §2, §5
- **Acceptance criteria:** AC2.14, AC2.16, AC2.17, AC2.18 (drawn)
- **Depends on:** none — claimable immediately
- **Owner:** unclaimed · **Pipeline:** build agent authors → **reviewer validates** → **Rob rules**
- **Review tier:** `sourcery` + `reviewer`
- **Status:** unclaimed
- **Unblocks:** T2.9 and T2.10, **on Rob's ruling**

**Builder brief.** Draw Settings and About at **390×844 plus AX variants**, HTML committed.

**Settings, grouped as ruled:** Appearance · Offline maps (moved in, with the map's contextual deep links intact) · Coverage · Map & data · Location · Diagnostics · Replay welcome. **On DS-1 rows and sheets — no system `List` chrome.** Today's screen is a stock SwiftUI `List` of `Section`s (`MapScreen.swift:6744`–`:6900`: Map theme, Downloads, Pins, Location, Storage, Diagnostics, Onboarding), so this is a re-grouping **and** a re-chroming; draw both.

- The **Appearance** group is a slot for DS-7's material picker. Today's "Map theme" section moves into it **unchanged** — four presets, same picker, same UITests. Do not draw DS-7's Appearance picker.
- **Read OF1 before drawing the Coverage group.** If it carries a coverage-*shading* toggle it collides with P2R-5's picker scope. Draw the reading you believe and say which — the wireframe is where this becomes visible and therefore rulable.

**About, rebuilt:** the story and the privacy promise **up top**, then **Software licences** (the OSS credits manifest, including Newsreader's OFL) and **Data licences** (OSM, Wikipedia, per-region sources) as **proper sub-areas** rather than a flat run. Today's `AboutView` (`:7566`–`:7900`) renders a `List` fed by `OSSCredits.json` plus attribution rows and build metadata; the licence **content** is not yours to change, only its structure.

**The P2R-7 proof-absence sentence goes in the record verbatim**, same as W-1: ***"this surface does not pair a filled action with a state cluster; the R16 proof obligation travels to the first surface that does."*** The ruling's own grounds for this surface: Settings and About rows *"carry no filled CTA beside state pills."*

Evidence law as W-1: measurements beside every frame, constraint structure enumerated, qualifiers stated.

---

### T2.7 — DS-3: the scope set persists, and the derivation-reach law gets teeth

- **Issue:** #469 · **Serves:** P2R-5, P2R-8 · **Spec section:** §2
- **Acceptance criteria:** AC2.7, AC2.10, and the predicate half of AC2.8
- **Depends on:** none — **no wireframe gate**: nothing visible changes, and the ruling is explicit
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `greptile` + `reviewer` — **the phase's stored-state row**
- **Status:** unclaimed
- **Contracts produced:** the versioned persisted scope set and the effective-scope-differs-from-default predicate. **T2.8 consumes both** — fix their shape here and name them in the PR body.

**Builder brief.** Make the user's scope choices survive relaunch, and pin the reach of the filters that read them. **No picker UI in this task** — that is T2.8, and it is gated on a wireframe this row is not.

**What persists today, and what must.** Only coverage shading survives a launch: `@AppStorage("map.coverageShading.visible")` (`MapScreen.swift:2460`, `:2480`) with a matching `UserDefaults` read at `:2580`. Include-hidden (default OFF), show-saved (default ON) and the category selection all reset. Under P2R-5 **all four persist**, as *"one versioned scope record (Data §11 applies)"*, with defaults exactly **hidden OFF, saved ON, coverage ON**. Scope is the user's standing statement of intent (PRINCIPLES → Product 7), not a session gesture.

**Data §11 is an acceptance requirement, not a citation.** *"Everything that crosses a boundary is versioned … Readers know their maximum understood version and refuse or degrade gracefully — never silently misread newer or older data."* Concretely, and each of these is a test: the record carries a version; a reader meeting a **newer** version than it understands **refuses or degrades to defaults** rather than misreading fields it does not know; a reader meeting an **older** version migrates it forward deterministically; and a record that fails to parse falls to defaults rather than to an empty scope — an empty scope renders a blank map and reads as data loss.

**The existing key is shipped state, so this is a migration, not a fresh store.** `map.coverageShading.visible` is asserted by `AppShellTests.swift:2888` and cleared on reset in `MakingTracksApp.swift:442`. A user upgrading with shading OFF must not silently get it back. Version the record, migrate the old key, and test the upgrade path from *both* prior values — this is why the Greptile slot is here.

**The predicate AC2.8 needs does not exist yet.** `MapLayerVisibility.isDefault` (`MapLayerVisibility.swift:18`) is `!showHiddenPlaces && showSavedPlaces && visibleCategories == nil` — **coverage shading is absent from it**, which was correct when coverage was not a scope choice and is wrong the moment P2R-5 lands. Five assertions in `MapLayerVisibilityTests.swift` (`:52`, `:57`, `:82`, `:94`, `:106`) pin the current meaning. Extend or replace it deliberately, re-point those tests, and say in the PR body which meaning you built: *effective scope differs from default* is what the indicator reports, and getting it wrong makes the door either cry wolf or stay silent while the map is thin.

**P2R-8, and this is the part that needs teeth rather than agreement.** *"scope filters govern discovery surfaces; story surfaces (Journal: tracks, lists, loved, hidden management) are exhaustive over their own domain and NAME overlaps instead of filtering them."* The saved-visibility filter reaches `PinFeatureFilter.discoveryFeatures` (`ios/Sources/MakingTracksMapStyle/PinFeatureFilter.swift:14`–`:20`) and **must never** reach track, list, loved or journal derivations. `Derivations.swift` is untouched today and — in the ruling's word — stays untouched by this filter **permanently**; `lovedPlaces()` (`:50`) not filtering is the pinned behaviour this ruling generalises.

Add the test that makes the law enforceable rather than documented: with **every** scope filter at its most restrictive, the Journal-side derivations return the same rows they return at defaults. The rationale is worth building to, not just citing — filtering saved out of lists is self-contradiction, and filtering your own history out of tracks subtracts the story: **seen is a fact** (Principle 4).

Host tests for the store and the derivation reach (`cd ios && swift test`), then the full gate — you touched app state.

---

### T2.8 — DS-3: the Scope picker, the chip merge, and the one-commit rename

- **Issue:** #469 · **Serves:** P2R-4, P2R-5(a)(b), P2R-6, R10 · **Spec section:** §2, §5, §7
- **Acceptance criteria:** AC2.8, AC2.9, AC2.11, AC2.12, AC2.13, AC2.19; AC2.5 as consumer
- **Depends on:** **T2.5 ruled by Rob** (not merged — ruled), and **T2.7**
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `reviewer` (second Greptile slot is planner's call — see *Review budget*)
- **Status:** unclaimed — **blocked until W-1 is ruled**
- **Contracts consumed:** T2.7's persisted scope set and default predicate; T2.2's roles if the picker draws row glyphs.

**Builder brief.** Build the picker W-1 draws. **The surface already exists** — `ExploreDoorRootView` (`MapDoorShell.swift:429`–`575`) with the three scope toggle rows (`ExploreScopeControl`, `:63`–`:90`), the category chip flow at the ratified 6pt gap, and `ExploreCategoryChipTopology`'s R10 neighbour-gap wiring (`:92`–`:124`). You are rebuilding it to the ruled wireframe, not starting it.

**The three things this row must not get wrong:**

1. **The identifier rename happens once, in one commit, with nothing in flight against it** (P2R-6). Take the names from W-1's annex — do not invent them. The blast radius is **36 references** (planner grep at landing; re-count when you claim) to `map.layers.*` across `ios/App/UITests` and `ios/App/Tests`: `show-hidden` ×9, `show-all-categories` ×8, `coverage-shading` ×7, `show-saved` ×4, `category.*` ×4. **Re-point tests; do not delete them to get green** — each one is coverage of a control that still exists. The vestigial plumbing names (`layersSheetVisibility`, `updateLayersSheetVisibility`, `MapScreen.swift:3882`–`:3890`) name a sheet that was already dismantled; rename them in the same commit or say why not.
2. **The chip merge is a semantic question, and W-1's ruling answers it** (OF4). `ListMapFilterChips` (`MapScreen.swift:1298`, rendered `:3390`) filters an **active list's** visits through `TracksVisitFilter`; the picker scopes **discovery** through `MapLayerVisibility`. `ListMapLayerVisibility.displayed/updating` already bridges them. Build what W-1 was ruled to draw; if the ruling is silent on a case you meet, that is a taste guess with a flag, not a silent decision.
3. **R10's numbers come from the gap you actually build, not from a worked example.** `min(11pt, gap/2)` per side; every screen point maps to exactly one control. The rider holds: tiling only for reversible, immediately-legible actions — Clear-scope restores defaults in one tap and is reversible; a row that **navigates** is not. Prove the target by **hit-testing, not by measuring the frame** (T1.12's evidence clause, still binding), and include a tiled-adjacency assertion: two adjacent distinct-action chips at a gap under 22pt, a tap in the band between them reaching exactly one and it being the nearer.

**Also in this row:** the scope-active indicator on the Explore door, consuming T2.7's predicate (AC2.8); the quiet Clear-scope row (AC2.9); and the P2R-4 geometry as **ratified defaults** — a deviation is its own gate with the delta named.

**AC2.19 lands concretely here**: the picker is dense, stateful and chip-heavy. Dynamic Type through AX5 with the AX row geometry, VoiceOver values on every state control (a toggle's *value* is not its label), never colour-alone.

Full gate plus renders of the picker at default and AX with measurements beside them, and a render of the door in both indicator states.

---

### T2.9 — DS-6: Settings rebuilt on DS-1 rows

- **Issue:** #472 · **Serves:** W-2 · **Spec section:** §2, §5
- **Acceptance criteria:** AC2.14, AC2.15, AC2.19
- **Depends on:** **T2.6 ruled by Rob**
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `reviewer`
- **Status:** unclaimed — **blocked until W-2 is ruled**
- **Contracts consumed:** T1.4's sheet/row patterns, T1.1 tokens, T1.2 font roles.

**Builder brief.** Rebuild `SettingsView` (`MapScreen.swift:6744`–`:6900`) to W-2's grouping on **DS-1 rows and sheets — no system `List` chrome**. Today's sections are Map theme, Downloads, Pins, Location, Storage, Diagnostics, Onboarding; the ruled grouping is Appearance · Offline maps · Coverage · Map & data · Location · Diagnostics · Replay welcome. **The mapping between the two is W-2's to have drawn**; if a today-section has no ruled home, flag it rather than inventing one.

**Three destinations you can silently break, and AC2.15 grades all of them.**

- **Offline maps moves in**, and it is reachable today through `settings.storage.manage` (`:6832`–`:6839`) → `SettingsStorageNavigation`. The map's **contextual deep links must survive**: the download-progress pill and the empty-region card's download action both route through `openOfflineMapsDeepLink`. Verify them in the simulator; a Settings re-group is exactly the change that breaks a route nobody re-tests.
- **Diagnostics** keeps `settings.diagnostics.export` (`:6840`–`:6862`) and routes to the unchanged screens — DS-9 owns their re-skin.
- **Replay welcome** keeps `settings.replay-onboarding` (`:6863`+) and routes to the unchanged flow — DS-8 owns its re-skin.

**Appearance is a slot, not a picker.** Today's Map theme section moves in **unchanged** — four presets, `map.theme.id` untouched, and the theme-picker UITests (`MakingTracksCoreLoopUITests.swift:2427`–`3246`) still green. DS-7 #473 owns the fold and the migration; doing it early risks performing the stored-preference migration twice.

**Read OF1 before you build the Coverage group.** If W-2's ruling puts a coverage-*shading* toggle here while the picker also carries one, stop and raise it — two homes for one control is the debt P2R-5 exists to kill, and it is cheaper to catch before both ship.

**Boundary with T2.8**, which may be running beside you: DS-3 owns `ExploreDoorRootView` and everything inside it, including the two quiet destination rows' presentation. **You own what those rows lead to.** Do not restructure the Explore root view.

Full gate plus renders of each Settings group at default and AX.

---

### T2.10 — DS-6: About rebuilt with licence sub-areas

- **Issue:** #472 · **Serves:** W-2 · **Spec section:** §2, §5
- **Acceptance criteria:** AC2.16, AC2.19
- **Depends on:** **T2.6 ruled by Rob**
- **Owner:** unclaimed
- **Review tier:** `sourcery` + `reviewer`
- **Status:** unclaimed — **blocked until W-2 is ruled**

**Builder brief.** Rebuild `AboutView` (`MapScreen.swift:7566`–`:7900`) to W-2: the **story and the privacy promise up top**, then **Software licences** and **Data licences** as proper sub-areas rather than one flat run. DS-1 rows and sheets; no system `List` chrome.

**The licence content is not yours to change — only its structure.** Software licences render from `OSSCredits.json` via `OSSCreditsManifest.load()`, and that manifest already carries Newsreader's OFL entry (added by T1.2 under AC6); Data licences come from the attribution set the view is handed, plus the OSM copyright link. **A licence that stops rendering is a compliance defect, not a layout regression** — assert that every entry present before your change is present after it, by count and by name.

Build metadata (version, build commit) keeps its home; the OSM attribution link keeps its behaviour. `testMenuAboutCarriesCreditsAndMapAttributionIsInert` and its siblings pin both — re-point rather than delete.

Full gate plus renders of About and both licence sub-areas at default and AX.

---

## Carried — not claimable this phase

- **OF3's 19×19 door pill icon.** The ratified metrics table says 19; the shipped door pill renders `IconRole.inline` = 15. No row this phase touches it, and #520 does not cover it. It is a **third** figure pressing a set that P2R-2(d) has just re-closed at five — which is precisely the pattern the anti-creep restatement exists to meet, so it belongs in front of the next session with its evidence rather than being resolved by a builder.
- **P2R-3 and P2R-10 close here as records.** P2R-3 requested no decision; the lesson is affirmed as existing law — *"a figure outside both the ratified set and the expected vocabulary is invisible to careful search, and every relay names its file."* P2R-10's R9 quiet-geometry remedy is fully ruled and shipped — symbol-weight pulse for glyphed quiet controls (A5), the ruled inset for text-only (A9), and the inset becomes a scaled metric in **T2.2**. Nothing further is owed; the packet item closes when T2.2 lands.

---
