# Infrastructure — access, signing, and where work runs

Operational facts agents need and cannot derive from the tree. Secrets handling is in
[`SECRETS.md`](SECRETS.md); this covers access topology and compute placement.

---

## 1. Raw SSH and commit signing route through 1Password

On Rob's Mac, `~/.ssh/config` sets `IdentityAgent` to the 1Password agent socket under `Host *`. A plain
non-VPS `ssh` diagnostic can authenticate through it even when an `-i` identity file is present; verify
with `ssh -v` before assuming which key was used. GitHub push and commit signing also go through
1Password.

The launchd `SSH_AUTH_SOCK` agent holds no identities.

**Consequence: raw SSH and GitHub signing fail together.** When the Mac locks, 1Password locks and keychain passphrase release
stops, so raw SSH attempts, GitHub push and commit signing all break at once with
`communication with agent failed` or `Permission denied (publickey)`. That is expected behaviour, not an
incident.

VPS operator work does not use raw `ssh`. Use the wrapper in **VPS Operator Path**; it disables the
1Password agent path and pins the VPS service identity.

### Signing is required on long-lived branches

The `protect-long-lived-branches` ruleset enforces `required_signatures` on `main`, `develop` and `ios`.
Squash merges performed through GitHub are signed by GitHub itself, so unsigned feature-branch commits can
still merge that way; anything pushed directly to a long-lived branch must carry a valid signature.

Agents sign through the 1Password agent socket
(`SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"`). The first
signature per session raises a biometric prompt that Rob approves; plan signing work for when he is
present. When existing commits need signatures, re-sign with a tree-preserving amend
(`git commit --amend --no-edit -S`) — the unchanged tree hash is what carries prior gate evidence forward.
Never sign with the VPS agent key (**VPS Operator Path**); GitHub does not recognize it, and a
bad-signature commit is worse than an unsigned one.

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

- VPS operator access through the wrapper is separate from GitHub commit signing. Lost monitoring from any
  non-wrapper path is lost **visibility**, not a failed run. Detached runs continue.
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

Operator requirements:

- Required VPS operator entry point: `/Users/rob/.local/bin/making-tracks-vps`. The connectivity receipt is
  `/Users/rob/.local/bin/making-tracks-vps making-tracks-dev.cynexia.net true`. Pass the remote command
  after the hostname for operator work. Use the hostname, not the raw IP, for VPS operator work.
- The wrapper also accepts `62.238.55.235` for host-resolution diagnostics. Do not use the raw IP for normal
  operator work.
- The wrapper is the only sanctioned VPS entry point for agents. It allowlists the VPS host, selects the
  `agent` account, disables the 1Password `IdentityAgent`, forces `IdentitiesOnly`, disables agent
  forwarding, and uses the on-disk VPS service key.
- Sandbox-default egress is blocked: `nc 62.238.55.235 22`, raw `ssh ...`, and the wrapper's underlying SSH
  connection fail with
  `Operation not permitted` unless the command runs with escalated network execution.
- The intended VPS operator key is `~/.ssh/id_ed25519_for_agent`, fingerprint
  `SHA256:GIxKIdcjeL3sF+TDYJ3QH02iaIq3iww95jwhiVAa8w8`.
- Do **not** use this key for GitHub commit signing. It is authorized for the VPS `agent` account only.
- Do **not** treat a successful default SSH connection as an agent-key receipt. Because `Host *` sets
  `IdentityAgent`, a raw default `ssh -v -i ~/.ssh/id_ed25519_for_agent agent@making-tracks-dev.cynexia.net exit`
  authenticates with Rob's 1Password key `SHA256:1X7YuLyK1iIuA/rZoKqk2kKjQBeagTfAl+QuUv6fsnU`, not the
  on-disk agent key.
- True agent-key verification must show the `GIxK...` fingerprint in the accepted and authenticated lines;
  the wrapper is built to produce that path. When a fingerprint receipt is needed, run the wrapper with SSH
  verbosity added inside the wrapper by a human, or have a human produce the receipt with the same wrapper
  options. Do not bypass the wrapper from an agent to produce it.
- Non-interactive commands on the VPS do not include `~/.local/bin` in `PATH`; include
  `export PATH="$HOME/.local/bin:$PATH"` in the same remote command before commands that need `uv`.
- `/data` is the heavy-run volume. Keep at least 10 GB free.

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

---

## 4. Rob's device artifacts

Screenshots and diagnostics exports from Rob's device sync into the repo checkout, untracked:
`.mt-data/screenshots/` and `.mt-data/diagnostics/`. When Rob references an `IMG_NNNN` or a diagnostics
export, read it from there rather than asking him to re-send it.
