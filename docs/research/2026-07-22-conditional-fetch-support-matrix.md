# Conditional Fetch Support Matrix

Probe date: 2026-07-22

Raw results: `docs/research/2026-07-22-conditional-fetch-probe-results.json`

Reproduce:

```bash
uv run --package making-tracks-pipeline --extra dev python scripts/probe_conditional_fetch.py \
  --output docs/research/2026-07-22-conditional-fetch-probe-results.json
```

The probe performs one initial `GET` per upstream class and, only when a validator
is observed, one follow-up conditional `GET`. It uses `MakingTracksBot/0.1`,
host allowlists, `Accept-Encoding: identity`, 64 KiB response caps, explicit
byte ranges for the configured Protomaps build URL, and a 60 second read
deadline.

Correctness rule: content hash is authoritative. HTTP `304 Not Modified` is a
bandwidth optimization only; it never proves correctness by itself.

## Matrix

| Upstream class | Probe target | Initial validators | Conditional result | Support decision |
| --- | --- | --- | --- | --- |
| Commons API metadata | `commons.wikimedia.org/w/api.php?action=query...imageinfo...` | No `ETag`, no `Last-Modified` | Not probed | No conditional-fetch benefit observed for this API shape. Re-fetch bounded JSON and hash content. |
| Commons image file | `upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg` | Unquoted/non-RFC `ETag`; `Last-Modified` present | `304`, empty body | Use validators as an optimization for file bytes, but treat the unquoted `ETag` as opaque and nonstandard. Retain content-hash fallback after any `200` or `206`. |
| Wikipedia API | `en.wikipedia.org/w/api.php?action=query...extracts...` | No `ETag`, no `Last-Modified` | Not probed | No conditional-fetch benefit observed for this acquisition API shape. Re-fetch bounded JSON and hash content. |
| Wikidata acquisition API | `www.wikidata.org/w/api.php?action=wbgetentities...props=sitelinks...` | No `ETag`, no `Last-Modified` | Not probed | No conditional-fetch benefit observed for the pipeline's sitelink acquisition shape. Re-fetch bounded JSON and hash content. |
| data.gov.sg API | `api-production.data.gov.sg/v2/public/api/datasets?page=1` | No `ETag`, no `Last-Modified` | Not probed | No conditional-fetch benefit observed for the current public listing API. Re-fetch bounded JSON and hash content. |
| ArcGIS REST | Historic England NHLE `FeatureServer?f=json` | Unquoted/non-RFC `ETag`; `Last-Modified` present | `304`, empty body | Use validators as an optimization for ArcGIS metadata and small REST responses. Treat `ETag` as opaque/nonstandard and retain content-hash fallback after any `200` or `206`. |
| Protomaps build | Configured `https://build.protomaps.com/20260714.pmtiles` with `Range: bytes=0-65535` | No validators; current response is `404` | Not probed | The configured source URL is unavailable, matching the publish-run fallback. Do not infer Protomaps conditional support until the configured build URL is live. Retain ranged fetches and content hashes. |
| R2/CDN catalog | `https://tiles.making-tracks.app/regions.json` | Strong quoted `ETag`; `Last-Modified` present | `304`, empty body | Use validators as an optimization for published catalog and manifest reads. Correctness still comes from content hash when a body is returned. |

## Implementation Notes

- Keep conditional method selection explicit: the probe and future client use the
  `GET` method constant, not stringly repeated call-site literals.
- Persist validators beside the content hash for each fetched resource. A stored
  validator without a stored content hash is not enough to skip processing.
- The retained validator store is `conditional-fetch.json` beside the owning
  cache or snapshot directory. Its entries are keyed by `GET`, the full URL, and
  caller-supplied request headers after removing only conditional replay headers
  (`If-None-Match`, `If-Modified-Since`). This means headers such as `Range`,
  `Accept`, and other representation-shaping headers participate in the key.
- JSON bodies retained for `304` reuse live under `conditional-fetch-bodies/`
  named by SHA-256. File callers retain the artifact at their destination path;
  a `304` is accepted only when that file still exists and hashes to the stored
  SHA-256.
- Do not normalize or quote upstream `ETag` values before replaying them in
  `If-None-Match`; Wikimedia image files and ArcGIS both returned useful
  nonstandard unquoted values.
- If a conditional follow-up returns `200` or `206`, hash the returned bytes and
  compare them to the stored content hash. This is an unchanged-content memo hit
  only when the hashes match.
- If a conditional follow-up returns `304`, reuse the prior complete body only
  when the prior body hash and metadata are already present in the acquisition
  cache.
- Do not make an `encoder-binary/:v1` cache assumption from a path/version label.
  If encoder identity affects output bytes, record the actual binary/version as
  cache metadata and keep content hashes as the final equality check.

## Source Notes

- The data.gov.sg target uses the current public dataset-listing API shape from
  the official data.gov.sg developer guide.
- The ArcGIS REST target uses the Historic England NHLE FeatureServer endpoint
  listed in the GOV.UK API catalogue.
