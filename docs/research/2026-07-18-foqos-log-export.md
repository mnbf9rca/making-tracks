# `family-foqos` log export — what we took and what we rejected

Research note supporting WP-LOGS. Read 2026-07-18 against
[`mnbf9rca/family-foqos`](https://github.com/mnbf9rca/family-foqos) at `main`.

The brief suggested foqos "implements privacy-based logging using some iOS framework". **It does not**, and
that inversion is the main finding. Verified by grep across all `*.swift`:

- `privacy: .` — **0 matches**
- `OSLogStore` — **0 matches**
- `Logger(subsystem:` — **0 matches**

It is a hand-rolled file logger (`Packages/FoqosShared/Sources/FoqosShared/Log.swift`, 459 lines) shared by
the app, widget, device-monitor and shield-config extensions. Its one line into the unified log is:

```swift
os_log("%{public}@", log: osLog, type: entry.level.osLogType, entry.formattedString)
```

Pre-interpolating the whole message into `%{public}@` bypasses the unified log's redaction model entirely.
Every profile name and record identifier it logs is permanently public in the unified log, readable via
sysdiagnose — a different and worse exposure than a user-initiated export.

Its privacy rests on call-site discipline across **499 `Log.*` call sites**, guarded by one test on one type
(`FoqosTests/FamilyMemberLogRedactionTests.swift`), with no lint and no export-time scrubbing.

**Our position is the reverse:** 282 `.public` and 130 `.private(mask: .hash)` annotations, a central
facade, three sanitizer helpers, and a real lint with a denylist. So the transfer runs the other way — take
the file handling, keep our privacy model.

---

## Adopted

**Per-process filenames from a pure function.** `logBaseName(forBundleIdentifier:)` maps bundle IDs to
`app` / `monitor` / `widget` / `shield`. Kills append interleaving without locks, and export just globs the
directory. Pure, so it is unit-testable, and they test it.

**Snapshot under lock with narrowly-typed race tolerance.** `copyLogFilesToStagingDirectory` holds the
serial queue while copying, and `isVanishedSourceCopyError` whitelists only `fileNoSuchFile` while
rethrowing everything else. Most implementations slap `try?` on the copy and lose real failures. Worth
copying as-is.

**Dependency-free zip** via `NSFileCoordinator` `.forUploading`, which zips a directory as a side effect. No
ZIPFoundation needed.

**The `.txt` fallback returning its real URL** rather than the requested one, so a failed zip does not share
a nonexistent path.

**Off-main export** — `Task.detached` for archive creation.

**Explicit `UIDevice.name` redaction** in the metadata header, replaced with `[REDACTED FOR PRIVACY]`. It is
usually a person's name.

**An included / not-included inventory in the UI**, as an idea. See below for why the execution fails.

**Purely local, user-initiated share.** No endpoint, no upload, no telemetry anywhere in the flow.

---

## Rejected

**`os_log("%{public}@", …)`.** Defeats the privacy model. We have a working one; keep per-value annotations
and never pre-interpolate into a public format specifier.

**Call-site discipline as the only control.** 499 sites, one test, no lint, no CI check. This regresses the
first time someone types `\(profile.name)`. We have a lint — keep it and extend it to any new sink.

**No export-time scrubbing.** The staged copy is byte-identical to what was written. We add a scrub that
fails closed.

**Unbounded export.** foqos ships every retained file with no size, count or time bound — a ~100 MB ceiling
across four process tags. We bound by time window.

**Debug level always on.** `minimumLevel = .debug` and `fileLoggingEnabled = true` are `let` constants with
no runtime toggle and no user opt-out, in production. Continuous unbuffered debug logging is a battery and
disk cost the user never agreed to.

**Unbuffered per-line `FileHandle` open/seek/write/close.** A genuine I/O hot path at debug verbosity. We
buffer and flush on a timer and on background transition.

**Tail-only preview.** `LogPreviewView` shows 100 tailed lines from one file against an unbounded multi-file
zip. It does not show the user what they are about to send. We preview the artifact.

**No backup exclusion, no file protection.** Zero matches for either. Logs sit in the app-group container
and ride to iCloud backups. We set both.

**Ungated export.** In a parental-control app, Debug Mode ships in release with no lock-code gate, so a
child can export the parent's diagnostic logs. Not directly applicable to us — we have no adversarial-user
model — but worth recording.

---

## The inventory problem, which is the transferable lesson

foqos ships this in its export UI:

> **Not Included:** Passwords or lock codes · Personal identifiers · Location coordinates · Blocked app
> names

Checked against the code, three of the four hold. **"Personal identifiers" does not.**
`CloudKitNetworkService+FamilyMembers.swift:97` logs a raw CloudKit user record name — a stable cross-device
account identifier — and heartbeat and command record names are logged too. Profile names are logged in at
least four places, and users name profiles things like "Emma's bedtime".

A privacy promise that drifts from the code is worse than no promise, because the user relies on it at the
moment they tap Share. **Hence WP-LOGS §6c: every "not included" claim is an assertion in a test against a
generated export.**

---

## Incidental bugs noticed

Not ours to fix, recorded because two are worth avoiding in our own implementation:

- `formattedTimestamp()` uses a bare `DateFormatter()` with `dateFormat` and no
  `locale = Locale(identifier: "en_US_POSIX")` — wrong filename year on a non-Gregorian calendar device.
- A fresh `ISO8601DateFormatter()` is allocated per log line.
- A 1000-entry in-memory ring buffer is maintained on every call and never read; `getEntries()` has no
  callers.
- Dead code: `shareLogArchive`, `getShareableLogFile`, `getEntries`, `archiveCreationFailed`. Notably
  `getShareableLogFile` builds an unbounded string in memory — an OOM if anyone wires it up.
