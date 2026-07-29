# A8 Explore and R15 Render Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author the two A8 candidate render packets that let the reviewer validate R14's collapsed Explore surface and R15/R16's fully-lit place-card state cluster before Rob rules them frozen.

**Architecture:** Add one self-contained HTML source and one PNG packet per ruled surface. Each packet contains an exact 390×844 default frame, an exact 390×844 accessibility-size frame, and an evidence panel beside the frames; the phone frames show only legitimate target UI, while annotations and measurements remain outside the phone canvas. Reuse ratified Snow tokens and component metrics, propose only the minimum new metrics, and keep the assets labelled `CANDIDATE` until reviewer validation and Rob's ruling.

**Tech Stack:** Static HTML/CSS/SVG, Playwright-bundled Chromium/headless shell `151.0.7922.34`, WCAG 2.x sRGB contrast calculations, PNG pixel inspection, repository Markdown lint.

## Global Constraints

- Start from the assigned pushed head `22902a808643c85023438a0b6f755f74e6dd4eba`, then merge the freshly fetched `origin/ios` before authoring.
- A8 is render work, not app implementation: do not change Swift, tests, accessibility identifiers, or production tokens.
- The Explore frame opens Scope directly; it contains no intermediate row list and no visible Search placeholder.
- Settings and About are quiet bottom rows; Settings' gear is the more prominent of the two.
- The R15 frame shows the fully-lit state cluster alone: Saved, Seen, and Loved simultaneously ON; no fabricated filled action appears beside it.
- ON state is carried by filled pill plus filled glyph, never colour alone.
- Seen uses `accent` `#0A6B5C`; Loved uses `love` `#C4312B`. Saved's former 12%-accent-over-surface `#DEE9E0` construction is a **rejected decision record**, not a candidate token.
- The replacement Saved comparison contains three designed opaque candidates, none ratified: Calm `#DFEDEB`, Balanced `#D4EDE9`, and Vivid `#CAECE6`. Each keeps accent ink `#0A6B5C`, remains within `1.31°` of accent's `170.72°` hue, and clears the 4.5:1 body-text gate.
- Per-pill foreground/background contrast is printed beside the R15 image. Seen remains `#FBFAF2` on `#0A6B5C` = `6.13:1`; Loved remains `#FBFAF2` on `#C4312B` = `5.25:1`; Saved's comparison prints the hue, hue delta, saturation, contrast, and non-composite proof for every candidate.
- HTML captures use Playwright-bundled Chromium only, never the system browser; renderer name and version appear beside both packets.
- Every new load-bearing figure is proposed in the spec's component-metrics table with its candidate source. Existing figures cite their existing table row rather than being silently redefined.
- Candidate assets become frozen only after reviewer validation and Rob's ruling.

---

## Post-validation Rob rulings — 2026-07-29

These rulings supersede the original Saved construction and extend the Explore frame before freeze:

1. Place-type chips keep the filled-chip selected morphology but replace the generic checkmark with
   the canonical category pin symbol. A second checkmark is deliberately not added.
2. Scope gains a `Show saved places` row, default ON, between `Include hidden places` and coverage.
   This preserves today's discovery-map default.
3. Container tokens are designed opaque colours in the `loveContainer` / `warningContainer` family,
   never mechanical composites. `#DEE9E0` remains visible only as the labelled rejected candidate
   that caused the rule to be made.
4. The approved Saved comparison is:

| Candidate | Hex | Hue | Delta from accent | Saturation | Contrast with `#0A6B5C` | Implied-alpha spread |
|---|---|---:|---:|---:|---:|---:|
| Calm | `#DFEDEB` | `171.43°` | `+0.71°` | `28.00%` | `5.34:1` | `0.0695` |
| Balanced | `#D4EDE9` | `170.40°` | `−0.32°` | `40.98%` | `5.23:1` | `0.1018` |
| Vivid | `#CAECE6` | `169.41°` | `−1.31°` | `47.22%` | `5.09:1` | `0.1233` |

The differing per-channel implied alphas prove these are not a single accent-over-surface composite.
The names are comparison labels, not token names. Rob picks and ratifies the actual value only after
reviewer delta validation.

---

### Task 1: Author the collapsed Explore candidate packet

**Files:**
- Create: `docs/design/design-system/a8-explore-surface.html`
- Create after rendering: `docs/design/design-system/a8-explore-surface.png`

**Interfaces:**
- Consumes: spec §2 R14; existing `ia-doors` Snow tokens; component-metrics rows for sheets, titles, section labels, chips, Explore icons, and quiet rows
- Produces: one reviewable packet containing default and AX 390×844 target frames plus beside-frame evidence

- [ ] **Step 1: Build the default 390×844 phone**

Render the Snow map under a large-detent sheet titled `Explore` with subtitle `what the map shows right now`. The first visible content is the Scope control set: category chips with their canonical pin symbols, followed by `Include hidden places` OFF, `Show saved places` ON, and `Show coverage shading` ON. Keep the Search slot structural and invisible—no disabled row, placeholder, empty rectangle, or fabricated copy.

- [ ] **Step 2: Build the AX 390×844 phone**

Use the same information and ordering at accessibility-size type. Allow chips to wrap and rows to grow; keep every control inside the sheet and keep Settings/About reachable at the bottom of the scroll presentation.

- [ ] **Step 3: Put evidence outside the phones**

Beside each phone, state: exact `390×844` canvas; Search renders nothing; Scope is the root; Settings and About are quiet bottom rows; Settings uses the stronger accent treatment while About remains muted. List every reused table metric by name and list the proposed new Scope-row metrics.

### Task 2: Author the fully-lit R15 candidate packet

**Files:**
- Create: `docs/design/design-system/a8-r15-place-card.html`
- Create after rendering: `docs/design/design-system/a8-r15-place-card.png`

**Interfaces:**
- Consumes: spec §5 R15/R16; Snow token values; `t1.10-place-card` structure; component-metrics rows for the action bar and control-label icon pairing
- Produces: one reviewable packet containing default and AX 390×844 target frames plus per-ON-pill AA evidence

- [ ] **Step 1: Reuse the legitimate place-card target**

Use the existing Snow place-card content and More control. Replace only the action bar with Saved, Seen, and Loved simultaneously ON. Give each pill a filled SF-style glyph and matching label; do not show Hide or any filled action.

- [ ] **Step 2: Preserve the rejected Saved record and compare opaque candidates**

Keep the original Saved `#DEE9E0` render labelled `REJECTED`: it is the dead 12%-composite candidate, not a value. Beside it compare Calm `#DFEDEB`, Balanced `#D4EDE9`, and Vivid `#CAECE6` as designed opaque candidates with accent foreground. Seen remains `#0A6B5C` with `accentContrast`, and Loved remains `#C4312B` with `accentContrast`. Keep the 44pt target floor, 15pt/600 labels, 17×17 glyph pairing, 6pt label gap, and 8pt between pills.

- [ ] **Step 3: Put the contrast proof beside both images**

Print the foreground/background hex pairs and ratios next to the default and AX phones. For each Saved candidate also print hue, delta from accent's hue, saturation, and the implied-alpha spread proving it is not a mechanical composite. State explicitly that every live comparison clears the 4.5:1 body-text gate, none is ratified, and the cluster contains no action, per the amended A8 criterion.

### Task 3: Render and verify the packets

**Files:**
- Modify as needed for capture provenance or capture-only corrections: `docs/design/design-system/a8-explore-surface.html`
- Modify as needed for capture provenance or capture-only corrections: `docs/design/design-system/a8-r15-place-card.html`
- Create: `docs/design/design-system/a8-explore-surface.png`
- Create: `docs/design/design-system/a8-r15-place-card.png`

**Interfaces:**
- Consumes: the two self-contained HTML sources
- Produces: deterministic PNG packets and exact measurement evidence

- [ ] **Step 1: Capture with Playwright-bundled Chromium**

Use the Playwright-bundled Chromium/headless-shell install under `~/Library/Caches/ms-playwright` through the locally installed Playwright runtime. Do not use Brave or another system browser. Capture at device scale factor 1 with each browser viewport set to the HTML packet's declared canvas.

- [ ] **Step 2: Verify PNG dimensions and colours**

Use `sips` for dimensions and a local pixel reader for the exact state-pill foreground/background samples. Independently recompute WCAG ratios from the sampled RGB values; reject any capture whose samples do not match the printed figures after integer rounding.

- [ ] **Step 3: Inspect both PNGs at original detail**

Confirm the phone canvases are exactly 390×844, no frame clips, the AX layouts remain readable, the Explore frame has no visible Search placeholder, and the R15 cluster contains only the three state toggles. Record `Playwright-bundled Chromium/headless shell 151.0.7922.34` beside each packet.

### Task 4: Wire the candidate artifact record

**Files:**
- Modify: `docs/design/design-system/README.md`

**Interfaces:**
- Consumes: measured candidate assets
- Produces: discoverable candidate records and a complete proposed-metrics packet ready for reviewer/Rob ruling

- [ ] **Step 1: Add candidate rows to the asset README**

Describe both sources/PNGs as A8 candidate packets awaiting reviewer validation and Rob's ruling. Do not add them to the frozen-record table yet.

- [ ] **Step 2: Keep proposed metrics in the candidate evidence**

Ensure the candidate packets contain the minimum rows needed for Scope toggles and state pills, including all values and the exact candidate source names. Do not amend the ratified spec before Rob rules.

- [ ] **Step 3: Run document checks**

Run `python3 scripts/lint_agent_law.py`, any repository Markdown/link checks available for the changed paths, and a search proving neither source contains `filled action`, an interactive Search placeholder, or an unaccounted load-bearing metric.

### Task 5: Review, ruling, and handoff

**Files:**
- Modify after rulings: the two candidate HTML sources, README, component-metrics rows in `docs/superpowers/specs/2026-07-25-design-system-and-ia-design.md`, and A8 status only as required by findings

**Interfaces:**
- Consumes: exact pushed SHA, two PNG packets, measurements, and checks
- Produces: reviewer validation request, Rob ruling gate, and a PR-ready exact head

- [ ] **Step 1: Run adversarial self-review**

Use distinct critics for spec fidelity, internal coherence, visual feasibility/correctness, hostile-content posture, and evidence quality. Cross-examine findings, fix what survives, and report raised/survived/fixed counts.

- [ ] **Step 2: Push the exact candidate head**

Copy the full SHA from `git rev-parse HEAD`, push it, and verify the remote branch resolves to the same SHA.

- [ ] **Step 3: Request reviewer validation**

Send the reviewer the exact SHA, both artifact paths, and the contrast/geometry evidence on `wp/526/a8`. Ask for design validation, not taste ruling.

- [ ] **Step 4: Route the validated candidates to Rob**

After reviewer validation, raise the human gate through the planner/reviewer workflow. Do not relabel the assets frozen or open the final PR before Rob rules.

- [ ] **Step 5: Apply the ruling and complete repository gates**

Fold any ruled changes, remove `candidate` markers only if Rob approves, update A8's ledger transition in both the tree and AMQ, run the docs-only gate set, re-ground on fresh `origin/ios`, inspect the two-dot diff, and open a ready PR into `ios` with `sourcery-review`, `track-b-ios`, and `wp`.

### Task 6: Apply Rob's post-validation Explore and container-token rulings

**Files:**
- Modify: `docs/design/design-system/a8-explore-surface.html`
- Recapture: `docs/design/design-system/a8-explore-surface.png`
- Modify: `docs/design/design-system/a8-r15-place-card.html`
- Recapture: `docs/design/design-system/a8-r15-place-card.png`
- Modify: `docs/design/design-system/README.md`

**Interfaces:**
- Consumes: Rob's approved canonical-icon interpretation, Saved-visibility wording/default, opaque-container law, and three-candidate comparison
- Produces: two updated candidate packets and an exact pushed SHA for reviewer delta validation and Rob's final value pick

- [ ] **Step 1: Replace generic category checks with canonical symbols**

Use the existing category registry mapping: Archaeological `hammer`, Artwork `paint palette`,
Attraction `star`, Historic Building `two buildings`, Memorial `flag`, Museum `camera`,
Religious `columns`, and Other `question mark`. Preserve the filled-chip selected morphology.

- [ ] **Step 2: Add the Saved visibility row**

Add `Show saved places` with a bookmark icon and an ON switch between Include hidden and coverage
in both default and AX frames. Account for the third row in the candidate metrics and prove the AX
bottom destinations remain reachable.

- [ ] **Step 3: Replace the settled-looking Saved evidence with the ruled comparison**

Label `#DEE9E0` rejected and retain its composite derivation as the decision record. Add the three
approved candidate swatches and the complete metrics in the beside-frame evidence; do not apply a
candidate as though Rob had picked it.

- [ ] **Step 4: Recapture and verify both packets**

Use only Playwright-bundled Chromium/headless shell `151.0.7922.34` at DSF 1. Verify 1540×980
PNGs, exact 390×844 phones, evidence-panel fit, scroll reachability, canonical icon inventory,
Saved row ordering/default, rejected/candidate labels, colour samples, HSL figures, WCAG ratios,
and deterministic repeat-capture hashes.

- [ ] **Step 5: Update discovery and route the exact SHA**

Update the README's candidate metrics/status without touching the frozen table or ratified spec,
run docs checks, commit signed, push and verify the exact remote SHA, then request scoped reviewer
delta validation before Rob picks the Saved value.
