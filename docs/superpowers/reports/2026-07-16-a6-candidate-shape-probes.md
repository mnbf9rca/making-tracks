# WP-A6 Candidate Shape Probes

Date: 2026-07-16
Thread: `wp/a6-impl`
Branch: `wp-a6-candidate-shapes`

Purpose: resolve the two live-screen candidate shape failures after PR #97 isolated
candidate-local provider errors.

## S1: `tencent/hy3:free`

Outcome: admission-failed for round 1.

The live probe exhausted these shapes against the NOUS/OpenRouter chat completion API:

- current `extra_body.tags=["making-tracks","curiosity"]`
- current tags plus top-level `user`
- current tags plus top-level `metadata.user`
- current tags plus a `user:making-tracks-eval` tag
- current tags plus `extra_body.user`
- current tags plus OpenRouter app headers `HTTP-Referer` and `X-OpenRouter-Title`

All six returned HTTP 400 with `missing user tag`. The roster keeps the slot and pricing
entry for auditability, but `llm_models.json` marks it with `live_skip_reason` so default
live round-1 runs do not retry a known failing free-tier route. Explicitly requesting the
model fails closed and prints the skip reason.

## S4: `nex-agi/nex-n2-mini`

Outcome: keep S4 active as the reasoning slot with a raised output ceiling for the
round-1 rerun.

The single-place probe showed current reasoning-enabled shape returns parseable curiosity
JSON at both 128 and 256 output tokens, but the live screen saw an input-dependent invalid
curiosity response. The actual failing row was not captured in the committed probe output, so
the 256-token cap is a conservative request-shape adjustment to reduce truncation risk, not
proof that the failing row is fixed. The round-1 rerun is the measurement. Parse failures now
include the failing kind, `place_id`, and a bounded response excerpt in the candidate-local
error so any future invalid JSON can be diagnosed from the run output without exposing key
material.

Live cache keys now use the roster candidate id while provider calls use the concrete API
model id. That keeps request-shape variants cache-distinct when the same provider model is
run under different caps or reasoning settings.

## S6: `z-ai/glm-5.2`

Outcome: bind S6 active as a minimal disabled-reasoning candidate.

The VPS one-call probe used the production minimal shape, `reasoning={"enabled": false}`,
with a 256-token output cap. The provider honored the disabled-reasoning request:
`reasoning_tokens=0`, `finish_reason=stop`, clean parseable curiosity JSON, and measured
cost. `llm_models.json` therefore keeps `nous-glm-5.2` live with
`reasoning.enabled=false`.

## S7: `meta/muse-spark-1.1`

Outcome: admission-failed for live round 1.

The VPS one-call probe used the same production minimal shape,
`reasoning={"enabled": false}`, with a 256-token output cap. The provider ignored the
disable request, burned `reasoning_tokens=253/256`, returned `finish_reason=length`,
and produced empty content. This is a mandatory-reasoning model for the snap task, not an
economical disabled-reasoning candidate; it is also priced outside the $40-60 production
class. The roster keeps the pricing entry for auditability, but `llm_models.json` marks it
with `live_skip_reason` so default live runs do not spend budget on the known failing route.
