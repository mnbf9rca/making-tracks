# Explore destination-row press-pulse implementation evidence

This packet records runtime implementation evidence for issue #595. It is not a new design ruling.
The designer ruled that the enabled, glyphed Settings and About rows join the existing
symbol-weight pulse family. The planner separately ruled the label-preserving adapter and the
live-edge evidence latch used to prove that enrollment.

## What the packet proves

- The production `ExploreQuietDestinationRow` mounts `MaterialQuietRowButtonStyle`, which delegates
  to `MaterialControlPressFeedback.symbolWeightPulse` and adds no resting chrome.
- Settings and About both capture a resting and pressed frame at default and AX text sizes.
- Every pressed frame is reachable only after a genuine live
  `ButtonStyle.Configuration.isPressed == true` edge from repeated `XCUIElement.tap()` calls.
- Every case records at least one live edge; the captured run recorded 100 edges per case.
- Pressed glyph crops differ from rest and contain more ink, while host rendering tests require the
  complete row at rest to remain byte-identical to the pre-enrollment rendering.
- `XCUIElement.press(forDuration:)` is excluded because it does not raise the production pressed
  configuration used by this evidence path.

## Evidence classification and provenance

The canonical evidence class is **Nondeterministic content**. The phrase
`latched from live press edge` is provenance for the pressed frame, not another evidence class.
The latch is test-only SPI consumed inside the production row style. Only a rising live pressed edge
can set it or increment the edge count; removing the mounted style or severing its live
configuration path leaves the count at zero and fails the UI test.

Each PNG is paired with a same-case `.txt` record containing the exact app, row, and icon frames,
selected candidate names, marker counts, glyph ink counts and bounds, pressed-minus-rest ink, and
the observed live-edge count. [`explore-row-press-pulse-captures.txt`](explore-row-press-pulse-captures.txt)
records the source head, clean-tree assertion, destination, capture interval, toolchain, hashes, and
all four measurement records.

A clean-worktree repeat capture from `bcf9ba4ba3b4b328e3e9bca9bfac2597d5046aa4` reproduced all
eight PNGs and all four measurement records byte-for-byte. Only the capture metadata's source head,
interval, and ephemeral staging paths changed between runs.

## Frames

| Row | Default | Accessibility size |
|---|---|---|
| Settings | `explore-row-press-settings-default-{rest,pressed}.png` | `explore-row-press-settings-ax-{rest,pressed}.png` |
| About | `explore-row-press-about-default-{rest,pressed}.png` | `explore-row-press-about-ax-{rest,pressed}.png` |

The full-screen DEBUG fixture deliberately keeps the tap counter, live-edge counter, state marker,
and colored analyzer markers outside the measured glyph crop. The analyzer fails closed for missing
or non-positive live-edge counts, invalid dimensions or frames, missing markers, identical glyph
crops, or pressed crops that do not increase glyph ink.

## Regeneration

Run from a clean committed worktree through the assigned simulator seat:

```bash
./scripts/sim-lock.sh --seat codex1 ./docs/design/design-system/regenerate-explore-row-press-pulse.sh
```

The script builds through `release-gate.sh`, runs exactly four focused UI tests, captures candidates
while each test performs 100 real taps, analyzes the four cases into eight selected frames, stages a
complete packet, and installs it atomically. It verifies the source head and clean worktree again
before installation and removes its result bundle and task directory on exit.
