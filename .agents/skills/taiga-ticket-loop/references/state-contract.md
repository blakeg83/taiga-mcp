# State and recovery contract

`workflow-state.ps1` stores one versioned registry outside all worktrees. The
default is `%LOCALAPPDATA%/TaigaMCP/agent-review-automation`; pass an explicit
temporary root for fixtures. The registry contains sessions, normalized ticket
claims, repository slots, host worker-turn reservations, actions, observations,
and a bounded event journal. Credentials and private ticket content do not
belong in it. A parent ticket is stored once in `tickets`; story/task aliases
are stored in `ticketAliases` and always resolve to that canonical record.

Every mutation other than `initialize-session` must include both
`expectedRevision` and `ownerGeneration`. The helper rejects missing or stale
values before applying a mutation. A short exclusive lock protects the
read/validate/replace cycle;
no repository lock is held during a worker turn. The helper writes a same-
directory temporary snapshot, flushes it, and atomically replaces the primary
while retaining a `.bak` prior snapshot. A malformed primary is recoverable from
the valid backup; if neither is valid, the result is an explicit recovery error.

Important operations are `initialize-session`, `inspect`, `claim-ticket`,
`release-ticket`, `reserve-slot`, `release-slot`, `prepare-action`,
`record-observation`, `consume-result`, `transition`, `pause-intent`,
`cancel-intent`, `reconcile-intent`, `resume-session`, and `set-heartbeat`. All
input and output is structured JSON. Unknown critical fields, path traversal,
invalid IDs, stale revisions, duplicate actions, invalid phase transitions, and
terminal dispatch are rejected.

Waiting for a dependency or merge releases an execution slot but retains the
ticket claim. Pause and cancel are two-step controls: the intent first moves
the session or ticket to `pausing` or `cancelling` and blocks new actions,
slots, and transitions; `reconcile-intent` requires `quiescent=true` and no
pending or uncertain actions before changing the phase and releasing a slot.
Unresolved actions retain their reservations. `record-observation` is fenced
to the action's session and owner generation and rechecks the action's ticket
owner. Recovery reconciles the external target before another action. A
pending chat client ID is not a thread ID, and action markers are correlation
identifiers rather than provider idempotency keys.

The current registry schema is version 2. On read, a version-1 registry is
migrated by collapsing duplicate parent/child ticket records into one
canonical parent and adding `ticketAliases`; divergent duplicate records are
rejected for manual recovery rather than silently discarded or replaced by an
older backup. JSON parse corruption may recover from `.bak`, but migration and
unsupported-schema errors fail closed. A successful migration is persisted
during inspection or the next mutation.

## Receipt validation

Review receipts are validated against the shared
[versioned receipt contract](review-receipts.md), not the registry version.
For `validate-receipt`, pass `receiptKind: "review"`, the receipt, and
`expectedCriteria` copied from the validated assignment packet as ordered
`{ "id", "text" }` objects. Omitting that trusted expected set is an error.
The helper preserves a source receipt and returns a separately normalized v1
view plus explicit normalization records for legacy input. Validation errors
name the failing field so routine formatting repairs do not require source
inspection.
