# Persistent story worker pair

The story owns one ordinary implementation chat and one ordinary reviewer chat
for its entire run. The coordinator creates or reuses both chats after the
single `Start` confirmation; neither worker creates the other worker. The pair
is reused for every task, correction, and final review in the story.

## Exact profiles and creation order

The setup record must carry the exact profiles below. An unavailable profile is
a blocker; the coordinator must not silently substitute another model or
effort:

| Chat | Model | Effort | Responsibility |
| --- | --- | --- | --- |
| Implementer | `gpt-5.6-luna` | `xhigh` | sole source writer, checks, commits, and Taiga task progress |
| Reviewer | `gpt-6.1-sol` | `medium` | read-only review of the frozen revision, findings, task acceptance, and final story approval |

Use the stable role-based titles in [work-item conversation names](conversation-naming.md).
For a user-story pair, create `User Story #<ref> Implementer` and
`User Story #<ref> Reviewer`. For an epic-level pair, create
`Epic #<ref> Implementer` and `Epic #<ref> Reviewer`. The selected work-item
reference must also be present in each bootstrap/full assignment; a title is a
human-facing label, not the authoritative routing identity.

After the story branch/worktree receipt is verified, the coordinator:

1. creates the implementer ordinary chat with `create_thread`, passing the
   role-based work-item title in its `title` field;
2. resolves its result to a usable `threadId` and records the returned host;
3. creates the reviewer ordinary chat with the same story/worktree receipt and
   its role-based work-item title;
4. resolves the reviewer result to a usable `threadId`; and
5. sends the full role assignments only after both IDs are usable.

The initial creation prompt may be a short bootstrap that identifies the story,
role, exact profile, and coordinator ID. It must not ask a worker to create a
peer. The full assignment names the coordinator, both worker IDs, the absolute
story worktree/branch, the scope topology, the story PR base, the ordered task
scope, and the user-confirmed authorization record. The reviewer receives the
implementer ID and the implementer receives the reviewer ID before task work
begins.

## Pending creation and reuse

`create_thread` can return a pending `clientThreadId` while setup is running.
That value is not a usable destination and must never be passed to
`send_message_to_thread`, `wait_threads`, or a worker prompt. The coordinator
waits for the creation operation to finish, then re-reads the thread inventory
and matches the requested story/role/worktree identity to the resulting real
`threadId` and `hostId`. A timeout, ambiguous match, or missing host leaves the
pair unresolved and blocks dispatch; it does not justify creating a duplicate.

On resume, inspect the continuation note and authoritative thread inventory
first. Reuse a matching implementer/reviewer pair, even when the note is
incomplete. Create a replacement only after the provider confirms that the
original chat cannot be used and the user authorizes the changed pair.

## Authorization and destinations

The setup confirmation is the source of authority. It must explicitly include
worker-to-worker and worker-to-coordinator messaging for this story, in
addition to the coordinator's ordinary dispatch and review actions. The
coordinator passes the same immutable authorization record to both workers;
routine findings and corrections stay within the worker pair, while worker
messages can report exceptional facts or request coordination but cannot widen
the authorization.
Each assignment includes a destination table:

| Sender | Destination | Purpose |
| --- | --- | --- |
| Implementer | reviewer | task-ready and correction-ready handoffs |
| Implementer | coordinator | blockers, delivery uncertainty, revision conflicts, or scope decisions |
| Reviewer | implementer | routine findings and exact-revision task acceptance |
| Reviewer | coordinator | final story approval and exceptional escalation |
| Coordinator | implementer, reviewer | scoped assignments, exceptional escalation, and recovery coordination |

## Lifecycle event ownership

Performance recording observes the transitions already owned by the pair; it
does not add a workflow action, a worker, a poll, or a telemetry-only message.
The actor at the real boundary appends one version-1 event through
`.agents/skills/taiga-story-loop/scripts/write-performance-event.ps1` using the
run, project, story, and explicitly selected `reviewMode` from setup. The
event's `eventId`/`transitionId` and `phaseId`, `correctionId`,
`reviewRequestId`/`reviewAttemptId`, or `waitId` identity are stable across
retries. Replaying a handoff or
observing an old revision is a duplicate/stale observation, not a new attempt.
Review event construction must explicitly set `supersedesReviewAttemptId` to
JSON `null`; it is not inherited from the finding that caused a correction.
Only the paired correction events carry that finding identity.

| Existing boundary | Event owner and event | Identity/boundary rule |
| --- | --- | --- |
| Confirmed `Start` and story-run initialization | coordinator: `story_started` | story scope; use the actual UTC start and setup provenance |
| First concrete work on a current task | implementer: `implementation_started` | task ref + phase ID; revision may be null before a commit |
| Frozen task-ready packet before direct delivery | implementer: `task_ready_for_review` | same phase ID + full revision; this does not prove delivery or review |
| Reviewer begins the exact request/attempt | reviewer: `review_started` | request ID + attempt ID + ordinal + review kind + exact revision; `supersedesReviewAttemptId=null` |
| Reviewer records a current finding or exact acceptance | reviewer: `review_findings` or `review_accepted` | same phase/request/attempt identity and revision; `supersedesReviewAttemptId=null` |
| Implementer begins a current correction | implementer: `correction_started` | new correction ID/phase ID; link the finding with `supersedesReviewAttemptId` |
| Corrected packet is frozen before direct re-review | implementer: `correction_ready` | same correction/phase identity + new full revision; retain `supersedesReviewAttemptId` |
| Reviewer begins or closes the whole-story review | reviewer: `final_review_started`, `review_findings`, `final_review_accepted` | final-story request/attempt identity; exact reviewed HEAD; `supersedesReviewAttemptId=null` |
| An existing explicit coordinator/recovery wait opens or closes | coordinator: `wait_started`/`wait_ended` | stable wait ID and wait kind; never infer a wait from polling or elapsed time |
| Confirmed reviewed PR creation or reuse | coordinator: `pr_ready` | story scope + PR identity + exact reviewed HEAD; owned by task #157 |

In both modes, `implementation_started` and `task_ready_for_review` record the
implementation interval at the first concrete task work and the frozen
implementation-ready boundary. In `per_task`, task review, finding, correction,
and re-review events are then recorded at their actual pair boundaries. In
`story_end_only`, the implementation-ready `task_ready_for_review` event does
not dispatch a reviewer and no task-scoped review/correction events are
invented. Final-story review, finding, correction, and re-review boundaries
remain valid in both modes. Mode is copied from setup and is never inferred
from the event sequence. Known model/effort
profiles and source-backed usage snapshots are optional provenance; an
unavailable usage sample remains null/unavailable, never zero. Recorder or
snapshot failure is fail-open for the workflow and is surfaced as measurement
coverage, not retried as a new handoff or reported through a routine message.

The coordinator is not a routine finding, correction, task-ready, or task-acceptance
relay. The implementer owns current-version Taiga checklist/status/
progress reconciliation and next-task advancement after the direct acceptance
when the selected review mode allows it.

The implementer is the sole source writer while the pair is active. Once a
review handoff has a successful direct-delivery result for the assigned
reviewer, it ends its turn and does not edit source, move the branch, or start
later-task work until a current reviewer message or explicit reconciliation
resumes it. A failed or unknown delivery is not a healthy review wait and is
reconciled by the coordinator before any redispatch. The coordinator records the pair IDs, host IDs, creation/reuse outcome, branch
receipt, authorization summary, and a reference to the first assignment message
in the continuation snapshot, replacing superseded values. Retain current
worker cursors; keep assignment text in the worker chat. This is connection
evidence, not reviewer acceptance.
