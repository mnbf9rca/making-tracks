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

## Implementation evidence

These renders record shipped implementation changes; they are not frozen design-session rulings.

| Asset | What it shows |
|---|---|
| `t1.5-map-theme-evidence.html` + `t1.5-map-theme-{before,after,after-ax}.png` | T1.5 before/after evidence at 390×844. One source selects `?variant=before`, `after`, or `ax`; the after render is the AC34 constant-pin pop check. |

HTML files are self-contained (fonts load from Google Fonts when online; system fallbacks otherwise).
