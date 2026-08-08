# App Store archive retention mutation teeth

This report records Task 6's deliberate, transient mutations at signed implementation
checkpoint `623a349b398ae197a397de60c5765569de24d057`. Each mutation was applied with
`apply_patch`, its focused pytest test was run, the exact production line was restored
with `apply_patch`, the same test was rerun, and `git diff --check` was green after
each restoration. No mutation remained in the worktree.

`uv` is unavailable on this host (`uv run ...`: exit 127), so the existing project
environment was used for the focused command equivalent:
`.venv/bin/python -m pytest <target> -q`. This changes only the runner wrapper, not
the test selection or interpreter environment.

| Guard | Production mutation | Targeted test | Observed RED | Restored GREEN | Commit |
| --- | --- | --- | --- | --- | --- |
| Real archive root | Allowed a symlink by removing the symlink predicate. | `test_symlink_archive_root_is_rejected_before_commands` | 1 failed: archive inspection accepted the symlink. | 1 passed | This report's signed commit |
| Exact dSYM tuple equality | Replaced tuple equality with non-empty presence acceptance. | `test_app_and_dsym_uuid_sets_must_match_exactly` | 2 failed: both differing UUID fixtures were accepted. | 2 passed | This report's signed commit |
| Existing local leaf | Returned an existing leaf without comparing candidate manifest/archive evidence. | `test_existing_different_packaged_archive_is_preserved_and_rejected` | 1 failed: differing leaf was accepted. | 1 passed | This report's signed commit |
| Immutable remote puts | Removed `IfNoneMatch="*"` from the object put. | `test_publish_conditionally_writes_archive_then_manifest_and_round_trips` | 1 failed: immutable write precondition was absent. | 1 passed | This report's signed commit |
| Manifest completion marker | Reordered publication to put the manifest before the archive's verified publication. | `test_publish_conditionally_writes_archive_then_manifest_and_round_trips` | 1 failed: object-put order was manifest before archive. | 1 passed | This report's signed commit |
| Fresh remote bytes | Made remote-object matching accept without downloading and hashing bytes. | `test_corrupt_archive_round_trip_keeps_publication_incomplete` | 1 failed: corrupt archive round trip was accepted. | 1 passed | This report's signed commit |
| Restored archive revalidation | Omitted manifest-to-restored-archive identity comparison after extraction. | `test_post_extraction_mismatch_preserves_staging_path` | 1 failed: a tampered restored binary was accepted. | 1 passed | This report's signed commit |
| Client-error redaction | Formatted a caught storage-client exception into the operator-visible upload error. | `test_client_operation_failures_are_redacted` | 1 failed, 2 passed: the put-path error was no longer redacted. | 3 passed | This report's signed commit |

The test suite's credential-redaction fixture was deliberately not reproduced in this
report. Its result above records only the redaction property and aggregate outcome.
