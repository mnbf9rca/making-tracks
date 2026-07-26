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
