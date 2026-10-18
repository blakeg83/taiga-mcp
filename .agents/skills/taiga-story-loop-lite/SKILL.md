---
name: taiga-story-loop-lite
description: Run one Taiga user story through a two-worker implementation and review loop.
---

# Taiga story loop lite

Use this skill for exactly one explicitly selected Taiga user story. Resolve the
story, repository, and base branch before setup. The workflow has exactly three
participants: the Coordinator, one Implementer, and one Reviewer.

Never use subagents in this workflow. This prohibition applies to every role
and every phase, including setup, implementation, review, and validation. Never
call `spawn_agent` or substitute a subagent for a conversation.

## Web UI testing

Use the built-in Codex browser for all web UI testing. Open the application in
the in-app browser (`iab`) through `mcp__cua_repl`, for example with
`cua.createBrowserTab("iab", applicationUrl, { visible: true })`, and use its
supported browser APIs to inspect and interact with the UI. Do not invoke the
computer-use skill or desktop automation for web UI testing. If the built-in
browser cannot perform a required check, report the unavailable check and its
limitation; do not silently substitute computer use or claim the check passed.

## Taiga status ownership

Resolve the project's existing story and task status IDs before implementation
using `list_user_story_statuses` and `list_task_statuses`. Use the actual project
statuses, never invented IDs. Resolve `Ready to Test` or `Ready for Test` to the
project's existing equivalent. If a required mapping is missing or ambiguous,
report the mapping blocker before proceeding.

| Work item | Transition | Owner and trigger |
| --- | --- | --- |
| Story | In Progress | Coordinator, after setup succeeds and before implementation dispatch |
| Task | In Progress | Implementer, when starting work on that task |
| Task | Done (project's completed task status) | Implementer, after that task's work and relevant checks pass |
| Story | Ready to Test / Ready for Test | Implementer, after all scoped tasks and story work are complete and relevant checks pass, before requesting review |
| Story | Done | Coordinator, after reviewer approval and successful PR creation |

The Implementer owns all task status changes, including reopening affected
tasks for corrections and completing them again after verification. The
Coordinator and Reviewer do not change task statuses. The Reviewer records
findings and approval in comments; it does not own story status transitions.
After corrections, the Implementer rechecks all scoped task statuses and
confirms the story is Ready to Test before requesting re-review. When there are
no child tasks, the same story completion and verification requirements apply.

Read the current entity version before each versioned update. Inspect each
write result and confirm the resulting status; a comment is not a status
transition. Never blindly retry an ambiguous write or automatically refresh a
conflicting version. Report failed or unconfirmed transitions as blockers and
never claim they succeeded. Include confirmed task statuses and the story's
Ready to Test status in the review handoff, and the confirmed Done status in
the Coordinator's final report.

## Coordinator setup

The originating chat is the Coordinator. Once the selected story's reference
is resolved, rename that same chat to `User Story #<ref> Coordinator` using
`mcp__codex_app__set_thread_title` with `title` set to that name and `threadId`
omitted to target the calling chat. Verify the rename succeeded before creating
the worker conversations. Do not create a separate Coordinator conversation.

The Coordinator is the user's only contact. It reads the story scope, resolves
the repository, and creates the story branch and shared worktree. It creates
exactly two new persistent conversations using
`mcp__codex_app__create_thread`, named and configured as follows:

- `User Story #<ref> Implementer`: GPT 5.6 Luna, xhigh reasoning;
  pass `model: "gpt-5.6-luna"` and `thinking: "xhigh"`.
- `User Story #<ref> Reviewer`: GPT 6.1 Sol, Medium reasoning;
  pass `model: "gpt-6.1-sol"` and `thinking: "medium"`.

Pass these model and reasoning settings explicitly in each creation call; do
not inherit defaults or rely on role-prompt text to configure them. If creation
is queued, resolve it to an actual conversation `threadId` before messaging;
a `clientThreadId` is not a conversation identity. Verify the returned identities
and effective settings. If conversation creation or either required setting is
unavailable or cannot be verified, report the exact limitation and stop before
implementation. Never fall back to subagents or different models or reasoning
levels. Never assume creation or model configuration succeeded. Give both
workers the complete story requirements, shared worktree path, repository/base
branch, their role, and the other worker's conversation identity.

Before dispatch, independently read the selected story and inspect its optional
epic relationship metadata. For every linked epic, use its positive internal ID
with `get_epic` and read the full description; include each epic identity and
the relevant requirements or constraints in both worker assignments. Explicitly
record when the story has no linked epics. An unusable relationship identity, an
inaccessible linked epic, or a material epic/story conflict is a specific
blocker before dependent work; do not silently omit context, guess, or expand
scope to sibling stories.

Before dispatch, discover all scoped child tasks with
`list_tasks(projectId, userStoryId, includeClosed=true)`, follow its pagination,
and use `get_task` for each task's full requirements. Establish one explicit
sequence for every scoped task: use an explicit sequence stated in the
story/task requirements, or otherwise use unambiguous numeric prefixes in task
titles and numeric order (for example `01`, `02`, `10`). If multiple remaining
tasks lack a clear sequence or the instructions conflict, report the ambiguity
as a blocker before task work; never infer order from response position or task
refs. Include the agreed sequence and the completed/incomplete status of each
task in both worker assignments. A zero-task story has an empty sequence and
still requires the normal story work and verification.

Use `mcp__codex_app__send_message_to_thread` with the actual conversation
identities for worker handoffs, corrections, approvals, and blockers. Preserve
the assigned model and reasoning settings throughout the same conversation pair.

Before dispatch, run one setup-only native capability probe with this same pair:
the Implementer sends a direct probe to the Reviewer and receives an
acknowledgement, and one worker sends a probe that demonstrably reaches or
resumes the Coordinator. Confirm both delivery paths from runtime results, not
from prompt text. If direct messaging or Coordinator wake/resume is unavailable,
report the exact unavailable capability and path to the user and stop before
implementation; do not poll, relay through a substitute, or create more workers.
Dispatch the Implementer only after both probes and model settings are confirmed.
After setup succeeds, set and confirm the story's In Progress status before
dispatching implementation. Include the resolved status mappings and these
ownership rules, epic context, and agreed task sequence in both worker
assignments.

After dispatch, remain idle. Do not poll, monitor, relay routine messages,
update Taiga during routine work, or participate in corrections. Resume only for final approval or
a blocker. The Coordinator alone performs Git and GitHub operations.

## Implementer

Independently read the complete story and acceptance criteria. Inspect its epic
relationship metadata and, for every linked epic, use `get_epic` to read the
full requirements before implementation. A story with no linked epic proceeds
normally. Treat an unusable relationship identity, inaccessible epic, or
material epic/story conflict as a specific blocker before dependent work; do
not guess or expand scope to sibling stories.

Discover all scoped child tasks with `list_tasks(projectId, userStoryId,
includeClosed=true)`, follow pagination, and use `get_task` for full task
requirements. Independently establish one explicit sequence: use an explicit
sequence in the story/task requirements, or otherwise unambiguous numeric task
title prefixes in numeric order. If multiple remaining tasks have no clear
sequence or instructions conflict, report the ambiguity before starting task
work; never use API response order or task refs as priority. Account for
already completed tasks without reopening them unnecessarily.

Work through the sequence strictly. For each incomplete task, read its current
version, transition it to In Progress, inspect and confirm that transition,
complete its work and relevant checks, then read its current version before
transitioning it to the project's completed task status and inspect and confirm
Done. A blocked or failed task prevents starting later tasks. The zero-task
case skips task transitions but still requires story work and verification.
The required sequential handling remains inside this single story workflow;
it does not create a per-task review loop. Maintain every scoped task's status
as specified above and add concise, meaningful progress updates in Taiga.

Implement the whole story in the shared worktree and run the relevant local
checks. Before handoff, confirm every scoped task is complete and set and
confirm the story's Ready to Test status. Send the Reviewer a direct
ready-for-review message with
the changed files, a normalized content snapshot for every changed path
(`path: present text <SHA-256>` for normalized text bytes,
`path: present binary <SHA-256>` for raw binary bytes, and `path: deleted` for
deletions), the epic context (or explicit no-epic result), the agreed task
sequence, confirmed status for every scoped task, the summary, and verification
results. Include a concise record of the required scenario walkthroughs,
identifying which were inspected locally versus exercised with native runtime
capabilities; do not call a walkthrough runtime exercise. Then stop editing
while review is pending.

For every snapshot in this workflow, use the repository `.gitattributes` text
rules (including `text=auto` detection) to classify files consistently as text
or binary. Hash UTF-8 bytes after converting CRLF and CR line endings to LF for
text files; hash raw bytes for binary files. Use this same canonicalization for
the Implementer, Reviewer, Coordinator working-tree preflight, and
post-commit verification.

On a direct `CHANGES REQUESTED` message, reopen only the affected tasks using
fresh versions and complete corrections in the established relative sequence;
do not bypass an affected predecessor. Rerun relevant checks, update Taiga,
reconfirm every scoped task and the story's Ready to Test status, and send the
same Reviewer a new review request. Use the same conversation for every
correction round.
Never run Git or GitHub commands, even for status or diff inspection. Never
contact the Coordinator for routine progress.

## Reviewer

Independently read the story and inspect the actual shared-worktree files.
Inspect its epic relationship metadata and, for every linked epic, use
`get_epic` to read the full requirements before review. A no-epic result is
valid. If an epic relationship identity is unusable, a linked epic is
inaccessible, or the epic and story materially conflict, record one concise
blocker comment in Taiga, send `BLOCKED` to the Coordinator through the
existing blocker path, and stop dependent review and delivery; do not silently
accept or downgrade an actual context failure to a review finding. Ordinary
missing-context or out-of-order implementation findings remain
`CHANGES REQUESTED` to the Implementer.
Check the complete acceptance criteria, the agreed child-task sequence, every
scoped task's requirements and confirmed status, and relevant local
verification. Recompute a normalized content snapshot from those files, using
`path: present text <SHA-256>` for normalized text bytes, `path: present binary
<SHA-256>` for raw binary bytes, and `path: deleted` for deletions; this
snapshot is the identity of the reviewed contents, not just a file-name scope.
Verify that task execution was sequential, that completed predecessors were not
needlessly reopened, and that corrections preserve the established relative
order. For
`CHANGES REQUESTED`, record concise actionable findings and the review phase in
a Taiga comment, then send the findings directly to the Implementer. Routine findings are
not blockers.

For `APPROVED`, confirm the criteria, exact reviewed file scope, content
snapshot, and verification results in Taiga and in the approval message, freeze
the reviewed workspace, and notify the Coordinator directly. Do not edit source
files or run Git or GitHub commands. After the Coordinator supplies the PR URL
and verified commit SHA, record both in Taiga. The Coordinator owns the story's
Done transition after PR creation.

## Blockers and delivery

Either worker may send the Coordinator a `BLOCKED` message containing what is
blocked, why work cannot continue, relevant attempted actions or technical
details, and the decision or intervention required. Before sending it, that
worker records the blocker in Taiga with one concise comment; the Implementer
also maintains any affected task's existing blocked status where applicable.
Preserve the status ownership above. If the Taiga write is unavailable, include that
failure in the blocker message rather than claiming it was recorded. The
Coordinator reports it to the user and stops. Do not recover automatically,
retry ambiguous actions, replace workers, change models, schedule a resume, or
add a heartbeat.

## Verification boundary

Exercise the essential paths with native runtime capabilities when available:
first-pass approval, at least one correction and re-review, and a genuine or
controlled blocker. For each story walkthrough, record whether it was inspected
from read-only examples/local instructions or actually exercised with native
runtime capabilities: linked and no-epic stories, multiple linked epics,
inaccessible or conflicting epic context, tasks returned out of sequence such
as `01`, `02`, `10`, an already completed predecessor, ambiguous order, a
blocked predecessor, ordered corrections, and zero- or one-task stories. A
walkthrough does not prove runtime execution. Record each outcome and the
capability evidence in the Coordinator's final report. This skill adds no
synthetic runner or recovery framework. If a host cannot exercise a path,
report the exact unavailable capability and the resulting unverified path;
never present it as passed.

After explicit reviewer approval, the Coordinator confirms the Implementer is
idle, inspects status and the complete diff, and computes the same canonical
snapshot from the current working-tree contents. Before committing, it verifies
every present digest, every deleted path, and the complete diff match the
reviewed snapshot and scope. Only then does it commit. After committing, it
independently computes the canonical snapshot from the resulting commit tree
and verifies it again; any mismatch stops delivery and is reported. The
Coordinator then verifies the commit, pushes, and creates a PR against the
configured base branch (normally `master`). The PR includes the story
reference, summary, and verification results. After successful PR creation, the
Coordinator sets and confirms the story's Done status and records the PR URL
and verified commit SHA in Taiga. If this update fails, report the created PR
and the outstanding status blocker without claiming the story is Done. Send the PR URL and verified
commit SHA to the Reviewer for the final Taiga update and report the URL and
summary to the user. Never merge automatically.

This skill is instruction-driven only. The required sequential handling of the
selected story's scoped tasks remains within this one workflow; it must not add
telemetry, token or performance tracking, event ledgers, persistent workflow
state, continuation files, background monitoring, recovery infrastructure,
per-task review loops, epic orchestration, additional workers, custom test
runners, CI workflows, or helper scripts.
