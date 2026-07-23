# Any-List Saved Mockups

HTML wireframes for #372's ruled Saved semantics. The design canvas is iPhone
17e at 390 x 844.

Artifacts:

- `save-any-list-default.png` from `wf-save-any-list-default.html`
- `save-any-list-ax.png` from `wf-save-any-list-ax.html`

Render command used on macOS:

```bash
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-save-any-list-default --screenshot=docs/design/save-any-list/save-any-list-default.png --window-size=1350,1040 file://$PWD/docs/design/save-any-list/wf-save-any-list-default.html
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-save-any-list-ax --screenshot=docs/design/save-any-list/save-any-list-ax.png --window-size=1350,1040 file://$PWD/docs/design/save-any-list/wf-save-any-list-ax.html
```

Validation target:

- A place in only the custom Date night list reads Saved on the place card.
- Tapping Saved opens the existing list picker; it never quick-removes a
  membership.
- Date night is checked and Want to go is unchecked.
- Removing Date night removes the final membership, so the refreshed card reads
  Save and no custom-list chip remains.
- The same three-state flow remains readable at accessibility text size, with
  card actions stacked and list rows given larger touch targets.
- Red dashed lines mark the fold above fixed action areas.
