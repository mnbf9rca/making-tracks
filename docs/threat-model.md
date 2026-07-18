# Threat Model — Making Tracks

**What this is for.** Making Tracks is a tourist discovery-map app: open public data, map tiles served
from a CDN, all user data on the device, no accounts required, no third-party SDKs. This document says —
bluntly — **what we defend against and what we deliberately do not**, so security and privacy engineering
stays proportionate. Its most important section is [§4 Out of scope](#4-out-of-scope-the-part-that-does-the-work):
most wasted security effort on an app like this comes from defending against attackers who have already
won. If a proposed defence isn't answering a threat named here, it's overreach — see the calibration tests
(§5) and the review rule (§6).

Register: this is an engineering calibration doc, not a user-facing policy. The user-facing commitments are
in [`privacy.md`](../privacy.md); this explains the adversary model those commitments assume.

## 1. Assets, ranked

1. **The user's location-interest pattern — the crown jewel.** Where a user looks on the map, what they
   download, and what they save or hide. Taken together this reveals where someone is, is going, or cares
   about. `privacy.md` commits that this stays on the device and that we "do not track where users are."
   Everything below is ranked against protecting *this*.
2. **Delivery integrity** — that the bytes a device renders are the bytes we published (no in-transit
   tampering). **Solved by design:** every **tile and basemap object** is content-addressed and SHA-verified
   against the manifest on download (`TileCodec.decode`, the
   [download safety contract](superpowers/plans/2026-07-18-wp-rm-region-manager.md) §8); a tampered object
   fails verification and is dropped. (The `current.json` / `manifest.json` trust root that *carries* those
   hashes is TLS-fetched and schema-validated, not itself content-addressed.) **This is publication
   integrity, NOT content safety** — SHA proves an object equals what we published, it says nothing about
   whether that content is *safe to render*. Safety of the content itself is a separate, in-scope adversary
   (§2, hostile upstream content) — don't conflate the two.
3. **Service availability and cost** — the CDN bill and staying up. Open buckets invite scraping and
   cost-inflation (#142, anti-abuse auth, deferred). A real but ordinary operational concern, not a
   user-privacy one.

## 2. In-scope adversaries (defend against these)

- **The passive network observer** (shared Wi-Fi, ISP, coffee-shop router). **TLS suffices** — standard
  HTTPS through the platform trust store already denies them request contents. We do **not** add more here
  (see §5, pinning).
- **Ourselves and the CDN vantage point — the interesting one.** We host on Cloudflare, which sees a
  device's IP and request timing. **Current posture: documented-and-accepted.** `privacy.md` is explicit
  that this is *not* anonymous, that we don't log it (Cloudflare may), and that a device downloading a
  bundle does not reveal a visit. This is the one first-party observer we take seriously *by design* rather
  than trust — but the engineered mitigation is **committed, not yet built**: **cover traffic** (decoy
  fetches so the pattern of what a device downloads doesn't reveal where the user cares about) is the
  intended control. `privacy.md` says of it plainly: *"We're still working out how, and we don't have it
  yet,"* framed as a user-choosable future ("you will be able to choose to… hide which one you actually
  want"). It is grounded in the region-model design (#131, which raises the movement-trace problem) and
  specified in the **proposed** PRINCIPLES cover-traffic amendment (P15, still Rob-gated); the decoy budget
  numbers are Rob's to set. Target behaviour, owned by the fetch-layer WP — not a shipped defense today.
- **Hostile / poisoned upstream content — the app's most likely attack, and already defended.** Our data
  comes from crowd-editable open sources (OSM, Wikipedia). A vandalized or malformed entry — a hostile
  place name, an attacker-chosen image URL, an oversized blurb — is ingested, published, and **SHA-verifies
  cleanly because it *is* what we published** (asset 2 proves delivery, not safety). The adversary is an
  ordinary public-database vandal (anyone with a browser — the *lowest*-sophistication attacker, squarely
  in register). This is **already solved by the untrusted-data posture** (PRINCIPLES §10; spec §5.5;
  `privacy.md`: *"a bad entry in a public database can't harm your phone"*): defensive decoding with size
  and length caps, `SAFE_TEXT` stripping, an https-only host allowlist for image URLs, source strings
  rendered as **inert plain text** (never HTML/attributed), and never interpolated unescaped into SQL,
  shell, or LLM prompts. **This is the citable home for every untrusted-data / content-validation review
  finding** (§6) — it does not need to name a network adversary.
- **Third-party SDK data brokers — designed out entirely.** **INVARIANT: the app ships zero third-party
  analytics, advertising, or tracking SDKs** (`privacy.md` principle 3). Dependencies are functional only
  (GRDB for the local database; MapLibre for rendering). This is the single most effective privacy control
  a consumer app has, and it is a standing invariant: **adding any data-collecting third-party SDK is a
  privacy regression that requires a `privacy.md` amendment, not a code review.**

## 3. Trust boundaries (one sketch, no ceremony)

Device (iOS sandbox: the user's data at rest, all reads/writes) → HTTPS → CDN (`tiles.making-tracks.app`,
sees IP + timing) → our published static objects (a TLS-fetched, schema-validated `manifest` whose listed
tile/basemap objects are SHA-verified on the device). User data never crosses the first arrow outward
except the explicit, user-initiated flows `privacy.md` already enumerates (share a list, report a place,
opt-in stats). There is no server-side store of user *activity* to attack, because there isn't one (the
optional accounts system, when built, stores only sharing identity + shared lists — never visits or map
history, per `privacy.md`).

## 4. Out of scope (the part that does the work)

These are **deliberate, engineered exclusions** — good engineering, not negligence. Each is out of scope
because the defence would sit *above a trust boundary the attacker has already crossed*, or because it asks
app code to solve a problem app code cannot. A review finding that assumes one of these is **overreach**
(§6).

- **Compromised, jailbroken, or rooted device / malicious OS.** Out of scope. Once the platform sandbox is
  broken, any app-layer control can be bypassed — defending here is security theatre. *"The sandboxing on
  an iPhone is sufficient isolation"*: we rely on the OS security model and do not duplicate it. (This is
  why on-device file-protection class is a **non-issue** — see §5.)
- **Forensic physical device seizure / extraction.** Out of scope. We store no account credentials and no
  server-linkable identity at rest; on-device data gets standard OS file protection, and we make **no
  claim** to resist a determined forensic adversary with the unlocked device in hand.
- **Nation-state / targeted advanced adversary.** Out of scope, emphatically. A consumer map app cannot and
  does not claim to withstand an adversary with unlimited resources. *Defending a tourist's map browsing
  against a nation-state is a category error* — a user with that threat model should follow platform-level
  guidance, not rely on us. This is the anti-pattern this whole document exists to stop.
- **Our own infrastructure turning hostile.** Out of scope **as an app-code concern** — this is **ops
  hygiene**, not something the app defends against. Securing the CDN, the pipeline, and the deploy path is
  operational discipline (§7), not a control we build into the client.
- **Enterprise-MITM / custom-root-CA interception.** Out of scope. A device that has been made to trust an
  attacker's root CA is already administratively controlled; TLS cannot be expected to defend a device
  configured against its own user.

## 5. Calibration tests (apply these mechanically)

Before proposing or accepting a security/privacy control, screen it:

1. **Trust-boundary test.** Does it only help *after* an attacker has crossed a boundary they'd have to
   cross to reach it (the sandbox, the OS, the user's unlocked device)? If yes → moot, reject.
2. **Register test.** Is the adversary in our realistic register (§2: network snoop, us/the CDN,
   **hostile upstream content**, opportunistic abuser, would-be SDK) or an out-of-register one (§4:
   nation-state, forensic seizure, broken OS)? Defend the former; document-and-accept the latter.
3. **Cost/fragility test.** Does the control add more operational failure risk than the attack risk it
   removes? If yes → reject (this is why cert pinning is out — below).

**Worked examples (2026-07-18 review decisions, retro-classified):**

- **TLS certificate pinning — REJECTED, correctly.** Fails the cost/fragility test: Google, Apple, OWASP,
  and Cloudflare all discourage pinning for apps of this profile (certs rotate, pinning causes outages, and
  it's trivially bypassed on a compromised device — the only device where it'd matter, which is already out
  of scope §4). The platform's Certificate Transparency + short-lived certs cover the residual risk.
- **Post-redirect origin re-check — KEPT.** Cheap and proportionate: background downloads can follow
  redirects without the delegate, so re-validating that a completed download's final origin is still
  `tiles.making-tracks.app` (#197's `validateDownloadedFile`) closes a real in-register gap at near-zero
  cost. In scope, small, kept.
- **On-device `.none` file-protection class — NON-ISSUE.** The only adversary it would help against
  (someone extracting files from the device) is out of scope §4, and the crown-jewel data is not
  server-linkable identity. Not worth engineering; not a finding.

## 6. Enforcement

Every security or privacy review finding must **cite a specific in-scope vector from this document**, or
**explicitly propose an amendment to this model**. A finding that cites no vector — or that assumes an
out-of-scope adversary (§4) — is **rejected as overreach**. This rule is mirrored in `AGENTS.md`'s review
gates (the §5.5 security-posture hook).

**Untrusted-data / content-validation findings have a standing home.** A finding about defensive parsing,
size/length caps, `SAFE_TEXT`, plain-text rendering, URL allowlisting, or unescaped interpolation cites the
**hostile-upstream-content vector (§2)** — equivalently the untrusted-data posture (spec §5.5, PRINCIPLES
§10). It does **not** need to name a network-style adversary, and it is never "overreach": this is the
app's most in-register threat and a ratified non-negotiable. The overreach rule targets defenses against
*out-of-scope* adversaries (§4), not the everyday hygiene of handling hostile content we ourselves publish.

The model is not frozen: if a genuine new vector appears, the right move is to argue it into §2/§4 here (Rob
ratifies, like `privacy.md`), not to smuggle it in as a one-off review comment.

## 7. Pipeline and infrastructure

Out of scope for bespoke modelling (Rob ruling): the pipeline and any VPS/CDN follow **industry best
practice** — secrets via `op` (never on disk), least privilege, timely patching. This is ops hygiene, held
to standard operational discipline, not a threat surface this app-facing model enumerates.
