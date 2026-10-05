# Issue #81: continuation context validation

The repo-local `taiga-story-loop` now replaces complete current snapshots via
`scripts/write-continuation-note.ps1`. The writer rejects history fields,
multiline values, missing core facts, and oversized context before changing
the existing note. Atomic replacement retains one previous snapshot; identical
observations leave both current note and backup untouched.

The continuation, setup, worker-pair, and merge-wait guidance now routes healthy
ticks through the current snapshot and at most one compact worker wait using
saved cursors. Unanswered user gates remain silent. Uncertain external results
require reconciliation before waiting or retrying. Full history and source
inspection are reserved for actionable changes or genuine recovery.

## Offline evidence

Run `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-continuation-note.ps1`.
This executes the production persistence helper against disposable synthetic
data, preserving an accumulated historical note as a separate evidence file.

| Measurement | Before | After |
| --- | ---: | ---: |
| UTF-8 bytes | 18,046 | 996 |
| Lines | 81 | 21 |

One hundred fixed-width corrections replace revisions/cursors without growing
the 996-byte snapshot. One hundred identical observations leave the note's
content, modification time, and backup unchanged. Additional checks preserve
worker/run/automation identities, authorization, exact approval identity,
unresolved trial inputs, and unknown external operations. Invalid snapshots
leave the current note and backup intact. Initial creation and cleanup of
temporary output are also checked.

All nine story-loop validation scripts and the skill-creator `quick_validate.py`
passed. The .NET server is unchanged.

Attributable token usage and cost: **unknown**. These byte/line counts describe
the synthetic persistence fixture, not the original live run or measured token
savings. Live scheduled behavior was not exercised. Existing active notes,
installed copies, and saved heartbeat prompts require authorized migration:
archive accumulated evidence separately, reconcile current facts, replace the
snapshot, and update the saved prompt to use the documented read budget.
