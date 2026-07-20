# Offline Maps Empty-Index Mockups

HTML wireframes for #247/#249's fail-closed Offline Maps state. The design canvas is iPhone 17e at 390 x 844.

Artifacts:

- `offline-maps-empty-installed-default.png` from `wf-empty-installed-default.html`
- `offline-maps-empty-installed-axxxl.png` from `wf-empty-installed-axxxl.html`

Render command used on macOS:

```bash
qlmanage -t -s 1800 -o docs/design/offline-maps docs/design/offline-maps/wf-empty-installed-default.html
mv docs/design/offline-maps/wf-empty-installed-default.html.png docs/design/offline-maps/offline-maps-empty-installed-default.png
qlmanage -t -s 1800 -o docs/design/offline-maps docs/design/offline-maps/wf-empty-installed-axxxl.html
mv docs/design/offline-maps/wf-empty-installed-axxxl.html.png docs/design/offline-maps/offline-maps-empty-installed-axxxl.png
```

Validation notes:

- `regions.json` is the pruned production list; the app offers everything in it.
- When no region index is available, the named-zone list is empty rather than falling back to a compiled allowlist.
- Installed packs remain visible in Storage so the user can understand local disk use even when the catalog is unavailable.
- No download, update or delete affordance is shown for a zone that is absent from the current production index.
