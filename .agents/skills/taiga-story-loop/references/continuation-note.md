# Minimal continuation note

Keep one short note per authorized story-loop run, outside the source
worktrees. It is a pointer to authoritative systems, not a durable workflow
engine. Store only the selected scope, ordered story/task sequence,
branch/worktree lineage, worker chats, PR identity, current stage,
approval/merge state, and recovery reference.

## Template

```text
Run: <run-id>
Scope: <project> story/epic #<ref> | stories: <ordered story refs> | tasks: <ordered task refs>
Repository: <absolute path> | remote: <name> <url>
Base: <remote>/<base-ref> @ <base-sha>
Topology: <standalone-story-direct-master or epic-shared-feature>
Feature: <branch/worktree/head for epic, or none (standalone direct-to-master)>
Current: story #<ref> | task/stage: <ref or stage>
Story branch: <branch> | worktree: <absolute path> | base: <sha>
Implementer: <thread-id> @ <host-id> | reviewer: <thread-id> @ <host-id>
Pair: <created/reused> | IDs resolved: <yes/no> | authorization: <scope marker>
Review mode: <per_task/story_end_only> | approved HEAD: <sha or pending>
PR: <url or pending> | base: <master or feature branch> | head: <sha>
PR delivery: <not_ready/ready/reused/created/unknown> | link evidence: <url or pending>
Approval: <pending/yes/no/stale> | prompt: <selectable/plain-text>
Review: <pending/approved/changes_requested>
Integrated review: <not_applicable/pending/findings/accepted> | profile: <model/effort> | head: <sha or pending>
Final delivery: <not_ready/ready/created/unknown> | base: <master> | head: <sha or pending>
Merge: <pending/merged/closed_unmerged/unknown>
Next: <one concrete action>
Recovery: <automation-id or none>
```

Values are updated only after their source system confirms a change. Keep the
previous note recoverable, and never use a note's claim as proof that a Git,
Codex, PR, or Taiga mutation succeeded.

## Replace current state

Rewrite the complete snapshot when an operational fact changes; never append
setup milestones, correction history, review findings, acceptance transcripts,
or repeated `Next` entries. Keep one value per template field. A correction
replaces the current revision and task/review state, supersedes approval for
the old HEAD, and replaces the next action. Preserve unresolved external
operations and user gates until their authoritative outcome is known.

Add these current facts to the template:

```text
Worker cursors: implementer <cursor or none> | reviewer <cursor or none>
Task state: <current revision> | <implementing/reviewing/accepted/blocked>
Gate: <none/user_input/approval/trial> | <unresolved question or decision reference>
Pending action: <none or external operation identity and unknown outcome>
Evidence: <current handoff/review/check references; no copied findings>
```

Keep authorization boundaries, topology, PR/base/head approval identity, worker
hosts and cursors, automation identity, and unresolved trial inputs in the
current note. For a newly created standalone run, `Topology` is
`standalone-story-direct-master`; for an epic it is `epic-shared-feature`.
Older active notes may omit `Topology`: preserve their existing
feature/story branch, worktree, PR, worker, cursor, and recovery identities
exactly and classify them as legacy feature-based runs until they are
explicitly reconciled. Do not rewrite those identities during migration.
Use explicit `pending`, `unknown`, `none`, or `not_applicable` values rather than
dropping a safety-relevant fact. Completed tasks need only ordered refs and a
concise evidence pointer, not a per-task account of every correction.

Use `scripts/write-continuation-note.ps1 -NotePath <absolute note path>
-Snapshot <ordered dictionary of template labels to single-line strings>` to
replace the note. It writes a complete UTF-8 snapshot atomically, keeps one
`.previous` backup, and leaves identical snapshots untouched. It rejects unknown
fields, missing core fields, multiline values, values over 1024 characters,
and snapshots over 16 KiB before changing the existing note. These are context
bounds, not permission to truncate unresolved facts: shorten evidence to
references, and stop for reconciliation if a required fact cannot be retained.
The helper only persists supplied observations; it does not verify their truth
or infer task acceptance, approval, or merge.

For an existing accumulated note, first preserve it as a separate historical
evidence file, then reconcile and write the current snapshot. Store only its
path under `Evidence`; routine reads never include that file or `.previous`.
Do not migrate or edit another active run without authorization.

## Healthy heartbeat versus recovery

The scheduled prompt names the current note path, run identity, and automation
identity and follows this read budget:

1. Read only the current snapshot. An unresolved external outcome or missing
   identity opens reconciliation before any wait. Otherwise, if a recorded
   user-input, approval, or trial gate remains unanswered, end silently.
   Elapsed time is not an answer.
2. For an active worker wait, take one compact `wait_threads` snapshot using
   the recorded thread/host IDs and `afterCursor`, with `timeoutMs: 0`. Preserve
   returned cursors in place when they change. Ongoing work or an unchanged
   state ends silently, without appending tick records or timestamps.
3. Only new actionable worker evidence, a failure, missing/ambiguous identity,
   an unknown external result, a user response, or an explicit resume after
   interruption opens recovery. Load only the relevant evidence references
   and authoritative systems for that action, then replace the snapshot.

Healthy and unanswered user waits do not reread tickets/comments, source,
diffs, tests, historical notes, or full chat transcripts; they do not repeat
prompts or send worker messages. A missing/corrupt snapshot requires
reconciliation, never guessed identities or new duplicate workers. A genuine
restart still uses the reconciliation steps below; the scheduled healthy
path does not invoke full restart reconciliation on every tick.

In per-task review, the implementer ending its turn in `awaiting_review` after
a confirmed handoff is expected. Reviewer messages resume that same chat. Do
not treat idle/completed chat status alone as interruption, resend readiness,
or wake the implementer to poll the reviewer. Recover only an evidenced missing
handoff, failed delivery, or interruption before dispatch; reconcile the
current task/revision and delivery outcome first.

Record context measurements in a separate evidence report: before/after UTF-8
bytes and line counts, the scenario and number of corrections/ticks, and
attributable usage only when available. Otherwise record usage as `unknown`;
bytes are a context-footprint measure, not tokens or measured cost savings.
Run `scripts/validate-continuation-note.ps1` for offline replacement, no-growth,
preservation, rejection, and no-op checks. Live heartbeat behavior and usage
attribution require separately authorized host evidence.

## Resume reconciliation

On restart, process the note in this order:

1. Verify the repository path, remote URL, base mapping, recorded topology,
   and recorded HEAD with Git. Fetch only after the run is authorized. A dirty
   user checkout remains untouched.
2. Inspect existing managed worktrees and branches for the recorded feature
   and story identities. A standalone run has no feature object to create or
   infer. If the path, branch, repository, and base match, reuse the object.
   If a create returned an unknown outcome, inspect before retrying.
3. Inspect the recorded implementer/reviewer thread and host IDs, pair outcome,
   and PR URL. Reuse matching chats/PRs; do not create duplicates because the
   note is stale or incomplete. A pending client ID is not a worker ID; resolve
   it through the authoritative thread inventory before messaging.
4. Read Taiga status/comments and the provider's PR state, then refresh the
   note with the authoritative result. Conflicting ownership or lineage is a
   blocker for user input.

Resume returns to the recorded current stage. A failed review uses the same
story checkout. A missing or unconfirmed external result remains pending or
unknown; it is never treated as success by timeout.

## Approved-merge advancement

For an epic, the next story branch may be created only when all of these are
observed:

The provider confirms the previous PR merged into the recorded feature branch
before the next story is dispatched.

- the current PR's base is the recorded feature branch;
- the provider reports the PR merged, not merely approved or closed;
- the merge result is reconciled to the repository and the feature branch has
  the updated authoritative HEAD; and
- the continuation note records `Merge: merged` and a new `Next` action.

If the PR is open or changes are requested, continue the current story. If it
is closed without merge, conflicting, or response-lost, keep the current story
waiting and ask for reconciliation or user input. Do not create the next story
branch from a stale local feature checkout, the story head, or the default
branch. Once a merge is confirmed, capture the updated feature HEAD and use
that SHA as the next story's base.

A standalone story has no next-story gate: its direct-to-`master` story PR uses
the exact reviewed story HEAD, and the run ends only after the provider
confirms that explicit merge.
