# Tracks Door Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Tracks door's provisional My Tracks and Lists destinations with one live Tracks surface containing the protected My Tracks hero, non-track list progress rows, and New list creation, while preserving the shared list-detail and Retrace behavior.

**Architecture:** `TracksDoorRootView` becomes the single collection surface. A pure `TracksDoorContent` projection turns existing `PlaceList`, `ListProgress`, and `TrackVisit` values into the hero/list presentation pinned by app unit tests; the view loads those values through the existing `MapScreenModel` wrappers and navigates directly to the existing `ListDetailView`. The separate `.lists` route and `ListsView` are removed; the legacy `openListsDeepLink()` aliases the Tracks root.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest/XCUITest, `MakingTracksData`, the local `DesignSystem` package, and the designated iOS simulator through `scripts/sim-lock.sh`.

## Global Constraints

- Target iOS 18+ with Swift 6 strict concurrency and warnings as errors.
- Implement `docs/superpowers/specs/2026-07-25-design-system-and-ia-design.md` §2 and the complete T1.8 row in `docs/superpowers/phases/phase-1/tasks.md`.
- Treat `docs/design/design-system/ia-doors.html` frame 3 and `coherence.html` frame 4 as primary ruled sources.
- The Tracks root order is: My Tracks hero, Lists heading, every non-track list row with visible `n of m seen` counts and thin progress bars, New list.
- Loved and Hidden positions remain reserved but render no rows until T1.9.
- Use the existing `MapScreenModel.listProgress(listID:)` wrapper over `AppDatabase.listProgress(listID:)`; add no query or migration.
- The My Tracks hero uses Newsreader `.listRowTitle`; counts and metadata use SF roles.
- Custom-list titles use Newsreader `.listRowTitle`; visible progress counts use SF `.metadata`.
- Use `MaterialRaisedCardRow`, `MaterialHairlineRow`, and `MaterialProgress`.
- Keep `lists.detail.show-map` as the list-detail/Retrace control and keep visit-event chronology, verdict editing, and system-list membership protection unchanged.
- Keep existing create-list identifiers `lists.create.name`, `lists.create`, and `lists.error`.
- Keep direct list-detail deep links, focused Tracks deep links, Settings/About/Offline routes, and every T1.6 door destination.
- Remove the duplicate Lists navigation surface; `openListsDeepLink()` must open the same Tracks root.
- Dynamic Type, Reduce Transparency, Reduced Motion, AA contrast, 44×44 targets, and non-colour progress counts remain gates.
- Re-point the drift-pinning UI test to prove one root surface; do not delete destination coverage.
- PR targets `ios`, names issue #470, issue #266, and T1.8, and carries `track-b-ios`, `wp`, and `sourcery-review`.

---

### Task 1: Pin the single-surface routing and content projection

**Files:**
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/Sources/Map/MapDoorShell.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`

**Interfaces:**
- Produces: `TracksDoorContent`, `TracksDoorHeroContent`, and `TracksDoorListContent`.
- Produces: `TracksDoorContent.make(lists:progress:visits:)`.
- Changes: `openListsDeepLink()` aliases the Tracks root.
- Changes: `.listDetail(id)` navigates directly from the root rather than through `.lists`.

- [ ] **Step 1: Write failing unit tests for the projection and route alias**

Add hand-derived fixtures that assert:

```swift
let content = TracksDoorContent.make(
    lists: [
        PlaceList(id: 1, name: "My tracks", isSystem: true, kind: PlaceList.trackKind, createdAt: .distantPast),
        PlaceList(id: 2, name: "Ghost signs", isSystem: false, createdAt: .distantPast),
        PlaceList(id: 3, name: "KL follies", isSystem: false, createdAt: .distantPast),
    ],
    progress: [
        2: ListProgress(visited: 4, total: 11),
        3: ListProgress(visited: 7, total: 9),
    ],
    visits: [
        TrackVisit(id: 10, placeID: "p1", visitedAt: .distantPast, verdict: nil, name: "First", category: "memorial", tier: 1, lat: 0, lon: 0),
        TrackVisit(id: 11, placeID: "p2", visitedAt: .distantFuture, verdict: nil, name: "Thean Hou Temple", category: "building", tier: 1, lat: 0, lon: 0),
    ]
)

XCTAssertEqual(content.hero?.listID, 1)
XCTAssertEqual(content.hero?.metadata, "2 visits · last: Thean Hou Temple")
XCTAssertEqual(content.lists.map(\.name), ["Ghost signs", "KL follies"])
XCTAssertEqual(content.lists.map(\.progress), [
    ListProgress(visited: 4, total: 11),
    ListProgress(visited: 7, total: 9),
])
```

Also change the legacy Lists deep-link expectation:

```swift
shell.openListsDeepLink()
XCTAssertEqual(shell.presentedDoor, .tracks)
XCTAssertNil(shell.deepLinkDestination)
```

Name the breaks: a system list leaking into the Lists block, lost/custom-list reordering, wrong final visit metadata, defaulted progress, or a legacy deep link recreating a second navigation surface.

- [ ] **Step 2: Run focused app tests and verify RED**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -derivedDataPath /private/tmp/dd-codex3 \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksTests/AppShellTests
```

Expected: FAIL because `TracksDoorContent` does not exist and `openListsDeepLink()` still sets `.lists`.

- [ ] **Step 3: Implement the minimal pure projection and route alias**

Implement:

```swift
struct TracksDoorHeroContent: Equatable {
    let listID: Int64
    let metadata: String
}

struct TracksDoorListContent: Equatable, Identifiable {
    let id: Int64
    let name: String
    let isSystem: Bool
    let progress: ListProgress
}

struct TracksDoorContent: Equatable {
    let hero: TracksDoorHeroContent?
    let lists: [TracksDoorListContent]

    static func make(
        lists: [PlaceList],
        progress: [Int64: ListProgress],
        visits: [TrackVisit]
    ) -> Self {
        let trackList = lists.first {
            $0.isSystem && $0.kind == PlaceList.trackKind
        }
        let hero = trackList.flatMap { list -> TracksDoorHeroContent? in
            guard let id = list.id else { return nil }
            guard let lastVisit = visits.last else {
                return TracksDoorHeroContent(listID: id, metadata: "No visits yet")
            }
            let noun = visits.count == 1 ? "visit" : "visits"
            return TracksDoorHeroContent(
                listID: id,
                metadata: "\(visits.count) \(noun) · last: \(lastVisit.name)"
            )
        }
        let rows = lists.compactMap { list -> TracksDoorListContent? in
            guard !(list.isSystem && list.kind == PlaceList.trackKind),
                  let id = list.id
            else {
                return nil
            }
            return TracksDoorListContent(
                id: id,
                name: list.name,
                isSystem: list.isSystem,
                progress: progress[id] ?? ListProgress(visited: 0, total: 0)
            )
        }
        return Self(hero: hero, lists: rows)
    }
}
```

Remove `.lists` from `MapShellDestination`, return `[.listDetail(listID)]` from `listDetailPath`, and make `openListsDeepLink()` call the same root preparation as `openTracksDoor()`.

- [ ] **Step 4: Re-run focused app tests and verify GREEN**

Run the Step 2 command.

Expected: all `AppShellTests` pass with zero failures and no warnings.

- [ ] **Step 5: Commit the routing/projection slice**

```bash
git add ios/App/Sources/Map/MapDoorShell.swift ios/App/Sources/Map/MapScreen.swift ios/App/Tests/AppShellTests.swift
git commit -m "Unify Tracks root routing"
```

---

### Task 2: Render the live hero, list progress, and New list row

**Files:**
- Modify: `ios/App/Sources/Map/MapDoorShell.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Changes: `MapDoorSheet` accepts `MapScreenModel?` and the list-deletion callback needed by the root.
- Produces: `TracksDoorRootView` loading through `model.lists()`, `model.listProgress(listID:)`, and `model.trackVisits()`.
- Produces IDs: `tracks.row.my-tracks`, `lists.row.<id>`, `lists.create.name`, `lists.create`, `lists.error`.
- Navigates: hero to `.tracks`, custom row to `.listDetail(id)`.

- [ ] **Step 1: Write failing rendering-contract tests**

Extend `AppShellTests` to render the root at standard and AX5 sizes from explicit content and assert the image is non-nil. Add a test that the row contract exposes only the hero, custom lists, and New list; Loved/Hidden have no renderable case.

Name the breaks: a fixed-height root clipping at AX5, a visible Loved/Hidden placeholder, or loss of the New list control.

- [ ] **Step 2: Run focused app tests and verify RED**

Run the Task 1 Step 2 command.

Expected: FAIL because the root cannot accept explicit/live content and still renders the provisional two-row layout.

- [ ] **Step 3: Implement the minimal live Tracks root**

Wire `MapDoorSheetIntegration.model` into `MapDoorSheet`, then render:

```swift
MaterialRaisedCardRow {
    HStack(spacing: 12) {
        Image(systemName: "shoeprints.fill")
            .foregroundStyle(tokens.accent.swiftUIColor)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("My tracks")
                    .font(Typography.font(for: .listRowTitle))
                Spacer()
                Label("Retrace", systemImage: "map")
                    .font(Typography.font(for: .button))
            }
            Text(verbatim: hero.metadata)
                .font(Typography.font(for: .metadata))
        }
    }
}

Text("Lists").font(Typography.font(for: .label))

ForEach(content.lists) { list in
    Button { path.append(.listDetail(list.id)) } label: {
        MaterialHairlineRow {
            MaterialProgress(
                state: .count(
                    completed: list.progress.visited,
                    total: list.progress.total,
                    suffix: "seen"
                ),
                accessibilityLabel: "\(list.name) progress"
            ) {
                Text(verbatim: list.name)
                    .font(Typography.font(for: .listRowTitle))
            }
        }
    }
}

MaterialHairlineRow {
    HStack(spacing: 8) {
        Button {
            Task { await createList() }
        } label: {
            Image(systemName: "plus")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Create list")
        .accessibilityIdentifier("lists.create")

        TextField("New list", text: $draftName)
            .font(Typography.font(for: .body))
            .textInputAutocapitalization(.words)
            .accessibilityIdentifier("lists.create.name")
    }
}
```

Load all lists, load progress only for non-system custom lists, and load track visits once for hero metadata. Creation uses the existing model mutation, existing error copy, reloads content, and calls no new query.

For non-system list deletion, retain a destructive context menu plus a named accessibility action; never expose that action on the system hero or any other system list.

- [ ] **Step 4: Remove the duplicate `ListsView`**

Delete `ListsView` and its `.lists` destination branch. Keep `ListDetailView`, `ListDetailDeepLinkView`, `TrackListDetailDeepLinkView`, verdict editing, and `lists.detail.show-map` unchanged.

- [ ] **Step 5: Re-run focused app tests and host package tests**

Run the Task 1 Step 2 command, then:

```bash
cd ios && swift test
```

Expected: `AppShellTests` pass; 452 or more host tests pass with zero failures.

- [ ] **Step 6: Commit the live root**

```bash
git add ios/App/Sources/Map/MapDoorShell.swift ios/App/Sources/Map/MapScreen.swift ios/App/Tests/AppShellTests.swift
git commit -m "Build the unified Tracks door"
```

---

### Task 3: Rewrite the drift UI test and preserve destination coverage

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes IDs from Task 2.
- Proves the old Lists door path no longer exists.
- Proves My Tracks and custom-list rows navigate directly from one root.
- Preserves the existing list-detail, verdict-edit, map/retrace, create-list, and deep-link tests.

- [ ] **Step 1: Rewrite the drift-pinning test before changing its production expectations**

Replace `testTracksDoorAndListsMyTracksReachSameScreenIdentity` with `testTracksDoorIsTheSingleListsSurface`. It must:

1. Open `map.door.tracks`.
2. Assert `tracks.row.my-tracks`, a seeded `lists.row.<id>`, `lists.create.name`, and `lists.create` coexist on the root.
3. Assert `tracks.row.lists` and a `Lists` navigation bar do not exist.
4. Tap My Tracks and assert `lists.detail.surface.track`.
5. Back to the same root and tap the seeded non-track list directly.
6. Assert its list detail and `lists.detail.show-map`.

Name the break: restoring the two provisional row paths while both still happen to reach a list detail.

- [ ] **Step 2: Run only the rewritten UI test and verify RED**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -derivedDataPath /private/tmp/dd-codex3 \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testTracksDoorIsTheSingleListsSurface
```

Expected before Task 2 production wiring: FAIL because the root still exposes `tracks.row.lists` and does not expose list rows directly. If Task 2 is already green through unit wiring, temporarily run the test against its pre-Task-2 commit to record RED before restoring HEAD.

- [ ] **Step 3: Re-point existing UI callers from the removed Lists row**

For tests that need a non-track list, open Tracks and tap its `lists.row.<id>` directly. For tests that need My Tracks, tap `tracks.row.my-tracks`. Retain all downstream assertions and screenshots.

- [ ] **Step 4: Run the rewritten UI test and representative destination tests**

Run the Step 2 command and focused tests for:

- `testTracksDoorOpensUnifiedMyTracksVisitEditor`
- create-list behavior
- custom-list detail and `lists.detail.show-map`
- focused-place Tracks deep link

Expected: every focused test passes with zero failures.

- [ ] **Step 5: Commit the UI migration**

```bash
git add ios/App/UITests/MakingTracksCoreLoopUITests.swift
git commit -m "Pin the single Tracks surface"
```

---

### Task 4: Produce ruled renders and complete gates

**Files:**
- Create: `docs/design/design-system/t1.8-tracks-door.html`
- Create: `docs/design/design-system/t1.8-tracks-door.png`
- Create: `docs/design/design-system/t1.8-my-tracks-landing.html`
- Create: `docs/design/design-system/t1.8-my-tracks-landing.png`
- Modify: `docs/design/design-system/README.md`
- Modify: `docs/superpowers/phases/phase-1/tasks.md`

**Interfaces:**
- Door render is grounded in `ia-doors.html` frame 3 and shows no T1.9 rows.
- Landing render shows the existing chronological visit editor/list detail with `lists.detail.show-map` one tap away.

- [ ] **Step 1: Capture the real app door and hero landing**

Use only `scripts/sim-lock.sh` for simulator boot, launch, screenshots, or UI tests. Author committed HTML sources at 390×844 plus an accessibility variant and render their PNGs; mark the fold.

- [ ] **Step 2: Re-ground on fresh `origin/ios`**

```bash
git fetch origin ios
git merge-base --is-ancestor origin/ios HEAD
```

If stale, merge `origin/ios` as a bare mutation and rerun all gates.

- [ ] **Step 3: Run host and full simulator gates**

```bash
cd ios && swift test
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Record exact test counts and zero-warning evidence.

- [ ] **Step 4: Run adversarial critics and prove teeth**

Use independent spec-fidelity, correctness/coherence, untrusted-data/threat-model, and test-quality lenses. Cross-examine every finding. For every surviving fix, neuter the guarded production branch and prove at least one relevant test turns red, then restore and rerun green.

- [ ] **Step 5: Record `tests green` in both channels**

Change the T1.8 ledger status to `tests green`, commit it, and send the same checkpoint to fable over AMQ with exact counts and render paths.

- [ ] **Step 6: Commit and push the completed gate evidence**

```bash
git add docs/design/design-system docs/superpowers/phases/phase-1/tasks.md
git commit -m "Document the unified Tracks surface"
git push origin HEAD
```

---

### Task 5: Open and process the PR

**Files:**
- Modify through GitHub: PR body and labels.
- Modify: `docs/superpowers/phases/phase-1/tasks.md` at each checkpoint.

**Interfaces:**
- PR serves #470 and #266, task T1.8, target `ios`.
- Labels: `sourcery-review`, `track-b-ios`, `wp`.
- Review tier: Sourcery + Opus; no Greptile unless fable explicitly spends it.

- [ ] **Step 1: Confirm the final diff is scoped**

```bash
git diff --stat origin/ios..HEAD
git diff --check
git status --short
```

Expected: only T1.8 code, tests, ledger, plan, and render artifacts.

- [ ] **Step 2: Open the PR and apply labels immediately**

The body includes issue/task links, exact host/full-gate counts, render images, adversarial accounting, `## Taste guesses` if needed, and explicit notes that Loved/Hidden are reserved for T1.9 and render nothing.

- [ ] **Step 3: Record and send `PR open`**

Update the ledger on the branch, commit/push, and send the same checkpoint to fable.

- [ ] **Step 4: Process Sourcery and Opus**

Resolve or rebut every actionable thread with evidence. If Sourcery errors, follow the phase graph's recover-first service-degradation protocol and record run IDs/timestamps verbatim.

- [ ] **Step 5: Record and send `review clean` then `ready-to-merge`**

Each transition is written to the ledger, committed/pushed, and announced to fable over AMQ. Do not self-merge.

- [ ] **Step 6: After fable merges, remove the worktree and local branch**

Cleanup is the final step after verified merge. Confirm the remote feature branch state, prune, notify fable, and stand down.
