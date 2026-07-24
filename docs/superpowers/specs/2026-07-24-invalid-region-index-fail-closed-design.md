# Invalid Region-Index Publish Version Fail-Closed Design

**Status:** Approved direction for issue #319

## Problem

`RegionIndex.decode(_:)` validates a network-published `search_compact.path`, but the
`RegionIndex` value types can also be constructed in memory by tests, migrations, caches,
or future readers. `OfflineRegionCatalog.init(regionIndex:)` currently assumes every value
passed through the decoder and calls `preconditionFailure` when it cannot extract the
publish-version segment. A malformed value can therefore crash the app at the catalog
projection boundary.

The region index is hostile upstream content under `docs/PRINCIPLES.md` Data 10 and the
approved design's §5.5. Catalog construction must fail closed without weakening the
decoder's existing validation.

## Decision

`OfflineRegionCatalog.init(regionIndex:)` will project `regionIndex.regions` with
`compactMap`. A region entry is retained only when its `search_compact.path` exactly
matches `<entry.id>/[0-9]{8}T[0-9]{6}Z/search/compact.json`; every other shape is omitted.
Valid entries in the same index remain available.

Dropping a malformed parent does not make a decoder-valid child downloadable: it is no
longer reachable from `rootZones`. Local state for such an orphan must still remain
visible for cleanup. Consequently, row derivation defines “known” IDs from the catalog
rows actually reached from `rootZones`, not from every retained zone. An installed,
paused, or quarantined orphan is appended as an unavailable local row with deletion
affordances, just like any other local region absent from the available catalog.

The catalog layer already imports and uses `MakingTracksLog`, including the diagnostic
file sink. Each omitted entry will emit one diagnostic record:

- category: `downloads`
- level: `error`
- message: `region catalog entry dropped`
- object field: `region=<entry id>`
- public field: `reason=invalid-search-compact-publish-version`

The object field preserves the existing diagnostic privacy grammar while making the
dropped entry and reason visible in an exported full-flow record.

## Data Flow

1. A `RegionIndex` reaches `OfflineRegionCatalog.init(regionIndex:)`.
2. Each entry's `search_compact.path` is checked against its own ID and the decoder's
   exact publish-version grammar.
3. A valid path produces an `OfflineRegionCatalogZone` exactly as it does today.
4. An invalid path produces one diagnostic record and no catalog zone.
5. Catalog row derivation consumes only retained zones, so a malformed entry cannot
   create a downloadable row.
6. Unreachable retained zones are excluded from the reachable-ID set; any corresponding
   local state is surfaced as unavailable data that the user can clean up.

`RegionIndex.decode(_:)`, current-manifest comparison, cache fallback, and the
stale/unknown-current behavior from PR #318 remain unchanged. Installed-pack visibility
is preserved for the newly exposed malformed-parent/valid-child case.

## Alternatives Rejected

- **Throw from catalog construction and reject the whole index.** This broadens caller and
  UI error handling and discards valid zones alongside one malformed entry.
- **Move the invariant into every `RegionIndex` constructor.** This redesigns the public
  value API and fixture/migration construction beyond the scope of the crash.

## Verification

An app-target regression will construct a `RegionIndex` directly with one valid entry and
malformed entries, bypassing `RegionIndex.decode(_:)`. It will prove:

- catalog construction does not trap;
- a decoder-contract-valid sibling is retained;
- entries with a missing component, a mismatched ID, a general invalid publish version,
  a trailing fifth component, or a 16-byte timestamp with a nondigit in a digit position
  are absent from lookup and downloadable rows;
- one exported diagnostic line per dropped entry records its region and fixed reason.
- a valid child whose malformed parent is dropped remains visible as an unavailable row
  when it has installed local state.

The test must fail against the current `preconditionFailure` implementation before the
production change, pass after the minimal `compactMap` change, and turn red again if the
drop or diagnostic write is removed. Targeted mutations must also prove that changing
the component count from exactly four to at least four admits the trailing component,
that replacing the timestamp grammar with a byte-count check admits the nondigit, and
that treating every retained zone as known hides the orphan local row. Existing #318
catalog tests and the full host and app gates remain required.

## Delivery Constraint

The implementation is built, tested, and staged on `origin/ios` at `8bfdc5e9`. Signing
and SSH have recovered; create the normal signed commit, push, and PR after the required
gates. Fable owns that delivery.
