# WP-BRAINSTORM: Scalable Content Enrichment

## Question

Malaysia's current publish proves that "more Wikipedia" is not enough. The live
app has thousands of places but sparse card content because only a narrow set of
retained source refs can feed descriptions and images. Rob's question is whether
Options B and C need separate specs, or whether there is a more scalable
architecture for bringing in structured sources such as Historic England and
national heritage registers generally.

This document proposes the scalable architecture. It is a design proposal, not
an implementation plan. After Rob approves the direction, the implementation
specs are cut from the chosen architecture.

## Context

The current pipeline already has the right outer shape:

- Acquisition writes bounded snapshots.
- Extractors normalize into `source_records`.
- Reconcile owns stable `place_id` assignment through source refs and the ID
  registry.
- Score, categorize, and publish are deterministic downstream consumers.
- `attribution.md`, `pipeline/config/a1d_sources.json`, and
  `pipeline/src/mt_pipeline/publish/attribution.py` already establish that
  runtime data credits come from structured source metadata.

The coverage research in
`docs/research/2026-07-20-content-coverage-research.md` showed the hard limit:
Malaysia has 3,811 shipped places, but 3,238 of them have no Wikidata ref in
the current place record. Fixing Wikidata-to-Wikipedia sitelinks is still worth
doing, but it cannot produce majority coverage alone. Majority coverage requires
linking OSM-only places to stronger evidence and accepting non-Wikimedia source
classes when their licenses and attribution are compatible.

## External Source Reality

Historic England is the useful worked example because it is not a special case:
it represents a broad class of official heritage registers with stable IDs,
coordinates or geometry, legal/designation signal, text fields, and explicit
licensing.

Official source checks:

- The GOV.UK API catalogue lists the National Heritage List for England as the
  official up-to-date register for nationally protected historic buildings and
  sites, with an ArcGIS FeatureServer endpoint, daily updates, and Open
  Government Licence usage.
- Historic England's open-data download page says NHLE data is available through
  the Open Data Hub in formats and APIs, and that GIS spatial data is free under
  OGL.
- Historic England's Open Data Hub terms require attribution, including
  Historic England and Crown/Ordnance Survey wording for spatial data.
- Historic Environment Scotland publishes listed-building spatial data through
  trove.scot, including download/WMS/WFS/Atom Feed routes, under OGL v3.
- Cadw's Listed Buildings metadata on DataMapWales describes a live current
  dataset, downloadable as GeoJSON/CSV/GML/GeoPackage and available under OGL
  with a required attribution statement.
- Malaysia and Singapore need source discovery rather than assumptions.
  Malaysia's public data portals show general open-data and public-sector data
  exchange surfaces, but this pass did not confirm an equivalent machine-readable
  national heritage register suitable for direct ingestion.

Source references:

- <https://www.api.gov.uk/he/national-heritage-list-for-england-nhle/>
- <https://historicengland.org.uk/listing/the-list/data-downloads>
- <https://historicengland.org.uk/terms/website-terms-conditions/open-data-hub/>
- <https://www.trove.scot/explore/download-our-data/listed-buildings-data-for-download>
- <https://datamap.gov.wales/layers/inspire-wg%3ACadw_ListedBuildings/metadata_detail>
- <https://data.gov.my/>
- <https://www.mygdx.gov.my/en/landing-page/theme?theme=second-theme>

## Design Goal

The target pipeline makes adding a new structured source mostly an adapter
problem, while keeping entity linking, ID stability, source trust, licensing,
attribution, and content promotion centralized.

Target outcomes:

- Majority card coverage comes from a union of source classes, not a dependency
  on Wikipedia/Wikidata.
- New sources can add descriptions, images, designations, names, aliases,
  taxonomy signals, and external IDs without minting a new place by accident.
- Entity linking has an explicit reviewable contract: exact identifiers first,
  scored candidates second, and false-merge guards before any accepted link can
  affect a shipped `place_id`.
- Runtime attribution is driven by every shipped piece of content, not only by
  the place's visible member refs.
- Acquisition remains bounded, polite, deterministic, and reproducible from
  complete snapshots.

"Majority card coverage" in this document means at least 50 percent of shipped
places in a region have one of:

- a source-attributed human-readable description or useful factual summary,
- an accepted image with complete per-asset attribution,
- or a strong designation/curiosity signal that materially improves the card
  and ranking even when prose and media are absent.

The higher product bar is "rich card coverage": description plus image or
designation context. The proposed architecture separates those metrics because
sources contribute differently.

## Coverage Forecast

These are planning estimates, not promised outputs. They define what each work
package must measure before it can claim success.

| Step | Malaysia expected contribution | UK expected contribution | Confidence |
| --- | --- | --- | --- |
| Current live path | 64 descriptions, 305 images among 3,811 shipped Malaysia places | not remeasured in this pass | measured for Malaysia |
| QID sitelink enrichment | up to 151 description candidates and 420 P18-backed image candidates among current shipped places before sanitization, overlap, and Commons audit | likely useful but not the scale proof | measured for Malaysia QIDs |
| Explicit identifier linker | unknown until OSM tag audit counts `wikidata`, `wikipedia`, register ID, and Commons refs on shipped OSM-only places | likely meaningful because UK OSM frequently carries heritage/Wikidata tags | measurement owned by WP-CE-2 |
| One official register adapter | no confirmed national heritage source yet; requires source portfolio work | Historic England is the proof source; NHLE has national scale, stable IDs, geometry, designation grade, and OGL attribution | high for UK, unknown for Malaysia |
| Scored linker | only path that can attach evidence to the 3,238 shipped Malaysia places without current QIDs; target is high precision first, then coverage | can link OSM-only places to HE/HES/Cadw/Wikidata candidates after explicit IDs are exhausted | medium after eval |
| Content promotion/eval | converts accepted evidence into shipped card content and reports quality-adjusted coverage | same | high once evidence exists |

The honest Malaysia answer is: current Wikimedia-only enrichment cannot reach
majority coverage. The plausible majority path is explicit IDs plus scored
linking plus a region source portfolio. If Malaysia/Singapore source discovery
finds no licensed machine-readable local registers, majority coverage depends on
how much OSM-only content can be safely linked to Wikidata/Wikipedia and other
open civic or collection sources. That is a measurement task, not an assumption.

## Options

### Option 1: Keep Adding Direct Extractors

Each source emits `source_records` and lets current reconcile/publish behavior
do the rest.

This is cheap for source records that are already place-like and uniquely
located. It is not enough for majority coverage. It conflates "this is another
place candidate" with "this is evidence about an existing place", and it forces
every source to solve linking, attribution, and content promotion indirectly.
False merges also become harder to reason about because the evidence path is
buried inside cluster membership.

Use this only for simple source records that truly are independent place
candidates.

### Option 2: Common Evidence And Link Tables

Adapters produce normalized evidence, not only place candidates. A central
linking stage attaches evidence to places through explicit IDs or reviewed
candidate matches. Publish reads accepted evidence when generating blurbs,
images, credits, scores, and tiles.

This is the recommended architecture. It preserves the current pipeline's
source-record model and stable registry, but adds a reusable enrichment layer
for many source classes.

Tradeoff: it adds new contracts and review gates. That is the right complexity:
the hard problem is not downloading more files; it is deciding which external
claims are allowed to enrich which stable place.

### Option 3: Build A Separate Knowledge Graph Service

A standalone graph/index service could ingest every external dataset and answer
entity-linking queries for the pipeline.

This is overbuilt for v1. It adds runtime or operational state that the current
static pipeline deliberately avoids. The useful part is the graph model, and
that can live inside SQLite snapshots and deterministic pipeline tables first.

## Recommended Architecture

### 1. Source Policy Surfaces

Extend the current `a1d_sources.json` pattern, but keep policy surfaces separate
so changing a retry cadence does not look like changing legal or matcher policy.

Source identity/licensing catalog:

- `source_key` and emitted canonical ref prefix.
- Source class: `knowledge_graph`, `article`, `heritage_register`,
  `museum_collection`, `plaque_register`, `image_archive`, or `civic_register`.
- Regions where it is enabled.
- License policy split by data, text, and media.
- Field-level license status: which fields are factual data, which fields are
  reusable prose, which fields are non-reusable or need a separate audit.
- Required source attribution text and whether downstream sublicensing or
  share-alike obligations apply.
- Fields exposed as evidence kinds.

Acquisition config:

- endpoint(s), allowed hosts, maximum bytes, cadence, retry/backoff policy,
  pagination/cursor rules, and whether the source may reuse the last complete
  snapshot if the current fetch fails.
- resource identity and version token used as the adapter memo key. Every
  adapter composes the shared conditional-fetch client where the protocol
  supports it, and never reprocesses unchanged content. Correctness is by
  content hash; HTTP `304 Not Modified` is only a bandwidth optimization.

Link strategy config:

- Link strategies allowed for the source.
- auto-accept thresholds, review thresholds, reject thresholds, and negative
  blockers.
- method-specific fixtures that prove false-merge guards.

Open Flag for Rob: decide whether optional enrichment sources may reuse the last
complete snapshot on source outage. That preserves "no partial publish" while
avoiding an entire region going stale because one optional enrichment feed is
down. If no complete snapshot exists, the source either aborts the run or is
explicitly disabled in config.

### 2. Adapter Output: Evidence, Not Just Places

Keep `source_records` for records that are candidate places. Add a common
evidence table for content and signals that may attach to an existing place.

Proposed table shape:

| Field | Purpose |
| --- | --- |
| `region` | Region scope. |
| `source_key` | Config/attribution key such as `historic_england`. |
| `source_ref` | Canonical external ref such as `hehle:1234567`. |
| `evidence_ref` | Stable source-local evidence ID for the specific claim. |
| `kind` | `description`, `media_candidate`, `designation`, `external_id`, `alias`, `taxonomy_signal`, `score_signal`, `article_link`. |
| `language` | Language code when the evidence is text. |
| `title` | Optional display/source title. |
| `text` | Bounded plain text for description-like evidence. |
| `license_key` | License for this evidence, not just for the dataset. |
| `attribution_key` | Source key that must appear if this evidence ships. |
| `source_url` | Canonical source URL for this evidence when attribution needs item-level linking. |
| `modified` | Whether shipped text is excerpted, transformed, or resized. |
| `props_json` | Bounded structured payload for source-specific fields. |
| `payload_hash` | Deterministic hash for change detection. |
| `run_id` | Snapshot/run provenance. |

Examples:

- Historic England emits a place-like `hehle:<list_entry>` source record plus
  evidence rows for designation grade, official entry URL, and
  architecture/history taxonomy signals. Register prose is blocked until the
  adapter declares that the specific text field is reusable under the recorded
  license and attribution wording.
- Wikipedia emits an article record and evidence rows for lead extract,
  wikibase item, page image candidate, and pageview score signal.
- A museum API can emit collection-object evidence for a monument only if its
  record carries a reliable place/external ID or passes the linker.

`media_candidate` evidence is never directly publishable. Promotion to a shipped
image requires an accepted media-asset record with the same attribution shape as
the existing image index: creator when required, license code/name/URL, source
URL, modified status, MIME/type gates, host rules, and explicit rejection on
ambiguous or incompatible media terms.

All text remains bounded through the existing untrusted-data posture:
plain-text only, size caps, control-character stripping, schema validation, and
no source content interpolated into shell, SQL, or LLM prompts.

### 3. Link Candidates And Decisions

Linking is not a hidden post-publish mutation. It is owned by the reconcile
surface because reconcile owns `place_id`, registry refs, and `places`.

Two implementation shapes are acceptable for a later spec:

- fold identity-link generation and review into `reconcile`, then write accepted
  identity refs into the registry before `places` are emitted;
- or add an explicit `link` stage between `reconcile` and `score` that owns only
  accepted identity-link artifacts, with `score`, `categorize`, and `publish`
  gated on that stage.

The common rule is that registry refs are identity refs only. Content evidence
refs, page image candidates, text snippets, and media archive asset IDs do not
get appended to the ID registry unless they are durable external identities for
the place itself.

Add a central table for proposed identity links between source refs and stable
places.

Proposed table shape:

| Field | Purpose |
| --- | --- |
| `region` | Region scope. |
| `place_id` | Existing place when known; nullable before decision. |
| `left_ref` | Existing place/source ref or candidate place anchor. |
| `right_ref` | External source/evidence ref being linked. |
| `method` | `explicit_id`, `registry_ref`, `geometry_contains`, `name_distance`, `name_address_distance`, `manual_review`. |
| `score` | Deterministic score for candidate methods. |
| `decision` | `accepted`, `review`, or `rejected`. |
| `ruleset_version` | Versioned matcher config. |
| `evidence_json` | Bounded explanation: matched names, distance, class compatibility, conflicts. |
| `run_id` | Run provenance. |

Linking rules:

- Explicit identifiers win first: OSM `wikidata`, `wikipedia`,
  `wikimedia_commons`, known register ID tags, source-provided Wikidata QIDs,
  and pageprops `wikibase_item` are accepted only when the identifier is
  canonical and unambiguous.
- Existing registry refs resolve before new matches. A source can enrich an
  existing `place_id` with accepted evidence without appending non-identity refs
  to the registry.
- Scored matching is conservative and source-aware. It can use name similarity,
  distance, geometry containment, address/postcode, source category, designation
  class, and negative blockers such as name conflict, class incompatibility, or
  multiple equally good candidates.
- Auto-accept thresholds are high. Ambiguous middle cases go to a deterministic
  review artifact. Low scores are rejected and persisted so they do not churn.
- Accepted links are additive. A false split is acceptable; a false merge can
  corrupt user history attached to `place_id`.

This is Option C's core, but it is not a separate world from Option B. The same
link-decision table is what lets taxonomy, descriptions, images, and source
credits use external evidence safely.

### 4. Accepted Evidence

Publishable or scoreable evidence is represented by an accepted-evidence
contract keyed by `(region, place_id, evidence_ref)`.

| Field | Purpose |
| --- | --- |
| `region` | Region scope. |
| `place_id` | Stable place being enriched. |
| `evidence_ref` | Specific source-local evidence claim. |
| `source_ref` | Source record that owns the evidence. |
| `kind` | Evidence kind being accepted. |
| `decision_id` | Link/review decision that permits this evidence for this place. |
| `ruleset_version` | Versioned matcher/promotion policy. |
| `license_status` | `allowed`, `blocked`, or `review`. |
| `attribution_key` | Manifest source key required if this evidence ships. |
| `payload_hash` | Evidence hash accepted by the decision. |
| `run_id` | Run provenance. |

Invariant: score, categorize, descriptions, images, search, tiles, and
attribution consume evidence only through a single deterministic query interface,
for example `accepted_evidence_for_places(region, place_ids, kinds)`. They do
not infer shippability from raw source membership, raw source refs, or unlinked
evidence rows.

### 5. Content Promotion

Publish consumes accepted evidence through a single promotion policy:

- Descriptions: choose the best accepted `description` evidence by source
  priority, language, length, license compatibility, and quality checks.
  Copyleft text such as CC BY-SA stays in a license-scoped sidecar or another
  explicitly designed artifact boundary until the tile contract records
  per-content license metadata.
- Images: choose only media whose source and per-media license policy are
  acceptable. Wikimedia Commons keeps its current audit path. Non-Commons
  images require a separate media-asset adapter before publication.
- Designations and score signals: Historic England grade, Cadw grade, plaque
  presence, sitelinks, pageviews, and source class feed scoring as evidence, not
  as hand-coded one-offs.
- Taxonomy: Option B belongs here. Taxonomy classifies what evidence means and
  decides which categories can ship. It does not perform linking and does not
  substitute for link review.
- Attribution: manifest attribution must be derived from shipped evidence as
  well as shipped `source_refs`. If a place has only `osm:*` as its visible
  member ref but ships a Historic England description, the manifest must include
  Historic England attribution.

Article evidence carries page title, canonical source URL, license code/name/URL,
approved contributor or source-level attribution wording, and modified/excerpted
status. A global manifest line alone is not enough for sources whose terms need
item-level attribution.

### 6. Operational Model

Every source follows the same pipeline contract:

1. `acquire`: fetch complete bounded snapshots using configured endpoints,
   allowed hosts, byte caps, source-specific rate limits, retry/backoff, and a
   compliant user agent. Write `_meta.complete=true` only after the snapshot is
   fully written.
2. `extract`: parse local snapshots only. Emit sorted deterministic records and
   evidence rows. No network.
3. `reconcile/link`: produce deterministic identity-link candidates and
   decisions from local tables and matcher config. No network.
4. `review`: write ambiguous candidates to a stable artifact. Human-reviewed
   accept/reject decisions become versioned input.
5. `score/categorize`: compute interest and category from accepted evidence.
6. `publish`: emit tiles, sidecars, images, manifests, and attribution from the
   accepted place/evidence graph.

Scaling properties:

- Adding a source is mostly adapter + source-catalog config + fixtures +
  licensing review.
- Heavy work stays on the VPS and writes progress heartbeats with counts,
  rates, durations, and log paths.
- Snapshots are immutable inputs. Re-running the same snapshot, matcher config,
  and review decisions produces byte-identical outputs.
- Acquisition concurrency is configured per source class. Wikimedia retains its
  current strict fetch policy; bulk-register downloads usually use lower
  concurrency and larger byte caps; paginated APIs use explicit cursors and
  sorted page assembly.
- Source freshness is explicit in metadata. A stale-but-complete optional
  snapshot is safer than silently dropping a source.
- Derived acquire is explicit. QID-sitelink enrichment seeded from the current
  or previous place graph gets its own bounded snapshot/fingerprint; no network
  call is hidden inside extract, link, score, or publish.

## Source Class Matrix

| Source class | Examples | Required fields | Link methods | License/attribution caveats | Region status |
| --- | --- | --- | --- | --- | --- |
| Official heritage registers | Historic England, Historic Environment Scotland, Cadw | stable ID, name/address, point or geometry, designation type, grade/class, official URL | explicit IDs, registry refs, geometry/name/address review | OGL-like data often needs source/Crown/OS attribution; prose and media are field-gated separately | UK examples confirmed or candidate-audited; Malaysia/Singapore discovery required |
| Knowledge graphs | Wikidata, authority files | canonical ID, coordinates, aliases, classes, external IDs, sitelinks | explicit IDs, redirects, registry refs, cautious name/distance | CC0 data still hostile input; media URLs are candidates only | Wikidata active |
| Article sources | Wikipedia, license-compatible local encyclopedias | page ID, title, entity ID when available, extract, source URL, license metadata | wikibase/pageprops, explicit page refs, reviewed title+distance | text needs item/source attribution, license URL, modified/excerpted state; share-alike boundaries matter | Wikipedia active; others discovery |
| Plaque/civic registers | Open Plaques, public art, memorial inventories | stable ID, text/title, coordinates, subject/place relation | explicit IDs, point/name review | plaque text may describe a person/event rather than the host place | Open Plaques planned/available for UK |
| Museum/collection APIs | national/local collections | object ID, place association, coordinates or external IDs, rights fields | explicit place IDs first, review otherwise | object text/media often has separate rights and may not describe the place | discovery |
| Media archives | Commons, source-specific image APIs | asset ID, source URL, creator, license, MIME, dimensions | linked only after place evidence is accepted | per-asset license audit required; dataset-level license is insufficient | Commons active |

## Source Class Playbook

### Official Heritage Registers

Examples: Historic England NHLE, Historic Environment Scotland designations,
Cadw listed buildings, local or national monument registers.

Use as high-trust designation evidence. Prefer explicit IDs where OSM or
Wikidata already references the register. Use geometry/name/address matching for
the long tail, guarded by review thresholds. Licenses are often OGL-like and
attribution-required. Descriptive prose is publishable only after the adapter
records field-level reuse permission. Images, when present, are separate media
evidence because text/data licensing does not automatically make the image
reusable.

### Knowledge Graphs

Examples: Wikidata and source-specific authority files.

Use for identifiers, aliases, sitelinks, classes, coordinates, and image
candidates. Treat labels/classes as hostile input despite CC0 licensing. Use
redirect maps and registry bridging before link decisions.

### Article Sources

Examples: Wikipedia now; possibly local encyclopedias only if license-compatible.

Use for descriptions, titles, page images, pageviews, and article-existence
signals. Verify entity identity when possible (`pageprops.wikibase_item` equals
the target QID). Article text is blocked unless item/source attribution and
license metadata are sufficient for the artifact where it will ship.

### Plaque And Civic Registers

Examples: Open Plaques, public-art inventories, local memorial inventories.

Use as strong "there is a thing here" evidence and sometimes as description
seed text. Link cautiously: plaques often describe people/events at a location,
not the building itself.

### Museum And Collection APIs

Use only when records include stable place association, monument IDs, Wikidata
IDs, or strong coordinates. Collection-object text can be high quality but often
describes an object rather than the place. Default to review unless the link is
explicit.

### Media Archives

Use after a separate media-license audit. Dataset openness does not imply every
photo can ship in the app. Store creator, license code, license URL, source URL,
modification status, and source-specific terms per asset.

## What This Means For B And C

Option B, taxonomy/eval promotion, is not a standalone attempt to rescue
Wikipedia rows. It becomes the evidence-promotion and evaluation layer:
measure source contribution, decide category/score impact, and prevent generic
or low-quality content from shipping.

Option C, entity linking, is the central unlock for majority coverage. It is a
reusable link-candidate system, not "match OSM to Wikidata" only. Wikidata is
the first and most useful target, but the same mechanics apply to Historic
England, Cadw, Open Plaques, and future national registers.

Option A remains separately buildable and goes first if Rob wants near-term
coverage movement: shipped places that already have current QIDs can gain
Wikipedia descriptions and P18 images without name-distance matching. The seed
set is explicit: a bounded derived-acquire snapshot generated from either the
current reconcile output or the previous shipped place graph. The implementation
spec must pick one seed source and fingerprint it.

## Recommended Work Packages

### WP-CE-0: Evidence Contract And Policy Surfaces

Define the `content_evidence` and `entity_link_candidates` schemas, source
identity/licensing catalog, acquisition config, link-strategy config,
accepted-evidence view, media-asset gate, attribution derivation changes, and
fixture contracts. No new source uses an ad hoc path around these tables.

### WP-CE-1: QID Sitelink Enrichment

Implement Option A on the new evidence path. From the chosen QID seed snapshot,
batch Wikidata sitelinks and Wikipedia extracts/pageimages, verify
`wikibase_item`, and emit canonical `wp:<pageid>` evidence plus attribution.

### WP-CE-2: Explicit Identifier Linker

Accept links from exact identifiers only: OSM `wikidata`, `wikipedia`, register
ID tags, source-provided QIDs, and known registry refs. Success is measured by
accepted identity links, no false-merge fixture failures, and card-content
coverage deltas.

### WP-CE-3: Historic England Proof Adapter

Port Historic England through the new adapter/evidence/link contract first. It
is the UK scale proof because the source is official, machine-readable,
attribution-defined in repo config, and rich in designation signal. Initial
scope is factual/designation evidence plus field-gated prose; media remains
blocked until a media-asset audit exists.

### WP-CE-4: Scored Linker And Review

Add name/distance/geometry/address candidate generation, conservative
auto-accept thresholds, reject persistence, and a deterministic review artifact.
This is the majority-coverage unlock and carries ID-stability regression tests,
false-merge fixtures, and a measured review-queue budget.

### WP-CE-5: Regional Source Portfolio

Produce per-region source portfolios before adding more adapters. HES/Cadw stay
candidate sources until source-catalog drafts capture license URL, attribution
text, allowed hosts, field-license split, and fixtures. Malaysia/Singapore get a
feasibility report first; do not invent an unavailable national register.

### WP-CE-6: Additional Register Adapters

Port confirmed sources such as Historic Environment Scotland and Cadw after the
portfolio audit. Each adapter is its own issue unless the source formats and
licensing are identical enough for one shared implementation.

### WP-CE-7: Content Promotion And Contribution Report

Publish descriptions, images, score signals, taxonomy signals, and attribution
from accepted evidence. Emit a per-region contribution report:

- candidate evidence count by source and kind
- accepted/review/rejected link counts
- shipped descriptions/images by source
- attribution sources included in manifest
- coverage deltas versus previous publish
- eval precision deltas for golden areas
- link precision by method/source
- description usefulness and generic-content rejection counts
- media-license rejection counts
- quality-adjusted coverage, not just raw coverage
- ambiguous candidates per 1,000 shipped places

## Success Criteria

The architecture is working when a new source can be added with:

- one source-catalog entry,
- one snapshot/acquire adapter,
- one extractor that emits source records/evidence,
- source-specific link strategy config and fixtures,
- licensing/attribution metadata,
- contribution/eval output proving whether it improved coverage without harming
  precision.

For Malaysia, the first real milestone is not "majority content overnight"; it
is proving the path:

1. QID-backed places gain the missing Wikipedia/Wikidata content.
2. Explicit OSM identifiers attach more QIDs/register refs without false
   merges.
3. Scored linking expands OSM-only places through reviewable evidence.
4. National/register source discovery determines which local sources can
   contribute legally and mechanically.

For the UK, Historic England is the immediate scale proof. A successful run
shows accepted designation links, source-attributed field-gated descriptions or
facts, and scoring/taxonomy gains without bespoke publish logic.

Per-work-package cost envelopes belong in the follow-on specs:

- snapshot bytes and retained snapshot policy,
- API request counts and rate limits,
- expected runtime and VPS disk,
- candidate rows by kind,
- accepted/review/rejected link counts,
- ambiguous links per 1,000 places,
- pack-size impact for sidecars and thumbs,
- human review workload,
- abort/reuse behavior on source outage.

## Review Record

Adversarial self-review ran with three independent critics:

- architecture/pipeline fit,
- source licensing and attribution,
- product coverage/eval realism.

Findings raised: 17. Survived and fixed in this document: 17.

Fixes folded:

- Defined majority card coverage and added a coverage forecast table.
- Made Malaysia's path honest: local source discovery is required, and majority
  coverage is not promised if suitable licensed sources do not exist.
- Split source policy into identity/licensing, acquisition, and link-strategy
  surfaces.
- Made linking owned by reconcile or by a formally inserted stage; no hidden
  post-reconcile mutation.
- Stated that registry refs are identity refs only; evidence provenance lives
  outside the ID registry.
- Added an accepted-evidence invariant keyed by `(region, place_id,
  evidence_ref)`.
- Required a single accepted-evidence query interface for score, categorize,
  publish, search, tiles, images, and attribution.
- Made image evidence unpublishable until promoted through a media-asset record
  matching the existing image-index attribution model.
- Added field-level license gates for heritage prose.
- Added share-alike artifact-boundary requirements for copied/excerpted text.
- Added item-level attribution requirements for non-Wikipedia article sources.
- Added the source-class matrix and regional source portfolio task.
- Decomposed the work package order so Historic England is a proof adapter, not
  bundled with every register.
- Added quality-adjusted coverage and review-queue metrics.

## Rob Decision

Recommended decision: approve Option 2, the common evidence and link-table
architecture, and cut specs in the WP-CE order above. Build Option A as the
first implementation on that architecture, not as another one-off join path.

Open Flag: rule whether optional enrichment sources may reuse their last
complete snapshot when the current fetch fails, with manifest/source metadata
making that freshness explicit.
