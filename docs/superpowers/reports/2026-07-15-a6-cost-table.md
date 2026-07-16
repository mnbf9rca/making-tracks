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
nous-nex-n2-mini	nous	41786	128	0.00306705	byte-estimate
modal-meta-llama-3.1-8b	modal	41786	0	0.00479688	byte-estimate
```

Live bake-off status: blocked on Rob's provider keys and op-run smoke test.
