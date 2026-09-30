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
