# Final feature-to-master delivery

This contract applies to an epic or to an active legacy standalone run. The
final delivery is a release handoff, not an automatic merge. For an epic it is
available only after every story PR has been verified merged into the shared
feature branch and the current feature HEAD has passed the integrated epic
review:

- an epic run requires the integrated epic acceptance from
  [the final epic review](final-epic-review.md) at the exact feature HEAD.

An active `legacy-standalone-feature` run is the compatibility exception. It
does not require an integrated epic review or another story. It becomes
eligible only after its preserved story-to-feature PR has passed the exact
story review, received the separate story merge approval, and been verified
merged into the recorded feature branch. Refresh that exact feature HEAD, then
obtain a separate final legacy review acceptance for that refreshed exact HEAD
before preparing the final PR. The earlier story review does not satisfy this
post-merge review because the merge can introduce a different revision.

The coordinator verifies the configured default branch is `master` for this
repository, then creates or reuses one final PR with the feature branch as
head and `master` as base. Reuse is valid only when the repository, base, head,
scope, and review evidence still match. A final PR is never treated as a
successful release merely because it was opened.

## Legacy standalone delivery

For an active `legacy-standalone-feature` run, create or reuse the final PR
with the preserved feature branch as head and `master` as base. Bind it to the
refreshed exact feature HEAD only after the final legacy review has accepted
that same SHA, and require a separate final user approval. The final legacy
review checks the story outcome, preserved integration evidence, and required
checks at the refreshed feature HEAD; its acceptance names that exact SHA.
Any feature movement, correction, requirement change, or new finding makes the
acceptance stale and requires another review. Do not dispatch another story,
substitute a new feature branch, or claim that the story-to-feature merge
released `master`; only the provider-confirmed final merge releases `master`.
New standalone runs never use this exception.

The final legacy review is a read-only review by the existing story reviewer
and is recorded in this form:

```text
Legacy final review accepted
Feature HEAD: <exact refreshed commit SHA>
Coverage: <story outcome, preserved integration evidence, and required checks>
Checks: `<command>` — exit <code>; <concise result>
Next: coordinator, prepare the final feature-to-master PR; do not merge it.
```

## New standalone story delivery

A new standalone story does not use this final feature-to-master PR. Its final
story approval is bound to the exact current story HEAD, and
[reviewed story PR delivery](pr-delivery.md) creates or reuses one story PR
with the story branch as head and `master` as base. The [story merge gate](merge-approval.md)
presents that direct PR for the user's explicit approval.
After the provider confirms the direct merge, the story is released and the
run ends. There is no feature branch, integrated epic review, or second PR.

## Final PR evidence

The description identifies the path that produced it:

```markdown
## Release
- Run: <epic or legacy-standalone-feature>
- Feature branch: `<branch>`
- Base: `master`
- Head: `<exact feature SHA>`

## Integrated evidence
- Story integration: <ordered story refs and verified feature merges, including the preserved legacy story merge when applicable>
- Final review: <legacy final review at refreshed feature SHA or Sol 6.1 high
  epic review and exact SHA>
- Checks: `<command>` — exit <code>; <result>

## Approval boundary
Final feature-to-master PR opened for user review.
Final master merge: pending separate user approval; not automatic.
```

Hand the exact URL and evidence to the user with a separate final decision
prompt. A No, no response, changed feature HEAD, failed/unknown merge, or
requested changes holds release and does not change Taiga completion state.
Only a provider-confirmed merge after that separate approval can be reported
as release into master. Story integration, final review, final PR creation, and
master release remain distinct facts.

## Sequence invariants

For an epic, story `n + 1` starts only after story `n`'s PR is confirmed
merged into the feature branch and the feature HEAD is refreshed. The final
PR cannot be opened until every ordered story is integrated and the final epic
review is accepted. A new standalone story follows the direct story PR and
merge gate described above and never enters this sequence. A legacy standalone
run has no story `n + 1`; its final PR may open only after the preserved story
merge, refreshed feature HEAD, and accepted final legacy review at that HEAD.

Any correction after final review or any material requirement change invalidates
the final PR evidence. Return to the appropriate existing worker/reviewer
route, obtain fresh review at the new HEAD, and reuse or update the final PR
only after revalidation. Do not claim epic or master completion from PR
creation alone.
