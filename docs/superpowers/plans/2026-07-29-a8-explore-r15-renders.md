# A8 Explore and R15 Render Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author the two A8 candidate render packets that let the reviewer validate R14's collapsed Explore surface and R15/R16's fully-lit place-card state cluster before Rob rules them frozen.

**Architecture:** Add one self-contained HTML source and one PNG packet per ruled surface. Each packet contains an exact 390×844 default frame, an exact 390×844 accessibility-size frame, and an evidence panel beside the frames; the phone frames show only legitimate target UI, while annotations and measurements remain outside the phone canvas. Reuse ratified Snow tokens and component metrics, propose only the minimum new metrics, and keep the assets labelled `CANDIDATE` until reviewer validation and Rob's ruling.

**Tech Stack:** Static HTML/CSS/SVG, the locally installed Chromium browser (Brave on this machine), WCAG 2.x sRGB contrast calculations, PNG pixel inspection, repository Markdown lint.

## Global Constraints

- Start from the assigned pushed head `22902a808643c85023438a0b6f755f74e6dd4eba`, then merge the freshly fetched `origin/ios` before authoring.
- A8 is render work, not app implementation: do not change Swift, tests, accessibility identifiers, or production tokens.
- The Explore frame opens Scope directly; it contains no intermediate row list and no visible Search placeholder.
- Settings and About are quiet bottom rows; Settings' gear is the more prominent of the two.
- The R15 frame shows the fully-lit state cluster alone: Saved, Seen, and Loved simultaneously ON; no fabricated filled action appears beside it.
- ON state is carried by filled pill plus filled glyph, never colour alone.
- Seen uses `accent` `#0A6B5C`; Loved uses `love` `#C4312B`; Saved uses the existing tonal-strength recipe, 12% `accent` composited over `surface`, yielding `#DEE9E0`.
- Per-pill foreground/background contrast is printed beside the R15 image: Saved `#0A6B5C` on `#DEE9E0` = `5.15:1`; Seen `#FBFAF2` on `#0A6B5C` = `6.13:1`; Loved `#FBFAF2` on `#C4312B` = `5.25:1`.
- Every new load-bearing figure is proposed in the spec's component-metrics table with its candidate source. Existing figures cite their existing table row rather than being silently redefined.
- Candidate assets become frozen only after reviewer validation and Rob's ruling.

---

### Task 1: Author the collapsed Explore candidate packet

**Files:**
- Create: `docs/design/design-system/a8-explore-surface.html`
- Create after rendering: `docs/design/design-system/a8-explore-surface.png`

**Interfaces:**
- Consumes: spec §2 R14; existing `ia-doors` Snow tokens; component-metrics rows for sheets, titles, section labels, chips, Explore icons, and quiet rows
- Produces: one reviewable packet containing default and AX 390×844 target frames plus beside-frame evidence

- [ ] **Step 1: Build the default 390×844 phone**

Render the Snow map under a large-detent sheet titled `Explore` with subtitle `what the map shows right now`. The first visible content is the Scope control set: category chips followed by `Include hidden places` and `Show coverage shading`. Keep the Search slot structural and invisible—no disabled row, placeholder, empty rectangle, or fabricated copy.

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

- [ ] **Step 2: Apply the ruled semantic fills**

Use Saved `#DEE9E0` with accent foreground, Seen `#0A6B5C` with `accentContrast`, and Loved `#C4312B` with `accentContrast`. Keep the 44pt target floor, 15pt/600 labels, 17×17 glyph pairing, 6pt label gap, and 8pt between pills.

- [ ] **Step 3: Put the contrast proof beside both images**

Print the foreground/background hex pairs and ratios next to the default and AX phones. State explicitly that every pair clears the 4.5:1 body-text gate and that the cluster contains no action, per the amended A8 criterion.

### Task 3: Render and verify the packets

**Files:**
- Create: `docs/design/design-system/a8-explore-surface.png`
- Create: `docs/design/design-system/a8-r15-place-card.png`

**Interfaces:**
- Consumes: the two self-contained HTML sources
- Produces: deterministic PNG packets and exact measurement evidence

- [ ] **Step 1: Capture with local Chrome**

Use `/Applications/Brave Browser.app/Contents/MacOS/Brave Browser` in headless mode with `--force-device-scale-factor=1`, `--hide-scrollbars`, no background networking or component updates, and dedicated profiles under `/private/tmp/chrome-a8-*`. Size each browser window to the HTML packet's declared canvas.

- [ ] **Step 2: Verify PNG dimensions and colours**

Use `sips` for dimensions and a local pixel reader for the exact state-pill foreground/background samples. Independently recompute WCAG ratios from the sampled RGB values; reject any capture whose samples do not match the printed figures after integer rounding.

- [ ] **Step 3: Inspect both PNGs at original detail**

Confirm the phone canvases are exactly 390×844, no frame clips, the AX layouts remain readable, the Explore frame has no visible Search placeholder, and the R15 cluster contains only the three state toggles.

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
