# Design-system visual assets

## Frozen design-session record

These renders come from the IA / look-and-feel design session (Rob + fable-design, 2026-07-25).
The ratified spec is [`docs/superpowers/specs/2026-07-25-design-system-and-ia-design.md`](../../superpowers/specs/2026-07-25-design-system-and-ia-design.md);
these assets are its visual record and are embedded in the implementation epic.

| Asset | What it shows |
|---|---|
| `coherence.{html,png}` | One language, two materials: snow and mud map homes (identical geometry), snow place card, mud Tracks door. Pins never theme. |
| `ia-doors.{html,png}` | The map and its two doors (World / Tracks). **Predates one ruling:** Offline maps + Coverage moved to Settings and a Search slot joined the World door — see spec §2. The door pattern stands. |
| `typography.{html,png}` | The story-voice decision record: Newsreader ratified over Besley, Piazzolla, Literata (and over dropped Fraunces / Bricolage / New York), with research rationale inline. |
| `t1.10-place-card.{html,png}` | Default-size Snow place card: Newsreader title, token-resolved surfaces, natural-ratio media, and the one-filled-action hierarchy. |
| `t1.10-place-card-ax.{html,png}` | Accessibility-size place card at the large detent with a scroll fade and vertically stacked action controls. |
| `t1.10-place-card-dark-system.png` | Runtime UI-test capture with the simulator forced to dark appearance. The map and place card remain on the Snow material sheet; its source and pixel oracle live in `MakingTracksCoreLoopUITests.testPlaceCardKeepsSnowTokensInDarkSystemAppearance`. |

## A8 candidate packets — awaiting validation and ruling

These packets are candidate evidence for the A8 amendment work. They await reviewer
validation and Rob's ruling; they are **not** part of the frozen design-session
record, and the ratified component-metrics table remains unchanged until that ruling.

| Candidate sources and capture | What the packet proves |
|---|---|
| `a8-explore-surface.html` + `a8-explore-surface.png` | R14's collapsed Snow Explore surface at default and accessibility-size 390×844 frames: Scope opens directly, Search renders nothing, and Settings/About remain quiet bottom destinations. |
| `a8-r15-place-card.html` + `a8-r15-place-card.png` | R15/R16's fully lit Snow place-card cluster at default and accessibility-size 390×844 frames: Saved, Seen, and Loved are simultaneously ON as filled pills with filled glyphs, with per-pill AA contrast evidence. |

Both packets name `Playwright-bundled Chromium/headless shell 151.0.7922.34` as
their renderer. The following is the complete candidate metrics packet for reviewer
validation and Rob's ruling, not a spec-table amendment.

| Candidate metric | Value | Exact candidate source | Status |
|---|---|---|---|
| Explore sheet placement | 62pt large-detent top; 12pt grabber-to-title gap | `a8-explore-surface.html` | Proposed; pending validation and ruling |
| Scope control row | 52pt minimum; 15pt/600 label; 20×20 established icon; 10pt gap; 6/2 padding; 44×28 switch; 22pt knob at 3/19pt offsets; 1pt hairlines | `a8-explore-surface.html` | Proposed; pending validation and ruling |
| Scope block rhythm | 18pt header-to-label; 11pt label-to-chips; 14pt chips-to-controls; row minimum yields to wrapped content | `a8-explore-surface.html` | Proposed; pending validation and ruling |
| Quiet destination row | 9/2 padding; 10pt gap; 12×12 chevron; 2pt title-to-metadata gap | `a8-explore-surface.html` | Proposed; pending validation and ruling |
| AX Scope stress scaling | 86pt row minimum; 23pt/600 label; 30×30 icon; 14pt gap; 10/2 padding; 51×31 switch; 25pt knob at 3/23pt offsets; 14/9/14pt block rhythm; minimum yields to content | `a8-explore-surface.html` | Candidate AX evidence; pending validation and ruling |
| ON state-pill geometry | 44pt minimum target; 15pt/600 label; 17×17 filled glyph; 6pt glyph-to-label gap; 8pt between pills; separate 44pt More control | `a8-r15-place-card.html` | Established §5 metrics demonstrated by candidate |
| ON state semantic fills and contrast | Saved: #0A6B5C on #DEE9E0 = 5.15:1; Seen: #FBFAF2 on #0A6B5C = 6.13:1; Loved: #FBFAF2 on #C4312B = 5.25:1 | `a8-r15-place-card.html` | Candidate evidence; pending validation and ruling |
| AX state-pill stress scaling | 23pt label; 25×25 filled glyph; three stacked 64pt targets; 8pt inter-pill gap | `a8-r15-place-card.html` | Candidate AX evidence; pending validation and ruling |

## Implementation evidence

These renders record shipped implementation changes; they are not frozen design-session rulings.

| Asset | What it shows |
|---|---|
| `t1.5-map-theme-evidence.html` + `t1.5-map-theme-{before,after,after-ax}.png` | T1.5 before/after evidence at 390×844. One source selects `?variant=before`, `after`, or `ax`; the after render is the AC34 constant-pin pop check. |
| `t1.12-chip-geometry-evidence.html` + `t1.12-chip-geometry-{before,after,ax}.png` | T1.12 before/after and accessibility-size evidence at 390×844. One source selects `?variant=before`, `after`, or `ax`; the PNGs prove the 44pt-to-22pt visible capsule correction, while `MakingTracksCoreLoopUITests.testMaterialChipExtendsHitTargetBeyondVisualCapsule` proves the isolated target's action fires 11pt beyond both rendered edges. The host geometry test pins the component-owned 44pt target independently of undocumented platform button tolerance. `MaterialChip` documents the accepted overlap contract for dense same-action flows. |
| `t1.6-ia-shell.html` + `t1.6-ia-shell.png` | T1.6 implementation packet with exact 390×844 home, World-open, and Tracks-open frames. |
| `t1.6-ia-shell-ax.html` + `t1.6-ia-shell-ax.png` | T1.6 AX5 stress packet with exact 390×844 home and World large-detent frames under dark system appearance and solid Snow surfaces. |
| `t1.7-contextual-chrome.html` + `t1.7-contextual-chrome.png` | T1.7 default-size Snow map proof of the four contextual states: whole-surface offline download progress, location-off settings, nearby Seen it/dismiss, and tonal undo. |
| `t1.7-contextual-chrome-ax.html` + `t1.7-contextual-chrome-ax.png` | T1.7 AXXXL stress proof with long representative copy, 44pt controls, and the stacked `ViewThatFits` fallback. |
| `t1.8-tracks-door.html` + `t1.8-tracks-door.png` | T1.8 unified Tracks door packet with exact 390×844 default and AX5 frames: protected My tracks hero, every non-track list with non-colour progress counts, and New list. Loved and Hidden intentionally render nothing until T1.9. |
| `t1.8-my-tracks-landing.html` + `t1.8-my-tracks-landing.png` | T1.8 My tracks landing packet with exact 390×844 default and AX5 frames: chronological visit editor, one-filled-action hierarchy, and Map/Retrace one tap away. |
| `t1.9-loved-hidden-surfaces.html` + `t1.9-loved-hidden-surfaces.png` | T1.9 default-size implementation packet with three exact 390×844 frames: counted Loved/Hidden rows in the unified Tracks door, populated Loved places with explicit remove-loved controls and visible hidden overlap, and populated Hidden places with explicit Unhide controls. |
| `t1.9-loved-hidden-surfaces-ax.html` + `t1.9-loved-hidden-surfaces-ax.png` | T1.9 AX5 stress packet with three exact 390×844 frames: large-detent Tracks entry points plus Loved/Hidden collections whose independent, non-colour action controls remain at least 44pt and inside the Snow surface. |

HTML files are self-contained (fonts load from Google Fonts when online; system fallbacks otherwise).
