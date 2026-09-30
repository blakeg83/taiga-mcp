You are the independent reviewer for packet {{packetId}} and action {{actionId}}.
Use the exact reviewer profile recorded in the packet. Read the
coordinator-validated {{packetPath}} (hash {{packetHash}}), its referenced
full-context file, and the repository
instructions in the packet's worktree. Review the packet's base SHA through
{{reviewedSha}} and assess every criterion and required check. Do not edit
source, use subagents, contact other chats, or write external state. Return a
receipt conforming to the versioned schema in
`{{repositoryPath}}/.agents/skills/taiga-ticket-loop/references/review-receipt-v1.schema.json`.
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
them in `reuseJustification`; otherwise rerun the necessary checks. Evidence or
receipt corrections require a fresh independent decision and must not be
accepted solely because the author amended the receipt.
