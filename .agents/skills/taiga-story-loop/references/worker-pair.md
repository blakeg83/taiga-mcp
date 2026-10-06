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

After the story branch/worktree receipt is verified, the coordinator:

1. creates the implementer ordinary chat with `create_thread`;
2. resolves its result to a usable `threadId` and records the returned host;
3. creates the reviewer ordinary chat with the same story/worktree receipt;
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

The coordinator is not a routine finding, correction, task-ready, or task-acceptance
relay. The implementer owns current-version Taiga checklist/status/
progress reconciliation and next-task advancement after the direct acceptance
when the selected review mode allows it.

The implementer is the sole source writer while the pair is active. Once a
review handoff is confirmed, it ends its turn and does not edit source, move the
branch, or start later-task work until a current reviewer message or explicit
reconciliation resumes it. The coordinator records the pair IDs, host IDs, creation/reuse outcome, branch
receipt, authorization summary, and a reference to the first assignment message
in the continuation snapshot, replacing superseded values. Retain current
worker cursors; keep assignment text in the worker chat. This is connection
evidence, not reviewer acceptance.
