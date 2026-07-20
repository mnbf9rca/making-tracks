# WP-MAPSCREEN-EXTRACT — decomposing `MapScreen.swift`

Deliberately excluded from the WP-B6 retrace build spec, because folding two surfaces into one while
moving them into new files makes the diff unreviewable. This is the separate proposal that was owed.

Grounded against `ios` after the slice-1 unification landed.

## 1. The problem, measured

`ios/App/Sources/Map/MapScreen.swift` is **7,378 lines** carrying **85 top-level declarations**. It is
not one screen. It is at least eight unrelated domains sharing a filename:

| cluster | approximate span | size |
|---|---|---|
| `MapScreen: View` — the map surface itself | 1330–3175 | ~1,845 |
| `MapScreenModel` | 6612–7373 | ~760 |
| Settings / Diagnostics / About / OSS credits | 4812–5752 | ~940 |
| `PlaceCardSheet` + photo slots | 5879–6492 | ~613 |
| Lists — `ListsView`, `ListDetailView`, deep links, copy, actions | 3776–4361 | ~585 |
| Offline maps — catalog, rows, download session, storage menu, `OfflineMapsView` | scattered: 113–450, 886–1330, 3180–3367, 4373–4812 | ~1,400 |
| Track/timeline — model, replay cache, pin presentation, autoplay, markers | scattered: 620–880, 6601 | ~300 |
| Chrome, layout, theme, small shared enums | scattered | remainder |

The offline and track clusters are the tell. Both are **scattered across four or more non-adjacent
ranges**, which is what a file looks like when it has stopped having a structure and started having a
history.

The concrete cost is not aesthetic. `MapScreen.swift` is the merge point for nearly every app-side work
package, so unrelated WPs collide in it, and a reviewer reading a diff hunk cannot tell which of eight
domains it belongs to without scrolling thousands of lines for context.

## 2. Why not now — the part that decides the sequencing

Four work packages are in flight against this file right now, and between them they touch **five of the
eight clusters**:

- WP-B6 retrace slices 2–5 — track/timeline, and the map surface itself
- \#247/\#249 region discovery — the entire offline/catalog cluster, including replacing the hardcoded
  catalog source
- place-card layout work — `PlaceCardSheet`
- diagnostics export — the Settings/Diagnostics cluster, with render corrections still pending

Splitting the file now converts every one of those into a conflict-resolution exercise against a moved
target. **Rebasing a work package across a 7,000-line file split is a worse problem than the one being
solved**, and it is a problem paid by every builder rather than by whoever does the split.

So the extraction is not blocked on anyone's permission. It is blocked on the file being quiet.

## 3. The proposal

**Three moves, in this order.**

### 3a. Stop the growth now (costs nothing, do it immediately)

New types go in new files. No WP currently in flight needs to add a top-level declaration to
`MapScreen.swift`, and any that thinks it does should say so and be argued with. This is the only part
of this proposal that should happen before the file is quiet, and it is the part that decides whether
the eventual split is 7,000 lines or 9,000.

### 3b. Agree the target decomposition now, execute it later

Publishing the target shape early is what makes 3a actionable — a builder adding a new type needs to
know which file it belongs in. Proposed files, all under `ios/App/Sources/`:

```
Map/MapScreen.swift              MapScreen: View + its direct chrome
Map/MapScreenModel.swift         MapScreenModel
Map/MapTrackTimeline.swift       timeline model, replay cache, pin presentation, autoplay, markers
Offline/OfflineCatalog.swift     catalog, zones, rows, availability
Offline/OfflineDownload.swift    download session, progress, storage menu
Offline/OfflineMapsView.swift    the offline maps surface
Lists/ListsView.swift            lists + list detail + deep links + list actions
Places/PlaceCardSheet.swift      place card and its slots
Settings/SettingsView.swift      settings
Settings/DiagnosticsView.swift   diagnostics + export + share
Settings/AboutView.swift         about, credits, OSS manifest
```

Boundaries are drawn on **domain**, not on size. Where a type is genuinely shared by two domains it
stays in the domain that owns its invariants, not the one that reads it most.

### 3c. Execute as a pure move, in a named window

The extraction lands **after** WP-B6 slices 2–5 and \#247/\#249, in a window agreed with fable, as a
single PR whose defining property is that **it contains no line that is not a move**.

**Teeth.** The usual neuter test does not apply — there is no behaviour to neuter, which is exactly the
risk, because a pure-move PR that quietly changes behaviour has no failing test to catch it. So the gate
is different in kind:

1. **Full release gate under sim-lock.** This is a display-path change by the standard in
   gate-lessons §5: not because the code changes, but because access-control changes when a type crosses
   a file boundary — `private` becomes `fileprivate` or `internal`, and a `private` that silently widens
   is a real behavioural surface, not a formatting detail.
2. **No line that is not a move.** Every changed line is a deletion in one file and an identical
   insertion in another. A review pass that finds an edited line rejects the PR rather than debating it.
3. **Access-control diff read explicitly.** Every `private` that had to widen is listed in the PR body
   with the reason. If the list is long, the boundary is wrong — the split should follow the access
   graph, not fight it.

Splitting 3c across several PRs by cluster is acceptable and probably better; the constraint is that
each one is still a pure move, and that no cluster moves while a WP is open against it.

## 4. Out of scope

Restructuring `MapScreenModel`, changing any view hierarchy, renaming types, or "tidying while we're in
there". Each of those is a real change wearing a move's clothes, and mixing them into 3c destroys the
only property that makes a 7,000-line reorganisation reviewable.
