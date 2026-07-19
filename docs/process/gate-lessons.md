# Gate lessons — the critic checklist

Every rule here was earned by a defect that reached a gate and nearly shipped. `AGENTS.md` states the law in
one line ("a test has teeth only if neutering the code it guards makes it fail"). This is how to apply it.

Use it as the checklist when running the adversarial-review gate, and when writing tests in the first place.

---

## 1. Teeth

**Neuter the fix and confirm the test goes red.** If it stays green, the test is a false green. Assert on the
specific signal, not on "it threw something".

**A neuter that leaves the observed value unchanged proves nothing.** Before claiming a neuter reds a test,
run the neutered code and confirm the output actually differs. A re-derived ID that comes out identical, or a
uniform rescale that leaves ranking untouched, is not a neuter.

**Ranking tests must flip relative order.** A rescale preserves order, so a test that only checks values
passes a broken ranker.

**A top-k metric is ranking-blind once k ≥ n_labeled** — it degenerates to total-positives over
total-labelled, which is order-independent. Pin an interior k (k < n_labeled) or the tooth is dead. Verify on
the host: correct order at k must beat mis-ordered at k.

**Every strict comparison needs a test a loose comparison would fail.** For `is True`, `== x`, or identity
checks, include truthy-but-unequal cases (`1`, `"true"`) that must be rejected, plus a malformed-type case
that must raise the typed error rather than `AttributeError`.

---

## 2. The test must exercise the real path

**Grep for the fix on the executed path.** A fix that is defined but not wired is not a fix. Check that
nothing bypasses it — a second call site, an older helper, a direct call that skips the guard.

**Drive the production entry point, not the helper.** Testing `_validate_target` proves nothing about
`get_json` if `get_json` never calls it.

**Build the test input the way the stage builds it.** A hand-fed value the stage never produces gives a green
test over dead code. Construct inputs from the real config or database, not from what the function under test
happens to want.

**Prefer a critic that compiles or runs the code** over one that reads the plan text. A read-only critic
believes a claimed fix.

---

## 3. Traps that produce green-but-wrong

**A wrapping `except` must never re-inject the phrase the test asserts on.** If the outer handler formats
unrelated errors into a message containing the asserted string, the test passes with the guard disabled. Only
the real guard may emit the asserted phrase.

**Use a body-serving, non-looping mock.** A mock that loops (`evil → evil`) raises via loop detection even
with the guard neutered. The neutered path must *complete* so the test goes red.

**Refuse-on-bad-input gates must fail closed.** An absent, empty or undated artifact must refuse, not
silently pass. Any dev bypass is explicit and barred from the shippable path.

**Numeric validators must explicitly reject JSON booleans.** `isinstance(True, int)` is `True`, and lax
parsers coerce `true` to `1.0`, smuggling a maximum value past a guard. Reject `bool` and non-finite values
before validation, and test with `true` / `false` / `NaN` / `Infinity` on the real parse path.

**A metric can be degenerate on the real input distribution while a hand-crafted teeth test passes.** A
hand-set adversary proves the metric *can* fire, not that it fires on real inputs. Prove discrimination per
unit: a maximally-bad input must fail and a maximally-good one must pass. If a probe cannot separate them,
it is predetermined — drop it.

---

## 4. Contracts and invariants

**Never hand-roll a validator a frozen contract already exports.** Import it. A local re-implementation
under-validates, and fixtures built to satisfy the copy may be invalid under the real one. Add a drift guard:
a value the real validator rejects must be handled as rejected.

**A fingerprint must cover every field the consuming stage reads, and be neutered per field.** Mutate each
input in turn, not one representative. Fixing one omission does not complete it — prove completeness with a
meta-test asserting the stage's reads are a subset of the fingerprinted inputs, so a new unfingerprinted read
fails CI.

**A load-bearing invariant needs an enforcement point, not prose.** `try`/`finally` plus a neuter test, not a
comment saying it holds.

**A budget on one representation does not bound another.** A cap on uncompressed bytes says nothing about the
compressed cap the next stage enforces.

**Adding a field to a frozen `additionalProperties: false` schema is not backward-safe.** An old pinned
reader rejects the unknown key. If the field carries legally-required data, bump `min_reader_version` so a
stale reader refuses rather than shipping without it.

**A separator character inside a field value collides delimiter-joined keys.** Encode each component, or hash
a canonical serialisation. Pin a test with a real hostile value, not a toy one.

---

## 5. Native and bridged code

**Verify the Swift-imported signature from the header, not the Objective-C selector and not the docs.**
`NS_SWIFT_NAME` changes the imported name entirely. A delegate method with the wrong label compiles clean,
is never called, and looks done. Confirming the selector exists is not confirming what Swift calls it.

**Find the host-testable seam even inside a simulator-gated work package.** Pure style, expression and matrix
generation can be `swift test`ed with no simulator. Single-source the load-bearing logic so only cosmetic
constants can drift between the host-tested path and the live one.

**Do not oversell what a host test proves.** A same-module evaluator asserting generated output matches its
own expectation proves self-consistency, not that it matches the real engine. State the split and gate a
read-back for the untestable half.

---

## 6. Gate conduct

**A zero-survivor gate is not licence to fold nothing.** Re-check the verify stage's dismissals against the
tree before accepting them.

**Re-ground against the current tree, not the commit you branched from.** With parallel merges, a doc's
`file:line` citations and its "not built yet" claims go stale while it is being written. Fetch and re-check
before opening the PR.

**Where implementation and design diverge, flag it.** Do not silently conform the doc to the code.

**Before rebasing an old branch, run `git diff origin/<target>..branch`.** A large-deletion diff means the
branch is stale and would regress shipped work. Argue to close it rather than rebasing.

**A hash proves delivery integrity, never content safety.** An object that verifies is the object we
published, not an object that is safe.
