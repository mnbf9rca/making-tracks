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
- Raw preview keeps object identifiers hashed and includes the decode table in the bundle.
- The not-included privacy promise is identical in default and accessibility-size renders.
- Scrub failure is a user-visible, fail-closed state.
