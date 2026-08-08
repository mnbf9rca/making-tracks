# Widen Validate AX Waits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `validate-ax-waits` honestly cover direct button, static-text, and switch existence/property decoys across the ruled five-line gap, convert all eight current decoys, and execute the checker tests in iOS CI.

**Architecture:** Keep the validator a bounded lexical scan over Swift source. A query-count sanity floor makes total scanner blindness fail loudly; the scanner skips blank and full-line `//` comments but stops at the first substantive statement. Existing AX readback/waiter seams provide property-specific synchronization in the UI tests.

**Tech Stack:** Python 3, `re`, pytest 8+, GitHub Actions, `uv`, Swift/XCTest/XCUITest.

## Global Constraints

- The lookahead is exactly five physical lines, recorded in a named constant with #417 provenance; changing it requires a new ruling.
- Supported element classes are exactly `buttons`, `staticTexts`, and `switches`.
- Supported selectors are string literals and simple Swift identifiers.
- No exemption syntax.
- Stop at the first substantive line; do not traverse `tap` or attempt alias analysis. Issue #631 owns the remaining classes.
- Run only `pipeline/tests/test_ios_test_shards.py` in the new CI step. Issue #630 owns full pipeline pytest coverage.
- Do not install `uv` or pytest ad hoc on the host.

---

### Task 1: Pin the widened scanner and CI contract

**Files:**
- Modify: `pipeline/tests/test_ios_test_shards.py`

**Interfaces:**
- Consumes: CLI `python3 scripts/ios-test-shards.py validate-ax-waits --source <path>`.
- Produces: regression coverage for the three element classes, simple-variable selectors, the ruled gap, stop semantics, horizon, sanity floor, and focused workflow invocation.

- [ ] **Step 1: Add failing scanner cases**

Add individual tests that write Swift fixtures and invoke `_run("validate-ax-waits", ...)`:

```python
def test_decoy_accessibility_wait_validation_flags_static_text_after_comment_gap(tmp_path):
    source = tmp_path / "UITests.swift"
    source.write_text(
        '''
        XCTAssertTrue(app.staticTexts["lists.detail.progress"].waitForExistence(timeout: 5))

        // Content arrives after existence.
        XCTAssertEqual(app.staticTexts["lists.detail.progress"].label, "all seen")
        ''',
        encoding="utf-8",
    )
    result = _run("validate-ax-waits", "--source", str(source))
    assert result.returncode == 1
    assert "lists.detail.progress" in result.stderr


def test_decoy_accessibility_wait_validation_flags_simple_variable_switch_selector(tmp_path):
    source = tmp_path / "UITests.swift"
    source.write_text(
        '''
        XCTAssertTrue(app.switches[showSaved].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches[showSaved].value as? String, "1")
        ''',
        encoding="utf-8",
    )
    result = _run("validate-ax-waits", "--source", str(source))
    assert result.returncode == 1
    assert "showSaved" in result.stderr
```

Add sibling cases proving: an assertion at physical line +5 is detected; +6 is clean; intervening substantive code is clean; different element class/selector is clean; zero supported queries fails with a dedicated diagnostic. Update the existing property-specific-wait clean fixture to contain one direct supported non-decoy query so it clears the sanity floor.

Use these exact fixture shapes:

```python
def test_decoy_accessibility_wait_validation_detects_fifth_physical_line(tmp_path):
    source = tmp_path / "UITests.swift"
    source.write_text(
        'XCTAssertTrue(app.buttons["x"].waitForExistence(timeout: 5))\n\n// one\n// two\n// three\nXCTAssertEqual(app.buttons["x"].label, "Y")\n',
        encoding="utf-8",
    )
    assert _run("validate-ax-waits", "--source", str(source)).returncode == 1


def test_decoy_accessibility_wait_validation_stops_beyond_fifth_physical_line(tmp_path):
    source = tmp_path / "UITests.swift"
    source.write_text(
        'XCTAssertTrue(app.buttons["x"].waitForExistence(timeout: 5))\n\n// one\n// two\n// three\n// four\nXCTAssertEqual(app.buttons["x"].label, "Y")\n',
        encoding="utf-8",
    )
    assert _run("validate-ax-waits", "--source", str(source)).returncode == 0


def test_decoy_accessibility_wait_validation_stops_at_substantive_line(tmp_path):
    source = tmp_path / "UITests.swift"
    source.write_text(
        'XCTAssertTrue(app.buttons["x"].waitForExistence(timeout: 5))\napp.buttons["x"].tap()\nXCTAssertEqual(app.buttons["x"].label, "Y")\n',
        encoding="utf-8",
    )
    assert _run("validate-ax-waits", "--source", str(source)).returncode == 0


def test_decoy_accessibility_wait_validation_requires_same_element_and_selector(tmp_path):
    source = tmp_path / "UITests.swift"
    source.write_text(
        'XCTAssertTrue(app.buttons["x"].waitForExistence(timeout: 5))\nXCTAssertEqual(app.staticTexts["x"].label, "Y")\n',
        encoding="utf-8",
    )
    assert _run("validate-ax-waits", "--source", str(source)).returncode == 0


def test_decoy_accessibility_wait_validation_fails_when_scanner_matches_no_queries(tmp_path):
    source = tmp_path / "UITests.swift"
    source.write_text('XCTAssertTrue(waitForButtonLabel("Y", identifier: "x", in: app))\n', encoding="utf-8")
    result = _run("validate-ax-waits", "--source", str(source))
    assert result.returncode == 1
    assert "matched no supported accessibility queries" in result.stderr
```

- [ ] **Step 2: Add a failing workflow-contract case**

```python
def test_ios_gate_runs_ax_wait_validation_and_focused_pytest():
    workflow = (REPO_ROOT / ".github" / "workflows" / "ios-gate.yml").read_text(encoding="utf-8")
    assert "python3 scripts/ios-test-shards.py validate-ax-waits" in workflow
    assert "astral-sh/setup-uv@v9.0.0" in workflow
    assert "pytest pipeline/tests/test_ios_test_shards.py" in workflow
```

- [ ] **Step 3: Execute the new tests directly to verify RED without installing pytest**

Run this import harness, listing every new `tmp_path` test in `test_names`:

```bash
python3 -c 'import importlib.util,tempfile; from pathlib import Path; p=Path("pipeline/tests/test_ios_test_shards.py"); s=importlib.util.spec_from_file_location("test_ios_test_shards",p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); test_names=[name for name in dir(m) if name.startswith("test_decoy_accessibility_wait_validation_")]; [getattr(m,name)(Path(tempfile.mkdtemp())) for name in test_names]'
python3 -c 'import importlib.util; from pathlib import Path; p=Path("pipeline/tests/test_ios_test_shards.py"); s=importlib.util.spec_from_file_location("test_ios_test_shards",p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); m.test_ios_gate_runs_ax_wait_validation_and_focused_pytest()'
```

Expected: scanner cases fail because static texts, switches, and gaps are not detected; the workflow case fails because setup-uv/focused pytest are absent. Record these assertion failures as RED evidence. Do not treat `python3 -m pytest` failing to import pytest as RED.

### Task 2: Implement the bounded scan and focused CI executor

**Files:**
- Modify: `scripts/ios-test-shards.py`
- Modify: `.github/workflows/ios-gate.yml`
- Test: `pipeline/tests/test_ios_test_shards.py`

**Interfaces:**
- Produces: `accessibility_wait_scan(source: Path) -> tuple[int, list[tuple[int, str, str]]]` where the integer is the supported-query count.
- Produces: CI step `uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_ios_test_shards.py`.

- [ ] **Step 1: Implement the minimal scanner**

Use shared patterns for element class and selector, plus the ruled constant:

```python
# Ruled in #417: widening this five-physical-line horizon requires a new ruling.
AX_WAIT_LOOKAHEAD_PHYSICAL_LINES = 5
AX_ELEMENT_PATTERN = r"buttons|staticTexts|switches"
AX_SELECTOR_PATTERN = r'(?:"[^"\\]+"|[A-Za-z_][A-Za-z0-9_]*)'
```

Count `AX_ELEMENT_QUERY_RE` matches independently. For every direct supported `waitForExistence`, inspect at most the next five physical lines; skip blank and full-line `//` comments; inspect only the first substantive line; require matching element class and selector; then report `label`/`value` or stop clean. If the query count is zero, `command_validate_ax_waits` returns an error before reporting a clean scan.

Add a nearby limitation comment naming #631 and stating that aliases, no-wait assertions, and read-only continuation are outside this wait-anchored lexical check.

- [ ] **Step 2: Add the focused workflow steps**

Immediately after checkout in the iOS gate job:

```yaml
      - uses: astral-sh/setup-uv@v9.0.0

      - name: Test iOS shard tooling
        run: uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_ios_test_shards.py
```

The step has no event guard, so it runs on both `pull_request` and `workflow_dispatch`. Keep the existing manual-dispatch `validate-ax-waits` invocation unchanged.

- [ ] **Step 3: Re-run the direct test harness to verify GREEN**

Expected: every new test function returns normally. Also run `python3 scripts/ios-test-shards.py validate-ax-waits --source ios/App/UITests/MakingTracksCoreLoopUITests.swift`; expected: exit 1 with exactly eight findings. This is the RED proof for Task 3.

- [ ] **Step 4: Commit the scanner and CI contract**

```bash
git add pipeline/tests/test_ios_test_shards.py scripts/ios-test-shards.py .github/workflows/ios-gate.yml
git commit -m "Widen accessibility wait validation"
```

### Task 3: Convert every current decoy to a property wait

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Produces: `waitForElementLabel(_ label: String, identifier: String, in app: XCUIApplication) -> Bool`.
- Consumes: existing `AXValueWaiter.wait`, `AXElementReadback.label`, and `waitForElementValue`.

- [ ] **Step 1: Add the generic label helper**

Place beside `waitForElementValue`:

```swift
private func waitForElementLabel(_ label: String, identifier: String, in app: XCUIApplication) -> Bool {
    let result = AXValueWaiter.wait(expected: label, timeout: 10) {
        AXElementReadback.label(for: identifier) {
            let current = element(identifier: $0, in: app)
            return (exists: current.exists, value: { current.label })
        }
    }
    if !result.matched {
        XCTFail("Expected \(identifier) label \(label), got \(result.observed ?? \"missing element\")")
        return false
    }
    return true
}
```

- [ ] **Step 2: Replace all eight scanner findings**

Replace each `staticTexts` existence/label pair with one `XCTAssertTrue(waitForElementLabel(...))` call, preserving exact expected strings and app instances. Replace the `switches[showSaved]` and `switches[showHidden]` existence/value pairs with the matching `waitForElementValue` assertions.

- [ ] **Step 3: Verify the real source is GREEN**

Run:

```bash
python3 scripts/ios-test-shards.py validate-ax-waits --source ios/App/UITests/MakingTracksCoreLoopUITests.swift
```

Expected: `accessibility wait guard found no decoys` and exit 0. Confirm the widened scanner reported exactly eight before these edits; otherwise stop and reconcile the current tree.

- [ ] **Step 4: Commit the conversions**

```bash
git add ios/App/UITests/MakingTracksCoreLoopUITests.swift
git commit -m "Synchronize accessibility property assertions"
```

### Task 4: Verify and hand off

**Files:**
- Verify: every file listed in Tasks 1–3.

**Interfaces:**
- Produces: exact test/gate evidence for PR #417 and follow-up links #630/#631.

- [ ] **Step 1: Run static verification**

Run `python3 -m compileall -q scripts/ios-test-shards.py`, `python3 scripts/lint_agent_law.py`, `git diff --check`, and the validator against the real UI-test source. Verify `.github/workflows/ios-gate.yml` still contains both the validator and focused pytest commands.

- [ ] **Step 2: Run available host tests and required iOS gates**

Do not install missing Python tooling ad hoc. Run the repository-required host Swift tests and the simulator gate through `./scripts/sim-lock.sh --seat codex3 ...`, capturing actual counts, warnings, result path, and final FREE status. The new focused pytest cases must execute in CI before merge eligibility.

- [ ] **Step 3: Run adversarial review**

Request distinct spec/correctness, test-teeth, and workflow/safety lenses. Require reviewers to challenge the five-line boundary, sanity-floor honesty, exactly eight conversions, workflow trigger scope, and false-positive behavior around post-action assertions. Fix every surviving finding test-first.

- [ ] **Step 4: Re-ground and publish**

Fetch `origin/ios`, verify ancestry and two-dot diff, push the branch, open the PR ready into `ios`, and apply `sourcery-review`, `track-b-ios`, and `wp`. The PR body links #417, #630, and #631 and reports the local pytest environment limitation plus live CI results. Do not merge; planner retains merge ownership.
