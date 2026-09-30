# State and recovery contract

`workflow-state.ps1` stores one versioned registry outside all worktrees. The
default is `%LOCALAPPDATA%/TaigaMCP/agent-review-automation`; pass an explicit
temporary root for fixtures. The registry contains sessions, normalized ticket
claims, repository slots, host worker-turn reservations, actions, observations,
and a bounded event journal. Credentials and private ticket content do not
belong in it.

Every mutation uses an expected registry revision plus session owner and fencing
generation. A short exclusive lock protects the read/validate/replace cycle;
no repository lock is held during a worker turn. The helper writes a same-
directory temporary snapshot, flushes it, and atomically replaces the primary
while retaining a `.bak` prior snapshot. A malformed primary is recoverable from
the valid backup; if neither is valid, the result is an explicit recovery error.

Important operations are `initialize-session`, `inspect`, `claim-ticket`,
`release-ticket`, `reserve-slot`, `release-slot`, `prepare-action`,
`record-observation`, `consume-result`, `transition`, `pause-intent`,
`cancel-intent`, `resume-session`, and `set-heartbeat`. All input and output is
structured JSON. Unknown critical fields, path traversal, invalid IDs, stale
revisions, duplicate actions, invalid phase transitions, and terminal dispatch
are rejected.

Waiting for a dependency or merge releases an execution slot but retains the
ticket claim. An uncertain action retains its reservation even after its lease
expires. Recovery reconciles the external target before another action. A
pending chat client ID is not a thread ID, and action markers are correlation
identifiers rather than provider idempotency keys.
