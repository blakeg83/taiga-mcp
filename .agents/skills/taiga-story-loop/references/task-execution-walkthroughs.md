# Synthetic ordered-task and blocker walkthroughs

These walkthroughs are synthetic evidence for the story-loop execution contract.
They do not call Taiga, GitHub, Codex, or a live repository. The executable
companion is `scripts/validate-task-execution.ps1`.

## Fixture

Story `synthetic-project` #900 has three dependent tasks in this declared
order:

1. #901 — establish the shared contract — no prerequisite;
2. #902 — consume the shared contract — depends on #901; and
3. #903 — verify the integrated behavior — depends on #902.

The discovered task mapping is synthetic but resource-specific:

```json
{
  "not_started": 101,
  "in_progress": 102,
  "awaiting_review": 103,
  "accepted": 104,
  "blocked": 105,
  "needs_info": 106
}
```

The fixture records versions, task status, checklist evidence, commit SHA,
parent-story comments, and the active task. The synthetic coordinator rejects
a second task while the current task is unaccepted; this is an execution gate,
not a claim that Taiga itself enforces dependencies.

## Ordered execution trace

| Step | Task | Action | Expected evidence/outcome |
| --- | --- | --- | --- |
| 1 | #901 | worker reads version 1 and sets `in_progress` | one active task; version 2 |
| 2 | #901 | required check exits 1 | checklist remains unchecked; task cannot become review-ready |
| 3 | #901 | worker repairs and reruns check | checklist evidence records exit 0 |
| 4 | #901 | commit `a901001`, set `awaiting_review`, add one story comment | ready-for-review, not accepted; task #902 is still untouched |
| 5 | #902 | worker attempts to start before #901 acceptance | rejected; no status/version/comment change to #902 |
| 6 | #901 | reviewer accepts the exact SHA | `accepted`; active task is released |
| 7 | #902 | worker starts, then records a prerequisite blocker | `blocked`, `isBlocked=true`; task #903 cannot start |
| 8 | #902 | blocker is resolved and task reopens | `in_progress`; blocker evidence is retained |
| 9 | #902 | human changes the status before the planned write | version conflict; human status is preserved and surfaced |
| 10 | #902 | worker rereads, reconciles, commits `a902001`, and requests review | current version used; one new story comment |
| 11 | #902 | reviewer rejects the exact SHA | task reopens to `in_progress`; rejection is not treated as acceptance |
| 12 | #902 | worker corrects, commits `a902002`, and requests review again | new revision-bound evidence; no duplicate old completion comment |
| 13 | #902 | reviewer accepts `a902002` | `accepted`; active task is released |
| 14 | #903 | worker starts and completes after #902 acceptance | ordered gate opens; commit/comment evidence recorded |

The failed check, blocked prerequisite, rejected review, and human version
conflict each stop or reject the unsafe transition. None is converted into a
Done/accepted claim by timeout, a stale version, a worker comment, or the mere
existence of a commit.

## Required assertions

The executable scenario must demonstrate all of the following:

- task #902 cannot start while #901 is only ready for review;
- a failed checklist/check leaves the task in progress and unchecked;
- task #903 cannot start while #902 is blocked or review-rejected;
- `isBlocked` and the blocker note are visible when a blocked status exists;
- a conflicting human version does not get overwritten by a blind retry;
- the corrected task uses a new commit and a new evidence comment;
- completion comments contain task ref, checklist evidence, check exit code,
  commit SHA, review state, and next action;
- no dependent task receives a status, commit, or completion comment before its
  prerequisite is accepted.

