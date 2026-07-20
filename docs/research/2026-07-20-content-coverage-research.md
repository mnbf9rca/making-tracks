# WP-RESEARCH: Malaysia Content Coverage

## Question

Malaysia live cards are content-sparse: the live publish has 3,811 shipped places,
64 description entries, and 305 image entries. Rob's example was St. John's
Cathedral in Kuala Lumpur: Wikipedia has a substantial article and photo, but the
app card has no blurb.

This report diagnoses where that content falls out, quantifies the available
Wikipedia/Wikidata potential for the current Malaysia publish, and lays out the
implementation options.

## Evidence Base

- Code paths inspected on `origin/develop`: `pipeline/src/mt_pipeline/acquire.py`,
  `pipeline/src/mt_pipeline/extractors/wikipedia.py`,
  `pipeline/src/mt_pipeline/extractors/wikidata.py`,
  `pipeline/src/mt_pipeline/publish/publish_stage.py`,
  `pipeline/src/mt_pipeline/publish/descriptions.py`, and
  `pipeline/src/mt_pipeline/publish/images.py`.
- VPS database: `/data/mt-data/malaysia/work.db`.
- VPS live staging snapshot:
  `/home/agent/tmp/b9-routine-republish-20260719T125813Z/malaysia-singapore-brunei/20260719T125813Z`.
- Official Wikimedia checks:
  - <https://www.wikidata.org/wiki/Q613619>
  - <https://www.wikidata.org/wiki/Q5552448>
  - <https://www.wikidata.org/wiki/Special:EntityData/Q5552448.json?flavor=simple>
  - <https://en.wikipedia.org/wiki/St._John%27s_Cathedral_%28Kuala_Lumpur%29>
  - <https://en.wikipedia.org/w/api.php?action=query&format=json&prop=pageprops%7Cextracts%7Ccoordinates%7Cpageimages&exintro=1&explaintext=1&piprop=original%7Cthumbnail&pithumbsize=768&titles=St._John%27s_Cathedral_(Kuala_Lumpur)>

## Current State

The CDN content is present; the live publish is sparse because card content is
fed by narrow retained source refs.

| Metric | Count |
| --- | ---: |
| Live DB places | 5,036 |
| Shipped places in live Malaysia publish | 3,811 |
| Source records: OSM / Wikidata / Wikipedia | 3,417 / 557 / 1,180 |
| Shipped places with `wp:` member refs | 64 |
| Shipped places with `wd:` member refs | 449 |
| Shipped places with any Wikidata ref in `places.refs_json` | 573 |
| Description sidecar entries | 64 |
| Image sidecar entries | 305 |

App-path status from codex2: online image sidecars are consumed by iOS, but
online description sidecars are not. The card model currently renders blurbs
from inline tile JSON/snapshots. For the live Malaysia publish that distinction
does not change the count: the same 64 Wikipedia-derived descriptions are
inlined into tiles and emitted as description sidecar entries. Offline bundles
do not yet consume image sidecars, image thumbs, or description sidecars; inline
tile blurbs are the only offline description path today.

The key implementation detail:

- `publish_stage._joined_places()` publishes `source_refs` from
  `places.member_refs_json`.
- `descriptions.descriptions_from_source_records()` only considers retained
  `wp:` refs already present on that published place.
- `images.candidates_from_source_records()` only considers retained source refs
  already present on that published place, and only accepts valid Commons-style
  URLs before Commons metadata/license audit.
- `places.refs_json` can contain join refs such as `wd:` references inferred
  from OSM/Wikipedia props, but those join refs do not drive card sidecars unless
  they are also members or otherwise looked up.

## Where The 98 Percent Falls Out

The losses are layered.

1. Most shipped places have no retained Wikidata or Wikipedia member. Of 3,811
   shipped places, 3,409 have OSM member refs, 449 have Wikidata member refs, and
   only 64 have Wikipedia member refs.

2. Wikipedia extraction is geosearch-first. `acquire_wikipedia()` calls
   `list=geosearch` over bbox tiles, then fetches extracts/pageprops only for
   the returned page IDs. It does not seed the Wikipedia snapshot from Wikidata
   sitelinks. A page with a Wikidata sitelink but no Wikipedia coordinate
   property is invisible to the current Wikipedia source table.

3. The database has many Wikipedia rows, but almost all are unpublished because
   taxonomy excludes them. There are 1,180 Wikipedia source rows and 1,179 have
   extracted text. Of the live DB places with `wp:` members, 1,116 are not
   shipped; all 1,116 are `uncategorized`. The shipped `wp:` members are only 64
   places across `museum`, `attraction`, `religious`, `historic_building`, and
   `memorial`.

4. Image strictness explains the gap between a retrospective candidate count and
   shipped image entries. Recomputing against the current DB/staging gives 334
   valid Commons candidates under the code's retained-ref rule. The reviewed
   audit contains 305 accepted Malaysia rows. The 29 candidate IDs not present
   in that accepted set have cached rejection reasons: 17 `license_missing`, 8
   `license_url_invalid`, 2 `metadata_missing`, and 2 `license_url_mismatch`.
   This is evidence about the audit/staging artifact, not proof that a fresh
   `upload=True` publish selected exactly the same 334 candidates.

5. Non-Commons image URLs are intentionally ignored by the image sidecar path.
   Some OSM records carry Mapillary, Google, Wikia, Imgur, or arbitrary web image
   URLs. Those are not compatible with the current Commons attribution and
   license model.

## Worked Example: St. John's Cathedral

Rob's cited `Q613619` is not the Kuala Lumpur cathedral. It is St. John's
Co-Cathedral in Valletta, Malta. The Kuala Lumpur item is `Q5552448`.

The pipeline has the Kuala Lumpur Wikidata record:

- source row: `wd:Q5552448`
- name: `St. John's Cathedral`
- coordinates: `3.14983, 101.69937`
- Wikidata image: `St. John's Cathedral, Kuala Lumpur.jpg`
- Wikidata sitelinks count in our snapshot: 11
- live place: `mt1_5W10AYPR6VCVZZ69NJFM8JE2WH`
- shipped tile: `10/801/503`
- published source refs: `["wd:Q5552448"]`

The official Wikidata entity confirms `P18`, `P625`, and an `enwiki` sitelink
for `St. John's Cathedral (Kuala Lumpur)`. The official Wikipedia API returns
`wikibase_item=Q5552448`, a lead extract, and a pageimage candidate requiring
Commons filename extraction plus Commons imageinfo license audit before
publication. It does not return a page-level `coordinates` property for that
article in the queried response.

That is the drop:

- The Wikidata image path works, so St. John's should be in the image candidate
  pool and should get a photo if its Commons metadata/license audit accepts.
- The Wikipedia article is not in our `source_records` table because current
  Wikipedia acquisition only starts from geosearch page IDs. Wikidata knows the
  enwiki title, but our extractor never asks for it.
- Since there is no retained `wp:` source row for `Q5552448`, description
  emission has nothing to attach and the card gets no blurb.

## Source Potential For The Current Publish

For the 3,811 shipped Malaysia places:

| Potential source | Count | Coverage |
| --- | ---: | ---: |
| Any Wikidata ref in `places.refs_json` | 573 | 15.0% |
| Official Wikidata `P18` among those QIDs | 420 | 11.0% |
| Official Wikidata enwiki sitelink among those QIDs | 387 | 10.2% |
| Official enwiki intro extract among those titles | 151 | 4.0% |
| Official enwiki pageimage candidate, not accepted image | 329 | 8.6% |
| Current code path: valid Commons image candidates | 334 | 8.8% |
| Current live image entries | 305 | 8.0% |
| Current live description entries | 64 | 1.7% |

This means a pure "bring Wikidata and Wikipedia together for already-shipped
QIDs" pass can improve content, but it cannot make Malaysia broadly rich by
itself. It exposes about 151 description candidates before sanitization and
sidecar emission checks. For images, it exposes 420 P18-backed candidate places;
the final image-entry count depends on overlap with the current 305 image
entries and Commons audit acceptance. That is materially better but still
single-digit or low-teens coverage.

The hard ceiling is that 3,238 of 3,811 shipped places currently have no
Wikidata ref at all. They need entity linking or another licensed content source.

## Options

### Option A: Fix The Obvious Join Gap

Add a Wikidata-sitelink enrichment path for shipped places with a current QID in
`places.member_refs_json` or `places.refs_json` for the live place. Registry refs
may resolve the current winner `place_id` and detect superseded/ambiguous IDs;
registry-only historical refs are not content evidence.

- During acquire/enrichment, batch `wbgetentities` for shipped QIDs with
  `sitefilter=enwiki`, then batch Wikipedia `extracts|pageimages|pageprops` by
  title.
- Persist derived `wp:` rows or an explicit QID-to-Wikipedia enrichment table so
  publish remains deterministic and offline from network.
- Make description/image sidecar selection use that persisted QID relationship,
  not only `member_refs_json`.
- For sitelink-seeded Wikipedia records, populate lat/lon from the owning
  QID/place, not from the Wikipedia title response; add a regression for a
  title-only page with no `coordinates`.
- Any QID-derived Wikipedia description must still emit a canonical
  `wp:<pageid>` source ref and must cause manifest attribution to include
  Wikipedia, even when the tile place source refs remain `wd:`-only. Tests must
  cover both inline blurb emission and description sidecar emission for a
  `wd:`-only place enriched through a verified Wikipedia page.
- P18 images require joining shipped QIDs to `wd:` rows and feeding
  `wd.props.image`; enwiki page images require acquiring and persisting a
  Commons-compatible `props.image` from `pageimages`. Fetching `pageimages` by
  title alone will not affect current sidecars.
- Reuse the hardened acquisition boundary: expected hosts, max bytes,
  retry/backoff, compliant User-Agent, `_meta.complete` snapshots, sorted
  deterministic writes, `source_record.parse`/SAFE_TEXT caps, canonical
  `wp:<pageid>` refs, and verification that `pageprops.wikibase_item` equals the
  QID before joining. Titles and source content must only enter URLs through
  structured encoding and must never be interpolated into SQL, shell, or LLM
  prompts.

Expected candidate ceiling on the current Malaysia publish: about 151
descriptions before description sanitization and sidecar emission checks, plus
420 P18-backed image candidates before overlap measurement and Commons audit.
Network volume for Malaysia is small: roughly 12 Wikidata entity requests for
573 QIDs and 8 Wikipedia page requests for 387 titles at 50-title batches, plus
pageview fetches only if we choose to score/rank the new page rows with
pageviews.

Pack impact is modest. Current Malaysia pack descriptor sidecars are:
49,668 bytes of description indexes, 140,098 bytes of image indexes, and
11,592,460 bytes of image thumbs. Scaling descriptions from 64 to 151 is tiny.
If the same 91.3% acceptance rate seen in the current retained-ref candidate set
held for the 420 P18 candidates, that subset would project to about 384 accepted
thumbs; total pack growth requires measuring overlap with existing image
entries and is dominated by WebP thumbs.

### Option B: Promote Wikipedia Rows Out Of `uncategorized`

The DB already has 1,179 Wikipedia rows with extracts, but 1,116 live
Wikipedia-backed places are not shipped because they are `uncategorized`.
Existing snapshots can use `props.wikidata`, title, and extract heuristics.
Wikipedia category-based taxonomy requires adding category acquisition and
refreshing snapshots.

Expected ceiling: higher than Option A for descriptions, because the source text
is already present. Risk is quality: many geosearch pages are towns, transit
stations, schools, districts, hotels, or broad articles. This needs an eval
sweep and taxonomy guardrails so the map does not become generic encyclopedia
POIs.

Network cost is low for heuristics that use existing snapshots. Category-based
classification and pageviews for newly promoted pages require new fetches; each
article pageview request must use the existing polite interval. Pack cost grows
with however many places are admitted, not only with sidecars.

### Option C: Entity-Link OSM-Only Places

Most shipped places are OSM-only. To get useful coverage across the product, the
pipeline needs a reconciliation/enrichment pass that links OSM places to
Wikidata/Wikipedia by explicit OSM tags first (`wikidata`, `wikipedia`,
`wikimedia_commons`), then by cautious name+distance candidate matching.

Expected ceiling: this is the only path toward majority coverage, but it is also
the highest-risk path for `place_id` stability and false merges. It needs a
scored candidate table, review thresholds, and regression fixtures for ID
stability and bad merges.

Network/API cost depends on strategy. Explicit tags are cheap and deterministic.
Name+distance search against Wikidata/Wikipedia is much larger and should run as
a bounded acquire snapshot with progress, retry/backoff, and persisted inputs.

### Option D: Broaden Image Sources Beyond Commons

This is not a near-term fix. The current image contract assumes Wikimedia
Commons metadata and license attribution. Non-Commons URLs found in OSM include
Mapillary and arbitrary web hosts; accepting them would require new source
policy, license handling, attribution fields, safety checks, and probably a
different user-facing credit model.

Expected ceiling: uncertain. Cost and policy risk are high. This should not
block Commons/Wikidata/Wikipedia fixes.

## Recommendation

Build Option A first as the immediate repair: QID-sitelink enrichment for shipped
places, persisted before publish, with sidecars joined by QID. It directly fixes
the St. John's class of failure, has small request and pack-size cost, and can
keep the existing Commons/Wikipedia attribution model if attribution source
accounting is updated alongside the QID join.

In parallel or immediately after, file a separate taxonomy/eval package for
Option B. The current Wikipedia snapshot contains useful text, but admitting the
1,116 `uncategorized` rows is a ranking/product-quality problem, not a publish
bug.

Treat Option C as the real coverage work. Rob is right that sub-2% descriptions
make cards feel useless; however, Wikidata/Wikipedia can only enrich the
minority of currently shipped places that already have or can be safely linked
to an entity. Majority coverage requires deliberate entity linking for OSM-only
places.

## Record / Routing

#297 is the research record. If accepted, create a separate Option A
implementation issue with `track-a-pipeline`, `enhancement`, and `wp` labels;
its PR must name that issue and cite #297 as research provenance. Option B and
Option C are separate follow-on issues, not riders on the Option A PR.
