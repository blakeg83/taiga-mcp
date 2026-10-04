# Direct worker handoffs

The coordinator routes short, plain-language messages through the persistent
pair. A handoff carries only the context needed for the next action; the
assignment packet, repository, Taiga pages, and Git history remain the sources
of full detail. Do not require a JSON receipt, a copied ticket transcript, or a
new chat for an ordinary correction.

## Task-ready message

The implementer sends this to the reviewer and coordinator after the task's
implementation evidence and commit exist:

```text
Task #<ref> ready for review
Branch: <story-branch>
Revision: <commit SHA or stable revision range>
Changes: <one-sentence summary>
Checks: `<command>` — exit <code>; <concise result>
Next: reviewer, inspect this exact revision and report findings or acceptance.
```

The revision is immutable review input. The implementer waits in per-task mode;
it does not start the next ordered task while this task is awaiting review.

## Findings message

The reviewer sends findings directly to the implementer and copies the
coordinator only when coordination is needed:

```text
Task #<ref> findings
Reviewed: <commit SHA>
Severity: <blocking|non-blocking>
Finding: <specific observable defect or missing criterion>
Evidence: <file/check/result that demonstrates it>
Requested change: <smallest correction needed>
Next: implementer, correct the same story branch and return a new revision for review.
```

Findings name the reviewed SHA and do not edit the implementer's checkout. A
blocking finding reopens only the affected task. The coordinator does not
rewrite a finding or turn it into acceptance.

## Correction-ready message

The implementer returns to the same reviewer chat:

```text
Task #<ref> correction ready
Branch: <story-branch>
Previous review: <old SHA>
Revision: <new commit SHA or stable range>
Changes: <what addressed the finding>
Checks: `<command>` — exit <code>; <concise result>
Next: reviewer, re-review the new revision; prior acceptance is superseded.
```

The new revision is a new review input. The coordinator keeps the branch stable
while the reviewer is inspecting it and routes later findings to the same
implementer; it never creates a correction chat or allows the next task to
race the active per-task review.

## Route table

| Handoff | Sender | Destination | Stable identity |
| --- | --- | --- | --- |
| ready | implementer | reviewer, coordinator | task ref + revision |
| findings | reviewer | implementer, optionally coordinator | task ref + reviewed SHA |
| correction | implementer | same reviewer, coordinator | task ref + new revision |

If a destination is missing or a message has an unresolved worker ID, stop and
escalate to the coordinator. A worker message cannot authorize a new chat,
widen the story, skip a review, or change the branch base.
