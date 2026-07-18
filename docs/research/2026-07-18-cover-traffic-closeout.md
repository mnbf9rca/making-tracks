# Cover traffic (WP-RM-CT) — parked, with the work preserved

**Status: PARKED 2026-07-18.** Not a rejection of the goal. Rob judged the cost too high against the rest
of the queue.

This is the closeout. It records what was learned so the next person to pick this up starts from the
findings rather than re-deriving them — including the wrong turns, which are recorded on purpose. Evidence
and citations: [`2026-07-18-cover-traffic-evidence.md`](2026-07-18-cover-traffic-evidence.md).

---

## 1. How it stays parked

P15 requires cover traffic on fetches **finer than the minimum online granularity**, and that granularity is
a parameter reserved to Rob (`docs/PRINCIPLES.md:15`). Parking sets it at **country** — the granularity we
ship today.

At country, nothing changes and nothing is given up:

- **No amendment.** P15 stands as written. Country-scale packs are what spec §9 already sanctioned before
  the 2026-07-17 amendment, so no ratified holding is relaxed.
- **`privacy.md:43` stays true.** It is future-tense — *"We're still working out how, and we don't have it
  yet"* — which is an accurate description of deferred work. But see §2: the mechanism it promises is not
  the one that survived, so resuming this work will need a copy change even though parking does not.
- **`docs/threat-model.md:83-89` needs a correction pass regardless.** It calls the P15 amendment *"still
  under review"* when it is ratified and inline at `docs/PRINCIPLES.md:15`; it describes the mitigation as
  scattered decoys (*"quietly fetches a few extra areas"*), which is the family that failed; and *"committed
  but not built yet"* is no longer the status once the work is parked.

### What parking does not do — WP-RM-B stays gated

`docs/superpowers/plans/2026-07-18-wp-rm-region-manager.md:452` marks WP-RM-B *"NOT user-shippable before
WP-RM-CT"*. **That gate stays.** It is tempting to re-express it against the dial and call WP-RM-B
unblocked, and that would be wrong.

A zone is sub-country by construction (`contracts/regions/uk.json:18-22` declares
`zone_levels {2: country, 4: region, 6: county}`), and the 2026-07-17 amendment exists precisely to make
sub-country downloads conditional on cover traffic — `#131:172-178` names the harm as *"a **sequence** of
metro-granular GETs from one IP over time"* and concludes *"sub-region download is materially less private
than a country pack."* Setting the dial at zone would permit, uncovered, exactly the class of fetch the
amendment was written to condition. A parameter value that makes a ratified amendment a no-op is not an
application of it.

**So: setting the dial finer than country is a substantive relaxation and needs an argued amendment, not a
parameter setting.** If unblocking WP-RM-B is wanted, that is a separate decision for Rob with the privacy
cost stated on its face — not a side effect of parking this work package.

If sub-country selection is ever shipped, the obligation fires again and this document is where to resume.

---

## 2. The direction that survived

**Cover traffic is buildable. The scattered-decoy family is the part that fails.**

The working construction is a **contiguous cohort**: fetch a published area larger than the one asked for,
so the request does not say which part was wanted. The cohort is a function of the **query**, not the user:

- Nothing to intersect. The same ask always returns the same set, so repeated observation adds nothing.
- No user-specific entropy, so no cohort fingerprint.
- No demand model needed. The blocks are published constants.
- The bytes are usable. The user gets a real, larger area.

**Rob's constraint (2026-07-18):** it must not default to the parent zone — *"it's silly to pull a 1 GB
country when the user asked for a 200 MB city."* So the unit is a **published partition block**: fixed
mid-tier contiguous groupings in the catalog, with the fetch being the smallest published block containing
the ask, and an explicit **cover-overhead budget** (~2× the ask) as the tunable parameter.

The user-facing form reads *"Download South Wales instead (+180 MB) — this hides which part you're
interested in."*

**This is not the mechanism `privacy.md` promises, and that must not be glossed over.** Line 43 (repo root)
commits to *"quietly fetching a few others at the same time"* — a scattered-decoy promise, which is the
family that fails (§6). A contiguous enclosing area is a different bargain with the user: they receive and
store bytes they did not ask for, rather than having extra requests made alongside theirs. **Shipping the
contiguous design therefore requires a `privacy.md` copy change.** Parking does not, because line 43 is
future-tense and describes deferred work honestly — but resuming does.

### What it does and does not deliver

It reduces the **resolution** of the disclosure. It does **not** deliver uniform k-anonymity, and the doc
that ships it must not say it does.

The reason is that contiguity and demand-balance pull against each other. Adjacent zones differ enormously
in demand, so a contiguous block is demand-skewed by construction: an observer seeing a fetch of a block
containing London will guess London, whatever the block's cardinality. **Effective k is the entropy of
demand within the block, not the number of zones in it.** Overhead is asymmetric for the same reason — in a
mixed block, the cheapest member pays the highest multiple.

Two residuals to carry forward: an ask spanning two blocks needs an explicit rule (go up a level), because a
block *pair* is more identifying than either block; and a user genuinely moving across blocks still reveals
the sequence at block resolution.

---

## 3. Measured numbers

All figures below are **externally measured** on 2026-07-18 — none of them existed in the repo, and none
can be re-derived by reading it.

**Method, so they can be re-run.** `pmtiles extract --dry-run` against the archive pinned at
`contracts/regions/uk.json:25`, with `--maxzoom=14 --overfetch=0.05` to match
`docs/superpowers/plans/2026-07-14-wp-a0-contracts.md:1655`. Zone figures use bbox approximations of the
admin polygons; per-cell figures use bboxes aligned to exact z10 cell boundaries, so each covers the full
341 tiles of z10–14. Cell counts are exact; sizes are the tool's 2-significant-figure report. Method
validated by extracting the UK bbox and reproducing the published `1,463,177,229 B`
(`contracts/basemap-budget.json:10`) exactly.

**Zone costs (z10–14):** Greater London 53 MB · Kent 40 MB · Greater Manchester 34 MB · Cornwall 27 MB ·
Highland 78 MB · Selangor 26 MB. **A UK county or metro zone costs 25–80 MB.** Dense-urban and sparse-rural
converge because rural zones are geographically larger.

**Per-cell basemap cost — do not use the mean.** Spread is ~95×: central London 18 MB, Birmingham 11 MB,
Kuala Lumpur 8.4 MB, Snowdonia 2.8 MB, Highlands rural 602 kB, Borneo interior 191 kB.

**Cells per country:** UK 1,310 non-empty (1,736 bbox); Malaysia 813 (1,083). A quarter of the UK bbox is
ocean.

**Also mandatory per pack:** shared z7–9 object (UK 19 MB, Malaysia 4.5 MB); app-bundled z0–6 world tier
(44,720,722 B, measured on a built artifact — no `.pmtiles` is committed to the repo). Place tiles are ~2% of basemap — the "adds negligibly" claim holds.

**Block sizing against Rob's ~2× budget:** parent zones run 4.3–8.4× (Kent→South East 6.9×,
Gtr Manchester→North West 4.3×, Selangor→Malaysia 8.4×), which is why parent-default was rejected. A
**2-county block lands ≈1.75× and a 3-county block ≈2.6×** — mid-tier blocks hit the band.

---

## 4. Two open questions that outlived the work package

**a. The UK level map may be wrong, and it is a privacy decision.** The plan declares
`zone_levels {2: country, 4: region, 6: county}`. In standard OSM tagging `admin_level=4` is
England/Scotland/Wales; the English *regions* are level 5. If that holds, the declared parent of Kent is
**England at 1.1 GB — a 27× jump**, not the ~7× the naming implies. Affordable coarsening exists at 4–7× and
does not exist at 27×. Boundaries are not extracted yet, so nothing in-tree pins the semantics. Verify
against real OSM before ratifying; it may just need `5: region`.

**b. The recurring update channel has no measured cost and cannot get one yet.** There is no publish
cadence anywhere — no document, config field, cron, or CI schedule. `publish_version` is hand-typed at the
shell. One publish has ever been attempted and it did not complete, so there are no two versions to diff.
The basemap is whole-file today, so one changed byte re-downloads the whole pack. WP-RM calls this recurring
path the biggest leak, and it is entirely unquantified. **The experiment that would settle it:** publish one
region twice from two upstream snapshots a month apart and count manifest entries whose sha changed.

---

## 5. Sequencing, if this is resumed

**The critical path is not the decoy numbers. It is the per-cell basemap cut.** k× a monolithic 1.46 GB
basemap with no resume is unshippable, and token decoys that dodge that cost are separable by request count
and byte length — which #131 already names as theatre.

Order: per-cell content-addressed objects (WP-RM-P / WP-RM-G) → block design → any residual shaping.

**Two pieces of publish-layout work are unowned:**
- **Block design** — the partition itself, and it must be balanced on demand (computable from the public
  population data we already ingest), not on area.
- **The wire-vs-store zone-name gap** — WP-RM §6b's content-addressing is *store*-side. The publish layout
  stays `{region}/{pv}/…`, so the zone name remains in the request path. Removing it is an additional change
  no work package owns, and the privacy argument for per-cell objects depends on it.

---

## 6. What was tried and was wrong

The first draft argued cover traffic was **impossible** and asked to retire it from P15. Four reviewers
rejected it, and they were right. The draft was never pushed — it exists only in the review record on this
PR, so what follows is the whole of it that survives. Check a new idea against this list before pursuing it.

- **The impossibility proof was a false dichotomy.** It argued a cohort is either fresh-random (intersected
  away) or sticky (a ~58-bit device fingerprint), with no third option. The 58-bit figure assumes each
  device samples its own cohort at random. A cohort that is a function of the **query** — a published
  partition — carries no user entropy at all. The lever is cardinality and derivation, not stability.
- **The argument was circular.** It rested on the update-diff and launch-poll channels leaking, while the
  same document proposed to fix both, and never re-ran the analysis against the fixed world.
- **The cost test priced the exempt object.** It computed k× against a 1.46 GB *country* pack. The
  requirement applies to *sub-country* downloads, and coarse chunks are explicitly exempt as their own
  anonymity set. The deciding numbers are in §3 above.
- **The prior art was from a different adversary model.** Website-fingerprinting results measure a classifier
  guessing at encrypted traffic shape. Cloudflare terminates TLS and reads the path. Under a well-formed
  cohort our bound is information-theoretic 1/k, not a classifier accuracy. See the evidence doc §1.
- **Governance errors.** P15 was misfiled as user-elective (its text is unconditional; only the parameters
  are open), and `privacy.md` was asserted to be senior to `PRINCIPLES.md` without support, which reached a
  preferred answer. The proposed amendment text — "reveals as little as the architecture permits" — was a
  tautology nothing could fail.
- **A leak was overstated as new.** The launch `current.json` poll was reported as a live per-installed-pack
  roll-call. It is one GET for one selected region today; the per-pack multiplication arrives with
  WP-RM-B3. It is also documented in three places already. Only "unowned" survived — see §7.

---

## 7. Spun out separately

**The launch update-poll roll-call.** Every launch fetches `{region}/current.json`, which names the region,
from the user's real IP. Today that is one request for the selected region. When multi-pack rendering lands
(WP-RM-B3) it multiplies to one per installed pack — a recurring inventory of every area the user holds.

Documented at `docs/architecture/offline.md:32`, `#131:176`, and `WP-B10:101,199` (where the same gap was
caught in review), but **no work package owns the mitigation**, and "check on launch, never on a schedule"
does not address it because launch is the trigger.

Cheap fixes exist and do not depend on any of the above: coalesce the polls into one request that does not
name zones, or move the update check to a shared content-addressed catalog object. Filed as its own issue
against the first-party-vantage attacker in `docs/threat-model.md` §2.
