# Saved ON Candidate Panel v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build deterministic default-size and accessibility-size evidence that
compares the two ruled Saved ON fills and makes Deep Companion `#08483E` the
default winner.

**Architecture:** One self-contained responsive HTML document owns the
candidate data, SVG glyphs, exact frozen A8 pill geometry, measurement cards,
and `?mode=default|ax` layout switch. A temporary untracked Playwright helper
loads that source through the locally cached Playwright 1.62.0 Chromium,
asserts its DOM contract, and captures two exact `1540×980` DSF1 PNGs; the
design-system README publishes their renderer and digests.

**Tech Stack:** HTML, CSS, inline SVG, vanilla JavaScript, Playwright 1.62.0,
Chromium/headless shell 151.0.7922.34, POSIX `shasum`, macOS `sips`.

## Global Constraints

- Work only in `.worktrees/wp-526-saved-on-candidate-v2`; never modify the root
  checkout.
- The canonical design is
  `docs/superpowers/specs/2026-07-30-saved-on-candidate-v2-design.md`.
- Create exactly one tracked source:
  `docs/design/design-system/a8-saved-on-candidate-v2.html`.
- Create exactly two tracked captures:
  `docs/design/design-system/a8-saved-on-candidate-v2-default.png` and
  `docs/design/design-system/a8-saved-on-candidate-v2-ax.png`.
- Both captures are exactly `1540×980` at device scale factor 1 through
  Playwright-bundled Chromium/headless shell `151.0.7922.34`.
- Default pill geometry is `44px` minimum height, `15px/600` label,
  `17×17px` glyph, `6px` glyph/label gap, and `8px` between pills.
- AX pill geometry is `64px` minimum height, `23px` label, `25×25px` glyph,
  `8px` glyph/label gap, and a vertically stacked cluster.
- Every candidate shows a Saved OFF/ON state axis, a simultaneous
  Saved/Seen/Loved ON cluster, and all seven constraint checks.
- Saved OFF stays `#0A6B5C` ink on `#DEE9E0` with an outline bookmark and
  `5.1484:1` ink contrast.
- Saved ON uses `#FBFAF2` ink and a filled bookmark. Candidate 1 is
  `#0A6B5C`; Candidate 2 is `#08483E`.
- Seen ON stays `#FBFAF2` ink on `#0A6B5C` with a filled eye; Loved ON stays
  `#FBFAF2` ink on `#C4312B` with a filled heart.
- Candidate 2 is labelled the default winner. Candidate 1 is a fallback only
  if Candidate 2 reads as a confusing third semantic or fails a hard gate.
- `#D4EDE9` is retired from this role without prejudice and is not rendered as
  a candidate.
- Record Cool-shift Deep `#064852` and Softer Cool `#0B4D56` as considered,
  not presented, and dominated by Deep Companion on ink, Seen separation, and
  Loved separation; the former also imports a blue/water hue shift.
- The frozen `a8-r15-place-card.{html,png}` files remain byte-for-byte
  unchanged. The current PNG anchor is
  `7704a185ebb872ed61017db757a24c20be0a5c2870bde8b575007398972c733b`.
- Do not change `ios/`, scripts, workflows, tests, phase ledgers, or production
  tokens.

---

### Task 1: Build and contract-test the responsive evidence source

**Files:**

- Create: `docs/design/design-system/a8-saved-on-candidate-v2.html`
- Reference:
  `docs/design/design-system/a8-r15-place-card.html`
- Reference:
  `docs/superpowers/specs/2026-07-30-saved-on-candidate-v2-design.md`

**Interfaces:**

- Consumes: `?mode=default` or `?mode=ax`; absent/unknown values resolve to
  `default`.
- Produces: a `1540×980` document with `<html data-mode="default|ax">`, two
  `[data-candidate]` columns, two `[data-state-axis]` groups, two
  `[data-fully-lit]` groups, and fourteen `[data-check]` rows.
- Produces: exact metric text addressable by `data-candidate` identifier and
  `data-metric` name.

- [ ] **Step 1: Record the failing source contract**

  Run this before creating the HTML:

  ```bash
  test -f docs/design/design-system/a8-saved-on-candidate-v2.html
  ```

  Expected: exit 1 because the source does not exist.

- [ ] **Step 2: Create the single responsive source**

  Use the frozen A8 pill declarations and SVG paths directly from
  `a8-r15-place-card.html`; do not redraw or approximate them. Define the ruled
  values once:

  ```html
  <script>
    const candidates = Object.freeze([
      {
        id: "accent-reuse",
        name: "Accent reuse",
        fill: "#0A6B5C",
        hue: "170.7216°",
        hueDelta: "0.0000°",
        saturation: "82.9060%",
        lightness: "22.9412%",
        luminance: "0.113526",
        ink: "6.1330:1",
        off: "5.1484:1",
        seen: "1.0000:1",
        loved: "1.1684:1",
        status: "Fallback only"
      },
      {
        id: "deep-companion",
        name: "Deep Companion",
        fill: "#08483E",
        hue: "170.6250°",
        hueDelta: "−0.0966°",
        saturation: "80.0000%",
        lightness: "15.6863%",
        luminance: "0.050342",
        ink: "9.9950:1",
        off: "8.3903:1",
        seen: "1.6297:1",
        loved: "1.9042:1",
        status: "Default winner"
      }
    ]);

    const requestedMode = new URLSearchParams(location.search).get("mode");
    document.documentElement.dataset.mode =
      requestedMode === "ax" ? "ax" : "default";
  </script>
  ```

  Keep the rendered pill contract explicit:

  ```html
  <div class="state-axis" data-state-axis>
    <div class="state-pill saved-off" data-fact="saved" data-state="off">
      <svg class="state-glyph"><use href="#bookmark-outline"/></svg>
      <span>Saved</span>
    </div>
    <span class="axis-arrow" aria-hidden="true">→</span>
    <div class="state-pill saved-on" data-fact="saved" data-state="on">
      <svg class="state-glyph"><use href="#bookmark-fill"/></svg>
      <span>Saved</span>
    </div>
  </div>
  <div class="fully-lit" data-fully-lit
       aria-label="Saved, Seen, and Loved simultaneously on">
    <div class="state-pill saved-on" data-fact="saved" data-state="on">
      <svg class="state-glyph"><use href="#bookmark-fill"/></svg>
      <span>Saved</span>
    </div>
    <div class="state-pill seen-on" data-fact="seen" data-state="on">
      <svg class="state-glyph"><use href="#eye-fill"/></svg>
      <span>Seen</span>
    </div>
    <div class="state-pill loved-on" data-fact="loved" data-state="on">
      <svg class="state-glyph"><use href="#heart-fill"/></svg>
      <span>Loved</span>
    </div>
  </div>
  ```

  Render seven individually numbered checks per candidate: ink AA hard gate;
  versus OFF; versus Seen; versus Loved; OFF invariant hard gate; fully-lit
  cluster; independent state morphology hard gate. Give checks 1, 5, and 7
  `data-gate="hard"`. Put every published value in a named metric node, for
  example:

  ```html
  <div class="metric-row">
    <span>Fill</span>
    <strong data-metric="fill">#08483E</strong>
  </div>
  ```

  Use these metric names consistently:
  `fill`, `hue`, `hueDelta`, `saturation`, `lightness`, `luminance`, `ink`,
  `off`, `seen`, and `loved`.

  Apply the exact geometry with mode-scoped CSS:

  ```css
  .state-pill {
    min-height: 44px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    border-radius: 999px;
    font: 600 15px/1 -apple-system, BlinkMacSystemFont, "SF Pro Text",
      "Segoe UI", sans-serif;
  }
  .state-glyph { width: 17px; height: 17px; flex: 0 0 17px; }
  .fully-lit { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
  html[data-mode="ax"] .state-pill {
    min-height: 64px;
    gap: 8px;
    font-size: 23px;
  }
  html[data-mode="ax"] .state-glyph {
    width: 25px;
    height: 25px;
    flex-basis: 25px;
  }
  html[data-mode="ax"] .fully-lit {
    grid-template-columns: 1fr;
    gap: 8px;
  }
  ```

  Use a two-column packet that leaves every pill at native scale. Candidate 1
  must show `1.0000:1` as a prominent callout. Candidate 2 must show `DEFAULT
  WINNER` in the header and the exact reversal condition beneath its fully-lit
  cluster. State that its distinction comes from depth within the accent hue,
  and that the historical saturation band is context rather than a gate. Add a
  compact Taste-guesses note recording why `#064852` and `#0B4D56` are not
  presented. State that `#D4EDE9` is retired from Saved ON without prejudice
  and is not a candidate. Include renderer identity and mode in the packet
  header. Do not put an action or CTA in the packet.

- [ ] **Step 3: Write and run the DOM contract probe**

  Create `/private/tmp/wp526-panel-contract.cjs` as an untracked helper with
  this complete logic:

  ```javascript
  const assert = require("node:assert/strict");
  const path = require("node:path");
  const { pathToFileURL } = require("node:url");
  const { chromium } = require(
    "/Users/rob/.npm/_npx/e41f203b7505f1fb/node_modules/playwright"
  );
  const executablePath =
    "/Users/rob/Library/Caches/ms-playwright/chromium_headless_shell-1234/" +
    "chrome-headless-shell-mac-arm64/chrome-headless-shell";

  const root = process.argv[2];
  const source = path.join(
    root,
    "docs/design/design-system/a8-saved-on-candidate-v2.html"
  );
  const expected = {
    "accent-reuse": {
      fill: "#0A6B5C", hue: "170.7216°", hueDelta: "0.0000°",
      saturation: "82.9060%", lightness: "22.9412%",
      luminance: "0.113526", ink: "6.1330:1", off: "5.1484:1",
      seen: "1.0000:1", loved: "1.1684:1"
    },
    "deep-companion": {
      fill: "#08483E", hue: "170.6250°", hueDelta: "−0.0966°",
      saturation: "80.0000%", lightness: "15.6863%",
      luminance: "0.050342", ink: "9.9950:1", off: "8.3903:1",
      seen: "1.6297:1", loved: "1.9042:1"
    }
  };

  (async () => {
    const browser = await chromium.launch({ headless: true, executablePath });
    try {
      for (const mode of ["default", "ax"]) {
        const page = await browser.newPage({
          viewport: { width: 1540, height: 980 },
          deviceScaleFactor: 1
        });
        await page.goto(`${pathToFileURL(source).href}?mode=${mode}`);
        await page.evaluate(async () => { await document.fonts.ready; });
        assert.equal(
          await page.locator("html").getAttribute("data-mode"),
          mode
        );
        assert.equal(await page.locator("[data-candidate]").count(), 2);
        assert.equal(await page.locator("[data-state-axis]").count(), 2);
        assert.equal(await page.locator("[data-fully-lit]").count(), 2);
        assert.equal(await page.locator("[data-check]").count(), 14);
        assert.equal(await page.locator('[data-gate="hard"]').count(), 6);
        for (const [id, metrics] of Object.entries(expected)) {
          const card = page.locator(`[data-candidate="${id}"]`);
          assert.equal(await card.locator("[data-fully-lit] [data-state='on']").count(), 3);
          for (const [name, value] of Object.entries(metrics)) {
            assert.equal(
              (await card.locator(`[data-metric="${name}"]`).textContent()).trim(),
              value
            );
          }
        }
        const geometry = await page.locator(
          '[data-candidate="deep-companion"] [data-fully-lit] .state-pill'
        ).first().evaluate((node) => {
          const style = getComputedStyle(node);
          const glyph = node.querySelector(".state-glyph").getBoundingClientRect();
          return {
            height: node.getBoundingClientRect().height,
            fontSize: style.fontSize,
            fontWeight: style.fontWeight,
            gap: style.gap,
            glyph: [glyph.width, glyph.height]
          };
        });
        assert.deepEqual(
          geometry,
          mode === "default"
            ? { height: 44, fontSize: "15px", fontWeight: "600",
                gap: "6px", glyph: [17, 17] }
            : { height: 64, fontSize: "23px", fontWeight: "600",
                gap: "8px", glyph: [25, 25] }
        );
        assert.equal(
          await page.evaluate(() =>
            document.documentElement.scrollWidth === 1540 &&
            document.documentElement.scrollHeight === 980
          ),
          true
        );
        await page.close();
      }
    } finally {
      await browser.close();
    }
  })();
  ```

  Run:

  ```bash
  node /private/tmp/wp526-panel-contract.cjs "$(pwd -P)"
  ```

  Expected: exit 0 with no assertion output.

- [ ] **Step 4: Verify the source-only patch and commit**

  Run:

  ```bash
  git diff --check
  python3 scripts/lint_agent_law.py
  git diff --name-only
  ```

  Expected: only the new HTML plus the already-reviewed spec/plan documents;
  whitespace and law lint both pass.

  Commit only the HTML:

  ```bash
  git add docs/design/design-system/a8-saved-on-candidate-v2.html
  git commit -S -m "docs(design): add Saved ON candidate panel source"
  ```

---

### Task 2: Capture and prove both deterministic PNGs

**Files:**

- Create: `docs/design/design-system/a8-saved-on-candidate-v2-default.png`
- Create: `docs/design/design-system/a8-saved-on-candidate-v2-ax.png`
- Do not modify:
  `docs/design/design-system/a8-r15-place-card.html`
- Do not modify:
  `docs/design/design-system/a8-r15-place-card.png`

**Interfaces:**

- Consumes: the committed HTML from Task 1 and modes `default`, `ax`.
- Produces: two `1540×980` RGB PNGs plus two byte-identical untracked repeat
  captures.

- [ ] **Step 1: Confirm the sanctioned renderer before capture**

  Run:

  ```bash
  /Users/rob/Library/Caches/ms-playwright/chromium_headless_shell-1234/chrome-headless-shell-mac-arm64/chrome-headless-shell --version
  ```

  Expected: `Google Chrome for Testing 151.0.7922.34`.

- [ ] **Step 2: Create the untracked capture helper**

  Create `/private/tmp/wp526-panel-capture.cjs` with:

  ```javascript
  const assert = require("node:assert/strict");
  const path = require("node:path");
  const { pathToFileURL } = require("node:url");
  const { chromium } = require(
    "/Users/rob/.npm/_npx/e41f203b7505f1fb/node_modules/playwright"
  );
  const executablePath =
    "/Users/rob/Library/Caches/ms-playwright/chromium_headless_shell-1234/" +
    "chrome-headless-shell-mac-arm64/chrome-headless-shell";

  const [root, mode, output] = process.argv.slice(2);
  assert.ok(["default", "ax"].includes(mode));
  const source = path.join(
    root,
    "docs/design/design-system/a8-saved-on-candidate-v2.html"
  );

  (async () => {
    const browser = await chromium.launch({ headless: true, executablePath });
    try {
      const page = await browser.newPage({
        viewport: { width: 1540, height: 980 },
        deviceScaleFactor: 1,
        colorScheme: "light",
        reducedMotion: "reduce"
      });
      await page.goto(`${pathToFileURL(source).href}?mode=${mode}`);
      await page.evaluate(async () => { await document.fonts.ready; });
      assert.equal(
        await page.evaluate(() =>
          document.documentElement.scrollWidth === 1540 &&
          document.documentElement.scrollHeight === 980
        ),
        true
      );
      await page.screenshot({
        path: output,
        type: "png",
        fullPage: false,
        animations: "disabled"
      });
    } finally {
      await browser.close();
    }
  })();
  ```

- [ ] **Step 3: Capture each mode twice**

  Run:

  ```bash
  node /private/tmp/wp526-panel-capture.cjs "$(pwd -P)" default docs/design/design-system/a8-saved-on-candidate-v2-default.png
  node /private/tmp/wp526-panel-capture.cjs "$(pwd -P)" default /private/tmp/a8-saved-on-candidate-v2-default-repeat.png
  node /private/tmp/wp526-panel-capture.cjs "$(pwd -P)" ax docs/design/design-system/a8-saved-on-candidate-v2-ax.png
  node /private/tmp/wp526-panel-capture.cjs "$(pwd -P)" ax /private/tmp/a8-saved-on-candidate-v2-ax-repeat.png
  ```

  Expected: all four commands exit 0.

- [ ] **Step 4: Prove dimensions and byte determinism**

  Run:

  ```bash
  sips -g pixelWidth -g pixelHeight docs/design/design-system/a8-saved-on-candidate-v2-default.png
  sips -g pixelWidth -g pixelHeight docs/design/design-system/a8-saved-on-candidate-v2-ax.png
  cmp docs/design/design-system/a8-saved-on-candidate-v2-default.png /private/tmp/a8-saved-on-candidate-v2-default-repeat.png
  cmp docs/design/design-system/a8-saved-on-candidate-v2-ax.png /private/tmp/a8-saved-on-candidate-v2-ax-repeat.png
  shasum -a 256 docs/design/design-system/a8-saved-on-candidate-v2-default.png docs/design/design-system/a8-saved-on-candidate-v2-ax.png
  ```

  Expected: both width/height pairs are `1540`/`980`; both `cmp` commands exit
  0; record the two printed SHA-256 values verbatim for Task 3.

- [ ] **Step 5: Inspect both files at original resolution**

  Use the image viewer at original detail for each PNG. Verify:

  - both candidate columns are wholly visible with no clipping;
  - every fully-lit row shows Saved, Seen, and Loved simultaneously ON;
  - default pills are horizontal and exactly `44px` high;
  - AX clusters are vertical and every pill is exactly `64px` high;
  - Candidate 1's `1.0000:1` Seen result is prominent;
  - Candidate 2 is visibly the default winner;
  - all fourteen checks and the exact reversal condition are readable;
  - there is no CTA or rendered `#D4EDE9` candidate.

  If an inspection fails, edit only the HTML, rerun the Task 1 contract, repeat
  both captures, and re-run every check in this task.

---

### Task 3: Publish provenance, run the final evidence gate, and hand off

**Files:**

- Modify: `docs/design/design-system/README.md`
- Verify:
  `docs/design/design-system/a8-saved-on-candidate-v2.html`
- Verify:
  `docs/design/design-system/a8-saved-on-candidate-v2-default.png`
- Verify:
  `docs/design/design-system/a8-saved-on-candidate-v2-ax.png`

**Interfaces:**

- Consumes: the two exact SHA-256 values from Task 2.
- Produces: a discoverable implementation-evidence row with renderer,
  dimensions, repeat-capture result, default-winner rule, and frozen-anchor
  digest.

- [ ] **Step 1: Add the README evidence row**

  Under **Implementation evidence**, add a row naming
  `a8-saved-on-candidate-v2.html` and
  `a8-saved-on-candidate-v2-{default,ax}.png`. State:

  - the captures are exact `1540×980` DSF1;
  - each candidate includes Saved OFF/ON, simultaneous Saved/Seen/Loved ON,
    and all seven ruled checks at frozen A8 default or AX geometry;
  - Deep Companion `#08483E` is the default winner and accent reuse `#0A6B5C`
    is limited to the ruled fallback;
  - the renderer is Playwright-bundled Chromium/headless shell
    `151.0.7922.34`;
  - the default and AX repeat SHA-256 values are the literal 64-hex outputs
    printed in Task 2, labelled by mode;
  - frozen `a8-r15-place-card.png` remains unchanged at
    `7704a185ebb872ed61017db757a24c20be0a5c2870bde8b575007398972c733b`.

  Paste both literal digest values into the row; do not enter symbolic digest
  markers.

- [ ] **Step 2: Run the complete local evidence gate**

  Run:

  ```bash
  node /private/tmp/wp526-panel-contract.cjs "$(pwd -P)"
  cmp docs/design/design-system/a8-saved-on-candidate-v2-default.png /private/tmp/a8-saved-on-candidate-v2-default-repeat.png
  cmp docs/design/design-system/a8-saved-on-candidate-v2-ax.png /private/tmp/a8-saved-on-candidate-v2-ax-repeat.png
  test "$(shasum -a 256 docs/design/design-system/a8-r15-place-card.png | cut -d ' ' -f 1)" = "7704a185ebb872ed61017db757a24c20be0a5c2870bde8b575007398972c733b"
  git diff --check
  python3 scripts/lint_agent_law.py
  git diff --name-only origin/ios...HEAD
  ```

  Expected: every command exits 0. The changed-file list contains only:

  ```text
  docs/design/design-system/README.md
  docs/design/design-system/a8-saved-on-candidate-v2-ax.png
  docs/design/design-system/a8-saved-on-candidate-v2-default.png
  docs/design/design-system/a8-saved-on-candidate-v2.html
  docs/superpowers/plans/2026-07-30-saved-on-candidate-v2.md
  docs/superpowers/specs/2026-07-30-saved-on-candidate-v2-design.md
  ```

- [ ] **Step 3: Commit the capture packet intentionally**

  Stage only the README and two PNGs:

  ```bash
  git add docs/design/design-system/README.md docs/design/design-system/a8-saved-on-candidate-v2-default.png docs/design/design-system/a8-saved-on-candidate-v2-ax.png
  git commit -S -m "docs(design): capture Saved ON candidate evidence"
  ```

- [ ] **Step 4: Push and request exact-head review**

  Push the branch, then verify local and remote refs match:

  ```bash
  git push
  git rev-parse HEAD
  git rev-parse origin/wp-526-saved-on-candidate-v2
  git status --short --branch
  ```

  Send the reviewer the exact pushed SHA, source path, both PNG paths, both
  digests, frozen-anchor digest, renderer version, dimensions, DOM-contract
  result, and byte-identical repeat result on thread `wp/526/a8`. Request the
  promised checks: both digests/dimensions, renderer identity, three
  simultaneous ON pills per candidate, real pill geometry, all figures, and
  unchanged frozen A8 digest.

- [ ] **Step 5: Apply findings and finish the branch**

  For every finding, verify it against the spec, edit only in-scope
  documentation/static evidence, rerun the full Task 3 gate, recapture both
  PNGs after any HTML change, and send the new exact pushed SHA for re-review.
  After reviewer PASS, use `superpowers:verification-before-completion`, then
  `superpowers:finishing-a-development-branch` to open the PR into `ios` with
  the repository-required labels and hand merge authority to the designated
  owner.
