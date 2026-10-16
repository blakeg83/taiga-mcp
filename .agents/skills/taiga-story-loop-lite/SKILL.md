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

After dispatch, remain idle. Do not poll, monitor, relay routine messages,
update Taiga, or participate in corrections. Resume only for final approval or
a blocker. The Coordinator alone performs Git and GitHub operations.

## Implementer

Read the complete story and acceptance criteria. At the start, set the story to
the project's existing In Progress status and add concise, meaningful progress
updates in Taiga. Implement the whole story in the shared worktree and run the
relevant local checks. Send the Reviewer a direct ready-for-review message with
the changed files, a normalized content snapshot for every changed path
(`path: present text <SHA-256>` for normalized text bytes,
`path: present binary <SHA-256>` for raw binary bytes, and `path: deleted` for
deletions), the summary, and verification results, then stop editing while
review is pending.

For every snapshot in this workflow, use the repository `.gitattributes` text
rules (including `text=auto` detection) to classify files consistently as text
or binary. Hash UTF-8 bytes after converting CRLF and CR line endings to LF for
text files; hash raw bytes for binary files. Use this same canonicalization for
the Implementer, Reviewer, Coordinator working-tree preflight, and
post-commit verification.

On a direct `CHANGES REQUESTED` message, make the requested corrections, rerun
relevant checks, update Taiga, and send the same Reviewer a new review request.
Use the same conversation for every correction round.
Never run Git or GitHub commands, even for status or diff inspection. Never
contact the Coordinator for routine progress.

## Reviewer

Independently read the story and inspect the actual shared-worktree files. Check
the complete acceptance criteria and relevant local verification. Recompute a
normalized content snapshot from those files, using `path: present text
<SHA-256>` for normalized text bytes, `path: present binary <SHA-256>` for raw
binary bytes, and `path: deleted` for deletions; this snapshot is the identity
of the reviewed contents, not just a file-name scope. For
`CHANGES REQUESTED`, record concise actionable findings and the review phase in
Taiga, then send the findings directly to the Implementer. Routine findings are
not blockers.

For `APPROVED`, confirm the criteria, exact reviewed file scope, content
snapshot, and verification results in Taiga and in the approval message, freeze
the reviewed workspace, and notify the Coordinator directly. Do not edit source
files or run Git or GitHub commands. After the Coordinator supplies the PR URL
and verified commit SHA, record both in Taiga; do not mark the story complete
unless the project's workflow requires it.

## Blockers and delivery

Either worker may send the Coordinator a `BLOCKED` message containing what is
blocked, why work cannot continue, relevant attempted actions or technical
details, and the decision or intervention required. Before sending it, that
worker records the blocker in Taiga with the existing blocked/review status
mapping and one concise comment. If the Taiga write is unavailable, include that
failure in the blocker message rather than claiming it was recorded. The
Coordinator reports it to the user and stops. Do not recover automatically,
retry ambiguous actions, replace workers, change models, schedule a resume, or
add a heartbeat.

## Verification boundary

Exercise the essential paths with native runtime capabilities when available:
first-pass approval, at least one correction and re-review, and a genuine or
controlled blocker. Record each outcome and the capability evidence in the
Coordinator's final report. This skill adds no synthetic runner or recovery
framework. If a host cannot exercise a path, report the exact unavailable
capability and the resulting unverified path; never present it as passed.

After explicit reviewer approval, the Coordinator confirms the Implementer is
idle, inspects status and the complete diff, and computes the same canonical
snapshot from the current working-tree contents. Before committing, it verifies
every present digest, every deleted path, and the complete diff match the
reviewed snapshot and scope. Only then does it commit. After committing, it
independently computes the canonical snapshot from the resulting commit tree
and verifies it again; any mismatch stops delivery and is reported. The
Coordinator then verifies the commit, pushes, and creates a PR against the
configured base branch (normally `master`). The PR includes the story
reference, summary, and verification results. Send the PR URL and verified
commit SHA to the Reviewer for the final Taiga update and report the URL and
summary to the user. Never merge automatically.

This skill is instruction-driven only. It must not add telemetry, token or
performance tracking, event ledgers, persistent workflow state, continuation
files, background monitoring, recovery infrastructure, per-task or epic loops,
additional workers, custom test runners, CI workflows, or helper scripts.
