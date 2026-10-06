# Final integrated epic review

The integrated review uses the [clean committed revision
contract](revision-freeze.md). The review input includes the expected
repository, integration worktree and branch, captured base, full current
feature SHA, relevant diff range, and clean tracked-source state. Ignored
verification outputs are allowed only when declared and source checks remain
clean.

The final epic review is a coordinator-owned gate after every ordered story
has been accepted and its story PR has been verified merged into the same
integration feature branch. It applies only to an epic run. A single-story run
uses the final story review and proceeds to final delivery without inventing an
epic review.

## Review assignment

The coordinator assigns the complete integration HEAD to exactly
`gpt-6.1-sol` with `high` effort. The assignment includes:

- the epic's internal ID, displayed reference, subject, goal, scope, and
  definition of done;
- every linked story in authoritative order, with its accepted revision and
  merged PR evidence;
- the repository, integration feature branch, base SHA, current HEAD, and
  expected integration worktree, clean tracked-source result, diff range, and
  changed-path summary; and
- the checks already run plus focused integration checks to run during review.

The reviewer checks the integrated result rather than repeating every task
review mechanically. The review must cover unmet epic requirements, combined
behavior across stories, branch/PR sequencing, worker and user approval
boundaries, cross-story state transitions, regressions, and missing or
contradictory evidence.

## Findings and re-review

Before inspecting or accepting, the reviewer verifies the expected worktree,
branch, exact full HEAD, diff range, and clean tracked-source state. If the
review finds a defect, the coordinator records the finding against the exact
feature HEAD and routes it to an appropriate implementer on an isolated
integration-correction branch. The implementer returns a focused commit and
integration checks; the correction is incorporated into the feature branch
only through the normal reviewed path. The Sol 6.1 high reviewer then reviews
the resulting exact feature HEAD again. Prior approval is superseded by any
source, HEAD, branch, or requirement change; preserve conflicts and never
reset, clean, stash, force-push, or silently substitute a revision.

Do not open the final feature-to-master PR while findings are unresolved. Do
not turn a passing task review, all-story merge, or a stale final approval into
epic acceptance. The final review result must name the exact current feature
HEAD, the epic criteria checked, findings/corrections, and the next delivery
action.

## Approval record

An accepted review records:

```text
Epic #<ref> accepted
Reviewer: gpt-6.1-sol / high
Repository: <absolute repository path>
Integration worktree: <absolute worktree>
Feature branch: <expected branch>
Base: <captured base SHA>
Feature HEAD: <exact full 40-character SHA>
Diff: <base SHA>..<feature HEAD>; paths: <relevant changed paths>
Source state: clean tracked source; ignored verification outputs: <none or declared paths>
Stories: <ordered refs and merged PR/head evidence>
Coverage: <epic, combined behavior, sequencing, approvals, regressions>
Checks: `<command>` — exit <code>; <result>
Next: coordinator, prepare the final feature-to-master PR; do not merge it.
```

The coordinator revalidates the feature HEAD and epic scope before using this
record. A changed HEAD, linked story, requirement, or integration result
requires a fresh high review.
