# Visit Edit Context Mockups

Rendered design packet for #435 and folded fidelity repair #641. The packet extends the ratified #221 Visit date screen without changing its paper/ink token family or the #454 picker-validity contract.

## Artifacts

- `visit-edit-context-default.png` — 390×844 default text, entry state
- `visit-edit-context-ax.png` — 390×844 accessibility text, scrolled context state
- paired `.html` sources, shared `context.css`, and deterministic `render.sh`

The accessibility image intentionally represents the user scrolling the introductory summary out of view. It demonstrates that the selected event, two read-only history rows, restored `After save` consequence, and fixed action bar remain legible and reachable at large text size.

## Ruled content

- `OTHER VISITS HERE` contains only other persisted visit events for the selected `place_id`.
- The selected `visits.id` is excluded; rows are newest first.
- History rows are contextual, not controls: no chevron, heart, delete, drag, button treatment, or reorder promise.
- `AFTER SAVE` restores the frozen #221 consequence and points ordering back to the full My tracks list.
- The history section is omitted when there are no other visits.
- Cancel/Save remains fixed below the scrollable content, matching every frozen #221 Visit date variant. The live baseline instead places the action HStack inside `ScrollView` at `ios/App/Sources/Map/MapScreen.swift:6126-6138`; the planner ruled that mismatch folded into #435 as deliberate fidelity restoration.

## Render and reproducibility

Run from the repository root:

```bash
bash docs/design/visit-edit-context/render.sh
```

Capture tool: Google Chrome for Testing `151.0.7922.34`, headless shell installed in the local Playwright cache and pinned by `render.sh`. Rendering uses fresh temporary profiles, disabled background networking/component updates, a scale factor of 1, and a 390×844 viewport.

Image SHA-256:

- default: `12c1c13bdefcc80ecb32edcabdf3222700ec17fb091b4b14b03f348b6dd66693`
- accessibility: `bfcf596e0c4500dc08a0d8ed7a58422634ce68f0cbec8148958ae9274a4d681b`

## Measured checks

Both PNGs report exactly 390×844 pixels via `sips`.

WCAG relative-luminance measurements from the declared token pairs:

- ink `#1c1c1e` on sheet `#fffdf7`: **16.73:1**
- dim `#64635d` on sheet `#fffdf7`: **5.92:1**
- context ink `#283747` on context fill `#e8eef5`: **10.41:1**
- accent `#0a6b5c` on paper `#f1eddf`: **5.48:1**

Visual inspection confirms both renders contain the selected card, two separately bounded history rows, `After save`, and the full cancel/save bar without clipping. The default image also retains the introductory summary; the accessibility image proves the ruled scrolled state with the long place name wrapping instead of truncating or colliding with the heart.
