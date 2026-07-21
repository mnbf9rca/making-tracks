# Visits Editing Mockups

HTML wireframes for #221's Tracks visit editing surface. The design canvas is
iPhone 17e at 390 x 844.

Artifacts:

- `visits-editing-default.png` from `wf-visits-editing-default.html`
- `visits-editing-ax.png` from `wf-visits-editing-ax.html`

Render command used on macOS:

```bash
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-visits-editing-default --screenshot=docs/design/visits-editing/visits-editing-default.png --window-size=1800,1800 file://$PWD/docs/design/visits-editing/wf-visits-editing-default.html
'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --disable-background-networking --disable-component-update --disable-sync --no-first-run --no-default-browser-check --user-data-dir=/private/tmp/chrome-visits-editing-ax --screenshot=docs/design/visits-editing/visits-editing-ax.png --window-size=1800,1800 file://$PWD/docs/design/visits-editing/wf-visits-editing-ax.html
```

Validation notes:

- Rows are visit events, not places. Row identity is `visits.id`; repeated visits
  to the same place remain separate rows.
- Same-day ordering is represented as `visit_order`. Consumers must order by
  day, then `visit_order`, and never infer same-day truth from `visited_at`.
- Date editing moves the visit to a local calendar day while preserving the
  recorded time-of-day display. It does not fabricate an exact time for the
  user's remembered order.
- Reorder controls only appear in the full chronological event view. Focused or
  filtered views can edit/delete rows, but do not pretend to own the full day's
  sequence.
- Loved remains place-level for this build. The heart appears on each row for
  that place, and toggling it affects the place across its visit rows.
- Delete is row-addressed and first-class for the #217 un-see fallback path.
  A route from a place card can land on repeated visits for that place without
  collapsing them into one place row.
- The rendering follows the #350 theming umbrella: quiet paper, system controls,
  restrained accent, and no route-recorder language.
