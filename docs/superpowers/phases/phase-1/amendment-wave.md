# Amendment wave — task graph — **WAVE OPEN**

**Owning issue: [#526](https://github.com/mnbf9rca/making-tracks/issues/526).** Every PR in this wave
cites it.

Source: the **2026-07-26 design session** (designer + Rob), ratified into the spec by #524
(`13244148`). Every row here implements something that session ruled; nothing here is new design.

**The wave is open and rows A1–A8 are live.** fable's budget and dependency pass is complete; claims
go out by doorbell. A row is **claimable when it is unclaimed *and* unblocked** — see the dependency
graph below, and note that A1 and A2 wait on A8.

**Read this file the way Phase 1's graph was read, and do not expect it to repeat what already has a
home.** These apply unchanged and are **not** restated here, per one-rule-one-home:

- ***Operating rules — every task*** → [`phase-1/tasks.md`](tasks.md): branch and PR shape, labels,
  open-ready-before-the-automated-layer, the SHA-copy rule, the body-states-evidence rule, gates on
  the host, the taste-guess protocol, the render-set rule.
- **Claim protocol, stall rules and the status vocabulary** →
  [`docs/process/coordination.md`](../../../process/coordination.md) → *Supervision-loop contract*.
  In particular: **claim state is authoritative only with fable, never from the tree** — a status
  line rides its own branch until its PR merges, so this file structurally lags every claim made
  since the last merge. A row reading `unclaimed` here may already be claimed. **Ask; do not infer.**
  Stall = **no status change for 45 minutes**; two unanswered nudges releases the row with an
  incident line. Vocabulary: `claimed → branch → tests green → PR open → review clean →
  ready-to-merge`, plus `blocked: <reason>` and `released`.
  **`released` means returned to the pool, never shipped** — it reads as its own opposite, so the
  merged state is written as `merged as <sha>` and nothing else.

**The `Status` field is the builder's until handoff, and the merger's record thereafter.** Rows below
are left `unclaimed` deliberately: **the three doorbelled claimants write their own lines** after
re-grounding on this file's merge. Do not write another seat's status.

---

## Dependency graph

Edges are "must have merged before this starts."

| Task | Depends on |
|---|---|
| **A8** frozen renders (Explore surface, R15 card) | — *(critical path: these ratify what A1 and A2 build)* |
| **A1** door rename + Explore collapse | **A8** (Explore frame) |
| **A2** place-card state morphology | **A8** (R15 card frame), **A4** |
| **A3** `trail` rename | — |
| **A4** `disabledAlpha` / `pressScale` rows + consumption | — |
| **A5** quiet-control feedback (symbol-weight pulse) | **A4** |
| **A6** #517 enforcement package | — |
| **A7** #522 post-merge annotations | — |

**A8 is the critical path and it is not a build task.** Per the render pipeline: a build agent
authors, **opus validates**, **Rob rules**. A1's Explore surface and A2's card are graded against
frames that do not exist yet, so starting either before A8 lands means building against prose.

**A3, A4, A6 and A7 are unblocked immediately** and are the right first claims while A8 is in the
render loop.

---

## A1 — Journal and Explore: the door rename and the Explore collapse

- **Serves:** R13, R14 · **Spec section:** §2 · **Review tier:** `sourcery` + `opus`
- **Depends on:** A8's Explore frame
- **Owner:** unclaimed
- **Status:** unclaimed
- **Branch:** `wp-526-journal-explore-doors` — cut from a freshly-fetched `ios`

**Builder brief.** Rename Door 2 *Tracks* → **Journal** and Door 1 *World* → **Explore**, and
collapse Explore so the door **opens Scope directly**: no intermediate row list, Settings and About
as quiet bottom rows on that surface with the gear the more prominent of the two, and the Search
slot reserved at the top rendering **nothing** until DS-11.

**Identifiers that migrate** — these are contracts, so change them deliberately and in one commit:
`map.door.tracks`, `map.door.world`, `tracks.root`, `tracks.row.my-tracks`, `tracks.row.loved`,
`tracks.row.hidden`, `world.row.scope`, `world.row.settings`, `world.row.about`.
**`world.row.scope` retires rather than renames** — the collapse means Scope is no longer a row.

**Tests whose names carry a door name** and must move with it: `testAppShellModelOpensEachDoorAtItsRoot`,
`testDoorRootsExposeOnlyRuledRows`, `testMapDoorsExposeDistinctRuledPresentation`,
`testAppShellModelRoutesOfflineMapsDeepLinkThroughWorldDoor`,
`testAppShellModelRoutesListsDeepLinkThroughTracksDoor`,
`testAppShellModelRoutesTracksDeepLinkThroughTracksDoor`,
`testAppShellModelClearsTracksFocusForDoorRootsAndOtherDeepLinks`.

> **The trap, and it is the whole reason this list is enumerated rather than described.** Several
> test names contain *World* or *Tracks* and **have nothing to do with the doors**:
> `testBundledWorldBasemapIsPresentInHostAppBundle`, `testCorruptWorldBasemapReturnsNil` and
> `testListMapViewportFitsAntimeridianMembersWithoutWorldSpan` are about the **basemap and world
> span**; `testFilterTracksExplicitlyReturnsFromNoCategoriesToAll` and
> `testListMapPinPresentationTracksModeUsesFullStrengthPins` are about **track mode and filtering**.
> A find-and-replace across the suite renames five tests into lies. **Rename by meaning, not by
> string.**

AC22 applies in its original form: **the door keeps every destination it had.** The collapse removes
a *row*, not a destination — Scope, Settings and About must all still be reachable, and the PR body
says by what path.

Renders of both doors at 390×844 plus an AX variant, graded against A8's frames.

---

## A2 — The place card adopts state morphology

- **Serves:** R15 · **Spec section:** §5 · **Review tier:** `sourcery` + `opus`
- **Depends on:** A8's R15 card frame, **A4**
- **Owner:** unclaimed
- **Status:** unclaimed
- **Branch:** `wp-526-place-card-state-morphology` — cut from a freshly-fetched `ios`

**Builder brief.** Re-implement the place card's action bar under R15: **ON = filled pill + filled
glyph; OFF = tonal + outline glyph; momentary verbs = quiet text**, with never-colour-alone applying
to state. The action vocabulary is `PlaceCardAction` — `save`, `seen`, `love`, `unlove`, `hide`,
`unsee`, `seenDisabled`, `unhide` — plus the `place-card.more` control, which is a **momentary verb**
and therefore quiet.

> **Raise before you build, do not resolve.** R15 says ON is a filled pill. §5 says **filled is one
> per screen, maximum**. A card whose place is saved *and* seen *and* loved has **three ON states at
> once**, and the two rules cannot both hold on that card. This is a design conflict between two
> ratified statements, not an implementation detail — **it needs a ruling, not a guess.** Possible
> readings the session may not have considered: filled-per-*group* rather than per-screen; the glyph
> carrying ON while the container stays tonal within an action bar; or the action bar being exempt
> as a control cluster. **Do not pick one.** Raise it through fable, build everything else meanwhile.

The `place-card.*` identifiers are contracts and survive unchanged.

Renders: the card in every state combination the bar can reach, default and AX, graded against A8.

---

## A3 — `trackLine` becomes `trail`

- **Serves:** R8's naming rider · **Review tier:** `sourcery` + `opus` · **Depends on:** none
- **Owner:** unclaimed
- **Status:** unclaimed
- **Branch:** `wp-526-trail-token-rename` — cut from a freshly-fetched `ios`

**Builder brief.** Rename the token `trackLine` → `trail` — the `SemanticColorToken` case, the
`MaterialTokenSheet` property, the Snow value `#2D8C83`, and every consumer including
`MakingTracksMapStyle`. **Code and sheet in one commit**, per R8's rider: a contract rename is safe
only when nothing is in flight against it, and splitting it across commits is how the contract
breaks under a second builder.

Nothing else changes. If a value moves, you have exceeded the task.

---

## A4 — `disabledAlpha` and `pressScale` become sheet rows

- **Serves:** the session's taste verdicts · **Review tier:** `sourcery` + `opus` · **Depends on:** none
- **Owner:** codex1
- **Status:** branch
- **Branch:** `wp-526-interaction-token-rows` — cut from a freshly-fetched `ios`

**Builder brief.** Add `disabledAlpha` (`0.46`) and `pressScale` (`0.98`) to the token sheet as
ratified rows, and make `MaterialControlInteractionFeedback` **consume them** rather than holding
literals. These are the two interaction constants R9 left implicit.

**The existing tests already have the teeth for this** — `ControlStylesTests` pins the pressed body's
centre pixel against an independent literal and the 0.98 geometry ratio. Keep them green and add the
wiring assertion: a mutation of the *sheet row* must fail, or the tokens are decorative.

---

## A5 — Quiet-control press feedback: the symbol-weight pulse

- **Serves:** the session's gap ruling · **Review tier:** `sourcery` + `opus` · **Depends on:** A4
- **Owner:** unclaimed
- **Status:** unclaimed
- **Branch:** `wp-526-quiet-press-pulse` — cut from a freshly-fetched `ios`

**Builder brief.** `quiet` is `background: nil`, `backgroundOpacity: 0`, so R9's geometry remedy has
no boundary to move: an icon-only quiet control's press feedback is currently ~0.35pt of motion on a
17pt glyph, effectively nothing. Implement the ruled **symbol-weight pulse**, with the **inset** as
the ruled fallback if the pulse reads badly.

**It must remain R9-consistent: geometry and weight, never restored opacity.** Restoring opacity is
the thing R9 forbids, and this task is the one most likely to reach for it.

First mounted instance to verify against: T1.7's location-off Settings gear.

---

## A6 — #517 enforcement: saved and hidden become mutually exclusive

- **Serves:** #517 (Rob) · **Review tier:** `sourcery` + `opus` · **Depends on:** none
- **Greptile slot recommended** — see *budget note*
- **Owner:** unclaimed
- **Status:** unclaimed
- **Branch:** `wp-517-saved-hidden-exclusivity` — cut from a freshly-fetched `ios` *(already cut)*

**Builder brief.** Four parts, and the third is a data migration:

1. **Hide affordance gating on the ruled axes.** Hide is **not** restricted to Unseen — *seen is a
   fact* (PRINCIPLES → Product 4) and **presentation is never gated by the fact axis**. Gating is by
   **saved-exclusivity** only.
2. **Hidden rows offer Unhide as primary, plus Save — and Save auto-unhides.**
3. **Coexisting rows auto-unhide by migration** — *intent lifts the veil, nothing destroyed.*
4. **Rewrite the orthogonality test.** `testHiddenIsOrthogonalToSavedAndVisitState` asserts the
   property this ruling **removes** for the saved axis and **keeps** for the visit axis. It must be
   split, not deleted: hidden stays orthogonal to *visit* state, and stops being orthogonal to
   *saved*.

Seen-marking stays on the card. A migration here is in scope **because Rob ruled it**; that is the
only reason a migration is ever in scope.

---

## A7 — #522 post-merge annotations

- **Serves:** #522 · **Review tier:** `sourcery` · **Depends on:** none
- **Owner:** unclaimed
- **Status:** unclaimed
- **Branch:** `wp-522-merged-body-annotations` — cut from a freshly-fetched `ios`

**Builder brief.** Annotate the merged bodies of **#486** and **#503** where their acceptance claims
contradict the ratified graph, preserving the historical evidence. **Follow the #518 precedent
exactly:** the annotation is added post-merge and **says so** — honest timing is what makes a
post-merge edit a correction rather than a rewrite.

Docs-only; no code, no gate.

---

## A8 — Frozen renders: the Explore surface and the R15 card

- **Serves:** R14, R15 · **Depends on:** none · **This is the critical path**
- **Pipeline:** build agent authors → **opus validates** → **Rob rules** → frozen
- **Owner:** unclaimed
- **Status:** unclaimed
- **Branch:** `wp-526-explore-r15-renders` — cut from a freshly-fetched `ios`

**Brief.** Two new frozen frames: the **Explore surface** as R14 collapses it (Scope directly, quiet
Settings/About bottom rows with the gear prominent, reserved Search slot at top rendering nothing),
and the **place card under R15** in the state combinations its action bar can reach.

**Every load-bearing number in these frames goes into the spec's component-metrics table when they
freeze.** That table is the phase's answer to four separate misattributions, one of them from the
design authority; a new frozen render that does not feed it recreates the problem it solved.

---

## Budget note

**opus design review on every row except A7**, which is docs-only and takes `sourcery` alone.

**A6 is the Greptile candidate, and it is the only one I would spend a slot on.** It is the wave's
sole task that changes **stored user data** — the auto-unhide migration — against a ruling that
removes an invariant a test currently asserts. Every other row is presentation. If a slot is spent
this wave, spend it there.

**A1 and A2 are the two rows most likely to come back with findings**, for opposite reasons: A1 is a
wide mechanical rename where the risk is a *string* match that changes meaning, and A2 carries a
ratified conflict it must raise rather than resolve.

---

## Taste guesses

- **Placement.** This file sits at `phase-1/amendment-wave.md` rather than opening a `phase-2/`
  directory, because the wave amends Phase 1's output rather than succeeding it, and claiming a
  phase number is fable's call rather than mine. Trivially moved if the convention says otherwise.
- **A8 as a task row at all.** The render work could have been left to the session's own pipeline
  rather than given a row. I gave it one because it is the critical path for two build tasks, and a
  critical path with no row is the deferral shape this fleet has been burned by — but it is the one
  row here that is not a build task, and it may belong in a different list.
