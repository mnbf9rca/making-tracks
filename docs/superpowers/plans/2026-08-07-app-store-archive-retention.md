# App Store Archive Retention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Making Tracks archive uploaded to App Store Connect durably retrievable by version and build from the private R2 state bucket, with matching dSYMs and verified provenance.

**Architecture:** A focused `mt_pipeline.app_store_archive` package owns archive inspection, deterministic manifest construction, caller-owned Application Support staging, immutable R2 publication, and recovery. A thin repository script exposes `publish` and `retrieve`; all filesystem, subprocess, clock, and S3 boundaries are injected so pytest exercises behavior without live credentials or source-text assertions. Publication validates and stages locally, uploads the archive before its manifest, downloads both objects to fresh temporary files for digest verification, and only then reports readiness for the human Xcode Organizer upload.

**Tech Stack:** Python 3.11, `plistlib`, `hashlib`, `pathlib`, macOS `ditto`, `git`, `xcrun dwarfdump`, `xcodebuild`, boto3's S3 client, pytest, Markdown release operations

## Global Constraints

- Work only in `/Users/rob/git/making-tracks/.worktrees/fix-549-store-xcarchive`; never switch or mutate the root `ios` checkout.
- Preserve the approved design at `docs/superpowers/specs/2026-08-07-app-store-archive-retention-design.md` and planner approval AMQ ID `2026-08-06T21-30-23.495Z_pid83760_76e3b387`.
- Retain every App Store Connect upload indefinitely, including TestFlight-only builds. Keep human Xcode Organizer upload, signing, export, review submission, and release promotion out of this tool.
- Publish to the private bucket named by `private_bucket` in `pipeline/config/r2_layout.json`, beneath immutable `app-store-archives/<version>/<build>/<full-sha>/` keys. Never add overwrite or delete behavior.
- Stage under `$HOME/Library/Application Support/making-tracks-releases/archives/<version>/<build>/<full-sha>/`. Never place release-gate markers there or use `/private/tmp/release-gate-*`, cache roots, or release-gate cleanup code.
- Require bundle identifier `app.making-tracks.MakingTracks`, matching archive/application version and build, a resolvable full 40-character Git SHA, a non-empty app dSYM, and exact architecture/UUID-set equality between the app binary and dSYM.
- Build the archive object before `manifest.json`, upload the archive first, upload the manifest last, and print `READY FOR APP STORE UPLOAD` only after fresh remote downloads reproduce the local byte counts and SHA-256 digests.
- The operator uploads the retained Application Support `.xcarchive`, not the original Organizer path. Local deletion is documented only after App Store Connect acceptance and a successful fresh retrieval; production code exposes no delete command.
- R2 credentials remain environment-only behind `op run --env-file=.env.tpl`. CLI and exception output name missing variable names but never credential values.
- Copy, ZIP, upload, and fresh-download liveness uses the existing stderr `PhaseProgress` format: START/DONE
  boundaries and a `processed=<done>/<total>` rate/elapsed heartbeat at least every 30 seconds; stdout
  remains the stable operator result contract.
- Follow strict RED → GREEN → REFACTOR. Every test invokes production functions or the production CLI; no test reads production source text as its oracle.
- Final publication requires rebasing onto an `ios` branch that contains #633. Until then, slice checkpoints use their focused suites and name the 26 full-suite failures as the pre-#633 release-gate fixture's inherited-signing defect. After that rebase, the full pipeline bar is zero failures with only the live-provider skip at the actual collected count; do not reuse a memorized count.
- Before final review, mutate each critical production guard one at a time, prove its named test fails for the intended reason, restore it, prove GREEN, and record the command/result in `docs/superpowers/reports/2026-08-07-app-store-archive-mutation-teeth.md`.
- Every repository mutation is a bare single command and is verified separately. Commits are signed and single-purpose.

---

## File map

- `pipeline/src/mt_pipeline/app_store_archive/model.py`: immutable identity/publication records, constants, safe key-component validation, digest helpers.
- `pipeline/src/mt_pipeline/app_store_archive/archive.py`: `.xcarchive` plist inspection, Git-SHA resolution, Xcode-version capture, `dwarfdump` parsing and UUID equality.
- `pipeline/src/mt_pipeline/app_store_archive/manifest.py`: exact v1 manifest assembly, deterministic serialization, and strict retrieval validation.
- `pipeline/src/mt_pipeline/app_store_archive/staging.py`: caller-owned Application Support copy/package lifecycle and idempotent collision checks.
- `pipeline/src/mt_pipeline/app_store_archive/r2_store.py`: private-bucket lookup, immutable conditional writes, object round trips, and exact version/build/SHA discovery.
- `pipeline/src/mt_pipeline/app_store_archive/progress.py`: existing-format blocking transfer liveness telemetry.
- `pipeline/src/mt_pipeline/app_store_archive/workflow.py`: publish/retrieve orchestration and readiness/recovery result objects.
- `pipeline/src/mt_pipeline/app_store_archive/cli.py`: argument parsing, stable redacted errors, and operator output.
- `scripts/app-store-archive.py`: executable import shim into the packaged CLI.
- `pipeline/tests/app_store_archive_helpers.py`: realistic archive fixture plus command and in-memory S3 doubles.
- `pipeline/tests/test_app_store_archive_validation.py`: identity, plist, Git, digest, and symbolication guards.
- `pipeline/tests/test_app_store_archive_staging.py`: manifest, packaging, Application Support ownership, collision, and atomicity behavior.
- `pipeline/tests/test_app_store_archive_r2.py`: immutable publication, interrupted retry, round-trip corruption, selection, and download behavior.
- `pipeline/tests/test_app_store_archive_cli.py`: end-to-end publish/retrieve orchestration, output, and credential redaction.
- `docs/app-store-release.md`: human archive, publish, Organizer upload, acceptance, retrieval, and retention checklist.
- `docs/ios-gate-ledger.md`: one ownership-boundary paragraph excluding release archives from gate cleanup.
- `docs/superpowers/reports/2026-08-07-app-store-archive-mutation-teeth.md`: permanent RED/GREEN evidence for critical guards.

---

### Task 1: Archive identity and dSYM validation

**Files:**

- Create: `pipeline/src/mt_pipeline/app_store_archive/__init__.py`
- Create: `pipeline/src/mt_pipeline/app_store_archive/model.py`
- Create: `pipeline/src/mt_pipeline/app_store_archive/archive.py`
- Create: `pipeline/tests/app_store_archive_helpers.py`
- Create: `pipeline/tests/test_app_store_archive_validation.py`

**Interfaces:**

- Produces: `AppStoreArchiveError`, `ArchiveValidationError`, `DsymUUID(architecture: str, uuid: str)`, `ArchiveIdentity`, `validate_key_component(value: str, label: str) -> str`, `validate_full_sha(value: str) -> str`, `sha256_file(path: Path) -> tuple[str, int]`, and `inspect_archive(archive_path: Path, repo_root: Path, run: CommandRunner = run_command) -> ArchiveIdentity`.
- `CommandRunner` consumes `Sequence[str]` and returns stdout as `str`; production `run_command` uses `subprocess.run(args, check=True, capture_output=True, text=True)` and translates failures into redacted `ArchiveValidationError` messages.

- [ ] **Step 1: Build the realistic archive fixture and write RED identity tests**

Create `make_archive(tmp_path, *, version="1.0", build="1", bundle_id="app.making-tracks.MakingTracks", git_commit="1234567", app_uuids=(DsymUUID("arm64", "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),), dsym_uuids=None)` in `app_store_archive_helpers.py`. It must write binary plists with `plistlib.dump` at:

```text
MakingTracks.xcarchive/Info.plist
MakingTracks.xcarchive/Products/Applications/MakingTracks.app/Info.plist
MakingTracks.xcarchive/Products/Applications/MakingTracks.app/BuildInfo.plist
MakingTracks.xcarchive/Products/Applications/MakingTracks.app/MakingTracks
MakingTracks.xcarchive/dSYMs/MakingTracks.app.dSYM/Contents/Resources/DWARF/MakingTracks
```

The archive plist contains `ApplicationProperties` with `ApplicationPath`, `CFBundleIdentifier`, `CFBundleShortVersionString`, and `CFBundleVersion`; the app plist contains the same identity plus `CFBundleExecutable`. The helper's command double returns a full SHA for `git rev-parse`, Xcode version lines for `xcodebuild -version`, and one `UUID: <uuid> (<architecture>)` line per requested `dwarfdump` result.

Write tests that prove a valid fixture yields:

```python
identity = inspect_archive(archive, repo_root, run=fake_commands.run)
assert identity.bundle_id == "app.making-tracks.MakingTracks"
assert identity.version == "1.0"
assert identity.build == "1"
assert identity.git_sha == "1234567890abcdef1234567890abcdef12345678"
assert identity.dsym_uuids == (
    DsymUUID("arm64", "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
)
assert identity.app_binary_sha256 == hashlib.sha256(b"app-binary").hexdigest()
```

Add parametrized failures for a symlink archive root, wrong suffix, missing/multiple app directories, unexpected bundle ID, disagreeing app/archive version or build, absent/empty executable, absent/empty dSYM, missing/ambiguous/non-hex Git resolution, malformed `dwarfdump`, empty UUID sets, and architecture/UUID mismatch. Assert the command log has no `xcodebuild -version` entry after any earlier identity failure.

- [ ] **Step 2: Run the focused tests and observe RED**

Run:

```bash
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_app_store_archive_validation.py -v
```

Expected: collection fails because `mt_pipeline.app_store_archive.archive` does not exist. Preserve that failure in the implementation notes before creating production files.

- [ ] **Step 3: Add immutable records, safe segments, and digest helpers**

Implement these exact records in `model.py`:

```python
APP_BUNDLE_ID = "app.making-tracks.MakingTracks"
REMOTE_PREFIX = "app-store-archives"
MANIFEST_SCHEMA = "making-tracks-app-store-archive-v1"

class AppStoreArchiveError(RuntimeError):
    """Expected, redaction-safe release archive failure."""

class ArchiveValidationError(AppStoreArchiveError):
    """Archive identity or symbolication evidence is invalid."""

@dataclass(frozen=True, order=True)
class DsymUUID:
    architecture: str
    uuid: str

@dataclass(frozen=True)
class ArchiveIdentity:
    archive_path: Path
    app_path: Path
    app_binary: Path
    dsym_binary: Path
    bundle_id: str
    version: str
    build: str
    git_sha: str
    app_binary_sha256: str
    dsym_uuids: tuple[DsymUUID, ...]
    xcode_version: str
    xcode_build: str

def validate_key_component(value: str, label: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", value) or value in {".", ".."}:
        raise ArchiveValidationError(f"unsafe {label}")
    return value

def validate_full_sha(value: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ArchiveValidationError("Git SHA must be 40 lowercase hexadecimal characters")
    return value

def sha256_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size
```

Keep exception messages to stable field/path labels; do not interpolate subprocess environments, credential values, or raw boto exceptions.

- [ ] **Step 4: Implement archive inspection and UUID equality minimally**

In `archive.py`, use `plistlib.load`, exact expected paths derived from `ApplicationPath`, and a strict parser:

```python
_UUID_LINE = re.compile(
    r"^UUID: ([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}) \(([^()\s]+)\) .+$"
)

def parse_dwarfdump(stdout: str) -> tuple[DsymUUID, ...]:
    parsed = {
        DsymUUID(match.group(2), match.group(1).upper())
        for line in stdout.splitlines()
        if (match := _UUID_LINE.fullmatch(line))
    }
    if not parsed or len(parsed) != len([line for line in stdout.splitlines() if line.strip()]):
        raise ArchiveValidationError("invalid dwarfdump UUID output")
    return tuple(sorted(parsed))
```

Resolve `BuildInfo.plist`'s `GitCommit` using:

```python
full_sha = run(["git", "-C", str(repo_root), "rev-parse", "--verify", f"{stamp}^{{commit}}"]).strip()
if not re.fullmatch(r"[0-9a-f]{40}", full_sha) or not full_sha.startswith(stamp.lower()):
    raise ArchiveValidationError("archive Git commit is not an unambiguous full SHA")
```

Run `xcrun dwarfdump --uuid` separately for the app and dSYM binaries, require exact tuple equality, compute the app binary SHA-256, then parse the two-line `xcodebuild -version` result into version/build fields.

- [ ] **Step 5: Run GREEN, refactor, and commit the validation slice**

Run the focused test, then the pipeline suite:

```bash
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_app_store_archive_validation.py -v
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests -q
```

Expected: all tests pass. Refactor only duplicated plist/path validation and rerun both commands. Commit:

```bash
git add pipeline/src/mt_pipeline/app_store_archive pipeline/tests/app_store_archive_helpers.py pipeline/tests/test_app_store_archive_validation.py
git diff --cached --check
git commit -S -m "Validate App Store archive identity"
```

Verify the signature and a clean status in separate commands.

---

### Task 2: Deterministic manifest and caller-owned staging

**Files:**

- Create: `pipeline/src/mt_pipeline/app_store_archive/manifest.py`
- Create: `pipeline/src/mt_pipeline/app_store_archive/staging.py`
- Create: `pipeline/tests/test_app_store_archive_staging.py`
- Modify: `pipeline/tests/app_store_archive_helpers.py`

**Interfaces:**

- Consumes: `ArchiveIdentity`, `DsymUUID`, `sha256_file`, `validate_key_component`, and `CommandRunner` from Task 1.
- Produces: `ManifestValidationError(AppStoreArchiveError)`, `StagingError(AppStoreArchiveError)`, `LocalArtifact(leaf: Path, archive: Path, archive_zip: Path, manifest_path: Path, manifest_bytes: bytes, manifest_sha256: str)`, `build_manifest(identity, archive_key, archive_sha256, archive_bytes, captured_at) -> dict[str, object]`, `serialize_manifest(value: Mapping[str, object]) -> bytes`, `parse_manifest(data: bytes, expected_version: str, expected_build: str, expected_sha: str) -> Mapping[str, object]`, and `stage_archive(identity, application_support_root, captured_at, run=run_command) -> LocalArtifact`.

- [ ] **Step 1: Write RED manifest and staging tests**

Test that `serialize_manifest` uses `json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"` and contains exactly the approved schema fields: `app_binary_sha256`, `archive_object`, `build`, `bundle_id`, `captured_at_utc`, sorted `dsym_uuids`, `git_sha`, `schema`, `tool`, `version`, and `xcode`.

Test `parse_manifest` rejects unknown/missing top-level or nested fields, unsafe identity values, wrong schema/bundle/key, malformed UTC timestamp, unsorted/duplicate UUIDs, invalid digests/sizes, and any mismatch with the key's version/build/SHA.

For staging, inject a `ditto` double that performs real fixture copies and writes deterministic zip bytes. Assert:

```python
artifact = stage_archive(identity, app_support, "2026-08-07T00:00:00Z", run=fake.run)
expected = app_support / "archives/1.0/1/1234567890abcdef1234567890abcdef12345678"
assert artifact.leaf == expected
assert artifact.archive == expected / "MakingTracks.xcarchive"
assert artifact.archive_zip == expected / "archive.xcarchive.zip"
assert artifact.manifest_path == expected / "manifest.json"
assert not any(path.name.startswith(".release-gate-") for path in expected.iterdir())
```

Add failures for a symlink or non-directory Application Support root component, a final leaf containing a different archive digest, a final leaf with an invalid manifest, `ditto` copy/package failure, and a rename collision. Prove failed build/package leaves its unique sibling staging directory and does not modify the final leaf. Prove an existing identical final leaf returns idempotently without replacement.

- [ ] **Step 2: Run the focused tests and observe RED**

Run:

```bash
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_app_store_archive_staging.py -v
```

Expected: collection fails because `manifest.py` and `staging.py` do not exist.

- [ ] **Step 3: Implement strict manifest serialization and validation**

Build the archive key only after validating all three segments:

```python
archive_key = (
    f"{REMOTE_PREFIX}/{validate_key_component(identity.version, 'version')}/"
    f"{validate_key_component(identity.build, 'build')}/"
    f"{validate_full_sha(identity.git_sha)}/archive.xcarchive.zip"
)
```

Use `datetime.fromisoformat(value.replace("Z", "+00:00"))` and require the original capture timestamp to end in `Z` and normalize back to exactly itself. `parse_manifest` must require exact key sets and types before returning data; booleans are not valid integer sizes. Reconstruct and compare the expected archive key from the manifest identity.

- [ ] **Step 4: Implement safe local staging and idempotency**

Default `application_support_root` in the workflow to `Path.home() / "Library/Application Support/making-tracks-releases"`, but make `stage_archive` require the explicit injected root. Validate/create each fixed parent as a real non-symlink directory. Create the unique sibling with `tempfile.mkdtemp(prefix=".archive-staging-", dir=sha_parent)`.

Copy and package with exact commands:

```python
run(["ditto", str(identity.archive_path), str(staging_archive)])
run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(staging_archive), str(staging_zip)])
```

Compute zip SHA/size, write the manifest using exclusive creation, fsync each file and the staging directory, then rename the staging directory to the absent final leaf. When the final leaf exists, validate its manifest, recompute its zip digest/size, and accept only if every identity field, app digest, dSYM UUID set, and packaged archive digest matches the newly staged candidate. Remove only an exact successful redundant sibling staging directory after all equality checks; preserve it on any failure and name it in the error.

- [ ] **Step 5: Run GREEN, refactor, and commit the staging slice**

Run:

```bash
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_app_store_archive_staging.py -v
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_app_store_archive_validation.py pipeline/tests/test_app_store_archive_staging.py -q
```

Expected: all tests pass. Commit:

```bash
git add pipeline/src/mt_pipeline/app_store_archive/manifest.py pipeline/src/mt_pipeline/app_store_archive/staging.py pipeline/tests/app_store_archive_helpers.py pipeline/tests/test_app_store_archive_staging.py
git diff --cached --check
git commit -S -m "Stage durable App Store archives"
```

Verify signature and status separately.

---

### Task 3: Immutable R2 publication and verified download

**Files:**

- Create: `pipeline/src/mt_pipeline/app_store_archive/r2_store.py`
- Create: `pipeline/tests/test_app_store_archive_r2.py`
- Modify: `pipeline/tests/app_store_archive_helpers.py`

**Interfaces:**

- Consumes: `LocalArtifact`, manifest parsing, `REMOTE_PREFIX`, `sha256_file`, and the existing `require_boto3()` / `require_upload_environment()` validation in `mt_pipeline.publish.r2`.
- Produces: `ArchiveStorageError(AppStoreArchiveError)`, `RemotePublication(bucket: str, prefix: str, archive_sha256: str, manifest_sha256: str)`, `DownloadedPublication(root: Path, archive_zip: Path, manifest: Mapping[str, object])`, `private_bucket(layout_path: Path) -> str`, `client_from_environment() -> object`, and `R2ArchiveStore(client: object, bucket: str)` methods `publish(local: LocalArtifact) -> RemotePublication`, `resolve_sha(version: str, build: str, requested_sha: str | None = None) -> str`, and `download(version: str, build: str, sha: str, temporary_root: Path) -> DownloadedPublication`.

- [ ] **Step 1: Build the in-memory S3 double and write RED immutable-storage tests**

The double stores `dict[(bucket, key), bytes]`, records ordered `put_object`, `get_object`, and `list_objects_v2` calls, honors `IfNoneMatch="*"` by raising a fake exception with `response = {"Error": {"Code": "PreconditionFailed"}}`, implements `Delimiter="/"` `CommonPrefixes`, and can corrupt one selected `get_object` response.

Write tests proving:

- `private_bucket` comes from a supplied parsed `pipeline/config/r2_layout.json`, never a public bucket or duplicated literal;
- publish lists the exact version/build prefix and refuses another SHA before any put;
- the absent archive is conditionally written before the absent manifest;
- each put is followed by a fresh download whose digest and size match the local object;
- `RemotePublication` is returned only after both objects verify;
- an archive-only interrupted prefix resumes by verifying the identical archive and publishing the manifest;
- identical complete objects are idempotent with no put;
- differing existing archive or manifest bytes are preserved and rejected;
- a precondition race downloads and accepts only identical bytes;
- corrupt round-trip bytes fail publication and do not publish the manifest;
- `resolve_sha` returns one exact direct SHA child, reports zero/multiple candidates, and honors a valid requested SHA only when present;
- download validates the manifest before requesting the archive, then verifies archive byte count/SHA in a fresh temporary path.

- [ ] **Step 2: Run the focused tests and observe RED**

Run:

```bash
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_app_store_archive_r2.py -v
```

Expected: collection fails because `r2_store.py` does not exist.

- [ ] **Step 3: Implement the environment/client boundary and private layout lookup**

Expose:

```python
def private_bucket(layout_path: Path) -> str:
    layout = json.loads(layout_path.read_text(encoding="utf-8"))
    bucket = layout.get("private_bucket")
    if not isinstance(bucket, str) or not bucket.strip():
        raise ArchiveStorageError("R2 layout has no private_bucket")
    return bucket

def client_from_environment():
    publish_r2.require_boto3()
    publish_r2.require_upload_environment()
    boto3 = import_module("boto3")
    return boto3.client(
        "s3",
        endpoint_url=os.environ["R2_S3_ENDPOINT"],
        aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
    )
```

Catch and wrap all client exceptions with operation/key labels only. Never include `str(exc)`, endpoint URLs, environment values, request headers, or response bodies in user-visible exception text.

- [ ] **Step 4: Implement conditional immutable publication and round trips**

For each local object, first try `get_object`; missing permits `put_object(Bucket=self.bucket, Key=key, Body=source, IfNoneMatch="*")`, existing requires complete byte equality. On a precondition failure, re-download and accept only byte equality. After either path, download again into a new file from `tempfile.mkstemp(dir=temporary_root)` and recompute digest and size. Publish the manifest only after the archive round trip succeeds.

List with `Prefix=f"{REMOTE_PREFIX}/{version}/{build}/"` and `Delimiter="/"`, following `IsTruncated` / `NextContinuationToken`. Accept only exact lowercase 40-hex direct children. Preserve and report every valid multiple-SHA candidate without selecting one.

- [ ] **Step 5: Run GREEN, refactor, and commit the R2 slice**

Run:

```bash
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_app_store_archive_r2.py -v
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_app_store_archive_validation.py pipeline/tests/test_app_store_archive_staging.py pipeline/tests/test_app_store_archive_r2.py -q
```

Expected: all tests pass. Commit:

```bash
git add pipeline/src/mt_pipeline/app_store_archive/r2_store.py pipeline/tests/app_store_archive_helpers.py pipeline/tests/test_app_store_archive_r2.py
git diff --cached --check
git commit -S -m "Publish App Store archives immutably"
```

Verify signature and status separately.

---

### Task 4: Publish/retrieve workflows and operator CLI

**Files:**

- Create: `pipeline/src/mt_pipeline/app_store_archive/workflow.py`
- Create: `pipeline/src/mt_pipeline/app_store_archive/cli.py`
- Create: `scripts/app-store-archive.py`
- Create: `pipeline/tests/test_app_store_archive_cli.py`
- Modify: `pipeline/src/mt_pipeline/app_store_archive/__init__.py`

**Interfaces:**

- Consumes: `inspect_archive`, `stage_archive`, `parse_manifest`, `R2ArchiveStore`, and injected command/client/clock/root dependencies.
- Produces: `WorkflowError(AppStoreArchiveError)`, `PublishResult(identity: ArchiveIdentity, local: LocalArtifact, remote: RemotePublication)`, `RetrieveResult(identity: ArchiveIdentity, destination: Path, archive_path: Path)`, `publish_archive(archive_path, repo_root, application_support_root, layout_path, client, captured_at, run) -> PublishResult`, `restore_and_validate(downloaded, destination, repo_root, run) -> RetrieveResult`, `retrieve_archive(version, build, destination, repo_root, layout_path, client, requested_sha, run) -> RetrieveResult`, and `main(argv: Sequence[str] | None = None) -> int`.

- [ ] **Step 1: Write RED workflow and CLI tests**

Patch only the package's injected boundaries, then invoke `cli.main(["publish", "--archive", str(archive)])` and the real script with `subprocess.run`. Prove publish:

1. inspects the source archive before local or R2 mutation;
2. stages the retained archive before remote publication;
3. prints exactly one readiness block only after `R2ArchiveStore.publish` returns:

```text
READY FOR APP STORE UPLOAD
version: 1.0
build: 1
git_sha: 1234567890abcdef1234567890abcdef12345678
local_archive: <absolute Application Support leaf>/MakingTracks.xcarchive
remote_prefix: s3://making-tracks-state/app-store-archives/1.0/1/1234567890abcdef1234567890abcdef12345678/
archive_sha256: <64 lowercase hex>
dsym_uuids: arm64=AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
```

Prove every earlier failure is nonzero and stdout lacks `READY FOR APP STORE UPLOAD`.

For retrieve, prove it resolves one SHA, downloads and validates the manifest/archive bytes, refuses an existing destination, extracts into a unique sibling with `ditto -x -k`, re-runs `inspect_archive`, compares version/build/SHA/bundle/app digest/dSYM UUIDs with the manifest, atomically renames the absent destination, and returns `<destination>/MakingTracks.xcarchive`. A post-extraction mismatch preserves the exact staging path and exits nonzero.

Set fake credential values containing recognizable sentinels, force failures from client creation, list, put, get, and CLI formatting, and assert neither stdout, stderr, nor `str(caught_exception)` contains any sentinel.

- [ ] **Step 2: Run the focused tests and observe RED**

Run:

```bash
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_app_store_archive_cli.py -v
```

Expected: collection fails because `workflow.py` and `cli.py` do not exist.

- [ ] **Step 3: Implement orchestration and retrieval revalidation**

Use these dependency-injectable signatures:

```python
def publish_archive(
    archive_path: Path,
    *,
    repo_root: Path,
    application_support_root: Path,
    layout_path: Path,
    client: object,
    captured_at: str,
    run: CommandRunner = run_command,
) -> PublishResult:
    identity = inspect_archive(archive_path, repo_root, run=run)
    local = stage_archive(identity, application_support_root, captured_at, run=run)
    store = R2ArchiveStore(client, private_bucket(layout_path))
    remote = store.publish(local)
    return PublishResult(identity=identity, local=local, remote=remote)

def retrieve_archive(
    version: str,
    build: str,
    destination: Path,
    *,
    repo_root: Path,
    layout_path: Path,
    client: object,
    requested_sha: str | None = None,
    run: CommandRunner = run_command,
) -> RetrieveResult:
    store = R2ArchiveStore(client, private_bucket(layout_path))
    sha = store.resolve_sha(version, build, requested_sha)
    with TemporaryDirectory(prefix="making-tracks-archive-download-") as temporary:
        downloaded = store.download(version, build, sha, Path(temporary))
        return restore_and_validate(
            downloaded,
            destination=destination,
            repo_root=repo_root,
            run=run,
        )
```

Production defaults belong in the CLI, not hidden inside tested workflows. Retrieval creates a sibling staging directory, downloads beneath a separate `TemporaryDirectory`, extracts with `ditto`, requires one top-level `MakingTracks.xcarchive`, re-inspects it, compares every manifest identity field, then atomically renames to the absent destination.

- [ ] **Step 4: Implement the thin CLI and stable redacted output**

The script contains only:

```python
#!/usr/bin/env python3
from mt_pipeline.app_store_archive.cli import main

if __name__ == "__main__":
    raise SystemExit(main())
```

`cli.main` defines required `publish --archive` and `retrieve --version --build --destination [--sha]` arguments. It resolves the repo root from the module location, the layout at `pipeline/config/r2_layout.json`, Application Support with `Path.home()`, and capture time with `datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")`. Catch only the package's expected archive exceptions, print `app-store-archive: <stable message>` to stderr, and return `1`; unexpected exceptions remain visible to tests and reviewers rather than being silently mislabeled.

- [ ] **Step 5: Run GREEN, the full Python suite, and commit the CLI slice**

Run:

```bash
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_app_store_archive_cli.py -v
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests -q
python3 -m py_compile scripts/app-store-archive.py pipeline/src/mt_pipeline/app_store_archive/*.py
```

Expected: all pipeline tests pass and every new module compiles. Commit:

```bash
git add pipeline/src/mt_pipeline/app_store_archive scripts/app-store-archive.py pipeline/tests/test_app_store_archive_cli.py
git diff --cached --check
git commit -S -m "Add App Store archive retention CLI"
```

Verify signature and status separately.

---

### Task 5: Release procedure and gate ownership boundary

**Files:**

- Create: `docs/app-store-release.md`
- Modify: `docs/ios-gate-ledger.md`
- Modify: `pipeline/tests/test_app_store_archive_cli.py`

**Interfaces:**

- Consumes: the exact `publish`/`retrieve` CLI and READY fields from Task 4.
- Produces: one operator checklist and one non-overlapping gate-ledger boundary; no new production API.

- [ ] **Step 1: Add RED CLI-help assertions for every documented operand**

Invoke the production parser and assert help exposes only:

```text
publish --archive ARCHIVE
retrieve --version VERSION --build BUILD --destination DESTINATION [--sha SHA]
```

Assert `delete`, `upload`, `export`, and App Store credential flags are rejected. Run the focused test and observe RED if the Task 4 parser exposes or omits any documented operand.

- [ ] **Step 2: Write the release checklist**

Create `docs/app-store-release.md` with exact commands through the existing 1Password boundary:

```bash
op run --env-file=.env.tpl -- uv run --project pipeline \
  python scripts/app-store-archive.py publish \
  --archive "/absolute/path/to/MakingTracks.xcarchive"

op run --env-file=.env.tpl -- uv run --project pipeline \
  python scripts/app-store-archive.py retrieve \
  --version 1.0 --build 1 \
  --destination "/absolute/caller-owned/recovery"
```

The checklist must require: archive the intended signed source state in Organizer; stop unless READY prints; upload the retained Application Support archive; record App Store Connect acceptance with version/build/SHA; retain remote TestFlight-only objects indefinitely; perform a fresh retrieve before deleting the exact local SHA leaf; never delete or overwrite R2 objects; escalate poisoned prefixes for reviewed exact-key infrastructure repair.

- [ ] **Step 3: Add the ledger ownership boundary without duplicating policy**

Immediately after `Local result-artifact retention`, add one paragraph stating that App Store `.xcarchive` retention is governed by `docs/app-store-release.md`, lives in caller-owned Application Support and private R2, never carries release-gate markers, and is never eligible for the gate's 24-hour pruning. Do not add release commands or restate the full retention checklist in the ledger.

- [ ] **Step 4: Verify docs/contracts and commit**

Run:

```bash
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_app_store_archive_cli.py -v
python3 scripts/lint_agent_law.py
git diff --check
```

Expected: CLI contract tests and law lint pass. Commit:

```bash
git add docs/app-store-release.md docs/ios-gate-ledger.md pipeline/tests/test_app_store_archive_cli.py
git diff --cached --check
git commit -S -m "Document App Store archive retention"
```

Verify signature and status separately.

---

### Task 6: Mutation teeth, independent reviews, and finishing gates

**Files:**

- Create: `docs/superpowers/reports/2026-08-07-app-store-archive-mutation-teeth.md`
- Modify: only files required by validated review findings

**Interfaces:**

- Consumes: the complete implementation and its named pytest tests.
- Produces: reviewable mutation evidence, green repository gates, signed remote commits, and a draft PR to `ios` for issue #549.

- [ ] **Step 1: Record one real failure/pass pair for every critical guard**

Create the report with a table containing `Guard`, `Production mutation`, `Targeted test`, `Observed RED`, `Restored GREEN`, and `Commit`. Apply one mutation at a time with `apply_patch`, run only the named test, record its assertion failure, restore the production line with `apply_patch`, rerun the same test, and record PASS. Cover at minimum:

1. allow symlink archive input;
2. replace exact dSYM tuple equality with presence-only acceptance;
3. allow a differing existing local leaf;
4. remove `IfNoneMatch="*"` from remote puts;
5. publish manifest before archive round-trip verification;
6. trust an ETag instead of fresh downloaded bytes;
7. skip restored app-binary/dSYM revalidation;
8. interpolate a caught client exception containing a credential sentinel.

After each restored GREEN, verify `git diff --check`. The final report contains outcomes, not secrets or raw credential-bearing exception output.

- [ ] **Step 2: Run the complete non-simulator verification set**

Run each command separately:

```bash
uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests -q
python3 -m py_compile scripts/app-store-archive.py pipeline/src/mt_pipeline/app_store_archive/*.py
python3 scripts/lint_agent_law.py
bash -n scripts/release-gate.sh scripts/sim-lock.sh scripts/sim-lock-tests.sh
shellcheck scripts/release-gate.sh scripts/sim-lock.sh scripts/sim-lock-tests.sh
./scripts/sim-lock-tests.sh
swift test --package-path ios
git diff --check
```

Expected: every command exits zero. If `swift test --package-path ios` rewrites `ios/Package.resolved`, restore only that known generated side effect with `apply_patch`, then prove the file matches `HEAD`.

- [ ] **Step 3: Commit and push the mutation report**

```bash
git add docs/superpowers/reports/2026-08-07-app-store-archive-mutation-teeth.md
git diff --cached --check
git commit -S -m "test: record archive retention mutation teeth"
git push origin HEAD
```

Verify the signed commit, clean worktree, and exact remote branch SHA in separate commands.

- [ ] **Step 4: Run the mandatory independent review gates**

Use the repository-required critics against the full `origin/ios...HEAD` range: spec compliance, code quality, test/mutation quality, security/privacy and secrets, and regression/UX relevance. Provide each critic the approved spec path, implementation plan path, exact diff range, and test evidence. Resolve every actionable finding test-first, commit each coherent repair, rerun affected suites, and repeat critics until all verdicts are unambiguously clean.

- [ ] **Step 5: Run the serialized iOS host gate on codex1**

Check the seat through the only simulator entry point:

```bash
./scripts/sim-lock.sh --seat codex1 --status
```

When free and planner scheduling permits, run:

```bash
./scripts/sim-lock.sh --seat codex1 ./scripts/release-gate.sh
```

Expected: Release build, unit tests, and UI tests pass. Report exact counts and retained result-bundle path. Do not use a copied UDID or any direct `simctl`/`xcodebuild` invocation.

- [ ] **Step 6: Rebase verification, push, and open the draft PR**

Fetch `origin/ios`, prove the branch remains derived from it, inspect the final range diff, rerun any gate invalidated by conflict resolution, and push. Open a draft PR targeting `ios` whose body includes issue #549, architecture and retention rationale, human-upload boundary, exact commands/results/counts, mutation report, security review, and local/remote ownership rules. Apply required labels, inspect the rendered PR and Actions checks, address review comments, and leave merge ownership with the planner.
