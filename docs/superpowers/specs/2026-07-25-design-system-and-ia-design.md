# Making Tracks — Design System & Information Architecture

**Status:** ratified by Rob in the 2026-07-25 design session (this is the IA / look-and-feel
thread that #455 and #350 pointed at). This spec *supersedes and absorbs #350*: its 15-surface
deviation inventory becomes the epic's work-list, and no second theming umbrella may be opened.
Frozen renders live in [`docs/design/design-system/`](../../design/design-system/) and are
embedded in the epic.

This document specifies; it does not implement. Each consuming issue carries its own mockup
gate per the standing mockup law.

---

## 1. Thesis

**The theme is a landscape material, and the whole app is that material's world.**
Snow, mud, forest, sand, petals: imagine a landscape covered in the stuff. As you discover
places you are making tracks through it. Theming is therefore not decoration laid over the
app — it *is* Principle 1 ("the map is fresh snow") extended to every surface. The map, the
sheets, the buttons and the accents are one material; the pins — the places, the subject —
never theme.

Three laws follow:

1. **One world per material.** A material defines the map style *and* the app surfaces *and*
   the accent palette from a single token sheet. No surface may mix materials.
2. **Pins never theme.** `#E4572E` and the category glyph set are constant across every
   material. The subject stays saturated; the world changes around it.
3. **Two voices.** The *story voice* (Newsreader) speaks about places and the user's story.
   The *machinery voice* (SF) operates the app. Never mixed within a role.

## 2. Information architecture

**The map is the only home.** Full-bleed, always. No tab bar, no hamburger.

Persistent chrome: compass, locate button, the two doors, and a bare-text attribution
(`© OpenStreetMap`, 11pt, muted ink, no pill — visible for ODbL compliance, quiet by design).
Contextual chrome (download progress, location-off notice, nearby prompt, undo toast) is one
toast/pill family that appears only when it has something to say.

**Doors are for things you do often; Settings is for things you set once.**

### Door 1 — World (*what the map shows, right now*)

| Row | Content |
|---|---|
| **Scope** | The single ruled scope surface (2026-07-23 ruling): category chips, include-hidden, coverage shading. Absorbs today's Layers sheet and the floating filter chips. |
| **Search** | Reserved slot. Search does not exist yet; it gets its own scoping issue in the epic and the door reserves its place. |
| *(quiet bottom rows)* | **Settings** · **About** |

### Door 2 — Tracks (*your story through the world*)

| Row | Content |
|---|---|
| **My tracks** (hero) | The #266 unified surface: list-detail landing, Retrace one tap away. |
| **Lists** | With per-list progress (n of m seen, thin accent bar). |
| **Loved places** | Virtual row — loving becomes visible and manageable. |
| **Hidden places** | Quiet virtual row — hiding becomes reversible in the open, not a buried toggle. |

### Settings (cleaned)

Groups: **Appearance** (material picker — replaces the map-theme picker), **Offline maps**
(packs, downloads, per-pack storage — moved here per Rob: set-and-forget), **Coverage**,
**Map & data** (cellular, pin size), **Location**, **Diagnostics**, **Replay welcome**.
The map keeps its contextual deep links into Offline maps (download-progress pill,
empty-region card's download action) so common offline *moments* never require digging.

### About (restructured)

The story and the privacy promise up top, then two sub-areas: **Software licences**
(OSS credits, including Newsreader's OFL text) and **Data licences** (OpenStreetMap,
Wikipedia, per-region sources such as Historic England). No more single scroll of stacked text.

Existing rulings honoured unchanged: #266 (one surface, list-detail landing, verdict edits
fold in, membership protected), Retrace map-level entry, PRINCIPLES §Product 7 (no pin ever
hidden/thinned/tiered by the app).

## 3. Materials and tokens

**Mode model — theme-locked (ruled):** each material has an intrinsic mode. Snow *is* light;
mud *is* dark. The user pins a material; the app renders that material regardless of system
light/dark. (An optional "snow by day, mud by night" pairing preference is an open knob for
Rob — not required for v1.)

**A material is one token sheet.** The sheet feeds three consumers that today are
disconnected islands: `PaperStyle` (map), the SwiftUI surface/component tokens, and the
pin/track layer constants. Semantic token names, one value column per material.

### v1 sheets (validated in the coherence render)

| Token | Snow (default, light) | Mud (dark) |
|---|---|---|
| `ground` (map land / canvas) | `#F4F1EA` | `#262019` |
| `water` | `#C9DBE2` | `#1E3038` |
| `park` | `#DCE5D4` | `#2A3224` |
| `road` / `roadMinor` | `#C9BFA8` / `#DDD5C2` | `#4A4136` / `#3A332A` |
| `surface` (cards, sheets) | `#FBFAF2` | `#322A21` |
| `surfaceRaised` | `#FFFFFF` | `#3A3128` |
| `ink` (primary text) | `#2B2823` | `#EFE8DC` |
| `muted` | `#6B675F` | `#A79E90` |
| `accent` | `#0A6B5C` | `#4DB6A0` |
| `accentContrast` | `#FBFAF2` | `#241E17` |
| `love` / `loveContainer` | `#C4312B` / `#FCE3E3` | Deferred to Mud implementation; must pass the sheet AA gate |
| `warning` / `warningContainer` | `#75571F` / `#F2E8D1` | Deferred to Mud implementation; must pass the sheet AA gate |
| `eyebrow` (category labels) | `#8A5A2B` | `#C9955C` |
| `hairline` | `rgba(43,40,35,0.14)` | `rgba(239,232,220,0.14)` |
| `scrim` | `rgba(43,40,35,0.35)` | `rgba(0,0,0,0.45)` |
| `shadow` | soft, warm, low-alpha | themed (invisible-on-dark fixed) |
| `pin` / `pinFaded` | `#E4572E` / 35% opacity | **identical — pins never theme** |

Notes: mud is warm dark-brown, never gray-black. The snow sheet is the ratified paper
language made canonical (`defined-paper` `#F3EFE5` family); the existing four paper themes
(`snow`, `defined-paper`, `street-contrast`, `verdant-kl`) fold into the material system —
the current picker's choices become material variants or retire, decided in the material
architecture issue with a migration for the stored `map.theme.id`.

**Future materials** — forest (greenish), sand, petals (pinkish) — are recipes: a new value
column that must pass the same gates. Every material supplies its own love and warning
foreground/container values; Snow's ratified rows do not become cross-material constants.
**Gates for any material:** every text/background pair, including `love`/`loveContainer`
and `warning`/`warningContainer`, ≥ WCAG AA (4.5:1 body, 3:1 large/UI). Enabled
interaction feedback must not alpha-composite either semantic pair below that
gate; use geometry rather than whole-control opacity for the pressed state. Pins must visibly
pop against `ground` (the render is the check); contrast gates are validated *in the token
sheet*, so an illegible material cannot ship.

## 4. Typography

**Story voice: Newsreader** (Production Type, SIL OFL 1.1) — ratified from specimen
comparison after sourced research (Fraunces: dated branding cliché; Bricolage: SaaS cliché;
New York: licence forbids bundling — retained only as runtime `design: .serif` fallback).

- Roles: display lines (onboarding hook, empty states), sheet titles, place names,
  list-row titles. Italic Newsreader for evocative sub-lines — the cartographic gesture.
- **Ship static named instances, not the variable file** (iOS variable-font APIs are
  unreliable): 3–4 cuts spanning the optical range, scaled via
  `UIFontMetrics(forTextStyle:)` with the text style matched to the design size.
- OFL licence text ships in About → Software licences.

**Machinery voice: SF** — buttons, labels, metadata, body copy, data. **On-map labels stay
sans** (cartographic-practice research; serif belongs on cards, not tiny map labels).

## 5. Components — one language

| Component | Rule |
|---|---|
| Buttons | Exactly three styles: **filled** (accent bg, one per screen max), **tonal** (12% accent tint), **quiet** (muted text). No `bordered`/`borderedProminent` anywhere. |
| Sheets | One pattern: grabber, 22pt top radius, `surface` token background, medium/large detents. No mixed `.material` backgrounds; one close affordance convention. |
| Rows | Two types: raised card-row (hero items, `surfaceRaised`, 14pt radius) and hairline row (lists). |
| Chips | One capsule family: filled = active, tonal = available. |
| Toasts/pills | One family (download progress, location notice, nearby prompt, undo). |
| Progress | One language: thin accent bar on hairline track — list progress, download progress, and the ruled #359 map-fetch hairline are the same component. |
| Doors | Pill buttons on `surface`, hairline border, soft shadow, SF 600 + accent stroke icon. |
| Attribution | Bare muted text, 11pt. Never a pill. |

`Color.accentColor` gets a real `AccentColor` asset (snow accent) so no stock-blue site
survives even before full adoption; the four scattered teal definitions collapse into the
token sheet.

## 6. Iconography

SF Symbols only, one weight (`.medium`), monochrome, tinted `ink`/`muted`/`accent` — never
multicolor, never emoji. The bespoke drawn set is reserved for: category glyphs on pins
(constant across materials) and the footprints motif. This retires the odd-one-out chrome
glyphs (filter icon, etc.) structurally rather than one at a time.

## 7. Motion & accessibility (standing gates)

These are review gates for every design-system PR, not features:

- **Reduced Motion honoured app-wide** (today: zero handling): pin pulse, shimmer, arc-glide,
  autoplay transitions all provide reduced variants. **Reduce Transparency** swaps material
  blur for solid `surface`.
- **Dynamic Type everywhere**, including Newsreader via `UIFontMetrics`; the AXXXL reflow
  patterns already validated (Retrace controls, diagnostics grid, menu subtitles) become the
  norm; fixed-height frames that clip at AX5 are defects.
- **Contrast in the token sheet** (see §3 gates) — a material proves AA before it ships.
- **Never colour-alone** (#130): seen-state = fade *plus* label; progress bars carry counts.
- VoiceOver: labels + values on all interactive elements; custom controls get real
  a11y actions (the replay `UISlider` shim is the exemplar); drag-reorder gets a VoiceOver
  path.

## 8. Code architecture

- **`DesignSystem` module** (new target/package): the material token sheets, the font
  provider (Newsreader statics + metrics), `ButtonStyle`s, sheet/row/chip/toast components,
  icon conventions. No view outside the module defines a color or font literal.
- The seven per-surface spec enums in `MapScreen.swift` (place card, visit editor, timeline,
  diagnostics…) dissolve into the module as their surfaces adopt it.
- `PaperStyle` consumes the material sheet (single source for map + UI); pin layer constants
  come from the same sheet's constant pin block.
- Extraction from the 10.3k-line `MapScreen.swift` proceeds **surface-by-surface as each
  surface adopts the system** — no big-bang rewrite, no adoption without extraction.

## 9. Migration order (the epic's spine)

Foundation first, then surfaces by severity (from the absorbed #350 inventory), materials
along the way:

1. **Foundation:** `DesignSystem` module — snow sheet, `AccentColor` asset, font provider,
   core component styles.
2. **IA shell:** two doors replace hamburger + Layers entry; chrome cluster; attribution.
3. **Scope surface** (World door): merge Layers + filter chips per the ruled single scope
   picker.
4. **Tracks door:** My tracks hero (#266 surface), Lists, Loved, Hidden.
5. **Place card adoption:** token fade (kills the cream→white seam), action-bar styles,
   ruled #376 adaptive photo height.
6. **Settings + About rebuild:** cleaned groups, Offline maps/Coverage move, licence
   sub-areas.
7. **Mud material** + Appearance picker + `map.theme.id` migration.
8. **Onboarding/welcome re-skin** (visual system only; #378 keeps per-screen copy/layout).
9. **Diagnostics + blocking surfaces** (DB recovery, update-required) — closes #455's remit.
10. **A11y sweep:** Reduced Motion/Transparency adoption + AX5 fixed-height fixes.
11. **Search** (World door slot): scoping issue.
12. **Future materials:** forest / sand / petals recipes (post-mud, cheap by then).

Welcome-flow copy (#378), Retrace tunables (#257) and other ruled-but-unbuilt items remain
their own issues; they *consume* this system rather than being absorbed by it.

## 10. Open knobs (Rob's, not blocking)

- Optional day/night material pairing preference (§3).
- Forest / sand / petals palettes — recipes exist as gates, values are taste rulings.
- Search scope (what it searches, how it ranks) — the IA only reserves the slot.

## Frozen renders

| Asset | File |
|---|---|
| Materials coherence (snow/mud × home/card/door) | [`coherence.html`](../../design/design-system/coherence.html) / [`coherence.png`](../../design/design-system/coherence.png) |
| IA — the map and its two doors | [`ia-doors.html`](../../design/design-system/ia-doors.html) / [`ia-doors.png`](../../design/design-system/ia-doors.png) |
| Typography decision specimens | [`typography.html`](../../design/design-system/typography.html) / [`typography.png`](../../design/design-system/typography.png) |

*Note: the IA render predates one ruling — it shows Offline maps and Coverage as World-door
rows; §2 (Offline/Coverage in Settings, Search slot in World) is the ratified state. The
render stands for the door pattern, not that row list.*
