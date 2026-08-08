# App Store archive retention

Use this checklist for every archive uploaded to App Store Connect, including builds that remain
TestFlight-only. The retention tool publishes immutable recovery artifacts; Xcode Organizer remains the
only place for signing, validation, upload, review submission, and release promotion.

## Publish before uploading

1. Confirm the intended signed source state and commit are checked out. Create the release archive from
   that state with Xcode Organizer, and do not substitute an older Organizer archive.
2. From the repository root, publish that exact `.xcarchive` through the 1Password environment boundary:

   ```bash
   op run --env-file=.env.tpl -- uv run --project pipeline \
     python scripts/app-store-archive.py publish \
     --archive "/absolute/path/to/MakingTracks.xcarchive"
   ```

3. Stop unless the command exits successfully and prints `READY FOR APP STORE UPLOAD`. Record its
   `version`, `build`, full `git_sha`, `local_archive`, `remote_prefix`, `archive_sha256`, and
   `dsym_uuids` fields with the release record.

   Long local copy/ZIP and R2 upload/download work reports liveness only on stderr: `PHASE START`, then
   every 30 seconds at most `PHASE HEARTBEAT ... processed=<done>/<total> rate=<bytes>/s elapsed=<seconds>s`,
   and `PHASE DONE`. These progress lines never replace or alter the stdout readiness block.
4. Open the exact archive named by `local_archive`—the retained copy under
   `$HOME/Library/Application Support/making-tracks-releases/archives/<version>/<build>/<full-sha>/`—in
   Xcode Organizer and upload that copy. Do not upload the original Organizer-path archive after
   publication.
5. When App Store Connect accepts the upload, record the accepted version, build, and full Git SHA in
   the release record. Acceptance does not shorten retention: private R2 objects for accepted,
   rejected, expired, and TestFlight-only builds are retained indefinitely.

The tool reads R2 credentials only from the `op run --env-file=.env.tpl` environment. It has no App
Store credential flags and does not perform the Organizer upload.

## Retrieve and retire a local copy

Use an absent, caller-owned destination for a fresh recovery:

```bash
op run --env-file=.env.tpl -- uv run --project pipeline \
  python scripts/app-store-archive.py retrieve \
  --version 1.0 --build 1 \
  --destination "/absolute/caller-owned/recovery"
```

If more than one retained SHA exists for the version/build pair, rerun with the recorded full SHA as
`--sha <full-sha>`. Treat recovery as successful only when the command prints
`RESTORED APP STORE ARCHIVE` and the reported version, build, and `git_sha` match the release record.

Delete a local retained archive only after both conditions hold:

- App Store Connect accepted that exact version/build/SHA; and
- a new retrieve of that exact SHA completed successfully.

Then remove only the exact local SHA leaf beneath
`$HOME/Library/Application Support/making-tracks-releases/archives/<version>/<build>/<full-sha>/`.
Never bulk-prune this tree, and never delete or overwrite private R2 objects.

## Poisoned or conflicting remote prefixes

If publication or retrieval reports an immutable-key conflict, unexpected object, digest mismatch, or
corrupt manifest, stop. Preserve the command output and exact `remote_prefix`, and escalate it for a
reviewed infrastructure repair scoped to the identified exact R2 keys. The operator CLI intentionally
has no overwrite or delete command; do not improvise one or repair a prefix broadly.
