# Final feature-to-master delivery

The final delivery is a release handoff, not an automatic merge. It is
available only after the current feature HEAD has passed the correct final
review:

- a single-story run requires final story approval at the exact feature HEAD;
- an epic run requires the integrated epic acceptance from
  [the final epic review](final-epic-review.md) at the exact feature HEAD.

The coordinator verifies the configured default branch is `master` for this
repository, then creates or reuses one final PR with the feature branch as
head and `master` as base. Reuse is valid only when the repository, base, head,
scope, and review evidence still match. A final PR is never treated as a
successful release merely because it was opened.

## Final PR evidence

The description identifies the path that produced it:

```markdown
## Release
- Run: <single-story or epic>
- Feature branch: `<branch>`
- Base: `master`
- Head: `<exact feature SHA>`

## Integrated evidence
- Story integration: <ordered story refs and verified feature merges>
- Final review: <story review or Sol 6.1 high epic review and exact SHA>
- Checks: `<command>` — exit <code>; <result>

## Approval boundary
Final feature-to-master PR opened for user review.
Final master merge: pending separate user approval; not automatic.
```

Hand the exact URL and evidence to the user with a separate final decision
prompt. A No, no response, changed feature HEAD, failed/unknown merge, or
requested changes holds release and does not change Taiga completion state.
Only a provider-confirmed merge after that separate approval can be reported
as release into master. Story integration, epic acceptance, final PR creation,
and master release remain distinct facts.

## Sequence invariants

For an epic, story `n + 1` starts only after story `n`'s PR is confirmed
merged into the feature branch and the feature HEAD is refreshed. The final
PR cannot be opened until every ordered story is integrated and the final epic
review is accepted. For a single-story run, omit the epic review but retain the
same final master approval boundary.

Any correction after final review or any material requirement change invalidates
the final PR evidence. Return to the appropriate existing worker/reviewer
route, obtain fresh review at the new HEAD, and reuse or update the final PR
only after revalidation. Do not claim epic or master completion from PR
creation alone.
