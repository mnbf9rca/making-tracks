# Validate AX Waits Scope Design

**Issue:** #417

**Status:** Ruled by planner. The five-physical-line horizon is fixed by this ruling; changing it requires a new ruling.

## Problem

`scripts/ios-test-shards.py validate-ax-waits` currently catches only a literal
`.buttons["..."]` existence wait followed on the immediately adjacent physical line by a
`label` or `value` assertion for the same button. Its name therefore claims more protection than
its implementation provides. A blank or comment line evades it, and equivalent `staticTexts` and
`switches` decoys remain outside its scope.

The current `ios` tree contains eight decoys in the widened scope: six same-selector
`staticTexts` existence/label pairs and two same-selector `switches` existence/value pairs. These
are appear-with-content checks: existence alone is not the state the test consumes.

## Ruled Design

The validator remains a bounded lexical source-policy check. It does not become a Swift parser.

1. Both wait and property patterns recognize `buttons`, `staticTexts`, and `switches`.
2. Selectors may be string literals or simple Swift identifiers. A finding requires the same
   element class and normalized selector on both statements.
3. A named constant fixes the lookahead at five physical lines. Its comment cites #417 and states
   that changing the horizon requires a new ruling.
4. Within that horizon the scanner skips blank lines and full-line `//` comments. It stops at the
   first substantive line, whether or not that line is a matching property assertion. Line-comment
   text never participates in query counting or balanced assertion matching.
5. A matching `label` or `value` assertion beginning on that first substantive line is reported
   against the wait line. The scanner reads a balanced `XCTAssertEqual` call so a direct assertion
   may span multiple lines; its first line still must fall inside the five-line horizon. There is no
   exemption syntax.
6. The scan counts supported element queries independently of findings and fails when that count is
   zero. This sanity floor distinguishes a clean source file from a scanner that no longer matches
   the source idiom at all.

This closes the specified gap-evasion while keeping findings local. Stopping at intervening code
prevents the checker from pairing unrelated statements merely because they occur nearby.

## Explicit Limitation

The lexical scanner does not perform local alias analysis. For example, it does not connect
`let button = app.buttons["x"]` to later `button.exists` and `button.label` statements. Supporting
that form would require a different ruled design. It also does not traverse a read-only
same-element statement such as `exists` or `isHittable` before the property assertion. Issue #631
owns both remaining classes. The scanner stops at an intervening `tap`:
`waitForExistence`; `tap`; assert-post-action-label is a legitimate action-effect assertion, not a
decoy, and must remain clean.

## Current-Site Conversion

All eight current findings are converted rather than exempted:

- Add `waitForElementLabel(_:identifier:in:)`, using the existing `AXValueWaiter` and
  `AXElementReadback.label` seams, and replace the six `staticTexts` existence/label pairs.
- Replace the `switches[showSaved]` and `switches[showHidden]` existence/value pairs with the existing
  `waitForElementValue(_:identifier:in:)` helper.

No product behavior, app accessibility contract, or production source changes. The change affects
test synchronization and its source-policy guard only.

## Failure Reporting

Validator output retains the source path, wait line, selector, and asserted property. Generic
label-wait exhaustion names the identifier, expected label, and final observed or missing state,
matching the existing value-wait diagnostic shape.

## Verification

Pytest fixtures prove:

- each of the three element classes is detected;
- simple variable selectors are detected;
- blank and full-line comment gaps are detected within the five-line horizon;
- intervening substantive code stops pairing;
- a property assertion beyond the ruled horizon is not paired;
- different element classes or selectors are not paired;
- multiline direct assertions and XCTest message/file/line overloads are detected;
- full-line comments neither count as supported queries nor act as wait anchors;
- a source with zero supported element queries fails the sanity floor;
- property-specific waits remain accepted.

The real UI-test source must pass `validate-ax-waits` after all eight conversions. The existing iOS
workflow invocation remains present. The iOS workflow adds `astral-sh/setup-uv` and runs only
`pipeline/tests/test_ios_test_shards.py` on both pull-request and manual-dispatch runs. Issue #630
owns the separately ruled question of full pipeline pytest coverage. Host verification follows
repository gate law; the PR evidence reports the local absence of `uv`/`pytest` honestly and relies
on the new focused CI step for these Python cases rather than installing tooling ad hoc.
