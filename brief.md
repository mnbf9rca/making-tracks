# Making Tracks — Project Brief

**Status:** pre-build. Naming settled, core mechanic settled, data model open.
**Platform:** iOS (SwiftUI). Solo developer.
**Domain:** makingtracks.app (registered)

---

## 1. What it is

A map app that surfaces interesting things around you — history, architecture, oddities, landmarks — sourced from open databases (Wikipedia/Wikidata, OpenStreetMap, Historic England, and similar). You can bookmark places you want to visit, mark places as **seen** so they stop dominating discovery, and curate and share custom lists.

## 2. The core metaphor

The map is fresh snow. Moving through the world marks it.

This is a **subtractive** discovery model: the map starts full of possibility and your life gradually consumes it. That is the emotional engine of the app and every design decision should be checked against it.

Two views over the same data:

- **Discovery** — seen places are *faded*, not hidden. Low opacity, still tappable.
- **Tracks (history)** — seen places are *visible*, chronological, place-anchored. The accumulated record of where you've been.

## 3. Decisions already made

| Decision | Rationale |
|---|---|
| Seen places fade, they don't disappear | Keeps the map legible; lets you re-find somewhere; fade *accumulating* reads as progress, not deletion. A "hide seen entirely" toggle serves the minority who want the clean version. |
| Marking seen is one tap, reversible, no confirmation | If it feels like a commitment people won't do it and the mechanic dies. Nothing is destroyed, so mis-taps cost nothing. |
| Three states, not two: Unseen → Bookmarked → Seen | "I want to go" and "I went" are different intents. A single boolean can't express both. Gives the natural loop: bookmark now, visit later, mark seen on site. |
| No auto-marking seen from geolocation | Walking past a plaque isn't seeing it. Silently consuming places the user never noticed feels like theft. Location may *prompt* ("You're near X — mark it seen?"); the user decides. |
| History/Tracks is a first-class screen, not secondary | It's the shareable artefact and the retention mechanism once discovery novelty fades. |

## 4. The open question (highest priority)

**Is `seen` global-per-user, or scoped per-list?**

Scenario: someone shares me a list of ten pubs. I've already seen three. Does the shared list render those three as seen?

- If **yes** → seen-state attaches to the *place*, globally per user. Lists become views over a shared place graph. Simpler, more coherent, but means importing a list can immediately show as 30% "consumed", which may undercut the pleasure of receiving it.
- If **no** → seen-state attaches to the *(place, list)* pair. Each list is a fresh slate. Preserves the gift-like quality of a shared list, but fragments the model and makes "have I seen this?" ambiguous.

This is expensive to change later. It needs deciding **before** the schema is written. There may be a third option (global seen, but lists show a "you've already seen 3 of these" affordance rather than pre-faded pins) that gets both properties — explore it.

## 5. Also unresolved

- **Data sources and merge strategy.** Wikipedia/Wikidata gives notability and prose; OSM gives coverage and precise geometry; they overlap and disagree. What's the canonical place identity, and how are duplicates reconciled? Assume the source set will grow — don't couple to any single provider.
- **What counts as "interesting"?** The filtering/ranking problem is the actual product. A map of every OSM node is noise. Wikipedia notability is one signal; there will need to be others.
- **Density handling.** Central London will have hundreds of candidate places in view. Clustering, zoom-dependent thresholds, or aggressive ranking?
- **Offline behaviour.** Discovery is a walking-around activity; connectivity is unreliable.
- **Sharing mechanism.** Link-based? Requires accounts/backend? What's the minimum that works?
- **Privacy posture.** History is a detailed record of a user's movements. Local-first / on-device by default is the strong assumption; server-side sync is a deliberate trade-off, not a default.

## 6. Naming risks to design around

- The App Store "tracks" category is dominated by music apps and GPS/GPX route recorders. Organic search discovery will be poor. The subtitle must disambiguate; installs will come from elsewhere.
- A meaningful share of people will assume it records your route. The first screenshot needs to correct this immediately.

## 7. What I want from this session

Brainstorming, not implementation. Specifically:

1. **Resolve §4.** Work the seen-state scoping question properly, including the third-option space. Reason about it from the user's emotional experience of receiving a shared list, not just from schema tidiness.
2. **Attack §5's "what counts as interesting"** — this is the make-or-break product problem and I have no answer.
3. Pressure-test §3. If any of those decisions are wrong, say so.
4. Then, and only then, propose a data model.

Push back on weak reasoning. Don't pad. If something is genuinely uncertain, say so rather than picking a plausible-sounding answer.
