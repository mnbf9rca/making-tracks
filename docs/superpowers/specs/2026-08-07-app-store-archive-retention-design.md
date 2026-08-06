# App Store archive retention design

## Status and scope

Issue #549 requires every archive uploaded to App Store Connect to remain retrievable after the Mac that
created it is lost or replaced. The retained artifact must contain the shipped app binary, its matching
dSYMs, archive provenance, signing record, and entitlements. This design is approved for implementation.

The target workflow preserves Xcode Organizer as the human App Store upload surface. It adds a mandatory
publication and verification step before that upload. It does not automate signing, export, App Store
Connect authentication, TestFlight submission, review submission, or release promotion.

Every App Store Connect upload is retained indefinitely, including a build that remains TestFlight-only.
At the pre-upload capture boundary the eventual promotion state is unknown, so retaining the superset is
the only policy that cannot lose a later-shipped archive.

This is not a simulator release-gate artifact. It neither enters `/private/tmp/release-gate-*` nor carries
`.release-gate-owned`, `.release-gate-success`, or `.release-gate-preserve`. The 24-hour successful-gate
cleanup from #546 never examines it.

## Decisions and rejected approaches

### Private immutable R2 objects — approved

The existing private `making-tracks-state` R2 bucket is the canonical off-machine store. The release
tool reads that bucket name from `pipeline/config/r2_layout.json` and uses the existing 1Password-backed
R2 credentials. Archive objects occupy an immutable `app-store-archives/` prefix that is distinct from
the bucket's mutable pipeline state.

The prefix boundary is sufficient separation because release archives are write-once evidence. The tool
has no overwrite or delete operation. A future operator can retrieve an archive by version and build
number without access to the originating Mac.

### GitHub Release assets — rejected as the canonical store

GitHub Release assets are machine-independent and tag-indexed, but this repository is public. Using them
as the canonical store would publish the signed archive, dSYMs, and signing metadata. GitHub also requires
each individual release asset to remain below 2 GiB. Public publication can be added later without
changing the private canonical layout, but it is not part of #549.

### Application Support only — rejected as the canonical store

Application Support is outside automatic temporary and cache cleanup, so it is the correct caller-owned
local staging home. It remains tied to one Mac and therefore cannot satisfy migration survival by itself.

## Operator command and boundaries

The target host CLI is `scripts/app-store-archive.py` with `publish` and `retrieve` subcommands. Commands
that access R2 run through the repository's existing secret boundary:

```bash
op run --env-file=.env.tpl -- uv run --project pipeline \
  python scripts/app-store-archive.py publish \
  --archive "/absolute/path/to/MakingTracks.xcarchive"
```

```bash
op run --env-file=.env.tpl -- uv run --project pipeline \
  python scripts/app-store-archive.py retrieve \
  --version 1.0 --build 1 \
  --destination "/absolute/caller-owned/destination"
```

The tool does not invoke `xcodebuild archive`, `xcodebuild -exportArchive`, App Store Connect, Xcode's
upload APIs, CoreSimulator, `sim-lock.sh`, or `release-gate.sh`. It receives an Organizer-produced archive
and proves that archive is safe to use for the subsequent human upload.

## Archive identity and symbolication gate

Before copying or uploading anything, `publish` validates the selected path and archive:

1. The argument resolves to a real `.xcarchive` directory, not a symlink.
2. The archive contains exactly one Making Tracks application with bundle identifier
   `app.making-tracks.MakingTracks`.
3. The application and archive metadata agree on `CFBundleShortVersionString` and `CFBundleVersion`.
4. `BuildInfo.plist` contains the stamped Git commit, and that commit resolves unambiguously in the local
   repository to one full 40-character SHA.
5. `dSYMs/MakingTracks.app.dSYM/Contents/Resources/DWARF/MakingTracks` exists and is non-empty.
6. `xcrun dwarfdump --uuid` reports the same complete, non-empty architecture/UUID set for the archived
   app binary and its app dSYM DWARF file.

Mere dSYM presence is insufficient. UUID equality is the symbolication guarantee: a dSYM from a sibling
build is useless even when its filename looks correct.

Version and build values must be safe single key segments. The full Git SHA is lowercase hexadecimal.
Unsafe, missing, contradictory, or ambiguous identity data fails before local staging or network access.

## Caller-owned Application Support staging

The validated archive is copied with macOS `ditto` into:

```text
$HOME/Library/Application Support/making-tracks-releases/archives/
└── <version>/
    └── <build>/
        └── <full-git-sha>/
            ├── MakingTracks.xcarchive/
            ├── archive.xcarchive.zip
            └── manifest.json
```

The leaf is caller-owned, non-purgeable staging. The tool never places a release-gate marker in it and
the gate never prunes it. A missing leaf is built under a unique sibling staging name and atomically
renamed only after archive validation and packaging succeed.

If the final leaf already exists, `publish` accepts it only when its manifest and packaged archive match
the newly selected archive exactly. A different archive at the same version/build/SHA fails closed. The
tool never replaces an existing leaf.

The operator must upload the retained `MakingTracks.xcarchive` from this Application Support leaf in
Xcode Organizer. Publish-before-upload makes the retained copy the artifact actually shipped rather than
a hopeful copy made after the fact.

The local leaf may be removed only after App Store Connect accepts the upload and a new `retrieve`
invocation has successfully restored and revalidated the remote archive. This deletion is a documented
operator action against the exact version/build/SHA leaf; the tool has no delete subcommand. The private
R2 objects remain indefinitely.

## Immutable R2 layout

The canonical remote prefix is:

```text
s3://making-tracks-state/app-store-archives/
└── <version>/
    └── <build>/
        └── <full-git-sha>/
            ├── archive.xcarchive.zip
            └── manifest.json
```

The bucket name is read from the `private_bucket` field of `pipeline/config/r2_layout.json`; it is not
duplicated in production code. The prefix constant is `app-store-archives`.

Before an upload, the tool lists the version/build prefix. No other SHA may already exist because App
Store Connect build numbers identify one build. A different SHA is a release-process conflict, not a new
revision to overwrite.

For each exact object key:

- absence permits the one upload;
- an existing byte-identical object makes a retry idempotent;
- an existing differing object poisons the prefix and fails closed;
- no code path overwrites or deletes it.

The archive object uploads first. `manifest.json` uploads last and is the completion marker. An archive
without a manifest is an interrupted publication, not a ready release. A retry verifies the existing
archive and may then finish the manifest publication.

After each object upload, the tool downloads that remote object to a fresh temporary file and recomputes
SHA-256. It prints `READY FOR APP STORE UPLOAD` only after both remote bytes match their local bytes and
the remote manifest describes the verified archive. Trusting client-supplied object metadata or a
multipart ETag is not sufficient.

## Manifest schema

`manifest.json` is UTF-8 JSON with sorted keys, a trailing newline, and schema
`making-tracks-app-store-archive-v1`. It is the first file an operator reads during an incident and
contains:

```json
{
  "app_binary_sha256": "<64 lowercase hex characters>",
  "archive_object": {
    "bytes": 123,
    "key": "app-store-archives/1.0/1/<sha>/archive.xcarchive.zip",
    "sha256": "<64 lowercase hex characters>"
  },
  "build": "1",
  "bundle_id": "app.making-tracks.MakingTracks",
  "captured_at_utc": "<RFC 3339 UTC timestamp>",
  "dsym_uuids": [
    {"architecture": "arm64", "uuid": "00000000-0000-0000-0000-000000000000"}
  ],
  "git_sha": "<40 lowercase hex characters>",
  "schema": "making-tracks-app-store-archive-v1",
  "tool": {
    "name": "scripts/app-store-archive.py",
    "schema_version": 1
  },
  "version": "1.0",
  "xcode": {
    "build_version": "<xcodebuild build version>",
    "version": "<Xcode version>"
  }
}
```

The timestamp placeholder and zero UUID illustrate format only; production values come from the archive
and capture environment. `dsym_uuids` is sorted by architecture then UUID and records the complete set
returned by `dwarfdump`. The capture time is current UTC at publication. The Xcode fields come from
`xcodebuild -version`. The manifest's archive size and digest describe the exact packaged object stored
locally and in R2.

The manifest itself is serialized once. Its local SHA-256 and byte count are computed before upload, and
the post-upload round trip must reproduce both exactly.

## Retrieval

`retrieve --version <version> --build <build>` lists only direct SHA children under the exact immutable
prefix. Exactly one SHA must exist. Zero matches reports not found; multiple matches reports every
candidate and requires investigation because publication should have refused that state. An optional
`--sha` narrows retrieval during recovery but does not weaken manifest validation.

Retrieval performs these steps:

1. Download `manifest.json` and validate its schema, key identity, bundle identifier, version, build,
   full SHA, dSYM UUID shape, Xcode/tool fields, capture timestamp, archive digest, and byte count.
2. Download the archive object named by that manifest.
3. Verify the downloaded byte count and SHA-256 before extraction.
4. Extract with `ditto` beneath the caller's explicit destination without replacing an existing path.
5. Re-run the archive identity checks and app-binary/dSYM UUID comparison.
6. Verify the restored app-binary digest and manifest identity.

Only then does retrieval report the restored `.xcarchive` path. A successful fresh retrieval is the proof
required before an operator may remove the caller-owned Application Support staging leaf.

## Failure handling and recovery

- Missing credentials, invalid R2 endpoint configuration, authentication errors, upload errors, download
  errors, archive validation failures, and digest mismatches are nonzero and never print READY.
- A failed local copy or package operation leaves only its unique staging name. The error reports that
  exact path for inspection; it never removes a parent or wildcard target.
- An archive object uploaded before interruption is incomplete until an identical manifest is uploaded
  and round-trip verified.
- An existing different object or corrupt round trip is preserved and escalated as a poisoned immutable
  prefix. Repair requires an explicitly reviewed, exact-key infrastructure operation outside this tool;
  the release must not proceed in the meantime.
- R2 credentials are read only from the `op run` environment. Values are never printed, persisted in the
  manifest, or included in exception text.
- Local staging and remote objects contain signed release material. The R2 prefix remains private; no
  public URL is created.

## Release-process documentation

Implementation creates `docs/app-store-release.md` as the minimal release checklist:

1. Produce the archive in Xcode Organizer from the intended source state.
2. Run `publish` through `op run` and stop unless it prints READY with version, build, full SHA, local
   retained path, remote prefix, archive digest, and dSYM UUIDs.
3. Open the retained Application Support archive in Organizer and distribute that archive to App Store
   Connect.
4. Record the App Store Connect acceptance against version/build/SHA.
5. Keep every remote archive indefinitely, including TestFlight-only uploads.
6. Remove local staging only after acceptance and a successful fresh retrieval, using the exact leaf.

`docs/ios-gate-ledger.md` gains a short ownership-boundary note. It does not restate the release
checklist or add App Store archives to the gate-owned lifecycle.

## Test design

Pytest exercises production functions with temporary archive/Application Support roots and fake R2 and
command boundaries. No test reads production source text as its oracle. The matrix proves:

1. valid archive identity, full-SHA resolution, key derivation, app-binary digest, and complete dSYM UUID
   matching;
2. missing, empty, or UUID-mismatched dSYMs fail before local or remote mutation;
3. unsafe identity segments, contradictory plist values, ambiguous commits, and unexpected bundle IDs
   fail closed;
4. staging is outside release-gate roots, never receives gate markers, and never replaces a differing
   existing leaf;
5. a publish uploads the archive before the manifest and reports ready only after both round-trip digests
   match;
6. interrupted archive-only publication resumes idempotently, while differing existing objects and a
   second SHA for one version/build are preserved and rejected;
7. a corrupt remote download keeps publication incomplete and nonzero;
8. retrieval by version/build requires one SHA, validates the manifest and archive bytes, refuses an
   existing destination, and revalidates the restored identity, binary digest, and dSYM UUIDs;
9. manifest serialization includes every required incident field with deterministic key and UUID order;
10. exception and CLI output never contain R2 credential values.

For every critical guard, the implementation record names the production break, changes one behavior at
a time, observes the targeted test fail, restores the guard, and observes it pass. The complete pipeline
test suite, shell/law checks, host Swift suite, and required iOS host gate remain the finishing gates.

## Out of scope

- Automated archive creation, export, signing, App Store Connect upload, TestFlight promotion, or App
  Store review submission.
- New App Store Connect credentials or changes to the existing 1Password secret topology.
- Public GitHub Release publication.
- dSYM upload to a crash-reporting service; the complete matching dSYMs are retained for a future service
  without selecting one here.
- Automatic deletion or retention shortening for either local staging or remote release evidence.
