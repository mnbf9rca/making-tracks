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
nous-nex-n2-mini	nous	41786	256	0.00508945	byte-estimate
nous-deepseek-v4-pro	nous	41786	256	0.05336667	byte-estimate
nous-glm-5.2	nous	41786	256	0.15890892	byte-estimate
nous-muse-spark-1.1	nous	41786	256	0.22413650	byte-estimate
modal-meta-llama-3.1-8b	modal	41786	0	0.00479688	byte-estimate
```

Live bake-off follow-up: `nous-tencent-hy3-free` is retained in the roster as S1 but skipped
for live round 1 because six probed request shapes returned 400 `missing user tag`.
`nous-nex-n2-mini` now uses a 256-token output cap for the reasoning-enabled S4 run.
Round 1b adds S5-S7 with the same 256-token reasoning-cap precedent:
`deepseek/deepseek-v4-pro`, `z-ai/glm-5.2`, and `meta/muse-spark-1.1` with
`reasoning.effort=xhigh`. AMQ handoff `2026-07-16T13-34-45.850Z_pid54913_e454708c`
records all three portal ids as live-verified. `deepseek/deepseek-v4-pro` and
`z-ai/glm-5.2` pricing was read from OpenRouter's public model list on 2026-07-16.
`meta/muse-spark-1.1` was absent from that public list even though the portal id
was reported live, so the roster uses the published Meta API price of $1.25/M
input and $4.25/M output until measured response usage replaces the estimate.
