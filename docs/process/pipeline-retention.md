# Pipeline data retention

What the pipeline host keeps, what it deletes, and when. Covers the publish VPS only; the app's on-device
storage is in [`../architecture/offline.md`](../architecture/offline.md).

## 1. The two rulings this is built on

Rob:

> "ok so then thats fine. keep logs forever"

> "surely the script cleans the staging folder before it generates again?"

Logs are the durable forensic record. Staged bytes are reproducible on demand. Everything below follows from
that split.

## 2. Steady state

The volume is 49 G. Measured composition of the current base:

| | Size | Kind |
|---|---|---|
| OSM node-locations index (UK) | 11.6 G | Derived cache, rebuildable from the PBF |
| Audited image cache | 14 G | Cost cache — `raw/` 12 G, `thumbs/` 2.3 G |
| OSM PBF (UK) | 2.2 G | Acquired source |
| Working DB (UK) | 719 M | Must survive |
| Registries | ~300 M | Must survive — see §6 |
| Everything else | ~2 G | |
| **Base total** | **~31 G** | |

Two caches dominate: the OSM index and the image cache are together about 24 G of the 31 G base. Neither is
scratch, and neither is deleted by this policy.

**Transient.** With staging pruned per run, one region's publish stages roughly 2.8 G (UK) or 0.4 G
(Malaysia/Singapore/Brunei), counting both the version tree and its `.work` twin. Without pruning, staging
has been observed to accumulate past 8 G.

**The floor.** Keep at least 10 G free. That covers the measured historical staging peak with margin against
a 31 G base. The pipeline already refuses to start an extract below 8 GiB free — a pre-flight refusal, not a
reclaim, so the floor exists to stop the refusal happening rather than to recover from it.

**Cadence.** No scheduler is installed. Runs are manual. The daily-cron steady state is a planning model, and
the figures above are what it would consume if adopted, not what is running.

## 3. Staging lifecycle

**Prune staged bytes unconditionally at the start of every run.** They are reproducible, they are the largest
avoidable pile, and nothing reads them across runs.

### What "staging" means, precisely

The staging root holds four sibling trees and only one is version-keyed. The distinction is load-bearing:
deleting the root wholesale destroys a cache that is expensive to rebuild.

| Tree | Prune? | Why |
|---|---|---|
| `<root>/<region>/<publish_version>/` | **Yes** | The R2-shaped tree. `build_staging` already clears this exact path at the start of each run, so pruning formalises existing behaviour. |
| `<root>/.work/<region>/<publish_version>/` | **Yes** | Holds a second full copy of every cut `.pmtiles`, never read after the copy, never deleted by any code. The largest reclaimable pile. |
| `<root>/thumbs/` | **Decide once, see below** | Global, content-hash deduped across every region and version. |
| `<root>/.image-cache/` | **Never** | A cost cache, not scratch. See §5. |

Also excluded: `regions.json`, `registry/`, `work.db`, and any audited-image-cache generation directory.

### The thumbs decision

Thumbs are deduped by content hash and shared across regions and versions. The upload path globs **every**
thumb ever staged, so the set of objects a run uploads is currently a function of local disk history rather
than of that run's output. Current-run thumbs are regenerated in memory, so pruning loses no data — but it
changes what gets uploaded.

Two defensible positions: prune with the version trees and accept that each run uploads only its own thumbs,
or retain and accept unbounded growth. **Recommendation: prune**, and rely on the existing
reuse-existing-thumbs path, which lists the remote rather than consulting local disk.

### Ordering and concurrency

The prune runs **before any region stages**, not per region. There is no local lock on the staging root, and
`thumbs/` and `regions.json` are deliberately shared, so a per-region prune during a multi-region publish
would delete another region's staged bytes between plan construction and upload.

Resume is not a risk. Publish is not fingerprinted, so a publish always fully re-derives its tree, and staged
bytes are read only within the same process call. There is no stage-now-upload-later path.

### Where the prune lives

This document sets the policy; it does not pick the implementation. Two constraints on whoever does:

- **The prune belongs in the publish entry point**, before the first region stages — not inside
  `build_staging`, which runs per region and per version and so cannot see the sibling trees or the other
  regions.
- **The safe set is a glob, not a wildcard.** `<root>/*/<publish_version>/` and `<root>/.work/` are prunable;
  `<root>/*` is not, because it takes `.image-cache/` with it. A prune that enumerates what it deletes is
  safer than one that deletes what it does not recognise.

## 4. Logs

**Keep forever. Do not rotate, do not compress, do not expire.**

The cost is small enough that the ruling needs no revisiting at this scale:

| | |
|---|---|
| Current total | 12 M |
| Per substantive run | 0.6–1.3 M |
| Projected at one two-region publish per day | 1–3 M/day, roughly 1.1 G/year |

Against a 49 G volume that is not a storage driver. **If the per-run figure or the cadence changes by an
order of magnitude, this section is the one to re-derive** — the ruling was made against these numbers.

**Where logs land is not yet defined in code.** The pipeline writes to stdout and stderr with no file
handler and no rotation; a helper exists to announce a redirect path but nothing calls it. Log files exist
because an out-of-repo wrapper redirects output. Until that wrapper is in the repo, "keep forever" is a
policy about files the pipeline does not itself create, and the owner of that redirect owns the retention.

**The division of responsibility, until that changes:**

| | Owns |
|---|---|
| The wrapper | Where output lands, the filename, and therefore retention |
| The pipeline | What is written and at what verbosity |

**Owed:** move the destination into the repo, so retention attaches to something the pipeline controls. Once
it does, this section governs the pipeline's own log files and the wrapper's role reduces to invoking it. The
helper that announces a redirect path already exists and is uncalled — wiring it is the smallest first step.

## 5. Caches

**The audited image cache is retained.** It holds raw downloads, transcoded thumbs, and — the part that
matters — cached accept and reject decisions per place. Deleting it forces a re-fetch and re-download of
every original, which is rate-limited. It also discards the record of which candidates were already
rejected, so the next run repeats work that was already done and thrown away. Rebuilding this cache is the
most expensive operation on the volume.

**Generations are operator-owned.** No code computes, selects or promotes a current generation; the pipeline
reads whichever directory it is pointed at. Nothing in the repo can tell you which generation is current.

- The current reviewed generation is retained in full, with its evidence: `completed.jsonl`, the audit
  report, and the run logs.
- A superseded generation may be deleted once a newer generation has been used for a successful publish, and — where the change is visible in the app — once the new generation has been confirmed on a device.
- Deleting a generation deletes the evidence for the audit that produced it. Retain the `completed.jsonl`
  and report from a superseded generation even when its cache is removed.

### The next thumb generation

A re-encoded thumb tier is planned: WebP q50 at 256 px max-edge, re-encoded from the originals rather than
transcoded from the current thumbs. Extrapolated from a sample, that is roughly 372 M against about 2.27 G
today — the largest single reduction available on the volume that costs nothing to serve.

It lands as an ordinary content-addressed generation swap during a routine publish. It is not urgent and is
queued behind the prune work in this document.

**The old tier is not retired until a device screenshot confirms the new one.** The sample was judged
identical by eye, and the gate exists because that judgement was made off-device: the card's photo slot
renders at roughly 540 px physical, so a 256 px source is being scaled up in the place it actually matters.
A sample viewed on a desktop cannot settle that. One screenshot after publish can.

Until that confirmation, both tiers are retained. This is the one case where two generations coexist by
design rather than by neglect.

**The OSM node-locations index is retained.** It is derived and rebuildable from the PBF, but rebuilding is
expensive and it is an active input. It is not scratch.

## 6. Databases and registries

**`work.db` is retained per region.** It is the working store and must survive.

**Registries are retained permanently and are not regenerable in the sense that matters.** A registry is the
record of which IDs were minted and when, so deleting one does not merely cost a rebuild — it loses the
mapping that guarantees IDs are never reassigned. Treat registry files as append-only durable state.

**Backups have no rotation policy and no restore runbook.** Both are gaps. Proposed:

- Keep the most recent backup plus the last backup taken before each schema change.
- Delete older backups once a subsequent publish has succeeded against the current schema.
- Write the restore procedure down. Practically it is: stop writers, move the backup into place, validate
  schema and stage markers, re-run the affected stages. That should be a runbook rather than an inference.

## 7. Audit and report artifacts

Reports and audit JSON are small and are evidence for a decision that was made. Retain them with the
generation they describe. They are not covered by the staging prune because they do not live in staging.

## 8. One-time cleanup — for ratification

Each item is a judgment call, not a rule. Cost of deletion is stated because size alone invites a yes that
nobody priced.

- [ ] **Scratch test DBs — ~555 M.** Copies of working DBs made for resolve, performance and index-reuse
      testing. Product-serving state is unaffected. Regenerate by copying the live DB and re-running the
      check; cheap to moderate. One of them may be the evidence for the index-reuse check it was made for.
- [ ] **Legacy registry aliases — ~150 M.** The short-name registries are byte-identical to their
      slug-named counterparts, so they appear to be literal copies rather than distinct records. Live stage
      markers are slug-based. **Confirm no legacy consumer reads short names before deleting**, and if an
      alias is ever recreated, do it explicitly rather than inferring it in retention code.
- [ ] **Superseded image-sweep generations — ~303 M.** Older generations, excluding the current reviewed
      cache and its evidence. Retain each generation's `completed.jsonl` and report per §5.
- [ ] **Pre-schema-change DB backups — ~574 M.** Delete once a subsequent publish has succeeded against the
      current schema, per §6.

Not on this list, deliberately: the audited image cache (14 G) and the OSM index and PBFs (13.8 G). They
dominate the volume and they are active, expensive inputs. Removing either needs a stated regeneration
budget and a minimum-free-space gate, not a tick box.

## 9. Known gaps

- No cleanup, prune, rotate or expiry exists anywhere in the pipeline today. The only disk guard is the
  pre-flight refusal. The current effective policy is "grow until a run refuses to start".
- Two cleanup helpers exist in the code and are never called: `purge_nc_from_staging` and
  `gc_unreferenced_thumbs`, both in `pipeline/src/mt_pipeline/publish/images.py`, with callers only in
  tests. Wire them or delete them; a helper nobody invokes is a claim of hygiene rather than hygiene.
- No scheduler is installed, so the steady-state model in §2 is prospective.
- The log destination is out of repo (§4).
- No backup rotation and no restore runbook (§6).
