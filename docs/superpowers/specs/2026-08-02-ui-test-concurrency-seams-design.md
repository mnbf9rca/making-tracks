# UI-Test Concurrency Seams Design

**Issue:** #607
**Prerequisite for:** #600
**Scope:** UI-test harness only; no app or product-behaviour change

## Problem

Issue #600's cap-2 measurements exposed two independent harness races.

Both gates in repetition 1 reached the custom-list root, created the named list, and then exhausted the generic five-swipe helper before the new row became hittable. The helper returned only a Boolean, so failure output did not preserve whether the row was missing or merely present but not hittable.

In repetition 2, one gate exported `place-card-r15-ax-saved-loved.png` as zero bytes while the concurrent gate passed the same test. Screenshot and measurement exports share `/private/tmp/making-tracks-artifacts` unless their logical name matches one of three prefixes. The place-card R15 names do not match that allowlist, so concurrent gates can truncate and inspect the same pathname.

## Chosen Design

### Artifact directory selection

Introduce a pure selector that accepts an optional simulator identity and returns the artifact directory. Every artifact uses `/private/tmp/making-tracks-artifacts.<simulator-id>` whenever a non-empty identity is available. Runtime identity keeps the existing precedence: `SIMULATOR_UDID`, then `MT_SIM_LOCK_UDID`. If neither is present, exports deliberately retain the documented single-process fallback `/private/tmp/making-tracks-artifacts`.

There is no filename-prefix allowlist. Directory isolation is an execution property, not an artifact-name property, so new forced exports become safe by default.

### Bounded condition-driven scrolling

Introduce a closure-driven bounded helper whose observation is one of `missing`, `presentNotHittable`, or `hittable`. It samples before scrolling, performs at most the supplied number of scrolls, stops immediately on `hittable`, and returns the attempt count plus final observation.

The custom-list root-row path uses a bound of ten scrolls. Five was empirically insufficient under cap-2 load; ten remains a strict bound while allowing the dynamically inserted row to settle. Exhaustion names the row predicate, the bound, and the final observation, and links the cap-2 evidence in #600. There are no sleeps or unbounded retries.

## Tests and Failure Semantics

Deterministic helper tests prove:

- two simulator identities select different directories;
- nil and empty identities select the documented fallback;
- an already-hittable element performs zero scrolls;
- a later hittable observation succeeds within the bound;
- exhaustion performs exactly the bound and preserves the final observation.

The focused integration gate runs the custom-list test and the place-card morphology export test. Mutation evidence must show the selector tests fail if simulator scoping is removed and the scroll tests fail if the bound is not enforced or a non-hittable observation is accepted.

## Rejected Alternatives

- Adding the R15 filename prefix would leave every future export vulnerable until manually enrolled.
- Randomized filenames would prevent deterministic evidence lookup and would not express ownership by simulator.
- Atomic screenshot writes alone would still let one gate overwrite another gate's evidence.
- Increasing the generic helper's blind loop would retain opaque failure output and change unrelated call sites.
- Fixed sleeps and retry-until-success loops do not observe the required state and obscure real failures.

## Delivery

The change ships in its own branch and draft PR into `ios`. It requires RED/GREEN helper evidence, focused integration tests, the host Swift suite, a solo codex3 full gate, independent AMQ review, and Sourcery review. After merge, #600 restarts cap-2 at repetition 1 with no credit carried from the paused matrix.
