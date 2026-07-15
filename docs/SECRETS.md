# Secrets: the 1Password pattern

Secrets live in the 1Password `making-tracks` vault and NOWHERE else — never in files, never in the repo, never rendered to disk. `.env.tpl` (committed) contains only `op://` secret references.

## Invocation patterns

**Agents and pipeline commands (the default):**
```bash
op run --env-file=.env.tpl -- uv run mt <command>
```
Secrets exist as env vars only for the subprocess duration, and `op run` MASKS secret values in stdout/stderr (accidental prints emerge as `<concealed>`). Never pass `--no-masking`.

**Interactive human shells (direnv-style):** `.envrc` does `eval "$(op inject -i .env.tpl)"` — acceptable for a human terminal; agents use `op run` instead (masking).

**Auth:** on Rob's Mac, the 1Password app integration (biometric). On the VPS, `OP_SERVICE_ACCOUNT_TOKEN` (a service account scoped to only the `making-tracks` vault) — provisioned by Rob.

## Never render secrets to files

No `op inject -o .env`, no `chmod 600` env files, nothing on disk. The rendered-`.env` gitignore entry is a tripwire, not a workflow.

## Compromised secrets (standing rule)

If a secret is ever compromised — accidentally logged, printed unmasked, read into an agent context, committed — the discovering agent IMMEDIATELY appends to `TO-ROTATE.log` (committed, durable): the secret's op:// reference or name, timestamp, and how it was exposed. NEVER the value. Rob rotates on his schedule. Discovering-and-logging is mandatory and blame-free; hiding an exposure is the only sin.
