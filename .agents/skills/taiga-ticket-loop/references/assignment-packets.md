# Assignment packet contract

Create one versioned packet for a ticket scope and pass its absolute path and
hash to the worker chat. The packet keeps the handoff short without dropping
requirements: it carries criterion IDs/text and a hash-bound reference to the
complete selected ticket context. Workers also read the instructions in their
actual checkout.

## Stored artifacts

`workflow-packet.ps1 -Operation create` writes under the durable local state
root, `%LOCALAPPDATA%/TaigaMCP/agent-review-automation` by default. It stores
the packet in `packets/<sessionId>/<packetId>.json` and copies the referenced
full-context file into `packet-context/<sessionId>/<sha256>.context`. Both
artifacts are outside the source worktree and outside the mutable registry.
Pass `-StateRoot` only for isolated fixtures or a deliberately selected state
root. The returned paths are absolute and must be reachable from the worker's
host; do not use the coordinator's initial working directory or an ephemeral
temporary directory as the handoff reference.

The packet contains:

- schema version, packet/session/run IDs, and packet and scope hashes;
- ticket key, project, kind, ID, ref, and title;
- the full-context artifact path and SHA-256;
- stable criterion IDs and exact text, sorted by ordinal ID;
- repository identity/path, worker worktree, branch, and captured base SHA;
- required repository commands and unresolved product requirements;
- explicitly authorized and excluded actions;
- coordinator/worker profiles and the immutable repository binding.

The worker profiles are currently `gpt-5.6-luna`/`xhigh` and
`gpt-6.1-sol`/`high`. The selected coordinator profile is captured as supplied.
The packet builder rejects other worker profiles, incomplete ticket/repository
bindings, inaccessible context/worktrees, and malformed criteria. A nonempty
`unresolvedRequirements` list is a clarification blocker:
resolve it with the user and issue a new packet before dispatch.

## Create and verify

Prepare a JSON request file with the packet fields, then create the packet:

```powershell
pwsh -NoProfile -File .agents/skills/taiga-ticket-loop/scripts/workflow-packet.ps1 `
  -Operation create -InputPath $requestPath
```

The helper returns the absolute packet/context paths, stable scope hash,
packet hash, and criterion IDs. Copy those references into a concise native
chat handoff. To verify exact run, ticket, and checkout bindings:

```powershell
pwsh -NoProfile -File .agents/skills/taiga-ticket-loop/scripts/workflow-packet.ps1 `
  -Operation validate -PacketPath $packetPath `
  -ExpectedRunId $runId -ExpectedTicketKey $ticketKey `
  -ExpectedWorktreePath $worktreePath
```

Validation checks the packet hash, current context-file hash, stable criterion
ordering, profiles, repository binding, and any supplied expected
identity. Packet files are immutable: create a new `packetId` after a scope
change and retain the prior artifact for audit. Do not paste the full packet or
full ticket history into the worker prompt.
