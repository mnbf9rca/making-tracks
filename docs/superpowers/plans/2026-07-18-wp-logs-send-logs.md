# WP-LOGS — send logs

A user-initiated diagnostic export. The user taps a button in Settings, sees what they are about to send,
and shares a file through the system share sheet. No server, no upload, no telemetry. That boundary is not
in question.

Builds on WP-LOGGING (#204), which gives structured `os.Logger`, sanitizer helpers, and a lint over what may
be logged.

> **Amendment 2026-07-20 — the posture moved. Read §0 first; it supersedes §1's content line and §2's
> hashing mechanism.** The original design hashed identifiers at rest and shipped a decode table, and drew
> a narrow content line. Rob has since ruled both differently. §1 and §2 are kept for the reasoning trail;
> where they conflict with §0, §0 wins.

---

## 0. Amendment — sharing is the consent; the log reconstructs the session

Two rulings, 2026-07-20, that reshape this WP.

**The posture.** Rob:

> "users chosing to share the logs expect that they can be used for diagnostics."

The deliberate, per-export act of sharing IS the consent that matters. So the shared file may carry the
app-and-user flow needed to reconstruct what happened — his MVP bar: the log must "contain the full flow of
the app as it happened, not just error codes" and "can directly be used to understand what a user did in the
app, and how the app behaved." The consent screen's job flips from **promising exclusions** to **honestly
disclosing inclusion**.

This changes what a user's export contains. It does **not** change the app's boundary: still no server, no
upload, no telemetry (the header holds). Data leaves only because the user hand-carries the file — the same
"nothing leaves unless you choose to share it" frame `privacy.md` already states. A companion `privacy.md`
line names this new user-chosen share channel (drafted with this amendment; ratified as a policy change).

**The hashing is deleted.** Rob:

> "i didnt chose the hashing. you did — you said that it was important to protect the logs on the device from
> other applications. I feel that apple's sandboxing is sufficient — this is ALREADY COVERED BY THE THREAT
> MODEL."

The salt, the at-rest hashing, and the decode table (§2) are removed. They defended only the on-device file
against an attacker the threat model already excludes via OS sandboxing (`docs/threat-model.md` §6 — defences
must cite an in-scope vector). The file sink writes plaintext; the log is directly readable, which is the
better decoding the posture ruling requires.

### The content line (supersedes §1)

The log is the session's **event stream within the chosen window** (§5 bounds: 15 min / hour / everything).
The boundary is **events, not inventory** — the session's actions, never a dump of the on-device database.

**In (the flow):**
- Place identity — id and name — for places viewed, tapped, or acted on.
- User action events: love / unlove / hide / unhide / save / add-to-list / remove-from-list, as
  transitions (place id + timestamp), not as a dump of the whole saved/loved/hidden corpus.
- Navigation flow: screens and sheets opened, the tap sequence.
- Viewport extent: bbox / centre / zoom. (Diagnostic for the map and tile pipeline, e.g. #275; it is
  app-state the user drove, not an ambient sensor read.)
- Search events and responses: that a search ran, the result count, and which result (place id) was
  tapped — **without the query text** (see Out).
- Everything from the original §1 system line: app version and build, OS version, device model, installed
  packs and publish versions, download/install states, error codes, timings, and our object URLs — now
  **plaintext**, no hashing.

**Out — exactly three classes, and this is the whole exclusion-lint set:**
- **Device name** (`UIDevice.name`) — identity, often the user's real name, zero diagnostic value over
  device model.
- **Precise device location** (GPS lat/lon). Permission state and the fact that location centred the map
  are in; the viewport is in; the precise fix is out.
- **Raw search query strings.** The search event, result count, and tapped result are in; the wording is
  out. This holds **WP-B9's "queries never leave the device" property (§2, D2) unamended** — Rob ruled the
  strings out precisely so that property stands.

### Consent copy (honest disclosure, not a promise of protection)

> **Send a diagnostic log**
> This file records what you did in the app and how it responded, during the window you choose above — the
> places you opened and saved, the actions you took, the map you browsed, and what the app fetched, showed,
> or failed to show. It is meant to let someone helping you see exactly what happened. Nothing is sent
> automatically; you choose where it goes.
>
> **Included:** your app version and device model; the places and actions in your session; the map areas you
> viewed; what the app fetched, and any errors and timings.
>
> **Not included:** your device's name; your exact location; your search wording.
>
> **This file describes your session. Share it only with someone you trust to help you.**

The footer is load-bearing: the file is now genuinely revealing, so the consent screen's real work is the
informed half of informed consent — "you are choosing to share this; here is what it is."

---

## 1. The ruling this is built to

Rob, 2026-07-18:

> "a user choosing to export and send logs to troubleshoot a problem expects the logs to be useful to the
> developer. So we need to know what's broken. We don't need place identifiers, low level detail. But we do
> need system info (what packs are installed and app version and so on). if the privacy policy needs to be
> updated so be it."

Utility is the requirement. **The benchmark is tonight's real case: the export must name the failing URL,
host and status for the Malaysia sub-region 404.** An export that cannot diagnose that has failed.

### The content line

**In:** app version and build, OS version, device model, installed packs and their publish versions,
download and install states, error codes, timings, and the URLs of our own objects (hashed in the log,
decoded by the bundle's table — see §2).

**Out:** place identifiers, place names, search terms, viewport and location, list contents, saved and loved
state.

Stated consciously, because it is not obvious: **our object URLs encode region and zone names.** That is
pack-install information, which the ruling puts in scope. It is included deliberately, not leaking through a
gap.

### Why this does not contradict the region-hashing elsewhere

Region IDs are hashed in the logs today because a region is user-linking, and the cover-traffic work
(#131, P15) treats it that way. That work defends against Cloudflare observing traffic the user did not
choose to send. This is a user choosing to hand a file to someone in order to get help. Same data,
different consent, different threat. The two positions are consistent.

---

## 2. Hashed at rest, decoded in the bundle

Rob, 2026-07-18:

> "the logs could contain hashes of objects as long as theres a rainbow table or whatever sent in the log
> bundle."

This is the mechanism. Identifiers stay hashed in the log itself; the **export bundle carries a decode
table** generated at export time. The device enumerates the identifiers it legitimately knows — installed
pack and region IDs, object keys it has fetched or staged, catalog snapshot IDs — hashes each with the same
function the sink uses, and writes `hash → plaintext` pairs alongside the log. The developer joins them
offline.

The result: the log at rest stays exactly as private as it is today, and the bundle the user has reviewed
carries the meaning. No annotation loosening, and no pack names in the system-wide unified log.

**One correction to the mechanism as stated.** `.private(mask: .hash)` is `os_log`'s internal,
per-device-salted transform. It is not callable from Swift, so the device cannot reproduce it and **a decode
table cannot decode the `os.Logger` stream**. The mechanism works, but only over a hash we control. So:

- **`os.Logger`** keeps the #204 annotations unchanged. Its masked values remain undecodable, which is fine
  because the export does not read them.
- **A file sink** in our own container hashes identifiers with **our** function, and that is what the decode
  table covers.

The facade therefore takes structured fields and renders twice, instead of call sites pre-interpolating a
string. That is a real refactor of the #204 call sites, and it is what lets one lint police both sinks.

**Salt.** Our hash is salted per install, with the salt stored in the Keychain and never exported. Without
it, a hash over a handful of known region IDs (`MapScreen.swift:33-73` hardcodes six) is reversible by anyone
who obtains the file. The salt is what makes the at-rest file genuinely opaque; the decode table is what
makes the reviewed bundle useful.

**Boundary.** The table decodes **our object namespace only** — pack IDs, region IDs, object keys, snapshot
IDs. Nothing user-generated ever enters it: no place identifiers, no list contents, no search terms. A
future call site that hashes a user-generated value must not gain a decode entry, and the lint should
enforce that the table is built from a fixed enumeration rather than from whatever appears in the log.

**Failure mode, accepted.** A hash of something the device no longer holds — an uninstalled pack, a
garbage-collected object — decodes to nothing. The line still shows its timing, status and error, just
without a name. This is acceptable and is not worth engineering around.

---

## 3. Why a file sink and not `OSLogStore`

**`OSLogStore` cannot see across a process boundary.** On iOS, third-party apps get
`scope: .currentProcessIdentifier` only; `.system` is unavailable. An `OSLogStore` export therefore sees the
current process and nothing else: not the previous launch, not the session before a crash, not the
background relaunch `nsurlsessiond` performs to service download completions
(`ios/App/Sources/MakingTracksApp.swift:150-156`; `sessionSendsLaunchEvents` at
`ios/Sources/MakingTracksTiles/MakingTracksTiles.swift:2061`).

Any useful export must survive process death, so an `OSLogStore` design needs its own persistence layer. At
that point it is a file sink with extra steps.

Second and independent: `.private(mask: .hash)` values read back redacted, so an `OSLogStore` export could
not carry the pack detail §1 requires.

**Not a reason.** The facade-monopoly lint exempts `MakingTracksLog.swift`
(`ios/Tests/MakingTracksTilesTests/LoggingPrivacyTests.swift:113`), so an `OSLogStore` reader placed in the
facade would pass. An earlier draft claimed this as a blocker. It is not one.

---

## 4. What today's logs already give

The gap is smaller than assumed. A today-export of the motivating 404 already yields object class, exact
publish version, HTTP status, host, and a region discriminator: `MakingTracksTiles.swift:2584` logs
`reason=object-404` with a `.public` publish version, and `:209` gives host, kind and status.

Missing for the benchmark: the full object path and the plain region ID. That is the entire delta §1 adds.

---

## 5. Design

**Sink.** File logger alongside `Logger`, both rendered from the same structured call. Application Support,
`isExcludedFromBackup = true`. Buffered, flushed on a timer and on background transition, with a bounded
buffer and an explicit drop policy when it backs up: 57 `.debug` sites sit inside a download loop.

**Rotation.** 5 MB per file, 5 files. Filenames keyed off bundle ID through a pure function, so extensions
added later cannot interleave.

**Retention.** Files purge on a fixed age. Settings carries a "Delete diagnostics" control. The staging
directory and generated archive are deleted when the share sheet dismisses and on every failure path.

**Export.** Snapshot under the serial queue, copy to staging, zip via `NSFileCoordinator(.forUploading)`.
Tolerate only "source vanished" copy errors and rethrow the rest. Fall back to a concatenated `.txt` that
returns the URL it actually wrote. Off-main and `Sendable`-clean under Swift 6.

**Bounds.** Last 15 minutes, last hour, or everything. Default to the shortest window covering the current
session.

**Metadata header.** App version, build, commit, OS version, device model, installed packs with publish
versions. Not `UIDevice.name`, which is usually a person's name.

**UI.** A Diagnostics section in `SettingsView`, after Storage (`ios/App/Sources/Map/MapScreen.swift:2633`)
and before Onboarding, identifiers `settings.diagnostics.*`. Ships in release builds; a debug-only
diagnostic is useless when a user needs it.

The screen carries a "what's included / what's not" inventory and a preview of the artifact itself, not a
tail of one file.

---

## 6. What must change before this ships

**a. The lint does not cover the file sink. This is a blocker.** The denylist fires only on lines containing
`MakingTracksLog.` (`LoggingPrivacyTests.swift:38`), so a new sink's call sites match nothing and are
ungoverned. Extend the lint to the new sink with the §1 content line as its rule: reject place identifiers,
names, search terms and coordinates; permit our own object URLs and pack IDs.

**b. `LoggingPrivacyTests` never runs in CI.** The only workflows are `attribution.yml` and
`main-source-guard.yml`, so the lint is enforced only when someone runs the suite locally. This feature
makes the lint load-bearing for a user-facing privacy claim, so wiring it into CI is a prerequisite.

**c. Every "not included" claim is a test.** Generate an export from a synthetic session and assert the
claimed-absent classes are absent. A promise the code does not keep is worse than no promise, because the
user relies on it when they tap Share.

**d. An export-time scrub with defined failure semantics.** A pass over the staged text for
coordinate-shaped and place-identifier-shaped content. If it finds anything the export **fails closed** and
says so, rather than proceeding with a substitution count nobody reads.

---

## 7. Policy changes needed — for Rob's ratification

Rob pre-authorised a `privacy.md` update. Two documents need one, and the second was not anticipated.

**`privacy.md`** — a new subsection under "Sharing lists, reporting problems…". Draft:

> ### Sending diagnostic logs
>
> If something goes wrong, you can send us a diagnostic log from Settings. Nothing is sent automatically and
> there is no background reporting.
>
> - You choose when to send one, you can read it before you send it, and you choose who to send it to.
> - It contains what the app was doing: the version you're running, your device model and iOS version, which
>   map packs you have installed, and the addresses and error codes of files the app was fetching from us.
>   Those addresses include the names of the areas you've downloaded.
> - It does not contain the places you looked at, saved, loved or hid, your searches, your lists, or where
>   you are.
> - It stays on your phone until you send it, and you can delete it at any time.

**`docs/threat-model.md` §3** — required, not optional. Lines 124-125 currently **close** the list of egress
channels: *"It leaves only over HTTPS, and only through the specific user-initiated actions `privacy.md`
already lists (share a list, report a place, opt-in place statistics)."* A diagnostic export is a fourth
channel, so that sentence must name it or the model is wrong the day this ships.

This applies whatever the content line is. Even a minimal export adds a channel to a list the threat model
states is complete.

---

## 8. Open questions

1. Retention age for log files, and whether "Delete diagnostics" also clears the current buffer.
2. Buffer bound and drop policy under download-loop load.
3. Whether the decode table is generated fresh at export time or maintained continuously. Recommend
   generating it at export, so no plaintext mapping sits at rest alongside the hashed log.
4. Whether `.debug` goes to the file. It carries the download narrative and the system log does not persist
   it. Recommend yes, within the size bound.
5. `MapScreen.swift:2209` holds a second `Section("Storage")` in a different view. Confirm Diagnostics
   belongs only in `SettingsView`.

---

Research on the `family-foqos` export design, and what was adopted or rejected from it, is in
[`2026-07-18-foqos-log-export.md`](../../research/2026-07-18-foqos-log-export.md).
