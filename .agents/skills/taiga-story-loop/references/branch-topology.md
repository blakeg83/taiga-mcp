# Scope-specific branch topology

The selected scope determines the branch and delivery topology. Do not create
an integration branch for a standalone story, and do not collapse an epic into
one worker branch.

| Scope | Integration branch/worktree | Story branch base | Story PR base | Final review and merge path |
| --- | --- | --- | --- | --- |
| Standalone story | None | Fresh captured `origin/master` SHA | `master` | Exact story HEAD review, then the user's explicit approval to merge that story PR to `master` |
| Epic | One shared `codex/feature-<slug>-<run-suffix>` branch/worktree | Current verified feature HEAD, one managed worktree per story | Shared feature branch | Exact integrated feature HEAD review, then a separate final feature-to-`master` PR and user approval |
| Legacy active standalone | Existing recorded feature branch/worktree | Existing recorded story lineage | Existing recorded feature branch | Resume the old story-to-feature review/merge, then the legacy feature-to-`master` PR and separate user approval |

## Standalone story

A standalone story has one managed story branch from the captured base SHA.

After setup, fetch the configured remote and capture the immutable base SHA.
Create one managed worker worktree from that SHA and create the story branch
there. The story branch is the only run branch. The coordinator and worker
must record `Feature: none (standalone direct-to-master)` and its story PR
targets `master`. The final story approval is bound to the exact
current story HEAD; opening the direct PR does not merge it. A `Yes` merge
decision applies to that exact PR and ends the run only after the provider
confirms the merge.

There is no feature worktree, story-to-feature PR, next-story sequencing gate,
integrated epic review, or second feature-to-master PR in this path.

## Legacy active standalone run

An active standalone run created by the older workflow may already have a
feature branch/worktree and a story PR targeting that feature branch. Classify
that run as `legacy-standalone-feature` and preserve its recorded feature and
story branches, worktrees, PR identity, worker pair, and recovery identity.
This is a resume-only compatibility path; new standalone runs must use the
direct-to-`master` topology.

Review the exact story HEAD against the recorded feature base and deliver the
story PR to that same feature branch. The story merge gate is still a separate
user approval: after the provider verifies that story PR merged, refresh the
recorded feature HEAD and continue to the legacy final feature-to-`master`
delivery. Do not dispatch another story, invent a new feature branch, require
an integrated epic review, or reinterpret the run as a new standalone run.

## Epic

An epic has one shared feature branch from the captured base SHA.

After setup, fetch the configured remote and capture the immutable base SHA.
Create one shared managed feature worktree and branch from that SHA before
creating any story worktree. Each story gets a distinct managed worktree and
branch from the current verified feature HEAD. Its reviewed PR targets the
shared feature branch. A later story starts only after the provider confirms
the preceding story PR merged into that exact feature branch and the feature
HEAD has been refreshed from the authoritative result.

After all stories are integrated, run the exact-HEAD integrated epic review.
Only its accepted feature HEAD may produce the final feature-to-`master` PR;
that final PR has its own user approval and merge verification.

## Setup and continuation values

New snapshots include a `Topology` line with one of:

```text
Topology: standalone-story-direct-master
Topology: epic-shared-feature
Topology: legacy-standalone-feature
```

For a standalone snapshot, retain the existing field shape with explicit
values: `Feature: none (standalone direct-to-master)` and `PR: ... | base:
master`. For an epic snapshot, `Feature` identifies the shared branch and
worktree and `PR` names that feature branch until final delivery.

The `Topology` field is optional only when reading an older active snapshot.
Determine the missing topology from the recorded `Scope` before considering
branch fields:

- If `Scope` identifies an epic or a set of ordered stories, classify the run
  as `epic-shared-feature`. Preserve its recorded feature/story branches,
  worktrees, PR, worker, and recovery identities; continue the next-story
  merge gates and the integrated epic review.
- If `Scope` identifies one standalone story, and the old note has a nonempty
  feature branch and story PR base, classify it as
  `legacy-standalone-feature`. Preserve the same identities and resume the old
  story-to-feature then final feature-to-`master` path.
- If the recorded scope is missing or ambiguous, stop for reconciliation.
  Feature fields alone are insufficient evidence for the legacy exception.

Never reinterpret an epic as standalone merely because the new contract has a
different default. New runs must write either
`standalone-story-direct-master` or `epic-shared-feature` before worker
dispatch; `legacy-standalone-feature` is never selected for a new run.
