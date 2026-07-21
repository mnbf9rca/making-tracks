# Diagnostics Export Mockups

HTML wireframes for #324's redesigned Settings diagnostics export flow. The
design canvas is iPhone 17e at 390 x 844.

Artifacts:

- `diagnostics-default.png` from `wf-diagnostics-default.html`
- `diagnostics-ax.png` from `wf-diagnostics-ax.html`

Render command used on macOS:

```bash
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-log-export-default --screenshot=docs/design/log-export/diagnostics-default.png --window-size=1800,1800 file://$PWD/docs/design/log-export/wf-diagnostics-default.html
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-log-export-ax --screenshot=docs/design/log-export/diagnostics-ax.png --window-size=1800,1800 file://$PWD/docs/design/log-export/wf-diagnostics-ax.html
```

Validation notes:

- Settings carries one Diagnostics row after Storage and before Onboarding.
  Delete logs appears inside the Diagnostics context and requires confirmation.
- The selected window and the actual export do not silently disagree: the review
  screen surfaces "Showing last hour to include this session" beside the size
  estimate, reflecting #352's session-covering default. The Try 15 min recovery
  remains an explicit short-window action.
- The icon grid names every included and excluded class, including map packs.
  Icons augment the class names rather than replacing them; the accessibility
  render drops supporting blurbs before it drops class names.
- The "Share boundary" jargon is removed, but the consent beat remains: the
  prepared state says the system share sheet opens and the user chooses the
  recipient. The preview shows plaintext session flow and plaintext object
  paths, matching the shipped export format.
- Action styling follows the Making Tracks action-bar hierarchy. Recovery is
  primary; Delete logs is destructive-secondary and confirmation-gated.
