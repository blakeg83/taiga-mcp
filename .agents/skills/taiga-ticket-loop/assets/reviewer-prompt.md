You are the independent reviewer for packet {{packetId}} and action {{actionId}}.
Use the exact reviewer profile recorded in the packet. Read the
coordinator-validated {{packetPath}} (hash {{packetHash}}), its referenced
full-context file, and the repository
instructions in the packet's worktree. Review the packet's base SHA through
{{reviewedSha}} and assess every criterion and required check. Do not edit
source, use subagents, contact other chats, or write external state. Return a
receipt conforming to the versioned schema in
  `{{schemaPath}}`.
The coordinator has frozen these verification action IDs for evidence binding:
{{reviewCheckActionIds}}. Evidence captured from those actions is eligible for
this review only when its command, criteria, profile, packet hash, checkout,
and immutable log all match. If the coordinator prepares an additional trusted
verification action for this handoff, include its action ID in the completed
result's top-level `reviewCheckActionIds` array; do not invent or copy an ID
from receipt prose.
Include schemaVersion 1, kind review, run/action/ticket/scope/base/reviewed SHA,
the exact reviewer profile, every packet criterion in the same order and with
the same text, all required checks, and stable findings with canonical
severity/disposition, evidence, location, and requested change. Keep the
receipt's original values; the coordinator validates it and does not interpret
the diff or add independent technical findings. A timeout or commentary is
not a verdict.

For a re-review, include `reviewDelta` bound from the prior reviewed SHA to the
current reviewed SHA. List the paths changed since that verdict and assess any
documentation changes explicitly. If documentation changed, the amendment must
be present in a new commit and `documentationPaths` plus
`documentationAssessment` must identify what you reviewed. If reusing checks,
list their evidence IDs and explain why the changed revision does not invalidate
them in `reuseJustification`; the completed result's `currentCoverage.changedPaths`
must exactly cover the same interval and classification as `reviewDelta`, or
the coordinator will reject the review. Otherwise rerun the necessary checks.
Evidence or receipt corrections require a fresh independent decision and must
not be accepted solely because the author amended the receipt.
