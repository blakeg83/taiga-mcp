# Yes/No story merge gate

The coordinator presents the exact reviewed story PR and waits for a scoped
user decision. The prompt is a real approval boundary, not a status update:

```text
Story #<ref> PR ready: <url>
Repository: <repository>
Scope: <story scope>
Base: <integration feature branch>
Head: <reviewed commit SHA>

Yes — merge and continue to the next ordered story
No — hold for feedback

Merge this exact PR and continue? Reply Yes or No.
```

When selectable UI is unavailable, use the same plain-text wording and accept
only an explicit `Yes` or `No` response. An empty response, timeout, unrelated
text, or a worker message is `no_response`; it is never approval.

## Decision table

| Observed input/state | Merge action | Story/next-story action |
| --- | --- | --- |
| `Yes`, PR URL/repository/base/scope/head still match, provider confirms merged | authorized merge result is verified | update truthful Taiga state, refresh feature HEAD, then begin the next ordered story |
| `No` | none | retain the current PR and hold for feedback |
| no response or invalid response | none | retain the current PR and wait silently for a user decision |
| `Yes` but PR URL, repository, head, base, or story scope changed | none | mark approval stale and return the same story pair for fresh review/user approval |
| `Yes` but merge fails, conflicts, closes unmerged, or is unknown | none beyond the provider attempt | keep the story waiting; reconcile before retrying and do not start another story |
| requested changes after review | no merge | route the same story branch to the existing implementer/reviewer pair; a new reviewed HEAD needs a new prompt |

Only a verified provider merge unlocks the next story. Do not update a story to
Done, create the next story branch, dispatch the next worker, or claim feature
progress from a Yes alone, PR approval, a Taiga status, or a timeout. The
feature branch must be refreshed from the authoritative merged result before
the next story receives its base.

## Waiting and recovery

While waiting for the decision, keep one prompt and one pending approval record.
Do not dispatch workers or send repeated notifications because the user has
not answered. A recovery check may inspect the recorded PR, current head, and
Taiga state, but it preserves the wait unless a meaningful state change or
required user action is observed.

An approval is bound to the PR URL, repository, base branch, reviewed head, and
story scope shown in the prompt. Any source change or material scope change
invalidates it. Re-read those facts immediately before a merge attempt and
reconcile unknown provider results before any further write.
