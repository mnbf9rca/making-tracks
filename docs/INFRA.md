# Infrastructure — access, signing, and where work runs

Operational facts agents need and cannot derive from the tree. Secrets handling is in
[`SECRETS.md`](SECRETS.md); this covers access topology and compute placement.

---

## 1. SSH and commit signing route through 1Password

On Rob's Mac, `~/.ssh/config` sets `IdentityAgent` to the 1Password agent socket under `Host *`. **All** ssh
authenticates through it regardless of any `-i` flag — VPS access and GitHub push alike. The launchd
`SSH_AUTH_SOCK` agent holds no identities. Git commit signing also goes through 1Password.

The VPS key is passphrase-protected with the passphrase in the macOS keychain (`UseKeychain yes`).

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
- **Never sign with the VPS agent key** (`~/.ssh/id_ed25519_for_agent`). GitHub does not recognise it, so it
  produces bad-signature commits — worse than unsigned ones. This is a standing prohibition.

---

## 2. Where work runs

**Heavy pipeline work runs on the VPS.** Full-region acquisition, extraction and multi-stage runs belong
there; the Mac is for iteration. Unattended and long-running work authenticates through the VPS service
account rather than Rob's desktop 1Password, which needs him present. Interactive `op run` on the Mac is
sanctioned and routine — see [`SECRETS.md`](SECRETS.md) §1 for both auth paths.

⚠️ **Unverified from the repo.** The following came from an agent's operational memory and could not be
checked against the tree or the host. Confirm before relying on them, and correct this file in place:

- Keep at least 10 GB free on `/data`.
- Non-interactive ssh needs `export PATH="$HOME/.local/bin:$PATH"` for `uv` to resolve.

---

## 3. Publish targets

The pipeline publishes static files to Cloudflare R2, served from `tiles.making-tracks.app`.

Two buckets: a public one for published objects, and a private one for the registry. **The registry must
never sit in the public bucket.** Layout and publish ordering are specified in
[`superpowers/plans/2026-07-15-wp-a7-publisher.md`](superpowers/plans/2026-07-15-wp-a7-publisher.md).

`regions.json` v3 requires `search_compact` metadata for every listed region. Until the app has a live
region-index consumer or the contract makes `search_compact` nullable with an explicit compatibility rule,
v3 publishes must include all live regions in one prepared publish. A single-region v3 publish intentionally
omits legacy regions that lack real compact-search metadata rather than synthesizing false URLs, so running
only one live region would temporarily unlist the others from `regions.json`.
