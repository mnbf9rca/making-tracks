# Making Tracks — Design System & Information Architecture

**Status:** ratified by Rob in the 2026-07-25 design session (this is the IA / look-and-feel
thread that #455 and #350 pointed at). This spec *supersedes and absorbs #350*: its 15-surface
deviation inventory becomes the epic's work-list, and no second theming umbrella may be opened.
Frozen renders live in [`docs/design/design-system/`](../../design/design-system/) and are
embedded in the epic.

This document specifies; it does not implement. Each consuming issue carries its own mockup
gate per the standing mockup law.

**Amended once, by the 2026-07-26 design session** (designer + Rob), which is the immutability
law's sanctioned channel for changing a ratified spec — a session ratification, not an edit.
The amendment lands: R4's map rows, R7's tone quartet, `trail`, `hiddenPinColor`, `disabledAlpha`
and `pressScale` into §3; the **component-metrics table** and **R15 state morphology** into §5;
the **refined literal carve-out** into §4; and R13/R14's door changes into §2.

**Sections describing state that is not yet built are marked *target*, with the owning task named**
— per the authoring law that a spec may describe intent but must never let a reader mistake intent
for the tree. The door rename, the Explore collapse and the R15 place-card re-render are all
target; their code lands in the amendment wave.

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

### Door 1 — Explore (*what the map shows, right now*) — **R14**

**The door opens Scope directly.** There is no intermediate row list: tapping Explore presents the
scope surface itself — category chips, include-hidden, coverage shading — absorbing today's Layers
sheet and the floating filter chips. Settings and About are **quiet bottom rows** on that surface,
the gear given the more prominent of the two. The **Search slot sits at the top** of the surface
when DS-11 lands; until then the position is reserved and renders nothing, per the standing rule
that a visible row which does nothing is a defect rather than a promise.

**Target state — owning task: the R13/R14 door-rename + Explore-collapse row in the amendment
wave.** The built door is still named *World* and still presents a row list; this section describes
what that task delivers, not what ships today.

### Door 2 — Journal (*your story through the world*) — **R13**

**Renamed from *Tracks*.** *Making Tracks* remains the brand and the footprints icon survives; the
subtitle is unchanged. What leaves is **"tracks" as a UI noun**: the word invites the route-recorder
misreading that PRINCIPLES → Product 6 exists to prevent, and a door label is the one place the app
cannot afford it.

| Row | Content |
|---|---|
| **My tracks** (hero) | The #266 unified surface: list-detail landing, Retrace one tap away. |
| **Lists** | With per-list progress (n of m seen, thin accent bar). |
| **Loved places** | Virtual row — loving becomes visible and manageable. |
| **Hidden places** | Quiet virtual row — hiding becomes reversible in the open, not a buried toggle. |

**Target state — same owning task as R14.** The built door is still named *Tracks*; the accessibility
identifiers and the rendered-order test naming migrate with the rename.

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
| `eyebrow` (category labels) | `#8A5A2B` | `#C9955C` |
| `hairline` | `rgba(43,40,35,0.14)` | `rgba(239,232,220,0.14)` |
| `scrim` | `rgba(43,40,35,0.35)` | `rgba(0,0,0,0.45)` |
| `shadow` | soft, warm, low-alpha | themed (invisible-on-dark fixed) |
| `pin` / `pinFaded` | `#E4572E` / 35% opacity | **identical — pins never theme** |
| `hiddenPinColor` | `#767B82` | **identical — constant pin block** |
| `mapBackground` (R4) | = `ground` | = `ground` |
| `mapLabels` (R4) | = `muted` | = `muted` |
| `mapLabelHalo` (R4) | = `ground` | = `ground` |
| `mapBoundaries` (R4) | = `hairline` | = `hairline` |
| `trail` (R8) | `#2D8C83` | *owed at material time* |
| `love` (R7) | `#C4312B` | *owed at material time* |
| `loveContainer` (R7) | `#FCE3E3` | *owed at material time* |
| `warning` (R7) | `#75571F` | *owed at material time* |
| `warningContainer` (R7) | `#F2E8D1` | *owed at material time* |
| `disabledAlpha` | `0.46` | `0.46` |
| `pressScale` | `0.98` | `0.98` |

**On the rows added by amendment.** `hiddenPinColor` joins the **constant pin block**, not the
per-material columns: pins never theme, and hidden pins are *deliberately* de-emphasised, so the
pin-pop gate does not apply to this one — DS-7's mud render validates that the de-emphasis stays
legible. **R4's four map rows are independently valued rows, not compile-time aliases**; they are
written here as equal to their current source token because that is their ratified value, and the
distinction matters because R4's rider lets the AA gate escalate `mapLabels` on a material without
dragging `muted` with it. **R7's quartet and `trail` carry Snow values only** — the sheet's AA gate
covers them per material under R7's rider, so a mud column is *owed when mud ships* rather than
guessable now. `disabledAlpha` and `pressScale` are **not colours**: they are the two interaction
constants R9 left implicit, ratified here so a control's disabled dimming and its press geometry
come from the sheet rather than from a literal in a style body.

Notes: mud is warm dark-brown, never gray-black. The snow sheet is the ratified paper
language made canonical (`defined-paper` `#F3EFE5` family); the existing four paper themes
(`snow`, `defined-paper`, `street-contrast`, `verdant-kl`) fold into the material system —
the current picker's choices become material variants or retire, decided in the material
architecture issue with a migration for the stored `map.theme.id`.

**Future materials** — forest (greenish), sand, petals (pinkish) — are recipes: a new value
column that must pass the same gates. **Gates for any material:** every text/background pair
≥ WCAG AA (4.5:1 body, 3:1 large/UI); pins must visibly pop against `ground` (the render is
the check); contrast gates are validated *in the token sheet*, so an illegible material
cannot ship.

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

### The literal carve-out, refined — inert values only

A figure ratified by a frozen render that **no role expresses** may stay a literal, provided the
code names its ratifying file. The refinement: **that permission covers INERT literals only.**

- **Inert** — the expression produces a value and nothing else. `Font.caption.weight(.semibold)`
  hides no behaviour, so inlining it loses nothing.
- **Behaviour-carrying** — the API the literal replaces does something *invisible* on the way to
  its value: an availability check, a fallback, a metrics anchor, a closed-set guarantee. Inlining
  such an API keeps the visible half and **silently drops the invisible half**, and an equality
  test cannot tell, because the expression still equals itself.

The worked case: a Newsreader role resolves a named face, applies `UIFontMetrics` scaling, **and
falls back to a serif system font when the face is unavailable**. A hand-rolled
`Font.custom(name:size:relativeTo:)` keeps the face and the scaling and drops the fallback — so the
one text on the screen that carries the story voice renders sans, in exactly the failure the
fallback exists to prevent, with every test still green.

**Therefore:** a figure the role API cannot express is a carve-out candidate; a figure the role API
*can* express is a **role**, and the carve-out is not the escape hatch for skipping one. Where a
literal must carry behaviour, replicate the behaviour and **test the invisible half** — construct
against the failing path and assert the fallback, not the happy path.

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

### State morphology — component law (**R15**), and the fourth category (**R16**)

**A `state toggle` is the system's fourth component category** — *a control reporting a persistent
fact*, alongside buttons, chips and the rest of §5's table. Its form law is R15:

| State | Container | Glyph |
|---|---|---|
| **ON** | filled pill | filled glyph |
| **OFF** | tonal | outline glyph |
| **Momentary verb** (does a thing, holds no state) | quiet text | — |

**State toggles sit outside the filled-action budget.** §5's *one filled per screen* continues to
govern **actions only**. The reasoning, ratified verbatim:

> **States are not buttons — the budget exists to stop screens shouting competing imperatives; an ON
> state is not an imperative, it is a fact the control is reporting; three true facts are not three
> CTAs.**

**Rider — an ON pill fills with the state's own semantic token.** Within a state cluster, **seen**
fills `accent`, **loved** fills the ratified `love` row, and **saved** fills an **accent-family dark
fill carrying `accentContrast` ink** *(amended by designer ruling 2026-07-30; "tonal-strength
companion" is retired from this rider — same-ink ON/OFF pairs cap at 1.43:1 separation by
arithmetic for a free pair, lower still once either value is pinned, so saved adopts the two-ink inversion seen and loved already use)*. **Exact values are
the re-render's job to prove against the AA gate.** The
purpose is that three ON pills read as three differently-toned *facts* rather than three copies of
the CTA colour, so a screen's single filled **action** stays unmistakable beside a fully-lit cluster.
Morphology still carries the state signal — **fill plus glyph, never colour alone**; the tones exist
to prevent CTA impersonation, not to replace the morphology.

**Never-colour-alone applies to state**, not only to seen-state and progress. This is what makes a
control's state legible without a legend: a filled pill with a filled glyph is on, a tonal pill with
an outline glyph is off, and anything that is neither is a verb rather than a switch. **The place
card is re-rendered under this rule** — target state, owning task in the amendment wave.

*Why it is here rather than in a component's row:* it is the rule that decides which of the three
button styles a control takes, so it governs the table above rather than sitting inside it.

### Component metrics — the ratified numbers, beside their elements

**The table ratifies; the API carries.** Every figure below is load-bearing and read from a frozen
render; a builder takes the number from here, and the code holds the vocabulary that consumes it.
The rule this table exists to enforce: **numbers belong in tables; renders certify feel;
information that only exists as pixels gets under-read.**

The first table contains **ratified** system law. The second preserves **MEASURED** facts from the
A8 frozen Explore render; those rows are visually distinct provenance, not ratified metrics, and
are carried as Open Flag 5 in Phase 1's next-design-session batch for wholesale ratification or
amendment.

| Element | Metric | Source |
|---|---|---|
| Door pill | 44pt height, 999px radius, 15pt/600 label, 7pt gap, **19×19 icon**, 10pt between doors | `ia-doors` |
| Sheet | 22pt top radius, 36×4 grabber, 6/14/14 padding | `ia-doors` |
| Sheet title / subtitle | 26pt Newsreader 600 / 14pt sans | `ia-doors` |
| Section label | 11pt/600 uppercase, `0.11em` tracking | `ia-doors` |
| Raised card row | 14pt radius, 12pt padding, 10pt gap | `ia-doors` |
| Row title (list) / row title (hero) | **17pt** / **18pt** Newsreader 600 | `ia-doors` `.t-serif` / `.t-serif.lg` |
| Row metadata | 13pt sans | `ia-doors` `.t-meta` |
| **Explore-surface row icon** | **20×20** | `ia-doors` (sliders, download, coverage) |
| **Quiet bottom row icon** | **18×18** | `ia-doors` (gear, book, heart, eye-off) |
| Quiet row title / metadata | 15pt/600 muted / 12pt | `ia-doors` `.row.quiet` |
| Compass · locate | 34×34 · 36×36 control, **20×20 icon** | `ia-doors` |
| Chip | 22pt height, 0/9 padding, 4pt gap, 12pt/600 label, **11×11 icon**; row gap 6pt | `ia-doors` `.chip` / `.chips` |
| Action cue (*Retrace*) | 13pt/600, 3pt gap, **11×11 chevron** | `ia-doors` `.action` (**R12**) |
| New-list affordance | **15×15 icon** | `ia-doors` |
| Control-label icon beside a 15pt label | **17×17** | `coherence` `.coh .act` — ratified **pairing constant**, deliberately outside `IconRole`'s closed set |
| Action-bar button | 15pt/600 label, 6pt icon gap, 8pt between buttons | `coherence` |
| `accentContainer` *(retired from the Saved role)* | designed opaque **`#D4EDE9`**; hue **170.40°**, delta **−0.32°** from `accent`, saturation **40.98%**, **5.23:1** against ink **`#0A6B5C`** | Historical A8 frozen-packet value; ratified by Rob on 2026-07-30, then retired from the Saved role without prejudice by the amended R16 rider |
| Saved `accentDeepContainer` | designed opaque **`#08483E`** with `accentContrast` ink **`#FBFAF2`**; ink **9.995:1**; **8.390:1** against Saved OFF's composited wash **`#DEE9E0`**; **1.630:1** against Seen ON **`#0A6B5C`**; **1.904:1** against Loved ON **`#C4312B`** | **RATIFIED** — designer pick 2026-07-30 via the v2 panel at SHA `442161239dacb3aab8df0392039de22ae39ba98d`; ratified by Rob on 2026-07-31 |
| Attribution | 11pt bare muted text, never a pill | `ia-doors` |
| Interaction target floor | 44pt, tiled per **R10** where the rider permits | R10 scope line |
| Pin | 20px circle, white stroke glyph | `ia-doors` |
| Place-card **More** control | 44×44 target, glyph at **`IconRole.hero` = 22** | ruled by this session — see the snap note below |

#### Measured A8 Explore frozen-render facts — not system law

| Element | Metric | Source |
|---|---|---|
| Explore default sheet placement | 62pt large-detent top; 12pt grabber-to-title gap | **MEASURED — measured from the A8 frozen Explore render at artifact SHA `f492296e932d8f3225362875f466f6d40504fe54`; not ratified** |
| Explore default Scope control rows (3) | 52pt minimum each; 15pt/600 label; 20×20 icon; 10pt gap; 6/2 padding; 44×28 switch with 22pt knob at 3/19pt offsets; 1pt hairlines | **MEASURED — measured from the A8 frozen Explore render at artifact SHA `f492296e932d8f3225362875f466f6d40504fe54`; not ratified** |
| Explore default Scope block rhythm | 18pt header-to-label; 11pt label-to-chips; 14pt chips-to-controls; row minimum yields to wrapped content | **MEASURED — measured from the A8 frozen Explore render at artifact SHA `f492296e932d8f3225362875f466f6d40504fe54`; not ratified** |
| Explore default quiet destination row | 9/2 padding; 10pt gap; 12×12 chevron; 2pt title-to-metadata gap | **MEASURED — measured from the A8 frozen Explore render at artifact SHA `f492296e932d8f3225362875f466f6d40504fe54`; not ratified** |
| Explore AX sheet / labels / chips | 48pt large-detent top; 10pt grabber gap; 41/22pt title/subtitle with 6pt gap; 17pt section label; chips 38pt minimum with 19pt/600 label, 18×18 icon, 5/14 padding, 6pt label gap and 8pt row gap | **MEASURED — measured from the A8 frozen Explore render at artifact SHA `f492296e932d8f3225362875f466f6d40504fe54`; not ratified** |
| Explore AX Scope control rows (3) | 86pt row minimum each; 23pt/600 label; 30×30 icon; 14pt gap; 10/2 padding; 51×31 switch with 25pt knob at 3/23pt offsets; 14/9/14pt block rhythm; minimum yields to content | **MEASURED — measured from the A8 frozen Explore render at artifact SHA `f492296e932d8f3225362875f466f6d40504fe54`; not ratified** |
| Explore AX quiet rows | 4pt block inset; 28×28 icon; 24/18pt title/metadata; 18×18 chevron; 14pt content gap; 10/2 padding; 4pt title-to-metadata gap | **MEASURED — measured from the A8 frozen Explore render at artifact SHA `f492296e932d8f3225362875f466f6d40504fe54`; not ratified** |

**The snapped 21.** T1.10's *implementation* render drew the More control's glyph at **21px**
(`t1.10-place-card.html:107`–`:114`, `.more { font-size: 21px }`). This session ruled that figure
**presumptively an accident** and snapped it to `IconRole.hero`'s 22. Two things about it are worth
keeping, because both explain why it survived every sweep that should have caught it: it lives in an
**implementation render, not a frozen one**, so it was outside the ratified render set anyone would
think to search; and it was a **`font-size` on a text span** — the control was drawn as a typed `•••`
rather than as an icon — so it never appeared in an icon-size sweep either. **A figure in neither the
ratified set nor the expected vocabulary is invisible to a careful search, which is the argument for
this table stated from the other side.**

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
