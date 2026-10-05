# Yes/No story merge gate

The coordinator presents the exact reviewed story PR and waits for a scoped
user decision. For a new standalone story this is the direct-to-`master`
release gate. For an epic it is the story-to-feature integration gate and does
not release the feature to `master`. An active legacy standalone run uses its
recorded story-to-feature PR as a compatibility integration gate, followed by
the legacy final feature-to-`master` release. The prompt is a real approval
boundary, not a status update:

```text
Story #<ref> PR ready: <url>
Repository: <repository>
Scope: <story scope>
Topology: <standalone-story-direct-master, epic-shared-feature, or legacy-standalone-feature>
Base: <master for new standalone, recorded feature branch for epic or legacy>
Head: <reviewed commit SHA>

Epic: Yes — merge and continue to the next ordered story
Standalone: Yes — merge this exact PR
Legacy standalone: Yes — merge this exact PR and continue to final release
No — hold for feedback

Merge this exact PR and continue along the recorded path? Reply Yes or No.
```

When selectable UI is unavailable, use the same plain-text wording and accept
only an explicit `Yes` or `No` response. An empty response, timeout, unrelated
text, or a worker message is `no_response`; it is never approval.

## Decision table

| Observed input/state | Merge action | Story/next-story action |
| --- | --- | --- |
| `Yes`, PR URL/repository/base/scope/head still match, provider confirms merged | authorized merge result is verified | standalone: update truthful Taiga state and end the run; epic: refresh feature HEAD and begin the next ordered story; legacy standalone: refresh the preserved feature HEAD and continue to final feature-to-`master` delivery |
| `No` | none | retain the current PR and hold for feedback |
| no response or invalid response | none | retain the current PR and wait silently for a user decision |
| `Yes` but PR URL, repository, head, base, or story scope changed | none | mark approval stale and return the same story pair for fresh review/user approval |
| `Yes` but merge fails, conflicts, closes unmerged, or is unknown | none beyond the provider attempt | keep the story waiting; reconcile before retrying and do not start another story |
| requested changes after review | no merge | route the same story branch to the existing implementer/reviewer pair; a new reviewed HEAD needs a new prompt |

Only a verified provider merge unlocks the next epic story. A standalone story
has no next-story dispatch, and a legacy standalone run has no next-story
dispatch either: its verified story merge unlocks only the preserved final
feature-to-`master` delivery. Do not update a story to Done, create the next
story branch, dispatch the next worker, or claim feature progress from a Yes
alone, PR approval, a Taiga status, or a timeout. An epic or legacy feature
branch must be refreshed from the authoritative merged result before its next
recorded delivery step.

## Waiting and recovery

While waiting for the decision, keep one prompt and one pending approval record.
Do not dispatch workers or send repeated notifications because the user has
not answered. Healthy ticks read only the current continuation snapshot and end
silently while the gate is unanswered. After a user response or a meaningful
change requiring reconciliation, a recovery check may inspect the recorded PR,
current head, and Taiga state. Follow the read budget in
[minimal continuation note](continuation-note.md).

An approval is bound to the PR URL, repository, base branch, reviewed head, and
story scope shown in the prompt. Any source change or material scope change
invalidates it. Re-read those facts immediately before a merge attempt and
reconcile unknown provider results before any further write.
