# Diagnostics Export Mockups

HTML wireframes for #269's Settings diagnostics export flow. The design canvas is iPhone 17e at 390 x 844.

Artifacts:

- `diagnostics-default.png` from `wf-diagnostics-default.html`
- `diagnostics-ax.png` from `wf-diagnostics-ax.html`

Render command used on macOS:

```bash
qlmanage -t -s 1800 -o docs/design/log-export docs/design/log-export/wf-diagnostics-default.html
mv docs/design/log-export/wf-diagnostics-default.html.png docs/design/log-export/diagnostics-default.png
qlmanage -t -s 1800 -o docs/design/log-export docs/design/log-export/wf-diagnostics-ax.html
mv docs/design/log-export/wf-diagnostics-ax.html.png docs/design/log-export/diagnostics-ax.png
```

Validation notes:

- Settings entry sits after Storage and before Onboarding.
- Review screen uses a real time-window control: 15 minutes, last hour, everything.
- Raw preview shows a plaintext session flow; no decode table is present.
- The not-included privacy promise is exactly device name, exact location and search wording in default and accessibility-size renders.
- Scrub failure is a user-visible, fail-closed state.
- Plaintext pack metadata, place identity, viewport scale and object URLs are deliberate: the user chooses to share a file that reconstructs the session flow without exact coordinates.
