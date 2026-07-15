# Secrets: the 1Password pattern

Secrets live in the 1Password `making-tracks` vault and NOWHERE else — never in files, never in the repo, never rendered to disk. `.env.tpl` (committed) contains only `op://vault/item/field` references. Researched against official docs 2026-07-15 (op CLI 2.33.1 local; 2.35.0 current).

## What actually protects the secrets

In order of real strength:
1. **Least-privilege auth**: the VPS uses `OP_SERVICE_ACCOUNT_TOKEN` from a service account scoped read-only to ONLY the `making-tracks` vault (vault grants are immutable — rescoping means a new account). On the Mac, the desktop-app biometric integration.
2. **Subprocess scoping**: `op run` exposes secrets as env vars only for the child process's lifetime.
3. **Masking** — explicitly BEST-EFFORT, not a security boundary: `op run` substitutes exact secret values in its own stdout/stderr (`<concealed by 1Password>`). It is defeated by any encoding (base64, URL-escaping, splitting) and does not cover files/logs/network the child writes. 1Password's docs never claim it as a control. Treat it as output hygiene; never rely on it.

## Invocation patterns

**Pipeline/agents (the default)** — wrap the WHOLE run, not each command (rate limits: see below):
```bash
op run --env-file=.env.tpl -- uv run mt <stage> <region> ...   # one resolution burst per invocation
```
Never `--no-masking` (or `OP_RUN_NO_MASKING`). Never `op inject -o` / any render-to-disk.

**Interactive human shells** — community practice (not official 1P docs), per [Rob's writeup](https://blog.cynexia.com/using-1password-and-direnv-to-store-developer-secrets/): `.envrc` does `eval "$(op inject -i .env.tpl)"` via direnv. Known costs: biometric prompt per new shell; secrets resident in the whole shell session (weaker than op run's scoping); **on declined/timed-out auth, vars are set to EMPTY STRINGS, not references**. 1Password Environments (beta, `op run --environment`) is the emerging official alternative for this case.

## Mandatory guards (the silent-empty class)

- **Every secret-consuming entry point verifies its required vars are NON-EMPTY and fails loud naming the variable.** Empty ≠ absent: declined biometric auth yields empty strings; malformed (non-`op://`-shaped) references pass through as LITERAL strings with no error. Well-formed-but-wrong references DO fail loud before the child runs.
- **Preflight**: `op run --env-file=.env.tpl -- true` validates every reference resolves (cheap; catches typos before a long run).
- Precedence is deterministic and worth knowing: env-file beats same-named shell vars; last `--env-file` wins.

## Rate-limit budget (service accounts)

Hourly per token: 1,000 reads (non-Business) / 10,000 (Business). Daily per ACCOUNT: as low as 1,000 (Individual/Families) / 5,000 (Teams) / 50,000 (Business). Burst throttling is real and undocumented (~15 rapid invocations → 429 block, 15+ min, no backoff hint). Rules: one `op run` per pipeline RUN; keep the default Unix daemon cache ON (never `OP_CACHE=false`); backoff-and-wait on 429, never retry-loop; cron units must not crash-loop through `op`. If volume ever grows past this, 1Password's documented answer is a self-hosted Connect server — not more retries.

## VPS token handling (our hardening — official docs stop at "not plaintext")

`~/.config/op/service-token` mode 0600 in the agent home, sourced only by the cron/pipeline entry script into the invocation environment — never in `.bashrc`/profile (whole-session exposure), never in the repo. Unset any `OP_CONNECT_*` vars on service-account hosts — they silently take precedence. Token is revocable; rotate via TO-ROTATE.log process like any secret.

## Stream/exit caveats

Masking rewrites the child's stdout/stderr and can disturb TUIs/progress bars/binary output — don't pipe raw binary through a masked `op run`. Exit-code passthrough has no documented contract (bugs fixed as recently as 2.32.1): verify on the pinned CLI version before orchestration depends on it.

## Compromised secrets (standing rule)

If a secret is ever compromised — accidentally logged, printed unmasked, read into an agent context, committed — the discovering agent IMMEDIATELY appends to `TO-ROTATE.log` (committed, durable): the secret's op:// reference or name, timestamp, and exposure vector. NEVER the value. Rob rotates on his schedule. Logging an exposure is mandatory and blame-free; hiding one is the only sin.
