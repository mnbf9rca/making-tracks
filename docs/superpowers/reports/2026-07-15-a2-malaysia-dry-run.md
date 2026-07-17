# WP-A2 Malaysia Reconcile Dry Run

Date: 2026-07-15
Branch: `wp-a2-impl` stacked on `wp-acquire-impl`
Input: copied VPS Malaysia `work.db` from `real-malaysia-20260715`

Command:

```bash
cp /data/mt-data/malaysia/work.db /tmp/malaysia-a2-dryrun.db
uv run --extra dev mt-pipeline --region malaysia reconcile \
  --db /tmp/malaysia-a2-dryrun.db \
  --run-id real-malaysia-20260715 \
  --version 20260715T000000Z
```

Result:

- Reconcile completed successfully.
- Places written: 5,036.
- Registry bytes: 1,256,972.
- Review file bytes: 20,604.
- Stage marker: `reconcile`, run id `real-malaysia-20260715`.

Sample places:

```text
mt1_0006YWREDNFW6QJNRKQHVZDTTF | Serdang Depot | ["wd:Q24884636", "wp:50863174"]
mt1_000TC4B3YK5FC552JACZBF6A9S | Tugu Peringatan Perang Dunia Pertama | ["osm:node/8929779503"]
mt1_001Q9H6YKMQ02X46A20149VBND | ss19 | ["osm:node/8308298319"]
```

This was run against a copied DB and did not mutate the retained VPS Malaysia working store.
