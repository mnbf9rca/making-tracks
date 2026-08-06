# Main source guard repository identity

Issue: [#464](https://github.com/mnbf9rca/making-tracks/issues/464)

## Problem

`.github/workflows/main-source-guard.yml` accepts a pull request to `main` when its branch name is
`develop` or `ios`. A fork can use either name, so branch identity alone does not prove that the
promotion came from this repository.

The required invariant is exact repository identity:

```text
github.event.pull_request.head.repo.full_name == github.repository
```

Repository identity is the outer trust boundary. The branch allowlist is meaningful only after that
boundary has passed.

## Design

Keep the existing inline guard step. Bind the pull request head repository and the current repository
through the step's `env` block, alongside `HEAD_REF`. The shell script must compare the two repository
values first and exit non-zero when they differ. Only a same-repository pull request may proceed to the
existing `develop|ios` branch check.

This preserves the workflow's explicit fail-closed behavior. The repository mismatch is a failed step,
not a skipped job, so a fork cannot satisfy the guard by causing its enforcement job to be skipped.

No reusable script or helper is introduced. The guard is a single-use, XS workflow rule, and extracting
it would add indirection without another consumer.

## Failure behavior

- A fork branch named `develop` or `ios` fails on repository identity before branch evaluation.
- A same-repository branch named `develop` or `ios` passes.
- Any other same-repository branch fails the existing branch allowlist.
- The rejection message identifies the repository mismatch without interpolating repository data into
  executable shell syntax; GitHub context values enter only through environment variables.

## Regression test

Add a pytest regression that reads the production workflow rather than a copied helper. It will:

1. Pin the exact GitHub-context-to-environment bindings for the head and base repository names.
2. Extract the workflow's actual inline `run` block.
3. Execute that block with a matrix covering allowed same-repository promotions, fork branches using both
   allowed names, and a disallowed same-repository branch.
4. Assert exit status and the ordering signal: a fork with an otherwise allowed branch is rejected for
   repository identity.

The RED state is the fork matrix passing against the current workflow. The GREEN state is the same matrix
passing after the minimal guard change. Teeth are proved by neutering the repository comparison and
observing the fork cases return to RED.

## Alternatives rejected

- Extract a dedicated shell script: testable, but needless indirection for one short workflow guard.
- Put repository equality in a job-level `if`: a mismatch skips enforcement instead of explicitly failing,
  which is the wrong semantic for a source guard.

## Scope

This change touches only the workflow, its regression test, and task documentation. It does not change app,
pipeline, contract, or simulator behavior, and it requires no simulator gate.
