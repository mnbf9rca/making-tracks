# WP-A6 Keyless Cost Table

Date: 2026-07-16
Corpus: `docs/superpowers/eval/real-malaysia-20260715-pageviews-golden-kl.jsonl`
Records: 158
Prompt: `curiosity-v1`
Token source: `byte-estimate` (UTF-8 byte upper bound; no tokenizer installed)

No live provider calls were made. No API keys were read. This run stops at the live bake-off line.

Input note: this keyless table prices the real A5 KL golden records using the fields present in that dump (`name`, `category`, `evidence`, and signal names). It is not a live provider usage bill and it is not yet a richer A2/A3 source-summary corpus.

Command:

```bash
uv run --extra dev python -m mt_pipeline.cli llm cost --corpus ../docs/superpowers/eval/real-malaysia-20260715-pageviews-golden-kl.jsonl
```

Equivalent from the repo root:

```bash
uv run python -m mt_pipeline.cli llm cost --corpus docs/superpowers/eval/real-malaysia-20260715-pageviews-golden-kl.jsonl
```

Output:

```text
model	provider	input_tokens	output_token_cap	total_usd	token_source
fake-curiosity-v1	fake	41786	16	0.00000000	byte-estimate
nous-tencent-hy3-free	nous	41786	16	0.00000000	byte-estimate
nous-meta-llama-3.1-8b-instruct	nous	41786	16	0.00229154	byte-estimate
nous-hermes-4-70b	nous	41786	16	0.00259490	byte-estimate
nous-nex-n2-mini-none	nous	41786	256	0.00508945	byte-estimate
nous-nex-n2-mini-low	nous	41786	1024	0.01722385	byte-estimate
nous-nex-n2-mini-high	nous	41786	1024	0.01722385	byte-estimate
nous-deepseek-v4-pro-none	nous	41786	256	0.05336667	byte-estimate
nous-glm-5.2	nous	41786	256	0.15890892	byte-estimate
nous-muse-spark-1.1	nous	41786	256	0.22413650	byte-estimate
modal-meta-llama-3.1-8b	modal	41786	0	0.00479688	byte-estimate
```

Live bake-off follow-up: `nous-tencent-hy3-free` is retained in the roster as S1 but skipped
for live round 1 because six probed request shapes returned 400 `missing user tag`.
The effort matrix now runs on the known-clean cheap `nex-agi/nex-n2-mini` candidate:
cache-distinct `none`, `low`, and `high` variants, with 1024-token caps for low/high
so reasoning has room to finish before JSON output. DeepSeek is retained as a single
probe-verified disabled-reasoning variant (`reasoning.enabled=false`). GLM 5.2 is now
bound as a probe-verified disabled-reasoning variant (`reasoning.enabled=false`):
the VPS probe returned `reasoning_tokens=0`, `finish_reason=stop`, clean parseable
output, and measured cost. Muse Spark remains priced in the table for auditability
but is marked admission-failed: the same `reasoning.enabled=false` probe was ignored,
burning `reasoning_tokens=253/256`, finishing by length with empty content, so it cannot
run the snap task economically and is outside the $40-60 production class.
