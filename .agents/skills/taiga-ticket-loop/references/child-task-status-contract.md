# Child-task status contract

Stories select child tasks from a complete `taskPages` capture. The capture
keeps closed tasks, records each selected task's numeric ID, project ID, parent
story ID, baseline status ID, version, criteria, and source alias, and refuses
to continue when pagination is missing, contradictory, or incomplete. A task
is selected by numeric ID; a story status ID is never reused as a task status
ID. A task with the wrong project or parent story is a scope error, not a
candidate for automatic repair. A nonempty selection also carries an immutable
packet binding (run/action IDs, packet and scope SHA-256 values, and exact
criteria per task); absent, empty, wrong-project, wrong-parent, or unselected
IDs fail closed. A complete empty task page remains a valid no-children scope.

Status mapping is resource- and project-specific. The coordinator resolves
actual status metadata IDs and stores logical states independently of labels:
`not_started`, `in_progress`, `awaiting_review`, `accepted`, and optional
`blocked`. If a task resource has no review status, `awaiting_review` falls
back to `in_progress`. Missing required mappings remain unresolved. The
mapping is never guessed from a label or copied from a story resource.

Worker progress is an append-only event stream in `task-progress.json`.
`started`, `blocked`, and `ready_for_review` events carry the run/action ID,
trusted ticket/project/parent identity, task ID, global sequence, current
revision, criterion IDs, evidence, and a deterministic event ID. Replaying the
same event is idempotent; a stale or gapped sequence is rejected. A correction
uses a new continuation action ID without rewriting prior event identities.
A final aggregate receipt may reference the events, but a progress event is
not a completed worker turn and cannot mark a task Done.

The coordinator consumes progress on its existing bounded observation. It
persists a per-consumer cursor and pending transitions, rejects caller cursor
drift, and acknowledges a transition only after its applied/unchanged outcome
is durable. Pending work survives a crash or failed write and is retried on
restart; only an acknowledged unchanged observation produces no write. Only
the coordinator may call the Taiga write path. Implementers and reviewers
provide task evidence; review receipts may carry accepted or rejected
`taskAcceptances`, and reviewer acceptance is required for the `accepted`/Done
transition.

Task writes are journaled through the existing Taiga task update path. Every
journal binds the authoritative version read immediately before the write,
the expected old and target status IDs, project/story/task identity, current
revision, and the run marker. A response-lost or version-conflict result is
uncertain until task detail/history is reread. A human status edit is
preserved and surfaced as unresolved; it is never overwritten by a blind
retry. A batch can retain successful sibling journals while reporting only
the failed or unresolved task.

Reopening is selective. A changed or rejected task is routed to the same
implementer and reopens only that task after new evidence is bound to the
current revision. Unrelated tasks and human status edits are preserved. New,
removed, or reparented tasks cause scope reconciliation; they are not silently
added to or removed from the selected set. Response loss and version conflicts
are reconciled by rereading authoritative task detail/history before deciding
whether a write was applied; blind retries are prohibited.
