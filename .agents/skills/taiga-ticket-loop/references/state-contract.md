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
terminal dispatch are rejected. `record-receipt-repair` also requires a stable
result ID, unique repair ID, repair class and route; original-author routing
must name the receipt's original action. The result ID must resolve to an
observed action owned by the same ticket and fencing generation.

The compact `workflow-coordinate.ps1` facade accepts packet, prompt, result,
and external-state file references with SHA-256 hashes. `prepare-dispatch` and
`prepare-publication` create local action descriptors only; the coordinator
performs the corresponding native desktop/provider operation and later calls
`record-external`. `accept-result` consumes a durable result through the state
helper and can apply one requested local phase transition. Its default output
contains references and correlation fields, not a copied receipt or transcript.

Reviewer dispatches freeze the packet ID/hash, scope hash, base SHA, reviewed
SHA, and the eligible verification action IDs in the local action target. If
the caller omits `reviewCheckActionIds`, `prepare-dispatch` discovers the
already-prepared implementation/review check actions owned by the same ticket
and fencing generation. A completed review result may supply additional
`reviewCheckActionIds`; the facade validates each against the current registry
before accepting its receipt and persists the binding for final publication
revalidation. A result may also carry worker-provided `currentCoverage` with
the current revision/base, environment/dependency hashes, `changedKind`, and
`changedPaths`; the facade validates its shape and consistency with the
receipt's `reviewDelta`, while the verification helper checks both the current
and evidence-origin Git intervals. The validated effective coverage is stored
with the accepted result regardless of whether it came from the result file or
the compatibility input field, so final publication revalidation sees the
same evidence context.

Repeated preparation of an existing action ID returns `reconcile` with the
stored action status instead of redispatching. An observed provider client ID
without its real thread ID remains `uncertain`; it is never treated as a
completed worker. The facade blocks new dispatch/publication when the supplied
remaining budget is exhausted, while already-running actions remain available
for bounded observation and reconciliation.

For observation, use `observe-wait` with one or more native wait targets. The
returned `waitThreadsArguments` preserves the native shape
`{ targets: [{ threadId, hostId?, afterCursor? }], timeoutMs }`, so concurrent
ticket waits retain their host IDs and cursors. An unchanged timeout returns a quiet continuation descriptor and does not read
source, reopen evidence, message a worker, or mutate the registry. Completion,
changed state, and blockers are the only ordinary reasons to request one
detailed `read_thread`; user input remains visible as a separate decision.
`heartbeat-plan` describes creation or reuse of one coordinator heartbeat and
never schedules a timer per ticket or a nested heartbeat.

`record-receipt-repair` is available only while the owned ticket is reviewing.
It records format/evidence repairs in a per-ticket ledger with remaining
minutes. The default `limits.maxReceiptRepairAttempts` is two and may be
reduced to one. Its counter is independent of `correctionRound`; exhaustion or
no remaining time returns `needs_input` and does not create another attempt.
Existing schema-2 tickets acquire an empty repair ledger on first use.

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

## Verification evidence

Prepared check actions retain only a small validated `evidenceContext` in the
registry. Use `workflow-evidence.ps1` to initialize trusted per-action metadata,
capture observed process results and external logs, validate immutable file
hashes, and summarize structured outcomes. See the
[verification evidence contract](evidence-contract.md) for storage layout,
lifetime, and classifications. Large logs never enter the registry.
