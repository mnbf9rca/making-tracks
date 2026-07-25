# Pre-phase task ledger

Status ledger for issue-routed work while no phase is active (coordination.md → Supervision-loop contract → *No active phase*). Same rules as a phase `tasks.md`: builders append a status line per transition; fable reads it on the supervision loop. Stall threshold: 45 minutes.

Status vocabulary: `claimed → branch → tests green → PR open → review clean → ready-to-merge` (plus `blocked: <reason>` / `released`).

Format: one line per transition, newest last:
`- <UTC timestamp> <handle> #<issue> <status> [note]`

## Active

(none)

## Done (pre-phase, 2026-07-24 wave — recorded retroactively)

- 2026-07-25T01:37Z codex3 #221 merged as PR #453 (13452386); device-passed and closed 2026-07-25
- 2026-07-25T00:47Z codex2 #257 merged as PR #452 (fbf215f2); device-passed and closed 2026-07-25
- 2026-07-24T23:56Z codex1 #319 merged as PR #451 (2763aed5); closed
- 2026-07-24T21:23Z codex1 #324 merged as PR #449 (8bfdc5e9); device-passed and closed 2026-07-25
- 2026-07-24T20:49Z codex4 #446 merged as PR #450 (ce4888de); closed
