# Place-Card Press-Inset Device Proof Design

## Context and authority

Issue #575 is the device-real remainder of Phase 2 AC2.3. T2.2 replaced the fixed quiet-text press inset with an `@ScaledMetric` anchored to the paired button typography role, and host tests pin that anchor and the resolved-value wiring. The macOS host cannot prove how the metric resolves at iOS accessibility sizes. The required property is therefore visual and comparative: the enabled text-only quiet-button displacement must be larger at Accessibility Dynamic Type than at default size.

Rob's fix-now directive retires the previous wait for Phase 3 DS-7. The approved implementation is a focused simulator fixture following `ChipHitTargetFixture` and `DoorGlyphEvidenceFixture`: DEBUG-only, coupled deliberately to the production place-card style path, and executed under the codex4 simulator seat.

## Considered approaches

### 1. Focused live-configuration fixture — chosen

Add a DEBUG-only launch argument and fixture that mounts the Hide action's real text-only presentation through `PlaceCardActionStyleModifier`. Its action is a no-op so repeated real taps cannot navigate away. A small evidence wrapper receives SwiftUI's live `ButtonStyle.Configuration`, delegates that same configuration to `MaterialQuietButtonStyle.textOnly(theme:)`, and exposes whether the configuration is currently pressed outside the measured text region.

The regeneration runner captures a known resting PNG, then takes rapid lossless simulator screenshots during a burst of real taps. It accepts a pressed frame only when the wrapper's live state marker says pressed. This mirrors A5's corrected method: `XCUIElement.press(forDuration:)` is not evidence because it did not raise `configuration.isPressed`; real taps did.

This approach isolates the one contract while retaining the production style, typography, theme, scale, and device Dynamic Type resolution.

### 2. Full `PlaceCardSheet` fixture — rejected

Opening the complete sheet would add map, database, card-loading, detent, and action-state timing. None strengthens the press-inset proof, and Hide navigation makes a stable tap burst harder. The focused fixture uses the same production style path without unrelated runtime dependencies.

### 3. Synthetic pressed-state renderer — rejected

A manually supplied pressed Boolean would be deterministic but would bypass SwiftUI's live button configuration. It could produce convincing frames even if the production mount or device-resolved scaled metric were broken, so it cannot discharge #575.

## Source design

`MakingTracksApp` recognizes `--ui-testing-place-card-press-evidence` only in DEBUG fixture-map launches and renders `PlaceCardPressInsetEvidenceFixture` instead of the normal map shell. Release behavior and normal DEBUG launches are unchanged.

The fixture lives beside the place-card styling seam so it can use the actual Hide label shape and `PlaceCardActionStyleModifier`. It contains a fossil comment stating that it exists only for device evidence and that direct coupling to the production style path is deliberate: divergence must break the fixture rather than let an evidence clone drift.

`PlaceCardPressEvidenceStyle` is a DEBUG-only wrapper `ButtonStyle`. Its `makeBody(configuration:)` delegates the exact live configuration to `MaterialQuietButtonStyle.textOnly(theme:)`. The wrapper adds a state marker outside the label-measurement crop; it does not replace, override, latch, or synthesize `isPressed`.

The fixture uses a no-op action, the production Snow theme, the production button typography role, the production Hide title, and the `place-card.hide` accessibility identifier. The UI test launches it separately at default and Accessibility Dynamic Type, verifies that the button is present and hittable, and performs enough real taps for the capture runner to intersect a live pressed frame.

## Capture and measurement flow

The committed regeneration script is invoked only through:

```bash
./scripts/sim-lock.sh --seat codex4 ./docs/design/design-system/regenerate-place-card-press-inset.sh
```

It boots the assigned seat on demand, uses the stable `/private/tmp/dd-codex4` derived-data path, builds once, launches the focused UI evidence test at default and AX, and captures screenshots only through the assigned simulator inside the wrapper-owned lock. Temporary captures are scoped to the assigned simulator and removed on success or failure. No result bundle survives count extraction.

The host has no `ffmpeg`; frame analysis is repository-native Swift using ImageIO/CoreGraphics. The analyzer reads lossless PNG pixels, identifies live-rest and live-pressed marker states, isolates the Hide text region, and records for every selected frame:

- dark-pixel count;
- dark-pixel bounding box as `x,y,width,height` in device pixels;
- top-edge and centre displacement from rest to pressed;
- image dimensions and SHA-256.

The runner fails closed if either state is absent, the crop is empty, a frame is malformed, default displacement is not positive, or AX displacement is not strictly greater than default. That last inequality is P2R-1's ruled property and the issue's acceptance oracle.

## Evidence packet

The committed packet contains:

- `place-card-press-inset-default-rest.png`;
- `place-card-press-inset-default-pressed.png`;
- `place-card-press-inset-ax-rest.png`;
- `place-card-press-inset-ax-pressed.png`;
- `place-card-press-inset-evidence.md` with measurements, source head, simulator seat/destination, Xcode version, capture method, and full-gate command;
- `regenerate-place-card-press-inset.sh` plus its repository-native analyzer.

Evidence class is **deterministic fixture** under `docs/process/coordination.md`. Each PNG digest is a reproduction oracle, so a repeat regeneration must match all four files byte for byte. Measurements sit beside the corresponding frames rather than relying on visual impression.

The issue body is rewritten as one coherent Request / Outcome record with the four images embedded beside the measured default/AX comparison and links back to T2.2/#574 and AC2.3.

## Test and review design

TDD begins with app tests that name the new fixture launch route and the production-style delegation; they fail on the current tree because those types and route do not exist. The minimal DEBUG-only source then makes them green. The focused UI test must fail if the launch argument does not mount the evidence fixture or if the real Hide button cannot receive taps.

The device evidence itself has teeth in two independent ways:

1. replacing the scaled resolved inset with the unscaled base value must make the default/AX growth oracle fail;
2. bypassing live configuration or capturing only rest frames must make the pressed-state requirement fail.

Before publication, independent critics review spec fidelity, production-path coupling, capture determinism, test teeth, and security/privacy. This fixture consumes no user or source content and creates no network or persistence path; the threat-model review should therefore find no new in-scope attacker surface. The full codex4 Release gate remains mandatory because the app target and UI tests change.

## Scope limits and failure handling

This work changes no production behavior, action order, accessibility contract, stored data, network flow, colour, opacity, or typography figure. It does not answer the separate A5 pulse-family question for quiet destination rows.

Any failure to observe live pressed configuration, reproduce byte-identical deterministic-fixture digests, or prove AX displacement greater than default is a product/evidence failure, not a reason to weaken the oracle. Infrastructure failures are classified only under the iOS gate ledger's existing rules.
