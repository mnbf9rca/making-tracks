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

## A8 frozen packets — exact-SHA freeze validated

Rob ratified `accentContainer = #D4EDE9` as designed opaque on 2026-07-30:
hue `170.40°`, delta `−0.32°` from accent, saturation `40.98%`, and `5.23:1`
against ink `#0A6B5C`. The ratified component-metrics table records that value.
`#DEE9E0` is the rejected mechanical composite; the decision record is retained in
git history. Reviewer freeze validation passed at exact remote head
`0682865dff178ff43ea3e1374685328f565d8cd1`.

| Frozen sources and capture | What the packet proves |
|---|---|
| `a8-explore-surface.html` + `a8-explore-surface.png` | R14's collapsed Snow Explore surface at default and accessibility-size 390×844 frames: Scope opens directly, selected category chips use the canonical pin symbols, Show saved places is ON between hidden OFF and coverage ON, Search renders nothing, and Settings/About remain reachable quiet bottom destinations. |
| `a8-r15-place-card.html` + `a8-r15-place-card.png` | R15/R16's fully lit Snow place-card cluster at default and accessibility-size 390×844 frames: Saved uses ratified opaque `accentContainer` `#D4EDE9` with accent ink `#0A6B5C`; Saved, Seen, and Loved are simultaneously ON; no action appears. |

Both packets name `Playwright-bundled Chromium/headless shell 151.0.7922.34` as
their renderer and are labelled `FROZEN`.

## Candidate decision evidence

These renders record ratified design decisions supported by comparison
artifacts. They are decision provenance, not shipped implementation changes or
frozen design-session packets; production wiring requires separate
implementation evidence.

| Asset | What it shows |
|---|---|
| `a8-saved-on-candidate-v2.html` + `a8-saved-on-candidate-v2-{default,ax}.png` | Saved ON candidate decision evidence at exact `1540×980` DSF1 captures. Each candidate shows Saved OFF/ON, simultaneous Saved/Seen/Loved ON, and all seven ruled checks at frozen A8 default or AX geometry. On 2026-07-31 Rob ratified Deep Companion `#08483E` as the accent-family dark Saved ON fill carrying `accentContrast` ink with the explicit pick “Deep is fine”; panel SHA `4421612` is the decision provenance. Accent reuse `#0A6B5C` is the rejected alternative. This evidence does not claim the ratified fill is wired into production code. Captured with Playwright-bundled Chromium/headless shell `151.0.7922.34`; byte-identical repeat SHA-256 values are `d7070aa1d97f769c57e6ad603d280d39b6a6c2a8947f787f7985f1bb48b67402` (default) and `0859dfd2532f3dca4d0182368e2df53b1393d1afb55f039b6c3d8fbba40c4eff` (AX). Frozen `a8-r15-place-card.png` remains unchanged at `7704a185ebb872ed61017db757a24c20be0a5c2870bde8b575007398972c733b`. |

## Implementation evidence

These renders record shipped implementation changes; they are not frozen design-session rulings.

| Asset | What it shows |
|---|---|
| `a10-saved-visibility-filter.html` + `a10-saved-visibility-filter{,-ax}.png` | A10 implementation evidence at exact 390×844: Include hidden OFF, Show saved places ON, and coverage shading ON in ruled order. Default rows measure 52pt each; AX rows measure 86pt each. Graded against frozen `a8-explore-surface.png` at exact remote head `0682865dff178ff43ea3e1374685328f565d8cd1`. Geometry comes from the spec's **Measured A8 Explore frozen-render facts — not system law** table at artifact SHA `f492296e932d8f3225362875f466f6d40504fe54`; it is **MEASURED, not ratified**, pending Phase 1 next-session Open Flag 5. Captured deterministically with Playwright-bundled Chromium/headless shell `151.0.7922.34`; repeat SHA-256 values are `3bfe121d48ff69bda7d83b1da77bd1d722ae0e56998c66292636108130026a7e` (default) and `324d74f190efec5ac37431dfee59bd7d7ee885f35d302fe0b4a01739c4da7ccd` (AX). |
| `a1-journal-explore-doors.html` + `a1-{explore,journal}-door{,-ax}.png` | A1 implementation evidence at exact 390×844: World/Tracks become Explore/Journal; Explore opens category, hidden, and coverage Scope controls directly with no DS-11 Search element or A10 saved-place control; Settings/About remain quiet destinations; Journal keeps the existing story and list behavior. One source selects `?variant=explore`, `explore-ax`, `journal`, or `journal-ax`. |
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
