# Scope-specific branch topology

The selected scope determines the branch and delivery topology. Do not create
an integration branch for a standalone story, and do not collapse an epic into
one worker branch.

| Scope | Integration branch/worktree | Story branch base | Story PR base | Final review and merge path |
| --- | --- | --- | --- | --- |
| Standalone story | None | Fresh captured `origin/master` SHA | `master` | Exact story HEAD review, then the user's explicit approval to merge that story PR to `master` |
| Epic | One shared `codex/feature-<slug>-<run-suffix>` branch/worktree | Current verified feature HEAD, one managed worktree per story | Shared feature branch | Exact integrated feature HEAD review, then a separate final feature-to-`master` PR and user approval |

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
```

For a standalone snapshot, retain the existing field shape with explicit
values: `Feature: none (standalone direct-to-master)` and `PR: ... | base:
master`. For an epic snapshot, `Feature` identifies the shared branch and
worktree and `PR` names that feature branch until final delivery.

The `Topology` field is optional only when reading an older active snapshot.
If an existing snapshot has a nonempty feature branch and a story PR base, it
is a legacy feature-based run: preserve its recorded branch, worktree, PR,
worker, and recovery identities exactly and resume that run under its recorded
lineage. Never reinterpret or rewrite an active run as standalone merely
because the new contract has a different default. New runs must write the
explicit topology before worker dispatch.
