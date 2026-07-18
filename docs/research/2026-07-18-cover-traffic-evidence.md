# Cover traffic — the evidence base

Research note supporting WP-RM-CT. Collected 2026-07-18.

This exists because an earlier draft of the CT design used these results without citation, and used them to
support a conclusion they do not support. Both problems are fixed here. Read §1 first: it says which of
these results transfer to our problem and which do not.

---

## 1. The adversary-model caveat — read before using anything below

Most published work on dummy traffic comes from **website fingerprinting** (WF). That literature studies an
observer who **cannot read the request**: a passive watcher of encrypted Tor traffic, trying to guess which
of ~100,000 sites was loaded from packet timing, burst structure, and volume. Defenses there work by
degrading statistical *features*, and the reported numbers are *classifier accuracies*.

**Our attacker is not that attacker.** Cloudflare terminates TLS and reads the full request path. There is
no classification and no guessing. The question is not "can you infer the target from traffic shape" but
"given k requests you can each read perfectly, which one did the user want".

The consequences:

- **WF defense overheads and accuracies do not transfer in either direction.** They are not more damning for
  us and not less. They measure a quantity that does not exist in our setting.
- **Under a well-formed cohort, our bound is information-theoretic: 1/k.** Not a classifier accuracy that
  improves as attacks improve. This is a genuinely different and stronger position than WF defenses occupy —
  provided the cohort is well-formed, which is where all the real difficulty sits (§3).
- **The relevant literature for us is the k-anonymity / private-retrieval family** (§3), not the padding
  family (§2). The failure mode that bites us is *correlation across channels*, not feature leakage.

§2 is included because it is genuinely informative about one thing: what it costs to defend a channel by
adding noise to it, and how reliably that class of defense has been broken. Do not use its numbers as
predictions about our system.

---

## 2. The padding / dummy-traffic literature (informative, does not transfer)

### 2.1 Measured on the live Tor network

Gong et al., *WFDefProxy*, implemented defenses as pluggable transports and evaluated them on the live Tor
network rather than on simulated traces — <https://arxiv.org/abs/2111.12629>. Open-world results:

| Defense | Data overhead | Time overhead | Attack true-positive rate |
|---|---|---|---|
| Undefended | 0% | 0% | 97.71% |
| FRONT (randomised dummy padding) | 75% | 0% | 42.79% |
| Random Walkie-Talkie (half-duplex) | 88% | 23% | 83.41% |
| Tamaraw (constant-rate) | 179% | 21% | 6.43% |

The shape of that table is the useful part. Randomised dummy injection — the family "one real plus k−1
decoys" belongs to — bought a partial reduction for a large bandwidth surcharge. The only defense that
substantially worked was constant-rate shaping, which is not a decoy scheme at all: the client sends a fixed
pattern regardless of what it wants.

### 2.2 Defenses broken by later attacks

Sirinam et al., *Deep Fingerprinting*, CCS 2018 — <https://arxiv.org/abs/1801.02265>
([PDF](https://mjuarezm.github.io/assets/pdf/ccs18.pdf)). 98.3% accuracy undefended; **90.7% against
WTF-PAD**, which carried a measured 64% bandwidth overhead.

Against Walkie-Talkie (31% bandwidth, 34% latency), top-1 accuracy fell to 49.7% but **top-2 was 98.44%**.
This is the single most relevant published number for small k: molding a real request with one decoy did not
hide it, it cost the attacker one guess.

Gong & Wang, *FRONT/GLUE*, USENIX Security 2020 —
<https://www.usenix.org/conference/usenixsecurity20/presentation/gong>. The authors report ~33% overhead in
simulation and are explicit that deep-learning attacks still exceed 59% accuracy against FRONT.

Cherubin, *Bayes-error security bounds*, PETS 2017 — <https://arxiv.org/abs/1702.07707>. Formalises why
"we beat attack X" claims are unreliable: a defense needs a bound on the best possible classifier, not the
current one. Defenses evaluated against contemporary attacks have repeatedly failed against later ones.

Shen et al., *Subverting WF Defenses with Robust Traffic Representation*, USENIX Security 2023 —
<https://www.usenix.org/system/files/usenixsecurity23-shen-meng.pdf>.

### 2.3 What Tor actually deployed

Tor built a circuit-padding framework generalising WTF-PAD, then **did not deploy a website-fingerprinting
defense with it**. The two live padding machines do a narrower job: making client-side onion-service circuit
setup look like a normal circuit. Spec:
<https://spec.torproject.org/padding-spec/circuit-level-padding.html>. Research machines:
<https://github.com/pylls/padding-machines-for-tor>.

Relevant as a cost/benefit signal, not as a result about our channel.

---

## 3. The k-anonymity / retrieval family (this is our comparison class)

### 3.1 Google Safe Browsing — the documented failure, and what actually failed

Gerbet, Kumar & Lauradoux, *Privacy Analysis of Google and Yandex Safe Browsing* —
<https://www.inrialpes.fr/planete/people/amkumar/papers/gsb-privacy.pdf>. Trail of Bits summary:
<https://blog.trailofbits.com/2019/10/30/how-safe-browsing-fails-to-protect-user-privacy/>.

Each 32-bit hash prefix maps to roughly 14,757 URLs — a large nominal anonymity set. The break **did not
attack the anonymity set**. It exploited the client submitting *multiple correlated prefixes in one
request* (URL decompositions), where "the probability that two given prefixes are included in the same
request as dummies is negligible."

**This is the result that matters most for us, and it is an indictment of a deployment rather than of the
primitive.** Our analogue is correlation across channels: the zone a user really downloaded is also the zone
they poll for updates, fetch deltas for, and stream tiles inside. Any cover scheme must hold across all of
those channels, not just the download.

### 3.2 HIBP / Pwned Passwords — the same primitive, not broken

Cloudflare: <https://blog.cloudflare.com/validating-leaked-passwords-with-k-anonymity/>. Mozilla:
<https://blog.mozilla.org/security/2018/06/25/scanning-breached-accounts-k-anonymity/>. API:
<https://haveibeenpwned.com/api/v3>.

A 5-character SHA-1 prefix range query returns ~800 hashes. It works, and the reasons it works are exactly
the conditions Safe Browsing violates: a one-shot query, for an unchanging secret, with no correlated
follow-up traffic, and a padded response.

**The primitive is sound. The deployment conditions decide.** Any cover-traffic design for us must be
argued against these conditions rather than against WF overheads.

### 3.3 Dummy-based location privacy — the standard breaks

*A Survey of Dummy-Based Location-Privacy Protection Schemes*, Sensors 2022 —
<https://www.mdpi.com/1424-8220/22/16/6141>.

Catalogues the recurring failures of scattered dummy locations: **location-distribution attacks** using
background knowledge of query probability, **temporal-constraint attacks** eliminating implausible dummies,
and cloaking regions collapsing when dummies are not physically dispersed.

Directly relevant: it is the literature on *scattered* cohorts, and it is the reason a *contiguous* cohort
(fetch a larger enclosing area) is a materially different proposition — it has no decoy distribution to
model and no plausibility to fake.

### 3.4 Intersection and statistical disclosure

Danezis, *Statistical Disclosure Attacks*, IH 2004 —
<https://link.springer.com/chapter/10.1007/978-3-540-30114-1_21>. Berthold & Langos, *Dummy Traffic Against
Long Term Intersection Attacks* — <https://dl.acm.org/doi/10.5555/1765299.1765308>.

The mechanic: if the target is present in every observation and the decoys vary, intersecting candidate sets
across observations recovers the target. This is why a cohort that is a function of the **user** degrades
under repetition, and why a cohort that is a function of the **query** does not — the latter returns the
identical set every time and offers nothing to intersect.

---

## 4. What deployed systems actually do

| System | Mechanism | Note |
|---|---|---|
| iCloud Private Relay | Two hops; Apple-run ingress sees IP not destination, third-party egress sees destination not IP. <https://support.apple.com/en-us/102602>, <https://blog.cloudflare.com/icloud-private-relay/> | **Scope matters: Safari, DNS and insecure HTTP only. Our app's HTTPS requests are NOT relayed** — <https://developer.apple.com/icloud/prepare-your-network-for-icloud-private-relay/> |
| Apple Live Caller ID / Enhanced Visual Search | PIR for query content, **plus** OHTTP to hide IP, **plus** Privacy Pass for anonymous auth. <https://machinelearning.apple.com/research/homomorphic-encryption>, <https://developer.apple.com/documentation/identitylookup/understanding-how-live-caller-id-lookup-preserves-privacy> | The layering is the lesson: even with PIR, OHTTP is still needed, because PIR hides the query and not the querier. No decoy traffic anywhere in it. |
| DNS padding, RFC 8467 | Block-length padding to fixed sizes — <https://www.rfc-editor.org/rfc/rfc8467.html> | A *size*-correlation defense only; it never claimed to hide which name was asked for. The RFC states fixed-length padding is "almost as useless as no padding" and random-length leaks more than block-length. **Use block/bucket padding.** |
| Tor circuit padding | Two narrow machines; no WF defense shipped (§2.3) | — |

The through-line: **serious deployments solve this with architecture — split trust, or crypto — not with
noise.** No major deployment uses decoy traffic as a primary defense.

---

## 5. Oblivious HTTP and Privacy Pass — availability

OHTTP, RFC 9458 — <https://www.rfc-editor.org/rfc/rfc9458.html>. A relay sits between client and gateway; the
origin never sees the client IP and the relay never sees request content.

- **Cloudflare Privacy Gateway is closed beta, Enterprise-only**, "available to select privacy-oriented
  companies and partners" — <https://developers.cloudflare.com/privacy-gateway/>. Not self-serve. Open
  implementations: [relay](https://github.com/cloudflare/privacy-gateway-relay),
  [gateway](https://github.com/cloudflare/privacy-gateway-server-go).
- **Fastly's relay is also beta / select partners** —
  <https://www.fastly.com/blog/enabling-privacy-on-the-internet-with-oblivious-http>. It is the relay behind
  Mozilla telemetry and Meta's Private Processing.

**Design constraint that is easy to get wrong: relay and gateway must not collude.** If Cloudflare runs both
our relay and our CDN, we have gained nothing against the attacker we named.

Privacy Pass: RFC [9576](https://www.rfc-editor.org/rfc/rfc9576.html),
[9577](https://datatracker.ietf.org/doc/rfc9577/), [9578](https://datatracker.ietf.org/doc/rfc9578/).

---

## 6. PIR — why not, for bundle bytes

Single-server PIR requires server work **linear in the whole database per query**, by a lower bound rather
than an engineering gap: any record the server does not touch leaks information.
<https://www.cs.umd.edu/~gasarch/TOPICS/pir/lowergasarch.pdf>.

State of the art: **SimplePIR** 10 GB/s/core, **DoublePIR** 7.4 GB/s/core — Henzinger et al., USENIX
Security 2023, <https://pdos.csail.mit.edu/papers/simplepir:usenixsec23.pdf>,
[code](https://github.com/ahenzinger/simplepir). SimplePIR needs a **121 MB client hint for a 1 GB
database** (242 KB/query); DoublePIR reduces the hint to 16 MB at 345 KB/query.
[YPIR](https://www.usenix.org/system/files/usenixsecurity24-menon.pdf), USENIX Security 2024, improves
preprocessing.

Applied to a multi-gigabyte tile corpus this is off by two to three orders of magnitude, and the response
still has to carry the object. Apple's own PIR deployments are keyword-value lookups of kilobytes, and their
reference server is explicitly labelled not for production —
<https://github.com/apple/pir-service-example>.

**Plausible for a small catalog lookup. Not for bundle bytes.**

---

## 7. Cloudflare logging — what is actually configurable

- **HTTP request logs are not retained by default**; Logpull retention is an explicit opt-in flag —
  <https://developers.cloudflare.com/logs/logpull/enabling-log-retention/>,
  [retention API](https://developers.cloudflare.com/api/resources/logs/subresources/control/subresources/retention/).
- Log Explorer ingestion is disabled per-dataset at account and zone level —
  <https://developers.cloudflare.com/log-explorer/faq/>.
- Cloudflare's stated handling: standard customers' access logs discarded within 4 hours; Enterprise 3 days
  by default where enabled; error logs 1 week — <https://blog.cloudflare.com/what-cloudflare-logs/>.

**The honest limit.** This blinds *us*, not Cloudflare. Cloudflare processes end-user IPs as part of
delivering the service regardless of our settings — <https://www.cloudflare.com/privacypolicy/>. Only a
non-colluding relay (§5) removes Cloudflare from the channel. Cover traffic does not remove it either; it
makes Cloudflare's copy noisier in a way Cloudflare is well placed to filter.

---

## 8. Mobile cost

**Radio energy is dominated by tail energy, not bytes.** Balasubramanian et al., *TailEnder*, IMC 2009 —
<https://people.cs.umass.edu/~arun/papers/TailEnder.pdf>. 100 KB transfers cost 5–15 J depending on
inter-transfer interval; radios hold a high-power state for seconds after the last byte.

Consequence for cover traffic: **many small fetches spread over time is close to the worst possible radio
pattern**, because the tail is paid repeatedly. One large contiguous transfer is far cheaper per byte. This
is an independent argument for contiguous coarsening over scattered decoys.

**Apple's guidance** — [Energy Efficiency Guide: Defer
Networking](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/DeferNetworking.html):
background `URLSession` with `isDiscretionary = true` so the system schedules at power-optimal times;
`allowsCellularAccess = false` for large downloads; `sessionSendsLaunchEvents = true` to be woken on
completion.

Note the privacy interaction: **discretionary scheduling is itself a mild privacy gain**, because it
decouples transfer time from the moment of user intent. Decoys that fire in a burst around a
UX-prioritised real request have the opposite property.

---

## 9. What this evidence supports, and what it does not

**Supports:**
- Scattered, randomised decoy cohorts are a poor buy: expensive, repeatedly broken in the padding
  literature, and subject to distribution and plausibility attacks in the location-privacy literature.
- Correlation across channels is the failure mode to design against — it is what broke the closest deployed
  analogue.
- Contiguous coarsening avoids the decoy-distribution problem entirely, is cheaper on radio and bandwidth,
  and delivers bytes the user can use.
- Not-logging is worth doing and must be described with its limit.
- OHTTP is the only standardised, deployable mechanism that addresses "Cloudflare sees the IP", and it is
  not yet available to us.

**Does not support:**
- Any claim that cover traffic in general is impossible. A cohort that is a function of the **query** rather
  than the **user** — a published partition, or simply the enclosing parent zone — is not touched by the
  intersection results in §3.4, has no distribution to model, and has no user-specific entropy to
  fingerprint.
- Any transfer of WF overhead or accuracy figures to our channel (§1).
- Any claim about our costs. The deciding numbers are our own sub-country pack and per-publish delta sizes,
  which are measured separately, not inferred from this literature.
