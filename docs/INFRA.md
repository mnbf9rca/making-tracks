# Infrastructure — access, signing, and where work runs

Operational facts agents need and cannot derive from the tree. Secrets handling is in
[`SECRETS.md`](SECRETS.md); this covers access topology and compute placement.

---

## 1. SSH and commit signing route through 1Password

On Rob's Mac, `~/.ssh/config` sets `IdentityAgent` to the 1Password agent socket under `Host *`. A plain
`ssh` command can authenticate through it even when an `-i` identity file is present; verify with `ssh -v`
before assuming which key was used. GitHub push and commit signing also go through 1Password.

The launchd `SSH_AUTH_SOCK` agent holds no identities.

**Consequence: they fail together.** When the Mac locks, 1Password locks and keychain passphrase release
stops, so VPS ssh, GitHub push and commit signing all break at once with
`communication with agent failed` or `Permission denied (publickey)`. That is expected behaviour, not an
incident.

### Do not diagnose a lock from the symptom alone

The simultaneous-failure pattern is necessary but not sufficient evidence of a locked Mac. Verify before
concluding:

- Is Rob demonstrably active? Recent messages mean the Mac is unlocked, so the lock is not the cause.
- Test the agent socket directly:
  `SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock ssh-add -l`

A transient 1Password agent fault under concurrent load (`failed to fill whole buffer`) produces the same
symptom as a locked Mac. Probe before concluding — see
[`process/incidents.md`](process/incidents.md) → *Lock misdiagnosed from the symptom*.

### When the signer is unavailable

- Lost VPS monitoring is lost **visibility**, not a failed run. Detached runs continue.
- Sanctioned degraded mode: unsigned commits on feature branches via `git -c commit.gpgsign=false`, declared
  in the PR body as "commits unsigned (signer unavailable)". Pushes queue until unlock.
- **Never sign with the VPS agent key** (`~/.ssh/id_ed25519_for_agent`). GitHub does not recognize it, so it
  produces bad-signature commits — worse than unsigned ones. This is a standing prohibition.

---

## 2. Where work runs

**Heavy pipeline work runs on the VPS.** Full-region acquisition, extraction and multi-stage runs belong
there; the Mac is for iteration. Unattended and long-running work authenticates through the VPS service
account rather than Rob's desktop 1Password, which needs him present. Interactive `op run` on the Mac is
sanctioned and routine — see [`SECRETS.md`](SECRETS.md) §1 for both auth paths.

### VPS Operator Path

Verified 2026-07-20 from the agent harness:

- Canonical invocation from Rob: `ssh -i ~/.ssh/id_ed25519_for_agent agent@making-tracks-dev.cynexia.net`.
  Use the hostname, not the raw IP, for VPS operator work.
- Sandbox-default egress is blocked: `nc 62.238.55.235 22` and `ssh ...` fail with
  `Operation not permitted` unless the command runs with escalated network execution.
- The intended VPS operator key is `~/.ssh/id_ed25519_for_agent`, fingerprint
  `SHA256:GIxKIdcjeL3sF+TDYJ3QH02iaIq3iww95jwhiVAa8w8`.
- Do **not** use this key for GitHub commit signing. It is authorized for the VPS `agent` account only.
- Do **not** treat a successful default SSH connection as an agent-key receipt. With the current `Host *`
  `IdentityAgent`, `ssh -v -i ~/.ssh/id_ed25519_for_agent agent@making-tracks-dev.cynexia.net exit`
  authenticates with Rob's 1Password key `SHA256:1X7YuLyK1iIuA/rZoKqk2kKjQBeagTfAl+QuUv6fsnU`, not the
  on-disk agent key.
- True agent-key verification must show the `GIxK...` fingerprint in the accepted and authenticated lines.
  The 2026-07-20 non-interactive receipt used
  `ssh -v -o IdentityAgent=none -o IdentitiesOnly=yes -o BatchMode=yes -i ~/.ssh/id_ed25519_for_agent agent@making-tracks-dev.cynexia.net exit`
  and authenticated with `SHA256:GIxKIdcjeL3sF+TDYJ3QH02iaIq3iww95jwhiVAa8w8`.
- Non-interactive ssh on the VPS does not include `~/.local/bin` in `PATH`; run
  `export PATH="$HOME/.local/bin:$PATH"` before commands that need `uv`.
- `/data` is the heavy-run volume. Keep at least 10 GB free; the 2026-07-20 probe showed 17 GB free.

---

## 3. Publish targets

The pipeline publishes static files to Cloudflare R2, served from `tiles.making-tracks.app`.

Two buckets: a public one for published objects, and a private one for the registry. **The registry must
never sit in the public bucket.** Layout and publish ordering are specified in
[`superpowers/plans/2026-07-15-wp-a7-publisher.md`](superpowers/plans/2026-07-15-wp-a7-publisher.md).

`regions.json` v3 requires `search_compact` metadata for every listed region. Until the app has a live
region-index consumer or the contract makes `search_compact` nullable with an explicit compatibility rule,
v3 publishes must include all live regions in one prepared publish. Do not run a v3 publish for only a
subset of live regions; entries that lack real compact-search metadata are omitted rather than given false
URLs.
