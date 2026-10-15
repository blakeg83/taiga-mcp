# Branch, worktree, and continuation contract

Review state follows the [clean committed revision
contract](revision-freeze.md). A branch/worktree receipt is not review
evidence until its expected branch, full HEAD, relevant diff range, and clean
tracked-source state are rechecked.

This contract keeps the story loop small while making its branch lineage and
resume point observable. It is a short note, not a registry or a workflow
state machine. Git, Taiga, Codex, and the pull-request provider remain the
authoritative systems. The selected scope chooses the topology described in
[scope-specific branch topology](branch-topology.md).

## Facts to retain

After setup is confirmed, retain only the facts needed to continue the selected
scope:

| Fact | Required value |
| --- | --- |
| Scope | project, story/epic ref, ordered task refs, and run identifier |
| Repository | absolute path, remote name/URL, resolved base ref, and captured base SHA |
| Topology | `standalone-story-direct-master` or `epic-shared-feature` |
| Feature integration | Epic: unique `codex/feature-<slug>-<run-suffix>` branch, worktree path, and current HEAD; standalone: `none (standalone direct-to-master)` |
| Current story | story ref, unique `codex/story-<ref>-<slug>-<run-suffix>` branch, worktree path, and base SHA |
| Review input | expected repository/worktree and branch, base SHA, pending full reviewed SHA, diff range/paths, and clean tracked-source state |
| Workers | current story implementer and reviewer chat IDs, when created |
| Integrated review workers | fresh epic-fix implementer and epic reviewer chat IDs/hosts, when the epic gate is reached |
| Review | PR URL, PR base/head, approval or wait state, and the next required action |
| Performance | optional compact schema/run/story/ledger pointer and last observed event identity; history stays in the external ledger |
| Recovery | one recovery automation ID, confirmed schedule state (`ACTIVE` or `PAUSED`), and any pending target |

Do not copy a ticket transcript, model output, full diff, or a second state
registry into the note. A missing value is an unresolved setup fact, not a
placeholder to guess.

Performance is initialized only after the submitted `Start` decision. The
coordinator invokes the existing recorder for the real `story_started` boundary
and then carries the pointer described in [the minimal continuation note](continuation-note.md).
The pointer is a recovery binding, not a ledger or a timestamp source. A
legitimate resume verifies the external ledger's last event and reuses its
`runId`; a missing or unverifiable event leaves historical coverage
unavailable. It must not create a second story start or reconstruct a missing
`occurredAtUtc`.

## Fresh base and topology setup

After the single setup confirmation and before worker dispatch:

1. Resolve the repository root, configured remote, default branch, and existing
   checkout state. Use `git rev-parse --show-toplevel`,
   `git remote get-url <remote>`, and `git ls-remote --symref <remote> HEAD`.
   A dirty user checkout is preserved; do not switch, reset, stash, or clean it
   to create the run branch.
2. Fetch the configured remote with `git fetch --prune <remote>` and capture
   `git rev-parse <remote>/<base-branch>`. The captured SHA is the only base
   for this run. A fetch failure, missing ref, or changed mapping blocks setup.
3. For a standalone story, create one managed Codex worktree from that captured
   SHA and create the unique story branch there. Verify the absolute path,
   branch, HEAD, captured base, clean tracked-source state, and repository identity. Record
   `Feature: none (standalone direct-to-master)` and `PR: ... | base: master`.
4. For an epic, create one managed Codex worktree from that captured SHA and
   create a unique `codex/feature-<slug>-<run-suffix>` branch there. Verify the
   absolute path, branch, HEAD, captured base, clean tracked-source state, and repository
   identity, then write the feature branch and current feature HEAD into the
   continuation note before creating a story worktree.
5. Never reuse a path or branch whose ownership cannot be reconciled. New
   runs must write the topology before worker dispatch.

Only a new epic creates a feature worktree. It is the integration line for
that run; it is not the user's checkout and it is not a worker's story
worktree. A legacy standalone resume may retain an existing recorded feature
worktree solely to complete its old delivery path.

## Story branch and worktree

For a new standalone story, create one managed worktree from the captured base SHA
and create a distinct `codex/story-<ref>-<slug>-<run-suffix>` branch there. The
story branch is the only branch in the run and its PR base is `master`.

For each story in an epic, after the preceding story is accepted according to
its stated approval boundary, read the continuation note and re-check the
feature branch with Git and the provider. Create one managed worktree from the
current feature HEAD, then create a distinct
`codex/story-<ref>-<slug>-<run-suffix>` branch in that worktree. Verify the
story branch, base SHA, clean status, and absolute path before passing the
path and branch receipt to the implementer and reviewer. The implementer is
the only source writer in that checkout; reviewers inspect the frozen revision
and return findings.

The supported handoff is explicit:

```text
create_worktree({ name: "<run>-story-<ref>", ref: "<captured-base-or-feature-head>", allowAsync: true })
→ wait for the operation to complete and use its returned workspace directory
git -C <workspace> switch --create <story-branch>
git -C <workspace> rev-parse --show-toplevel
git -C <workspace> branch --show-current
git -C <workspace> rev-parse HEAD
git -C <workspace> status --porcelain
git -C <workspace> diff --quiet HEAD --
git -C <workspace> diff --cached --quiet
git -C <workspace> ls-files --others --exclude-standard
```

The coordinator records the returned absolute path and verifies that the
repository root, story branch, HEAD/base SHA, and clean tracked-source checks
match the topology mapping. Declared ignored verification outputs may exist,
but an unexpected ignored path is reconciled separately. A pending worktree operation has no usable path; wait for
its completion rather than inventing one. A path or branch collision is
reconciled against the recorded scope and ownership, or blocks for user
input. The same receipt is passed to the implementer and reviewer chat. The
implementer may write source and commit on the story branch; the reviewer is
read-only and reviews the frozen commit from that same path/revision.

The new standalone story pull request targets `master` and ends only after its
explicit merge gate is verified. An epic story pull request targets the shared
feature branch. A legacy standalone story PR targets its preserved feature
branch; after its verified merge, the preserved feature HEAD is reviewed again
for the final legacy delivery before the separate final feature-to-`master`
gate, and no next story is dispatched. A
later epic story is based on the updated feature HEAD only after the provider
confirms that the preceding story PR merged into that exact feature branch. A
closed-unmerged, conflicting, or response-lost merge cannot advance an epic
or legacy delivery. Do not infer merge completion from a branch name, a local
checkout, a chat message, or a Taiga status alone.

## Resume and preservation

On interruption, read the continuation note first, then reconcile the current
Git worktrees/branches, Codex chats, PR, and Taiga status before creating
anything. If an existing object matches the recorded repository, branch, base,
and scope, reuse it and refresh the note. If a create or write has an unknown
outcome, inspect the authoritative system before retrying. If ownership or
lineage is ambiguous, stop for user input.

Resume never resets or deletes unrelated branches, user changes, worktrees, or
PRs. It never force-pushes. A failed review returns to the same implementer
checkout. For a new standalone run, a confirmed direct-to-master merge
completes the run. For an epic, a confirmed story merge advances the feature
HEAD; for a legacy standalone run, it unlocks only the preserved final
feature-to-master delivery. An unconfirmed merge keeps the run waiting at the
current story.

## Compact continuation note

Use the [minimal continuation note](continuation-note.md) template and resume
decision table for the persisted form. The example below shows the same facts
inline for a single story.

The note can be Markdown or JSON. A Markdown shape is sufficient:

```text
Run: <run-id> | scope: <project> story/epic #<ref> | stories: <ordered story refs>
Repository: <absolute path> | remote: <name> (<url>)
Base: <remote>/<base> @ <base-sha>
Topology: <standalone-story-direct-master, epic-shared-feature, or legacy-standalone-feature>
Feature: <feature-branch and worktree for epic/legacy resume, or none (standalone direct-to-master)>
Current story/task: <story ref> / <task ref or review stage>
Story branch: <story-branch> | worktree: <absolute path> | base: <sha>
Workers: implementer <chat-id> | reviewer <chat-id>
PR: <url or pending> | base <master or feature-branch> | head <sha>
Approval: <pending/approved/merged/blocked> | next: <one action>
Recovery: <automation-id or none> | schedule: <ACTIVE/PAUSED/pending> | target: <none or ACTIVE/PAUSED>
Quota wait: <optional compact waiting|delivered|unknown state for an affected worker and continuation outcome>
```

Replace the complete snapshot only after an authoritative fact changes; never
append milestones or repeated next actions. Keep one previous note recoverable
outside routine reads, and do not treat the note as evidence that an external
operation succeeded. Use the replacement helper and healthy-heartbeat read
budget in [minimal continuation note](continuation-note.md); full resume
reconciliation is for interruptions or actionable changes, not healthy ticks.

An optional `Quota wait` is planning context only. It preserves the existing
`Recovery` automation identity and its 30-minute schedule while a confirmed
future reset or exhaustion is deferred. The healthy tick may use one fresh
capacity result or the reset estimate to return a bounded eligibility decision,
but it never creates a capacity poller, retries a rejected attempt immediately,
wakes a stopped worker, or creates a nested heartbeat. Unknown delivery remains
a reconciliation state, and the reconciliation owner must record the later
attempt and delivery outcome before replacing the compact field.
