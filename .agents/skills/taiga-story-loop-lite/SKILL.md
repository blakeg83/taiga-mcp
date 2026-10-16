---
name: taiga-story-loop-lite
description: Run one Taiga user story through a two-worker implementation and review loop.
---

# Taiga story loop lite

Use this skill for exactly one explicitly selected Taiga user story. Resolve the
story, repository, and base branch before setup. The workflow has exactly three
participants: the Coordinator, one Implementer, and one Reviewer.

## Coordinator setup

The Coordinator is the user's only contact. It reads the story scope, resolves
the repository, and creates the story branch and shared worktree. It creates
exactly two persistent conversations named:

- `User Story #<ref> Implementer`
- `User Story #<ref> Reviewer`

Configure each conversation with the requested model and reasoning effort using
capabilities available on the current host, then verify the returned identities
and settings. Never assume creation or model configuration succeeded. Give both
workers the complete story requirements, shared worktree path, repository/base
branch, their role, and the other worker's conversation identity. Dispatch the
Implementer after both workers are confirmed.

After dispatch, remain idle. Do not poll, monitor, relay routine messages,
update Taiga, or participate in corrections. Resume only for final approval or
a blocker. The Coordinator alone performs Git and GitHub operations.

## Implementer

Read the complete story and acceptance criteria. At the start, set the story to
the project's existing In Progress status and add concise, meaningful progress
updates in Taiga. Implement the whole story in the shared worktree and run the
relevant local checks. Send the Reviewer a direct ready-for-review message with
the changed files, summary, and verification results, then stop editing while
review is pending.

On a direct `CHANGES REQUESTED` message, make the requested corrections, rerun
relevant checks, update Taiga, and send the same Reviewer a new review request.
Use the same conversation for every correction round.
Never run Git or GitHub commands, even for status or diff inspection. Never
contact the Coordinator for routine progress.

## Reviewer

Independently read the story and inspect the actual shared-worktree files. Check
the complete acceptance criteria and relevant local verification. For
`CHANGES REQUESTED`, record concise actionable findings and the review phase in
Taiga, then send the findings directly to the Implementer. Routine findings are
not blockers.

For `APPROVED`, confirm the criteria, reviewed file scope, and verification
results in Taiga, freeze the reviewed workspace, and notify the Coordinator
directly. Do not edit source files or run Git or GitHub commands. After the
Coordinator supplies the PR URL and verified commit SHA, record both in Taiga;
do not mark the story complete unless the project's workflow requires it.

## Blockers and delivery

Either worker may send the Coordinator a `BLOCKED` message containing what is
blocked, why work cannot continue, relevant attempted actions or technical
details, and the decision or intervention required. The Coordinator reports it
to the user and stops. Do not recover automatically, retry ambiguous actions,
replace workers, change models, schedule a resume, or add a heartbeat.

After explicit reviewer approval, the Coordinator confirms the Implementer is
idle, inspects status and the complete diff, verifies it matches the reviewed
scope, commits, verifies the commit, pushes, and creates a PR against the
configured base branch (normally `master`). The PR includes the story reference,
summary, and verification results. Send the PR URL and verified commit SHA to
the Reviewer for the final Taiga update and report the URL and summary to the
user. Never merge automatically.

This skill is instruction-driven only. It must not add telemetry, token or
performance tracking, event ledgers, persistent workflow state, continuation
files, background monitoring, recovery infrastructure, per-task or epic loops,
additional workers, custom test runners, CI workflows, or helper scripts.
