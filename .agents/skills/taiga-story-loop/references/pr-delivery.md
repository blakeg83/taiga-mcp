# Reviewed story PR delivery

The coordinator owns delivery of a reviewed story revision. A task-ready
handoff or a task acceptance is not enough to create a pull request. Delivery
starts only after the reviewer has approved the complete story at an exact
current HEAD and the setup authorization includes the repository and PR
destination.

## Delivery preflight

Before pushing or creating/reusing a PR, reconcile the authoritative records:

1. Read the continuation note, the story's current requirements/comments, and
   the provider's current PR records.
2. Verify the story branch is the expected branch in the expected repository,
   has no uncommitted changes, and currently resolves to the reviewer's
   approved HEAD.
3. Re-run the required repository checks or verify their recorded results are
   for that same HEAD. A missing, failed, or stale check blocks delivery.
4. Verify the topology-specific PR base: `master` for a new
   `standalone-story-direct-master` run, or the recorded integration feature
   branch for an `epic-shared-feature` run. An active
   `legacy-standalone-feature` run is the explicit compatibility exception:
   retain and verify its recorded feature branch as the story PR base. A new
   standalone delivery must not invent or substitute a feature branch; an
   epic must not substitute `master` or a similarly named branch.

If any preflight result is unknown, preserve the state and reconcile it before
retrying. A changed HEAD, story requirement, branch base, or check result makes
the approval stale and returns the story to the existing implementer/reviewer
pair.

## Push and PR identity

After preflight succeeds, push only the authorized story branch. Find an
existing PR by repository, exact head branch, topology-specific base, and
reviewed head commit. Reuse a PR only when all of those identities match and
the provider reports it open and unclosed. A PR from another branch, an
incorrect base, a closed/unmerged PR, a PR with a changed head, or a
response-lost create is not a successful delivery; inspect the provider before
creating anything else. If an exact-match PR has missing or null provider
state, return an unknown/reconcile outcome and do not create another PR until
the provider state is resolved.

The story PR must target the topology-specific base and must include this
review evidence in its description:

```markdown
## Problem
<the story outcome and user-facing reason>

## Changes
<the implementation delivered by this story>

## Validation
- `<check>` — exit <code>; <result>

## Review
- Reviewed HEAD: `<exact commit SHA>`
- Review profile: `<configured reviewer profile>`
- Review state: accepted for PR delivery; merge still requires user approval

## Scope
- Story: #<ref>
- Base: `<master for new standalone, feature branch for epic or legacy active standalone>`
- Head: `<exact commit SHA>`
```

For a legacy active standalone run, this is still the old story-to-feature PR;
after its separate merge approval and provider-confirmed merge, follow
[final feature-to-master delivery](final-delivery.md) for the preserved feature
branch. The exception never authorizes a new story or changes the recorded
lineage.

The coordinator attaches the resulting PR to the current chat and links the
exact PR URL, topology, base, head, and checks in the parent Taiga story
comment. The comment records `state: pr_ready_for_approval`; it does not mark
the story Done, claim a merge, or authorize the next epic story.

## Delivery result and recovery

Persist the confirmed PR URL, repository, base branch, head SHA, and
`Approval: pending` in the continuation note. A provider approval is not a
merge. The coordinator must verify a later user Yes before merging, and must
verify the merge result before changing Taiga completion state or advancing the
feature branch.

If PR creation, attachment, the Taiga link, or the state of an exact-match PR
has an unknown result, read the provider/chat/story records first. Reuse a
confirmed matching object or report the unresolved operation; never blindly
retry a write or create a duplicate PR.
