# Reviewed story PR delivery

PR delivery uses the [clean committed revision contract](revision-freeze.md).
The delivery input is the expected repository/worktree and branch, captured
base, full reviewed HEAD, relevant diff range, and clean tracked-source state.

The coordinator owns delivery of a reviewed story revision. A task-ready
handoff or a task acceptance is not enough to create a pull request. Delivery
starts only after the reviewer has completed the one explicit final
whole-story review for the selected mode at an exact current HEAD and the
setup authorization includes the repository and PR destination. The final
approval must identify its request, task coverage, definition of done,
cross-task and deferred-criterion evidence, independent verification,
inspected worker evidence, required checks, and limitations.

## Delivery preflight

Before pushing or creating/reusing a PR, reconcile the authoritative records:

1. Read the continuation note, the story's current requirements/comments, and
   the provider's current PR records.
2. Verify the story branch is the expected branch in the expected repository
   and worktree, has clean tracked source (non-ignored untracked source is also
   absent), and currently resolves to the reviewer's approved full HEAD. Record
   the captured base and relevant `<base SHA>..<reviewed SHA>` diff range. The
   final whole-story approval request ID and reviewed HEAD must match this
   exact branch state; task acceptance records alone are insufficient.
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
retrying. A tracked or non-ignored source change, changed HEAD, unexpected
branch/worktree, changed diff range, story requirement, branch base, or check
result makes the approval stale and returns the story to the existing
implementer/reviewer pair. Do not reset, clean, stash, force-push, or silently
review another revision.

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
- Reviewed HEAD: `<exact full 40-character commit SHA>`
- Review input: `<repository>` | worktree `<absolute path>` | branch `<expected branch>`
- Base/diff: `<base SHA>` | `<base SHA>..<reviewed SHA>` | paths `<relevant changed paths>`
- Source state: `clean tracked source`; ignored verification outputs: `<none or declared paths>`
- Final story review: `<request ID>` accepted at exact HEAD `<full SHA>`
- Independent verification: `<reviewer-run checks and results>`
- Inspected worker evidence: `<task revisions, artifacts, and evidence inspected>`
- Deferred criteria: `<owner/evidence for each, or none>`
- Limitations: `<known limitations or unavailable evidence>`
- Review profile: `<configured reviewer profile>`
- Review state: accepted for PR delivery; merge still requires user approval

## Scope
- Story: #<ref>
- Base: `<master for new standalone, feature branch for epic or legacy active standalone>`
- Head: `<exact full 40-character commit SHA>`
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

## Performance report finalization

Report finalization is a coordinator-owned side effect of confirmed PR
delivery. It runs only after the provider confirms an exact-match open PR that
has the authorized repository, story head branch, topology-specific base, and
the exact reviewer-approved HEAD. A `create` intent, a response-lost provider
write, an unknown PR state, a closed PR, or a stale head is not confirmation:
none of those outcomes may append `pr_ready`, call the aggregator, or create a
report.

After confirmed create or reuse:

1. Append one coordinator `pr_ready` event through
   `.agents/skills/taiga-story-loop/scripts/write-performance-event.ps1` with
   the exact PR identity and reviewed HEAD. The run ledger remains external to
   the repository.
2. Invoke the read-only `scripts/get-story-performance.ps1` aggregator with
   that ledger, the selected review mode, the exact reviewed HEAD, captured
   base, repository path, and an external artifact directory. The invocation
   is not another provider operation and does not change PR or merge state.
3. Include a concise report summary and the immutable JSON artifact reference
   in the normal `pr_ready_for_approval` response. Retain the Markdown sibling
   and manifest when the aggregator publishes the artifact set.

The report identity is `runId + projectId + storyId + PR identity + reviewed
HEAD`. Reobserving the same confirmed PR and HEAD reuses the existing report
artifacts and does not create a second report. A newly confirmed reviewed HEAD
creates a new retained report sibling; it never overwrites the prior report.
If recorder, aggregator, or artifact publication fails, keep the confirmed PR
delivery and user merge gate intact, return the report as unavailable/limited
with its safe limitation, and do not fabricate `pr_ready`, retry a provider
write, add a worker message, or block normal delivery. Unknown provider or
recorder outcomes remain reconciliation cases and produce no report.

## Delivery result and recovery

Persist the confirmed PR URL, repository, base branch, head SHA, and
`Approval: pending` in the continuation note with a pending heartbeat target
of `PAUSED`. A provider approval is not a merge. Before waiting on the user,
update the existing recovery automation to `PAUSED` with the same automation
identity and confirm the provider schedule result. A provider approval is not
allowed to leave the heartbeat active. The coordinator must verify a later
user Yes before merging, and must verify the merge result before changing Taiga
completion state or advancing the feature branch.

If PR creation, attachment, the Taiga link, or the state of an exact-match PR
has an unknown result, read the provider/chat/story records first. Reuse a
confirmed matching object or report the unresolved operation; never blindly
retry a write or create a duplicate PR.
