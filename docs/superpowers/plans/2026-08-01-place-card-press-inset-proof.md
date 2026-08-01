# Place-Card Press-Inset Device Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Discharge issue #575 and Phase 2 AC2.3 by proving on the assigned iOS simulator that the live text-only Hide button's pressed displacement is larger at Accessibility Dynamic Type than at default size.

**Architecture:** A DEBUG-only app fixture mounts the real production text-only quiet style through a wrapper that delegates SwiftUI's live `ButtonStyle.Configuration` and exposes its state outside the measured label crop. A seat-locked regeneration script takes lossless screenshots during repeated real taps, and a repository-native Swift/ImageIO analyzer selects genuine rest/pressed frames, measures their text bounds, and fails unless AX displacement is strictly greater than default.

**Tech Stack:** Swift 6, SwiftUI, XCUITest, CoreGraphics/ImageIO, Bash 3.2, `scripts/sim-lock.sh --seat codex4`.

## Global Constraints

- Build from `origin/ios` exact base `f667615` on `wp-575-press-inset-proof`; target `ios`.
- Fixture and state wrapper are DEBUG-only and change no production behavior.
- The wrapper delegates the live configuration to `MaterialQuietButtonStyle.textOnly(theme:)`; it never synthesizes, latches, or overrides `isPressed`.
- The fixture carries a fossil comment stating its evidence-only purpose and deliberate production-path coupling.
- Use repeated real taps. `XCUIElement.press(forDuration:)` is not accepted as press evidence.
- Every simulator operation goes through `./scripts/sim-lock.sh --seat codex4`; the regeneration script boots the seat on demand.
- Use stable derived data `/private/tmp/dd-codex4`; delete every task-created `.xcresult` after extracting counts.
- Evidence class is **deterministic fixture**. All four PNG SHA-256 values are reproduction oracles and a repeat regeneration must match byte for byte.
- Every frame carries dark-pixel count and bounding box beside it.
- The acceptance oracle is exact: default displacement is positive and AX displacement is strictly greater than default.
- Do not couple to codex1's concurrent #584 edits to existing evidence scripts; helper unification is post-merge work.

---

### Task 1: Mount the live place-card press fixture

**Files:**
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Modify: `ios/App/Sources/MakingTracksApp.swift`
- Modify: `ios/App/Sources/PlaceCard/PlaceCardSheet.swift`

**Interfaces:**
- Consumes: `PlaceCardActionAppearance.presentation(for:isSaved:)`, `MaterialQuietButtonStyle.textOnly(theme:)`, and SwiftUI `ButtonStyle.Configuration`.
- Produces: `PlaceCardPressEvidenceStyle`, `PlaceCardPressInsetEvidenceFixture`, launch argument `--ui-testing-place-card-press-evidence`, button identifier `place-card.press-evidence.hide`, and marker identifier `place-card.press-evidence.state`.

- [ ] **Step 1: Write the failing mounted-style test**

Add an app test that names the wished-for wrapper and requires its stored production style to be the ruled text-only strategy:

```swift
@MainActor
func testPlaceCardPressEvidenceStyleDelegatesToRuledProductionStyle() {
    let style = PlaceCardPressEvidenceStyle(theme: .snow)

    XCTAssertEqual(style.productionStyle.pressFeedback, .textInset(points: 1))
    XCTAssertEqual(style.action, .hide)
}
```

Add a fixture-body inspection that requires one `PlaceCardPressEvidenceStyle` descendant so a clone using `.plain` cannot satisfy the test.

- [ ] **Step 2: Verify RED**

Run:

```bash
./scripts/sim-lock.sh --seat codex4 xcodebuild -project ios/App/MakingTracks.xcodeproj -scheme MakingTracks -destination-timeout 5 -parallel-testing-enabled NO -disable-concurrent-destination-testing -derivedDataPath /private/tmp/dd-codex4 -only-testing:MakingTracksTests/AppShellTests/testPlaceCardPressEvidenceStyleDelegatesToRuledProductionStyle test
```

Expected: compile failure because `PlaceCardPressEvidenceStyle` and the fixture do not exist.

- [ ] **Step 3: Add the minimal DEBUG-only live wrapper and fixture**

In `PlaceCardSheet.swift`, add the evidence style and marker under `#if DEBUG`:

```swift
struct PlaceCardPressEvidenceStyle: ButtonStyle {
    let action = PlaceCardAction.hide
    let productionStyle: MaterialQuietButtonStyle

    init(theme: MaterialTheme = .snow) {
        productionStyle = .textOnly(theme: theme)
    }

    func makeBody(configuration: Configuration) -> some View {
        productionStyle.makeBody(configuration: configuration)
            .overlay(alignment: .topLeading) {
                PlaceCardPressEvidenceStateMarker(
                    isPressed: configuration.isPressed
                )
            }
    }
}
```

The marker uses exact fixture-only RGB values, exposes `rest` or `pressed` as its accessibility value, and sits outside the Hide-text crop. Add the required fossil comment immediately above the fixture: it is evidence-only, and direct coupling to the production style is deliberate so production divergence breaks the proof.

The fixture renders the production Hide title from `PlaceCardActionAppearance`, uses the production button typography and Snow tokens, applies `PlaceCardPressEvidenceStyle`, and gives the action a no-op closure.

In `MakingTracksApp`, recognize `--ui-testing-place-card-press-evidence` only under `#if DEBUG` and route it before `rootView`, following `ChipHitTargetFixture` and `DoorGlyphEvidenceFixture`.

- [ ] **Step 4: Verify GREEN**

Run the same focused app test. Expected: 1 passed, 0 failed.

- [ ] **Step 5: Add the focused UI tap-burst test RED then GREEN**

Extend the existing `launch` helper with `placeCardPressEvidence: Bool = false`. Add:

```swift
func testPlaceCardPressInsetEvidenceDefault() {
    exercisePlaceCardPressInsetEvidence(accessibilityTextSize: false)
}

func testPlaceCardPressInsetEvidenceAX() {
    exercisePlaceCardPressInsetEvidence(accessibilityTextSize: true)
}
```

The shared helper launches the fixture, asserts the Hide button and rest marker exist, exports the button frame and screen scale to the simulator-scoped artifact directory, then performs at least 80 real `tap()` calls. First run before adding the launch route must fail because the fixture button is absent; after the route is implemented both tests must pass.

- [ ] **Step 6: Commit the mounted fixture**

```bash
git add ios/App/Tests/AppShellTests.swift ios/App/UITests/MakingTracksCoreLoopUITests.swift ios/App/Sources/MakingTracksApp.swift ios/App/Sources/PlaceCard/PlaceCardSheet.swift
git commit -m "Add the live place card press fixture"
```

---

### Task 2: Build the fail-closed frame analyzer and regeneration runner

**Files:**
- Create: `docs/design/design-system/measure-place-card-press.swift`
- Create: `docs/design/design-system/regenerate-place-card-press-inset.sh`

**Interfaces:**
- Consumes: simulator-scoped PNG candidates, exported button frame records, exact rest/pressed marker RGB values, `MT_SIM_LOCK_UDID`, `MT_SIM_LOCK_DESTINATION`, and `MT_RELEASE_GATE_DERIVED_DATA`.
- Produces: four selected PNGs, per-frame ink/bounds measurements, exact displacement comparison, SHA-256 records, and nonzero exit on any missing/invalid state or failed growth property.

- [ ] **Step 1: Write the analyzer self-test first**

Create the Swift analyzer initially with a `--self-test` entry point that calls not-yet-defined functions against in-memory 30×30 RGBA fixtures. The fixtures contain a text-shaped dark rectangle at `y=8` for rest, `y=11` for default pressed, and `y=14` for AX pressed, plus exact marker pixels outside the crop. Assert:

```swift
precondition(defaultDelta == 3)
precondition(axDelta == 6)
precondition(axDelta > defaultDelta)
precondition(classify(restPixels) == .rest)
precondition(classify(pressedPixels) == .pressed)
```

- [ ] **Step 2: Verify analyzer RED**

Run:

```bash
xcrun swift docs/design/design-system/measure-place-card-press.swift --self-test
```

Expected: compile failure for the missing measurement and classification functions.

- [ ] **Step 3: Implement the minimal ImageIO analyzer**

Implement:

```swift
struct InkBounds: Equatable {
    let darkPixelCount: Int
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

enum LivePressState: String { case rest, pressed }

func classify(_ raster: Raster, marker: CGRect) throws -> LivePressState
func measureInk(_ raster: Raster, crop: CGRect, luminanceThreshold: UInt8) throws -> InkBounds
func displacement(rest: InkBounds, pressed: InkBounds) -> Int
```

Decode with `CGImageSourceCreateWithURL`, normalize into an 8-bit RGBA bitmap, reject non-finite/out-of-frame crops, require nonzero marker and ink samples, and use one documented luminance threshold for every frame. Candidate selection accepts only full live-state marker matches and chooses a fully displaced pressed frame, never an intermediate animation frame.

- [ ] **Step 4: Verify analyzer GREEN and mutation teeth**

Run `--self-test`; expected: `PASS default=3 ax=6`. Temporarily change AX fixture displacement to `3`; expected: nonzero exit at `AX displacement must exceed default`. Restore `6` and rerun green.

- [ ] **Step 5: Write the seat-locked regeneration script**

The Bash 3.2 script must:

1. fail unless `MT_SIM_LOCK=1` and the destination/UDID match;
2. boot through the already-owned wrapper environment;
3. use `/private/tmp/dd-codex4` and simulator-scoped temporary/export directories;
4. run the default UI tap-burst test while a background loop captures lossless PNG candidates from only `MT_SIM_LOCK_UDID`;
5. repeat for AX;
6. stop and reap every background screenshot process under a trap;
7. run the analyzer to select rest/pressed frames and enforce positive default plus AX-greater-than-default displacement;
8. stage output in a temporary directory, validate all four files, then install them into `docs/design/design-system`;
9. extract focused test counts and delete the exact `.xcresult`;
10. print measurements, SHA-256 values, tool versions, head, and destination.

No unexpanded glob or unvalidated environment variable may be a deletion target.

- [ ] **Step 6: Verify shell and analyzer checks**

Run:

```bash
bash -n docs/design/design-system/regenerate-place-card-press-inset.sh
```

Run:

```bash
shellcheck docs/design/design-system/regenerate-place-card-press-inset.sh
```

Run the analyzer self-test again. Expected: all checks pass.

- [ ] **Step 7: Commit the runner**

```bash
git add docs/design/design-system/measure-place-card-press.swift docs/design/design-system/regenerate-place-card-press-inset.sh
git commit -m "Add the press inset evidence runner"
```

---

### Task 3: Capture deterministic device evidence and prove the oracle's teeth

**Files:**
- Create: `docs/design/design-system/place-card-press-inset-default-rest.png`
- Create: `docs/design/design-system/place-card-press-inset-default-pressed.png`
- Create: `docs/design/design-system/place-card-press-inset-ax-rest.png`
- Create: `docs/design/design-system/place-card-press-inset-ax-pressed.png`
- Create: `docs/design/design-system/place-card-press-inset-evidence.md`
- Modify: `docs/design/design-system/README.md`
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`

**Interfaces:**
- Consumes: the exact-head fixture and regeneration runner.
- Produces: the issue #575 implementation-evidence packet and the AC2.3 closeout measurements.

- [ ] **Step 1: Boot and run the focused capture**

Run:

```bash
./scripts/sim-lock.sh --seat codex4 --boot
```

Then run:

```bash
MT_RELEASE_GATE_DERIVED_DATA=/private/tmp/dd-codex4 ./scripts/sim-lock.sh --seat codex4 ./docs/design/design-system/regenerate-place-card-press-inset.sh
```

Expected: default displacement greater than zero, AX displacement greater than default, both focused UI tests green, four PNGs installed, no result bundle retained.

- [ ] **Step 2: Prove scaled-metric teeth**

Temporarily neuter `MaterialButtonStyleBody` so the text inset uses its base `1` point at both size categories instead of the resolved scaled value. Rerun the regeneration command. Expected: nonzero exit because AX displacement is not greater than default. Restore the production line and rerun green.

- [ ] **Step 3: Prove live-state teeth**

Temporarily make the DEBUG marker report `.rest` regardless of `configuration.isPressed`. Rerun the focused regeneration. Expected: nonzero exit because no live pressed candidate exists. Restore the live configuration and rerun green.

- [ ] **Step 4: Prove deterministic-fixture reproduction**

Record the four SHA-256 values, run the unchanged regeneration command again, and compare freshly computed hashes. Expected: all four match byte for byte. Any mismatch is a finding; do not relabel the packet.

- [ ] **Step 5: Write the evidence record**

`place-card-press-inset-evidence.md` embeds the four frames in default and AX rest/pressed tables and states beside each image: dark-pixel count, bounding box, displacement, digest, exact source head, `codex4` seat/destination, Xcode version, capture method, evidence class, reproduction result, focused counts, mutation reds, and the full gate command.

Add one implementation-evidence row to `docs/design/design-system/README.md`. Add `evidence captured` and `tests green` transitions to the pre-phase ledger.

- [ ] **Step 6: Commit the packet**

```bash
git add docs/design/design-system/place-card-press-inset-default-rest.png docs/design/design-system/place-card-press-inset-default-pressed.png docs/design/design-system/place-card-press-inset-ax-rest.png docs/design/design-system/place-card-press-inset-ax-pressed.png docs/design/design-system/place-card-press-inset-evidence.md docs/design/design-system/README.md docs/superpowers/phases/pre-phase/tasks.md
git commit -m "Record device-real press inset growth"
```

---

### Task 4: Review, full gate, issue record, and PR handoff

**Files:**
- Modify if findings survive: only the files introduced or modified above.
- External record: GitHub issue #575 body.

**Interfaces:**
- Consumes: exact pushed candidate head, four deterministic fixture images, measurement record, review findings, host and simulator gate results.
- Produces: draft PR into `ios`, reviewer-tier handoff, and a coherent #575 Request / Outcome body ready for merger closure.

- [ ] **Step 1: Run adversarial review**

Use independent critics for spec fidelity, capture correctness/determinism, test teeth, and security/privacy. Cross-examine every claim, fix what survives, and prove each fix by mutation. Record Critical / Important / Minor raised, survived, and fixed.

- [ ] **Step 2: Run fresh verification**

Run:

```bash
swift test --package-path ios
```

Run the analyzer self-test and the focused regeneration again. Extract exact counts and remove task-created result bundles.

- [ ] **Step 3: Re-ground and run the full host gate**

Fetch current `ios`, integrate it if needed, inspect the two-dot diff for stale-base damage, and boot codex4. Then run exactly:

```bash
./scripts/sim-lock.sh --seat codex4 ./scripts/release-gate.sh
```

Record Release build, Debug build-for-testing, app/unit count, UI count, warnings, duration, and reusable derived-data path; delete the exact result bundle after count extraction.

- [ ] **Step 4: Rewrite issue #575 body**

Preserve its original rationale and replace the parked status with an Outcome section embedding the four frames beside their measurements. Link T2.2/#574, AC2.3, the exact source head, deterministic reproduction result, gate counts, and PR. Do not use a running-status comment as the record.

- [ ] **Step 5: Publish the draft PR**

Push the exact branch, open a draft PR into `ios`, and immediately apply `sourcery-review`, `track-b-ios`, and `wp`. The body names #575, includes the exact full-gate command and counts, evidence paths/digests, mutation reds, adversarial accounting, and `## Taste guesses` with `None` if no judgement remains.

- [ ] **Step 6: Request reviewer tier and process every comment**

Send AMQ `review_request` with PR number, exact pushed SHA, four artifact paths, measurements, deterministic reproduction result, tests, gate counts, and adversarial accounting. Process Sourcery and reviewer feedback with technical rigor; fix and re-gate any surviving code-bearing finding. The planner retains merge authority and closes #575 after merge.
