# WP-A1d Malaysia Heritage Register Feasibility

Checked: 2026-07-15

## Verdict

Default-exclude. Do not implement a Malaysia national-register extractor in WP-A1d.

I did not find an official, stable, machine-readable national heritage register with per-site records, stable ids, and coordinates suitable for the A1 extractor contract. The existing region config default remains correct:

```json
"national_register": {"id": "malaysia_heritage", "enabled": false}
```

## Evidence Checked

### Malaysia open-data portal

- Source: `https://data.gov.my/data-catalogue`
- The catalogue presents Malaysia's official open-data portal and its listed categories; I found no `warisan`, `heritage`, or culture/heritage dataset category.
- The documented Data Catalogue API requires a concrete `id` parameter: `https://developer.data.gov.my/static-api/data-catalogue`.
- Probe: `https://api.data.gov.my/data-catalogue?id=warisan`
- Result: `404`, with response `The data catalogue (warisan) requested does not exist.`

### Jabatan Warisan Negara

- Source: `https://heritage.gov.my/ms/`
- The official JWN homepage exposes navigation for `Daftar Warisan`, `Warisan Kebangsaan`, declaration-year pages (`Pengisytiharan 2007`, `2009`, `2012`, `2015`, `2018`), and `Muat Turun`.
- I did not find a public CSV/JSON/API endpoint or downloadable geospatial dataset for the register from the official site. Direct probes to likely detail/download paths returned site error pages rather than structured data.

### National geoportal / MyGeoportal

- Source: `https://www.mygeoportal.gov.my/`
- Probe: `https://www.mygeoportal.gov.my/search?search=warisan`
- Result: site search page reported no results for the query. I found no public heritage/warisan layer with stable feature ids and coordinates.

## Decision

Keep `national_register` disabled for Malaysia. A1d should not scrape HTML pages, PDFs, gazette notices, or image-backed portal content to synthesize a register. That would violate the project's untrusted-data and determinism rules and would create brittle ids without an upstream stable-id contract.

## Follow-Up Trigger

Revisit only if an official source appears with all of:

- bulk CSV, JSON, GeoJSON, WFS, ArcGIS FeatureServer, or documented API access;
- stable per-place identifiers;
- name/title fields;
- usable coordinates or geometry;
- clear licensing/attribution terms.

If that appears, implement it as a separate work package with a new extractor plan and fixture-first tests.
