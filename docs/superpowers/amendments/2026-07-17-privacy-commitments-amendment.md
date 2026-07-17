# Amendment — Privacy commitments that constrain the roadmap (2026-07-17)

> **STATUS: PROPOSED — REQUIRES ROB'S APPROVAL TO MERGE.**
> This is an argued amendment to `docs/PRINCIPLES.md` (P14, P15) and spec §9, per the header rule
> in PRINCIPLES.md: *"the principle needs an explicit, argued amendment to this file — never a
> silent exception."* The design lead (fable) will **not** merge this; only Rob merges it, or
> explicitly instructs otherwise. Until then the current principles stand unchanged.

## Why this exists

`privacy.md` (repo root, PR #137) was authored and ratified by Rob as a set of **commitments that
constrain the roadmap** — not a snapshot of v1. Several of those commitments go beyond what the
current PRINCIPLES.md / spec §9 sanction: they describe v2 accounts and sync, and they resolve an
open privacy tension in the download model (the region-model design, #131 §4/§7). A policy document
that binds the roadmap must be backed by the principles it claims to apply. This amendment folds the
ratified commitments back into the non-negotiables so the two cannot drift.

Each item below states: **what changes**, **the argument**, and **what it constrains downstream**.

---

## 1. Accounts arrive in v2 — data-minimized, sharing-only (amends P14)

**What changes.** P14 currently says "no accounts in v1." That stays. The amendment states what an
account **is** when it arrives in v2: it exists *only* to identify you and your recipients for
**private** sharing, and it is data-minimized by construction.

- It stores **only**: the sharing identity, and the lists you chose to share.
- It stores **nothing else**: never your visits, your map, or your history; never a tracking hook.
- It is **never required** to use the app for yourself, and never used to track what you do.

**Argument.** P14 is "unable, not unwilling." An account is the classic place that principle dies —
once you have identities you *can* link behaviour. The guardrail keeps "unable" true even with
accounts: the account schema is structurally incapable of holding a movement trace because the
fields that would carry one (visits, map, history) are never in it. Private sharing genuinely needs
an identity mechanism (spec §9 already notes this as "deferred design"); this amendment pins the
*shape* of that mechanism before it is built, rather than discovering the guardrail after.

**Constrains downstream.** WP for accounts/sharing (v2) inherits a fixed data-minimization schema;
any field beyond {sharing identity, shared lists} is a principle violation requiring its own
amendment. Onboarding must never gate self-use on an account.

## 2. v2 CloudKit sync stays private to the user (amends P14)

**What changes.** When cross-device sync arrives (v2, CloudKit — already deferred in spec §10), its
contents stay private to the user under their own Apple account; **the developer never sees them.**

**Argument.** Sync is the other place "unable, not unwilling" is easy to lose — a sync backend the
developer can read is a server-side copy of user history. Routing sync through the user's own
CloudKit (not our infrastructure) keeps the developer structurally unable to read it. This matches
how P8 ("user history never depends on someone else's database") already treats on-device data.

**Constrains downstream.** The sync WP must use CloudKit private database (user's Apple account),
not a developer-operated store; no user-content telemetry off the sync path.

## 3. The map-fetch channel is held to the unlinkability bar (amends P15; resolves #131 §4)

**What changes.** P15's movement-trace bar currently governs opt-in stats. This amendment states
explicitly that the **map-fetch channel** (tile/bundle GETs to the CDN) is held to the same bar —
and resolves the open §4 tension in the region-model design (#131). Spec §9 today sanctions offline
packs only at **country scale** ("downloading UK locates you to tens of millions"); it does not
sanction **sub-country** downloads, which are sequenced, finer CDN fetches — a movement trace P15
otherwise forbids.

**The resolution (Rob's ruling, folded into #131 §4 + §7):**
- **Bundle-first.** The committed product default is downloading bundles, not per-viewport
  streaming. Streaming is the honest interim/fallback.
- **The privacy win is chunky prefetch + cover-traffic, not "small bundles."** Sub-country downloads
  are sanctioned **provided** finer-grained fetches carry cover-traffic: decoy fetches, drawn
  **geographically spread** and selected **intersection-resistant** (a fixed cohort per session /
  steady background hum, never fresh-random per fetch — else a longitudinal attacker intersects
  candidate sets and recovers the real trace). Offline packs remain the strongest mitigation (zero
  recurring fetches); they are the coarsest point on one continuum with online prefetch.
- **This replaces the withdrawn "k-anonymity floor."** The earlier region-model draft asserted a
  ≥1M-metro k-anonymity floor and cited §9 as licensing it; §9 licenses no such floor. The correct
  answer is a **cover-traffic requirement**, not an anonymity-set size.

**Argument.** A sub-country bundle fetched on demand over the user's real IP reveals "user ∈ this
area at time t"; the sequence is a movement trace at that granularity — exactly what P15 forbids.
Renaming a tile a "bundle" changes nothing. The bar is met only by reducing the *number* of exposure
events (chunky prefetch) and the *precision* of each (spread, intersection-resistant decoys). See
#131 §7 for the quantified tradeoff and the obligations WP-B7 must meet.

**The policy numbers are Rob's.** This amendment sets the *shape* — bundle-first; cover-traffic
required below a coarse threshold; spread + intersection-resistant. It does **not** bake the numbers
(minimum online granularity, decoy count *k*, cohort policy). Those are P15 parameters for Rob to
ratify; #131 §7 recommends a shape, the design WPs implement against the ratified numbers.

**Constrains downstream.** WP-B7 must ship the cover-traffic mechanism with the spread +
intersection-resistance obligations, not a bare "fetch a few others." B10 onboarding must not frame a
bare metro download as "a privacy feature" absent the decoys.

## 4. Aggregate bundle-download counts — user-unlinked, distinct from opt-in stats (amends P15)

**What changes.** The developer may count **how many times each bundle is downloaded** (to see which
areas need work) as **aggregate, user-unlinked totals** — no per-request IP logs, no per-user
linkage. This is distinct from the opt-in behavioural stats P15/§9 already govern (visited /
bookmarked / loved events via an OHTTP relay).

**Argument.** Download counts are inherent to serving — the CDN tallies GETs regardless. The privacy
question is only whether they *link to a person*. Held as aggregate per-bundle totals with no IP
logging, they carry no movement trace and need no opt-in (there is nothing about a user to consent
to). This is weaker telemetry than the behavioural stats, and the P15 bar (unlinkability) is met by
construction. `privacy.md` commits to exactly this: "we count how many times each bundle is
downloaded … we can't tell who downloaded which one."

**Constrains downstream.** New infra requirement (WP-P / infra): aggregate per-bundle download
counts must exist and be **provably user-unlinked** — Cloudflare aggregate analytics, never our own
per-request IP logs.

## 5. Already ratified — restated, not amended

For completeness (these are in the current docs and `privacy.md` restates them; **no change**):
- **Sharing permission tiers** (viewer / contributor-add-not-remove / editor) — spec §9 already
  captures these as v2 requirements.
- **Offline packs eliminate the channel at country scale** — spec §9 already sanctions this; item 3
  extends the *mechanism* downward (sub-country) under cover-traffic, it does not weaken the packs.
- **Opt-in stats via OHTTP relay + small-N suppression** — spec §9 unchanged.

---

## Proposed edits (applied in this PR — merging = ratifying)

This PR applies the following to the ratified files so that Rob merging it **is** the ratification:

- `docs/PRINCIPLES.md` — P14 gains the v2 account-minimization + sync clauses (items 1, 2); P15
  gains the map-fetch-channel + download-counts clauses (items 3, 4).
- `docs/superpowers/specs/2026-07-14-making-tracks-design.md` §9 — the tile-fetch-channel paragraph
  is updated to bundle-first + the cover-traffic continuum; the account-minimization, sync, and
  user-unlinked download-count commitments are added.

If Rob wants the numbers (granularity floor, *k*, cohort policy) pinned before merging, that is a
follow-up he directs; this amendment deliberately leaves them open.
