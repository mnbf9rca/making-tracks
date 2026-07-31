# Saved ON Candidate Panel v2 — Design

**Status:** Approved for implementation by planner on 2026-07-30 and updated
for the designer's three riders. On 2026-07-31 Rob ratified Deep Companion
`#08483E` as the accent-family dark Saved ON fill carrying `accentContrast`
ink with the explicit pick “Deep is fine”; panel SHA `4421612` is the decision
provenance. Accent reuse `#0A6B5C` is the rejected alternative.

## Purpose

Produce deterministic evidence for the designer to verify the default Saved ON
winner after the first ratified `accentContainer` value proved too close to the
live Saved OFF tonal wash.

This is evidence work adjacent to A8, not a new amendment-wave row. It changes
no production token, Swift source, test, frozen A8 artifact, or phase ledger.

## Binding decision

The designer selected the two-ink inversion:

- Saved OFF remains dark `accent` ink on the existing tonal wash, with an
  outline bookmark.
- Saved ON uses light `accentContrast` ink on a dark, designed-opaque
  accent-family fill, with a filled bookmark.
- `#D4EDE9` is retired from the Saved ON role without prejudice. It is not a
  candidate in this panel.
- The attempted `1.5:1` ON/OFF fill-separation floor is withdrawn. Fill
  separation is measured and stated, with no replacement floor.
- Fact identity remains bookmark + `Saved` label + fixed first position. State
  is carried by the whole-pill ink/fill inversion and outline-to-filled glyph,
  never by colour alone.

The canonical R16 rider now says Saved fills an **accent-family dark fill
carrying `accentContrast` ink**. The former “tonal-strength companion” wording
was retired in
`docs/superpowers/specs/2026-07-25-design-system-and-ia-design.md` at merged
`ios` commit `ecf98db7778ad7b4ca7f08487e375fd45005f7d3` (PR #555); the
same-ink separation statement was then qualified for pinned values at
`1afcc3febb7b18a676a654305fea9af591c52eb3` (PR #556).

The panel presents the two alternatives evaluated for the decision:

1. **Accent reuse** — `#0A6B5C`, rejected.
2. **Deep Companion** — `#08483E`, ratified.

These are comparison labels, not token names.

## Constraint structure

Every candidate must publish and render all seven checks. Only the checks
explicitly called hard gates below are pass/fail bars.

1. **Saved ON ink — hard gate.** `accentContrast #FBFAF2` against the
   candidate fill is at least `4.5:1` for the 15pt/600 default label.
2. **Saved ON versus Saved OFF — stated, no floor.** Measure the candidate fill
   against the fixed OFF composite `#DEE9E0`.
3. **Saved ON versus Seen ON — stated pick evidence, no floor.** Measure the
   candidate fill against live Seen ON `#0A6B5C`. Candidate 1's exact
   `1.0000:1` result must be prominent rather than buried.
4. **Saved ON versus Loved ON — stated cluster evidence, no floor.** Measure
   the candidate fill against live Loved ON `#C4312B`.
5. **Saved OFF invariant — hard gate.** `accent #0A6B5C` on tonal wash
   `#DEE9E0` remains `5.1484:1`, with an outline bookmark. The panel does not
   change the wash construction.
6. **Fully-lit cluster — required visual evidence.** Render Saved, Seen, and
   Loved simultaneously ON for every candidate at the exact target geometry.
   The designer evaluates the three facts together in the R16 worst case.
7. **Independent state morphology — hard gate.** Saved ON is light-on-dark
   with a filled bookmark; Saved OFF is dark-on-tonal with an outline bookmark.

Sibling-fill differences have no numeric acceptance floor. Before the human
pick, the binding comparison rule made Deep Companion the default because it
is distinguishable from Seen and reserved Accent reuse as the fallback only if
Deep Companion read as a confusing third semantic or failed a hard gate. Rob's
explicit pick ratified Deep Companion and closed that fallback; Accent reuse is
the rejected alternative.

## Candidate measurements

All figures use WCAG 2.x sRGB relative luminance and contrast calculations on
the exact integer RGB values.

| Measurement | Accent reuse | Deep Companion |
|---|---:|---:|
| Fill | `#0A6B5C` | `#08483E` |
| Hue | `170.7216°` | `170.6250°` |
| Hue delta from accent | `0.0000°` | `−0.0966°` |
| HSL saturation | `82.9060%` | `80.0000%` |
| HSL lightness | `22.9412%` | `15.6863%` |
| Relative luminance | `0.113526` | `0.050342` |
| `#FBFAF2` ink against fill | `6.1330:1` | `9.9950:1` |
| Fill against OFF `#DEE9E0` | `5.1484:1` | `8.3903:1` |
| Fill against Seen `#0A6B5C` | `1.0000:1` | `1.6297:1` |
| Fill against Loved `#C4312B` | `1.1684:1` | `1.9042:1` |

The candidate space is feasible before rendering: candidate 1 itself proves
the binding ink gate is non-empty, and Deep Companion clears the same gate with
substantial margin while improving both sibling comparisons.

## Construction choice

Deep Companion gains distinction through depth inside accent's own hue
(`−0.0966°`), rather than importing another semantic hue. Its `80%` saturation
also happens to sit inside the historical `56–81%` container band, but that
retired light-container band is context, not a current acceptance rule.

Deep Companion was therefore the default winner during comparison. The
fully-lit cluster rows tested the single allowed reversal: whether that dark
companion read as a clean third fact or as a confusing third semantic beside
live Seen and Loved. The explicit human pick settled that comparison in Deep
Companion's favour.

Two alternatives were considered and are recorded only as Taste guesses:

- **Cool-shift Deep `#064852`** — not presented because its `+17.17°` hue shift
  adds blue/water semantics and it is lower than Deep Companion on ink,
  Seen separation, and Loved separation: `9.7534:1`, `1.5903:1`, and
  `1.8582:1`, respectively.
- **Softer Cool `#0B4D56`** — not presented because it gives up sibling
  separation and ink margin relative to Deep Companion without gaining a
  binding benefit: ink `9.0755:1`, Seen `1.4798:1`, and Loved `1.7290:1`.

## Artifact topology

Create one self-contained responsive source:

`docs/design/design-system/a8-saved-on-candidate-v2.html`

Capture it into two deterministic assets:

- `docs/design/design-system/a8-saved-on-candidate-v2-default.png`
- `docs/design/design-system/a8-saved-on-candidate-v2-ax.png`

Each PNG is exactly `1540×980` at device scale factor 1. Both come from the
Playwright-bundled Chromium/headless shell used by the frozen A8 packet, not a
system browser. Publish the renderer identity, dimensions, and SHA-256 digest
for each capture. Each mode's repeat must be byte-identical to its first
capture.

Do not recapture or modify the frozen A8 frame. Its unchanged digest is the
comparison anchor.

## Canvas anatomy

Each canvas contains two candidate columns. Each column contains:

1. **State-axis strip:** Saved OFF beside Saved ON for that candidate.
2. **Fully-lit row:** Saved ON, live Seen ON, and live Loved ON simultaneously.
3. **Measurement card:** all seven checks, exact token pairs, ratios, hue,
   saturation, renderer provenance, and candidate status.

The default canvas reuses the frozen A8 default pill geometry exactly:

- 44px minimum height
- 15px/600 label
- 17×17px glyph
- 6px glyph/label gap
- 8px between pills

The AX canvas reuses the frozen A8 AX pill geometry exactly:

- 64px minimum height
- 23px label
- 25×25px glyph
- 8px glyph/label gap
- vertically stacked three-pill cluster

Pills render at native pixel scale. The layout must never shrink a pill or use
scaled screenshots to make the evidence fit.

## Visual semantics

- Saved OFF: `#0A6B5C` label and outline bookmark on `#DEE9E0`.
- Candidate Saved ON: `#FBFAF2` label and filled bookmark on the candidate.
- Seen ON: `#FBFAF2` label and filled eye on `#0A6B5C`.
- Loved ON: `#FBFAF2` label and filled heart on `#C4312B`.
- Candidate 1 intentionally shares Seen's fill. Its `1.0000:1` measurement and
  the resulting cluster trade stay visible.
- Candidate 2 carries the panel's pre-decision default-winner label; the
  subsequent human pick ratifies it as the Saved ON fill.
- The packet carries no action, CTA, fabricated state, or new product copy.

## Validation and decision record

The pre-decision evidence gate required:

1. Recompute every published colour figure independently from the exact hexes.
2. Verify both captures are `1540×980`, use the sanctioned renderer, and each
   repeat capture is byte-identical to the first capture of the same mode.
3. Inspect both PNGs at original resolution for true geometry, clipping,
   typography, and all-three-ON cluster completeness.
4. Confirm the tracked diff is documentation/static evidence only and contains
   no `ios/`, script, workflow, test, or ledger change.
5. Send the exact pushed SHA, both PNG digests, and all seven checks to the
   reviewer.

After reviewer validation, Rob selected Deep Companion on 2026-07-31 with
“Deep is fine”; the validated panel at SHA `4421612` is the decision
provenance. Ratification settles the Saved ON fill design, but it does not by
itself wire the fill into production code, create a production token, or turn
the panel into a frozen implementation packet.
