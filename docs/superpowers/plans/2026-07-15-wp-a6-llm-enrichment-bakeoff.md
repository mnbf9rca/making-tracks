# WP-A6 (LLM Enrichment — Provider Abstraction + Curiosity Bake-off) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The LLM enrichment layer as a **METHOD for choosing a model, not a chosen model** — a provider abstraction that runs the *identical* curiosity task on **both** Modal (open-weight) and OpenRouter (hosted), an R2-cache keyed `(task_id, model, prompt_version, input_hash)` with schema-validation **on read**, a **cost model computed from real token counts** (keyless), and a **model bake-off that RIDES ON WP-A5's frozen eval seam** — each candidate model's curiosity value is written into A5's `llm_curiosity` slot and scored by A5's own `precision@k`, divided by measured cost → a **quality-per-dollar matrix** that decides empirically whether the LLM signal earns its weight (§5.2).

**Architecture:** A new `mt_pipeline.llm` package modelled on Rob's `trader` LLM layer (github.com/mnbf9rca/trader `aihedgefund/llm/`): a `Provider` **Protocol** (`acomplete`/`acomplete_batch`, capability flags, cost-returning `shutdown`) with `ModalProvider` (lazy single-`app.run()` session, GPU-second cost attribution), `OpenRouterProvider` (hosted, usage×pricing), and a deterministic keyless `FakeProvider` that drives the **entire** harness with no credentials. The curiosity task renders `name + summary + tags` into a **delimited** prompt (§5.5), and its output is a schema-validated `CuriosityResult` (`curiosity ∈ [0,1]`). The bake-off imports A5's `rescore`/`metrics`/`GoldenRow` **unchanged** (consume-don't-reinvent) — it never re-implements scoring. **Key-gate:** every layer except the *live* provider RPC is keyless and runnable now; only calling real Modal/OpenRouter is blocked on Rob's credentials.

**Tech Stack:** Python 3.11+ (`mt_pipeline`), `pydantic` (frozen models, mirroring trader), `jsonschema` (2020-12, validate-on-read), a tokenizer for counting (`tiktoken`/HF `tokenizers`, or the byte-bounded upper estimate as a keyless fallback), `pytest`. Modal / OpenRouter SDKs are **import-gated** (only imported inside their provider module, never at package import) so the keyless path never needs them installed.

## Global Constraints

- **The design is a METHOD, not a model pick.** A6 chooses NO model and hard-codes no winner. It delivers the abstraction + the bake-off + the cost model; the *winner* is whatever the bake-off's quality-per-dollar matrix shows on real labels. "We haven't even chosen a model — HOW?" is answered by the harness, not by a constant.
- **Run the IDENTICAL task on BOTH Modal (open-weight) AND OpenRouter (hosted) — the bake-off substrate.** The `Provider` Protocol is the seam: `bakeoff` and `curiosity` depend on the Protocol, never on a concrete provider (mirrors trader's `LlmClient depends on the protocol, not concrete provider classes`). Swapping Modal↔OpenRouter↔Fake is a constructor change, nothing else.
- **RIDE ON A5's frozen seam — import it, never re-implement it (consume-don't-reinvent; the A5/place_id lesson).** The bake-off writes each model's curiosity into A5's `GoldenRow.signals["llm_curiosity"]` and scores it with A5's `rescore.rescore(..., llm_on=True)` + `metrics.precision_at_k` — the exact seam A5 froze (arbitrary signal column + on/off toggle + full breakdown). Precision-**lift** = `precision@k(with model curiosity)` − `precision@k(A4-only, llm_on=False)`. A re-implemented scorer would make the bake-off lie (the same failure the A5 plan forbids for `composite.score`).
- **Cache keyed `(task_id, model, prompt_version, input_hash)` — task_id is LOAD-BEARING (§5.2).** curiosity/blurb/category consume near-identical input; without `task_id` a same-shape output collides silently (a category label shipping in the blurb field would pass schema validation). Cached outputs are **schema-validated against their task's expected shape ON READ** (§5.2 + §5.5 untrusted-output). `task_id` is single-sourced from A0's manifest `provenance.task_id` enum (`curiosity/blurb/category/reconcile`) — pinned with a drift-guard test, never re-typed locally.
- **LLM output is UNTRUSTED (§5.5).** Source text (`name/summary/tags`) is **delimited** in the prompt, never interpolated raw; the model's response is parsed + schema-validated **before use** (`curiosity ∈ [0,1]`, reject out-of-range / wrong-type / extra-field / non-JSON). A malformed or out-of-range curiosity value is dropped to "no LLM signal for this place" (the composite's absent-signal path — A4's renormalise-over-present), never a crash and never a smuggled value.
- **LLM is NEVER the sole gate (§4 + the Malaysia floor).** Curiosity is ONE weighted signal in A4's composite; A4's renormalise-over-present + the KL LLM-off floor (A5) already guarantee ranking survives with curiosity absent. A6 adds the signal and measures its lift; it cannot make the LLM load-bearing.
- **KEY-GATE placed so impl proceeds keyless to the live-run line.** Keyless + runnable now: the Protocol, `FakeProvider`, the cache, the curiosity prompt/parse/validate, the cost model (token counting needs no API key), and the whole bake-off harness driven by `FakeProvider`. Key-blocked (declared, not discovered): the *live* Modal/OpenRouter RPCs. The provider modules import their SDK lazily so the keyless path never imports an unavailable dependency; a missing key raises a typed `ProviderCredentialsMissing`, never a partial run.
- **Deterministic + cost-bounded (§5.2, Principle 12).** Re-runs touch only new/changed places (cache hit on `input_hash`). `FakeProvider` is a pure function of `(request)` — no wall-clock/RNG in the harness; latency/cost are recorded fields, not computed from `Date.now()`. The bake-off report is a deterministic function of `(golden labels, per-model curiosity, pricing table)`.
- **BLOCKED-ON declarations (up front — the A2/A3/A4/A5 lesson).** The *live* bake-off is BLOCKED-ON Rob's Modal/OpenRouter keys. The *real* curiosity inputs + cost corpus are BLOCKED-ON A2 `places`/A3 `place_categories` impls + `wp-acquire-impl` real extracts. A5's `mt_pipeline.eval` is a **merged plan-only** package (not in code yet) — the bake-off's A5 import is declared BLOCKED-ON the A5 impl, same as A5's own `composite.score` import is BLOCKED-ON A4's impl. Nothing claims a real bake-off number before keys + impls land.
- **Scope discipline (YAGNI).** A6's bake-off task is **curiosity** — the signal A4/A5 consume. blurb / category-long-tail / reconcile-adjudication are named `task_id`s that reuse the SAME provider abstraction + cache unchanged, but are NOT designed in detail here (each is its own later WP); the cache/provider seam is built to carry them (task_id-parameterised), nothing more.

**A6 brief (fable, thread `wp/a6`)** — provider abstraction from trader's `ModalProvider` patterns (lazy `app.run()` single job-type per session for GPU-second cost attribution; cost-safety `BaseException`s that punch through retries while teardown still runs; derived-KV context sizing; per-session billing; batch RPCs); the model bake-off riding on A5's harness; the cost model from real token counts on real extracted records; the key-gate placed so impl proceeds keyless to the live-run line. This is the last design of the run.

---

## File Structure

```
pipeline/src/mt_pipeline/llm/
  __init__.py            # NO SDK imports at package level (keyless import path)
  models.py              # LlmRequest, ProviderResponse, CuriosityResult (pydantic, frozen, extra=forbid); PricingRow
  provider.py            # Provider Protocol + BatchNotSupportedError + ProviderCredentialsMissing
  cache.py               # LlmCache: (task_id,model,prompt_version,input_hash) key; local-first store; validate-ON-READ; task_id-collision guard
  curiosity.py           # render_prompt(place) [§5.5 delimited]; parse_curiosity(text)->CuriosityResult (validate-on-read); CURIOSITY_TASK_ID
  costmodel.py           # count_tokens(prompt, tokenizer|estimate); estimate_cost(corpus, pricing) -> CostTable
  bakeoff.py             # run_bakeoff(golden_rows, providers, models, pricing, *, k) -> BakeoffReport  [imports A5 rescore/metrics]
  providers/
    __init__.py
    fake.py              # FakeProvider — deterministic, KEYLESS; drives the whole harness in tests
    modal.py             # ModalProvider — lazy single app.run() session, GPU-second cost [live BLOCKED-ON keys]
    openrouter.py        # OpenRouterProvider — hosted, usage×pricing [live BLOCKED-ON keys]
pipeline/config/
  llm_pricing.json       # VERSIONED pricing table: per-model $/1M input + $/1M output (+ Modal $/GPU-second)
  llm_models.json        # VERSIONED candidate-model roster for the bake-off (id, provider, tokenizer)
pipeline/schemas/
  curiosity-result.schema.json   # {curiosity: number [0,1]} — validate-on-read; task_id single-sourced from A0
pipeline/tests/
  test_llm_provider_fake.py  test_llm_cache.py  test_llm_curiosity.py
  test_llm_costmodel.py      test_llm_bakeoff.py  test_llm_providers_live.py  # live tests skip w/o keys
docs/superpowers/reports/
  2026-07-15-a6-cost-table.md    # real-token cost table (keyless; after extracts)
  2026-07-15-a6-bakeoff.md       # quality-per-dollar matrix (BLOCKED-ON keys + impls)
```

---

### Task 1: Provider Protocol + models + the keyless FakeProvider

**Files:** Create `pipeline/src/mt_pipeline/llm/{__init__.py,provider.py,models.py,providers/__init__.py,providers/fake.py}`; Test `pipeline/tests/test_llm_provider_fake.py`

**Interfaces:**
- Consumes: nothing (new package).
- Produces:
  - `models.Message` — `pydantic frozen (role: str, content: str)`.
  - `models.LlmRequest` — `frozen (model_id, system, messages: tuple[Message,...], max_tokens, temperature, top_p, seed, prompt_version, task_id, query_id)` (mirrors trader; `task_id` replaces trader's `job_detail` as the cache-namespacing key).
  - `models.ProviderResponse` — `frozen (text, model_fingerprint, input_tokens, output_tokens, latency_ms, cost_usd, app_id)`. (Adds `cost_usd` to trader's shape — hosted providers know per-call cost from usage; Modal fills it at session `shutdown`.)
  - `provider.Provider` — `runtime_checkable Protocol`: `async acomplete(req) -> ProviderResponse`; `async acomplete_batch(reqs) -> list[ProviderResponse]`; `supports_batch: bool`; `is_gpu_batchable: bool`; `async shutdown() -> float | None` (returns session cost_usd or None).
  - `provider.BatchNotSupportedError(Exception)`, `provider.ProviderCredentialsMissing(Exception)`.
  - `providers.fake.FakeProvider(scorer: Callable[[LlmRequest], float], *, price_per_call_usd=0.0)` — deterministic, keyless; `acomplete` returns a `ProviderResponse` whose `text` is `json.dumps({"curiosity": scorer(req)})` and whose token counts are the byte-bounded estimate; drives the whole harness.

- [ ] **Step 1: Write the failing test**

```python
import asyncio, json
from mt_pipeline.llm import models as M, provider as P
from mt_pipeline.llm.providers.fake import FakeProvider

def _req(text="Old Windmill\ntags: heritage"):
    return M.LlmRequest(model_id="fake-1", system="score", messages=(M.Message(role="user", content=text),),
                        max_tokens=16, temperature=0.0, top_p=1.0, seed=7,
                        prompt_version="curiosity-v1", task_id="curiosity", query_id="mt1_x")

def test_fake_provider_is_deterministic_and_keyless():
    fp = FakeProvider(scorer=lambda r: 0.5 if "heritage" in r.messages[0].content else 0.1, price_per_call_usd=0.002)
    a = asyncio.run(fp.acomplete(_req())); b = asyncio.run(fp.acomplete(_req()))
    assert a == b                                             # deterministic (frozen model equality)
    assert json.loads(a.text)["curiosity"] == 0.5            # scorer drives the output
    assert a.cost_usd == 0.002 and a.input_tokens > 0

def test_fake_provider_satisfies_the_protocol():
    fp = FakeProvider(scorer=lambda r: 0.0)
    assert isinstance(fp, P.Provider)                        # runtime_checkable structural conformance
    assert fp.supports_batch is False
```

- [ ] **Step 2: Run to verify it fails** — `uv run pytest pipeline/tests/test_llm_provider_fake.py -v` → FAIL (module not found).
- [ ] **Step 3: Implement** the models (pydantic frozen, `extra="forbid"`), the `Provider` Protocol, and `FakeProvider`. `__init__.py` imports ONLY `models`/`provider` (no SDKs). `FakeProvider.acomplete_batch` = `[await acomplete(r) for r in reqs]`.
- [ ] **Step 4: Run to verify it passes.** **Teeth:** `test_fake_provider_is_deterministic_and_keyless` reds if the fake is non-deterministic or ignores the scorer; the Protocol test reds if a required method/flag is missing.
- [ ] **Step 5: Commit** — `"Add LLM provider Protocol + frozen models + keyless FakeProvider (trader pattern)"`

---

### Task 2: The LLM cache — (task_id, model, prompt_version, input_hash) + validate-ON-READ

**Files:** Create `pipeline/src/mt_pipeline/llm/cache.py`, `pipeline/schemas/curiosity-result.schema.json`; Test `pipeline/tests/test_llm_cache.py`

**Interfaces:**
- Consumes: `models.CuriosityResult` (Task 3 defines the parser; the cache stores/validates the raw JSON per task).
- Produces:
  - `cache.cache_key(task_id, model, prompt_version, input_hash) -> str` — the R2/local key.
  - `cache.input_hash(*, task_id, prompt_version, rendered_prompt) -> str` — sha256 over the EXACT rendered prompt (so a prompt change ⇒ a new key ⇒ a re-run).
  - `cache.LlmCache(root, *, validators: dict[str, Callable[[dict], Any]])` — local-first store (JSONL/dir); `get(task_id, model, prompt_version, input_hash) -> Any | None` **validates the stored blob against `validators[task_id]` ON READ and raises `LlmCacheCorrupt` (with the key) if it fails**; `put(key, blob)`. R2 push is a thin deferred adapter (declared, not built here).
  - `CURIOSITY_TASK_ID = "curiosity"` re-exported; a drift-guard test pins it against A0's manifest `provenance.task_id` enum.

- [ ] **Step 1: Write the failing tests** (the load-bearing task_id-collision + validate-on-read teeth):

```python
import json, pytest
from mt_pipeline.llm import cache as C

CURIOSITY_V = {"curiosity": lambda d: d if isinstance(d.get("curiosity"), (int, float)) and 0 <= d["curiosity"] <= 1 else (_ for _ in ()).throw(ValueError("bad curiosity")),
               "blurb": lambda d: d if isinstance(d.get("text"), str) else (_ for _ in ()).throw(ValueError("bad blurb"))}

def test_task_id_namespaces_the_key_no_silent_collision():
    # SAME model/prompt_version/input, DIFFERENT task -> DIFFERENT keys (else a category value collides into blurb)
    a = C.cache_key("curiosity", "m", "v1", "hhh"); b = C.cache_key("blurb", "m", "v1", "hhh")
    assert a != b

def test_prompt_change_changes_the_input_hash():
    h1 = C.input_hash(task_id="curiosity", prompt_version="v1", rendered_prompt="Old Windmill | tags: heritage")
    h2 = C.input_hash(task_id="curiosity", prompt_version="v1", rendered_prompt="Old Windmill | tags: pub")
    assert h1 != h2

def test_read_validates_against_the_TASK_schema_not_just_any_json(tmp_path):
    cache = C.LlmCache(tmp_path, validators=CURIOSITY_V)
    k = C.cache_key("curiosity", "m", "v1", "hhh")
    cache.put(k, {"text": "a nice blurb"})                   # a BLURB-shaped blob written under a CURIOSITY key
    with pytest.raises(C.LlmCacheCorrupt):                   # read MUST reject it (task-shape validation, §5.2/§5.5)
        cache.get("curiosity", "m", "v1", "hhh")

def test_task_id_matches_the_frozen_A0_enum():
    import json, pathlib
    schema = json.loads(pathlib.Path("contracts/schemas/manifest.schema.json").read_text())
    # walk to provenance.items.properties.task_id.enum — single source of truth
    enum = schema["properties"]["provenance"]["items"]["properties"]["task_id"]["enum"]
    assert C.CURIOSITY_TASK_ID in enum                       # drift-guard: never re-type the task_id locally
```

- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement.** `cache_key` = `f"{task_id}/{model}/{prompt_version}/{input_hash}"`; `input_hash` = sha256 hexdigest of `rendered_prompt` (task_id + prompt_version already in the key path, but include them in the hash input too so a hash alone is unambiguous). `LlmCache.get` loads the blob then calls `validators[task_id](blob)` — any exception → `LlmCacheCorrupt(key)`.
- [ ] **Step 4: Run to verify it passes.** **Teeth:** `test_read_validates_against_the_TASK_schema` reds if `get` returns any well-formed JSON without task-shape validation (the exact silent-collision §5.2 warns about — a blurb-shaped blob under a curiosity key); the enum drift-guard reds if `CURIOSITY_TASK_ID` is re-typed to a value A0 doesn't know.
- [ ] **Step 5: Commit** — `"Add LLM cache: task_id-namespaced key + validate-on-read (no silent cross-task collision)"`

---

### Task 3: The curiosity task — delimited prompt (§5.5) + validated CuriosityResult

**Files:** Create `pipeline/src/mt_pipeline/llm/curiosity.py`; extend `models.py` with `CuriosityResult`; Test `pipeline/tests/test_llm_curiosity.py`

**Interfaces:**
- Consumes: `models.LlmRequest`, the A2 `places` shape (`name`, `summary`, `tags`) — read as a plain dict here (BLOCKED-ON A2 for the real join).
- Produces:
  - `models.CuriosityResult` — `frozen (curiosity: float)` with a validator pinning `0.0 <= curiosity <= 1.0`.
  - `curiosity.render_prompt(place: Mapping) -> str` — renders `name + summary + tags` **inside explicit delimiters** (`<<<SOURCE>>> … <<<END>>>`), with the source text passed through `mt_contracts.strip_unsafe_text` and the delimiter tokens stripped from the source so it cannot forge a boundary (§5.5). Deterministic.
  - `curiosity.parse_curiosity(text: str) -> CuriosityResult` — parse the model's JSON response and validate-on-read: reject non-JSON, missing/extra fields, wrong type, and out-of-range → raises `CuriosityParseError`.
  - `curiosity.CURIOSITY_TASK_ID = "curiosity"`, `curiosity.CURIOSITY_PROMPT_VERSION = "curiosity-v1"`.

- [ ] **Step 1: Write the failing tests** (§5.5 injection + validate-on-read teeth):

```python
import pytest
from mt_pipeline.llm import curiosity as Q

def test_prompt_delimits_and_scrubs_source_text():
    p = Q.render_prompt({"name": "The <<<END>>> Trick", "summary": "x", "tags": ["heritage"]})
    assert p.count("<<<END>>>") == 1                          # the injected delimiter in the NAME was stripped;
    assert "<<<SOURCE>>>" in p                                # only the real framing delimiters survive

def test_parse_rejects_out_of_range_and_nonjson():
    assert Q.parse_curiosity('{"curiosity": 0.7}').curiosity == 0.7
    for bad in ['{"curiosity": 1.5}', '{"curiosity": -0.1}', '{"curiosity": "high"}',
                '{"curiosity": 0.5, "evil": 1}', 'not json', '{}']:
        with pytest.raises(Q.CuriosityParseError):
            Q.parse_curiosity(bad)                            # untrusted output rejected BEFORE use (§5.5)
```

- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement.** `render_prompt` strips control chars (`strip_unsafe_text`) and removes the literal delimiter tokens from source before framing; `parse_curiosity` uses `CuriosityResult.model_validate_json` with `extra="forbid"` + the range validator, wrapping any pydantic/JSON error as `CuriosityParseError`.
- [ ] **Step 4: Run to verify it passes.** **Teeth:** the injection test reds if source text isn't delimiter-scrubbed (a place named `<<<END>>>` would otherwise forge the boundary); the parse test reds if any out-of-range / extra-field / non-JSON value is accepted (the §5.5 untrusted-output guarantee).
- [ ] **Step 5: Commit** — `"Add curiosity task: delimited+scrubbed prompt (§5.5) + validated CuriosityResult"`

---

### Task 4: The cost model — real token counts × pricing (KEYLESS)

**Files:** Create `pipeline/src/mt_pipeline/llm/costmodel.py`, `pipeline/config/llm_pricing.json`, `pipeline/config/llm_models.json`; Test `pipeline/tests/test_llm_costmodel.py`

**Interfaces:**
- Consumes: `curiosity.render_prompt`, `config/llm_pricing.json`, `config/llm_models.json`.
- Produces:
  - `costmodel.count_tokens(text, *, tokenizer=None) -> int` — exact count via the model's tokenizer when available; else the **byte-bounded upper estimate** (`#tokens <= #bytes`, the trader `estimate_context_length` rule — keyless, deterministic, honestly labelled an upper bound).
  - `costmodel.CostTable` — `frozen` per-model rows `(model, input_tokens, est_output_tokens, input_usd, output_usd, total_usd, token_source: "tokenizer"|"byte-estimate")`.
  - `costmodel.estimate_cost(prompts: list[str], pricing: PricingRow, *, est_output_tokens, tokenizer=None) -> CostRow` — sum input tokens × `$/1M in` + `est_output_tokens × N × $/1M out`.
  - `costmodel.build_cost_table(corpus: list[Mapping], models, pricing) -> CostTable` — render curiosity prompts for the corpus, count, cost, per model → the "30-second cost table".

- [ ] **Step 1: Write the failing tests:**

```python
from mt_pipeline.llm import costmodel as K

def test_token_count_upper_bounds_bytes():
    t = "Old Windmill heritage site"
    assert 0 < K.count_tokens(t) <= len(t.encode("utf-8"))   # byte-bounded estimate, honestly an UPPER bound

def test_cost_scales_with_corpus_and_pins_source():
    pricing = {"input_per_m": 0.15, "output_per_m": 0.60}
    row1 = K.estimate_cost(["a place"], pricing, est_output_tokens=8)
    row2 = K.estimate_cost(["a place", "another place here"], pricing, est_output_tokens=8)
    assert row2.total_usd > row1.total_usd                   # more corpus -> more cost
    assert row1.token_source in ("tokenizer", "byte-estimate")   # source is disclosed, never hidden
```

- [ ] **Step 2–4:** implement; keyless (token counting needs no API key). **Teeth:** the upper-bound test reds if the estimate exceeds byte length (dishonest); the scaling test reds if cost is corpus-independent. `token_source` MUST be recorded so a byte-estimate is never mistaken for an exact count (the "don't oversell what a measurement proves" lesson).
- [ ] **Step 5: Commit** — `"Add keyless cost model: real-token counting (tokenizer|byte-estimate) × versioned pricing"`

---

### Task 5: The bake-off — riding on A5's frozen seam  `[A5 import BLOCKED-ON A5 impl]`

**Files:** Create `pipeline/src/mt_pipeline/llm/bakeoff.py`; Test `pipeline/tests/test_llm_bakeoff.py`

**Interfaces:**
- Consumes: **A5's `mt_pipeline.eval.rescore.rescore`, `mt_pipeline.eval.metrics.precision_at_k`, `mt_pipeline.eval.golden.GoldenRow`** (imported UNCHANGED — the frozen seam); `provider.Provider`; `curiosity`; `costmodel`.
- Produces:
  - `bakeoff.score_places(rows, provider, *, prompt_version) -> dict[str, float]` — run the curiosity task over each golden `GoldenRow` via `provider.acomplete_batch`, return `{place_id: curiosity}`. (`provider` is any `Provider` — `FakeProvider` in tests.)
  - `bakeoff.with_curiosity(rows, curiosities) -> list[GoldenRow]` — return NEW rows with `signals["llm_curiosity"]` set from the model (A5's slot — write, don't re-score).
  - `bakeoff.run_bakeoff(golden_rows, labeled, models, providers, pricing, *, k, config) -> BakeoffReport` — for each model: score → write into A5's slot → **A5's `rescore.rescore(rows, config, llm_on=True)` + `metrics.precision_at_k`** for lift over the `llm_on=False` A4-only baseline → `÷` measured cost → a **quality-per-dollar** row. Deterministic; the winner is whatever the matrix shows.
  - `bakeoff.BakeoffReport` — `frozen` rows `(model, provider, precision_at_k_llm_on, precision_at_k_llm_off_baseline, lift, cost_usd, lift_per_usd)` sorted by `lift_per_usd`.

- [ ] **Step 1: Write the failing test** (FakeProvider-driven, keyless, and it proves the A5 seam is what's scoring):

```python
import asyncio
from mt_pipeline.llm import bakeoff as B
from mt_pipeline.llm.providers.fake import FakeProvider
from mt_pipeline.eval.golden import GoldenRow          # A5's frozen type (BLOCKED-ON A5 impl)

def _row(pid, article, lbl):
    return GoldenRow(pid, "kl", "n", 3.1, 101.6, "history", 2, 0.0,
                     {"article": article, "llm_curiosity": None}, lbl, data_version="v1")

def test_bakeoff_lift_comes_from_A5_precision_at_k():
    # two KL places: the interesting one (labeled yes) has WEAK article evidence, so an A4-only
    # ranking mis-orders it; a good curiosity model that scores it high LIFTS precision@1.
    rows = [_row("mt1_"+"0"*26, 0.1, "yes"), _row("mt1_"+"1"*26, 0.9, "no")]
    good = FakeProvider(scorer=lambda r: 0.9 if "0"*26 in r.messages[0].content or r.query_id.endswith("0"*26) else 0.1,
                        price_per_call_usd=0.001)
    rep = B.run_bakeoff(rows, rows, models=[("good","fake")], providers={"fake": good},
                        pricing={"good": {"input_per_m": 0.1, "output_per_m": 0.4}}, k=1, config={"article":1.0,"llm_curiosity":3.0})
    r = rep.rows[0]
    assert r.precision_at_k_llm_off_baseline == 0.0 and r.precision_at_k_llm_on == 1.0   # A5's precision@k did the scoring
    assert r.lift == 1.0 and r.lift_per_usd > 0
```

- [ ] **Step 2: Run to verify it fails.** (Also fails to IMPORT until A5's `mt_pipeline.eval` lands — that's the declared BLOCKED-ON; the logic is written against the frozen signatures now.)
- [ ] **Step 3: Implement.** `run_bakeoff` calls A5's functions directly — NO local re-scoring. Lift = `p@k(llm_on) − p@k(llm_off baseline)`; `lift_per_usd = lift / cost_usd` (guard cost 0 → report lift with cost "n/a", never divide by zero — the A5 divisor lesson).
- [ ] **Step 4: Run to verify it passes** (once A5 impl is present in the venv). **Teeth:** the test reds if `run_bakeoff` re-implements scoring instead of calling A5's `precision_at_k` (neuter the A5 import → the lift numbers change / the test can't run — proving the seam, not a copy, is doing the work). The baseline==0.0 vs on==1.0 split proves curiosity actually moved the A5 ranking.
- [ ] **Step 5: Commit** — `"Add model bake-off riding on A5's eval seam (lift ÷ cost = quality-per-dollar)"`

---

### Task 6: Live providers — Modal (open-weight) + OpenRouter (hosted)  `[live RPC BLOCKED-ON keys]`

**Files:** Create `pipeline/src/mt_pipeline/llm/providers/{modal.py,openrouter.py}`; Test `pipeline/tests/test_llm_providers_live.py`

**Interfaces:**
- Consumes: `provider.Provider`, `models.*`. SDKs (`modal`, `openai`/`httpx`) imported **inside the module**, never at package import.
- Produces:
  - `providers.modal.ModalProvider(concurrency, *, max_model_len=None)` — mirrors trader: lazy `_ensure_started()` single `app.run()` session (ONE job_type per session for GPU-second cost attribution), `acomplete_batch` = one RPC per chunk (`is_gpu_batchable=True`), `shutdown()` queries session cost via the billing adapter and returns `cost_usd`. A cost-safety terminal condition (engine window below floor) is a `BaseException` subclass that propagates through the retry envelope while teardown still runs (trader's `ServedWindowBelowFloorError` pattern) — documented + a unit test that the teardown `finally` runs on it.
  - `providers.openrouter.OpenRouterProvider(api_key, concurrency, *, base_url)` — hosted, mirrors trader's `OpenAIProvider` shape (AsyncOpenAI-compatible against OpenRouter's endpoint); `is_gpu_batchable=False`; per-call `cost_usd` from `usage` × pricing; `acomplete` sets `response_format` for JSON.
  - Both raise `ProviderCredentialsMissing` (typed) when their env credentials are absent — never a partial/half-authenticated run.

- [ ] **Step 1: Write the tests** — structural + credential-gating, NO live call:

```python
import os, pytest
from mt_pipeline.llm import provider as P

def test_providers_conform_and_gate_on_credentials():
    from mt_pipeline.llm.providers.modal import ModalProvider
    from mt_pipeline.llm.providers.openrouter import OpenRouterProvider
    assert isinstance(ModalProvider(concurrency=1), P.Provider)              # structural conformance, no RPC
    with pytest.raises(P.ProviderCredentialsMissing):
        OpenRouterProvider(api_key="", concurrency=1)                        # empty key -> typed refusal, not a partial run

@pytest.mark.skipif(not os.getenv("OPENROUTER_API_KEY"), reason="live run BLOCKED-ON keys")
def test_openrouter_live_smoke():
    ...  # a single real curiosity call; runs ONLY when Rob supplies a key
```

- [ ] **Step 2–4:** implement both providers; the keyless test suite passes with no SDK RPC (import-gated). **Teeth:** the credential test reds if a provider silently constructs without a key (a half-authenticated run is worse than a loud refusal — the fail-closed lesson); the Protocol test reds if either drifts from the interface. The live smoke test is `skipif`-gated on the env key (declared BLOCKED-ON, never a false green).
- [ ] **Step 5: Commit** — `"Add Modal + OpenRouter providers (import-gated SDKs; credential-fail-closed; live RPC key-gated)"`

---

### Task 7: CLI + the real deliverables (cost table now-ish; live bake-off key-gated)

**Files:** Modify `cli.py` (an `mt llm` group); Create the report stubs.

**Interfaces:** `mt llm cost --region <r> --models <roster>` (keyless — real-token cost table) and `mt llm bakeoff --region <r> --labeled <golden.tsv> --models <roster>` (the quality-per-dollar matrix — BLOCKED-ON keys + A2/A3/A5 impls). `llm` is a **tool group, not a `STAGE_ORDER` stage** (the score stage consumes a *published* curiosity signal from cache; the bake-off is an offline method run).

- [ ] **Step 1 (keyless, real-token — after A2/A3 impls + real extracts):** `mt llm cost --region uk` and `--region my` → render curiosity prompts over the REAL extracted places, count tokens, cost against `llm_pricing.json` → commit `docs/superpowers/reports/2026-07-15-a6-cost-table.md` (the "30-second cost table"; needs NO keys — token counting only).
- [ ] **Step 2 (BLOCKED-ON keys + A5 impl + real golden labels):** once Rob supplies Modal/OpenRouter keys AND A5's golden TSVs are labelled, `mt llm bakeoff --region my --labeled docs/…/golden-kl.tsv` → run each candidate model's curiosity over the KL golden places, write into A5's slot, precision@k lift ÷ cost → commit `docs/superpowers/reports/2026-07-15-a6-bakeoff.md` (the quality-per-dollar matrix + the recommended model + its earned weight). This is the ONLY key-blocked step.
- [ ] **Step 3: Commit** — `"Add mt llm CLI + real cost table (keyless) + bake-off matrix (after keys+impls)"`

---

## Review Record

**Author self-review** — deliverables map to tasks: the provider Protocol + frozen models + keyless FakeProvider (T1), the task_id-namespaced validate-on-read cache (T2), the delimited curiosity task with untrusted-output validation (T3), the keyless real-token cost model (T4), the bake-off riding on A5's frozen seam (T5), the live Modal + OpenRouter providers with credential-fail-closed (T6), and the CLI + real deliverables (T7). The design is a **method for choosing a model** — identical task on both providers, empirical lift ÷ cost — not a model pick. A6 is the last WP of the run.

**Ratifications (fable, thread `wp/a6`)** — provider abstraction from trader's ModalProvider patterns; bake-off riding on A5's harness; cost model from real token counts on real records; key-gate placed so impl proceeds keyless to the live-run line.

**Cross-package needs surfaced:**
- **RIDES ON A5's frozen seam:** `bakeoff` imports `mt_pipeline.eval.rescore`/`metrics`/`golden` UNCHANGED and writes into the `llm_curiosity` slot A5 froze — consume-don't-reinvent (the exact rule A5 applied to `composite.score` and the place_id validator). **BLOCKED-ON the A5 impl** (A5 is merged plan-only; `mt_pipeline.eval` not in code yet).
- **Feeds A4's composite:** the published curiosity signal is A4's optional `llm_curiosity` signal column (A4's renormalise-over-present makes it non-load-bearing — the Malaysia floor). A6 produces the value + cache; A4 consumes it. No A4 change.
- **task_id single-sourced from A0:** the cache's `task_id` enum is A0's manifest `provenance.task_id` (`curiosity/blurb/category/reconcile`) — pinned by a drift-guard test, never re-typed.
- **BLOCKED-ON Rob's keys** (Modal + OpenRouter) for the LIVE bake-off only; **BLOCKED-ON A2/A3 impls + `wp-acquire-impl`** for the real curiosity inputs + cost corpus. Everything else is keyless + runnable now.
- **Later task_ids reuse this abstraction:** blurb / category-long-tail / reconcile-adjudication are named task_ids that reuse the provider + cache unchanged (each its own later WP) — not designed here (YAGNI).

**Adversarial review (per AGENTS.md gate) — TO RUN before PR:** (1) fixes on the **executed path**; (2) **teeth** — the cache read reds if a blurb-shaped blob is accepted under a curiosity key (silent cross-task collision, §5.2); curiosity parse reds on any out-of-range/extra-field/non-JSON output (§5.5); the prompt reds if source text isn't delimiter-scrubbed (injection); the bake-off lift reds if it re-implements scoring instead of calling A5's `precision_at_k` (neuter the A5 import → numbers change); the providers red if they construct without credentials (fail-closed) or drift from the Protocol; the cost model reds if the estimate exceeds byte length or hides its `token_source`; (3) **the coherence critic RUNS the keyless path on fixtures** (FakeProvider through Protocol → cache → curiosity → cost → bake-off) against a real venv and confirms determinism + that the bake-off imports A5's seam rather than a copy; (4) confirm the **key-gate is honest** — every keyless claim runs with NO credentials, and the live RPC is `skipif`-gated (declared BLOCKED-ON, never a false green), and the A5/A2/A3 imports are honestly BLOCKED-ON their impls (the A2/A3/A4/A5 lesson — no executed-path over-claim).
