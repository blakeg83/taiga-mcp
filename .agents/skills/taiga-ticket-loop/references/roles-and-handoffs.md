# Ordinary chat roles and handoffs

The coordinator creates or reuses one ordinary implementation chat per
executable ticket and one ordinary reviewer chat for that ticket. The initial
prompt carries the run/action marker, ticket identity, scope hash, repository,
absolute checkout, branch, captured base SHA, current HEAD, validation commands,
and explicit no-subagent/no-independent-write rules.

The coordinator reads ticket scope, repository instructions/configuration,
Git/provider metadata, worker status, receipts, and the immutable assignment
packet to route work. It does not
read production source, interpret the diff, run tests/smoke checks, diagnose
failures, or create technical findings during routine execution. Route failed
or missing implementation evidence to its producing implementer, changed
revisions to review, unclear product requirements to the user, and technical
disagreements to the reviewer before escalating unresolved decisions. The
[coordinator boundary matrix](coordinator-boundaries.md) defines these cases.

Pass workers the packet's absolute path and hash. The packet carries stable
criteria, complete-context reference/hash, checkout/base, required commands,
authority, deadline, and exact profiles. This short prompt is only a file
reference; it does not remove any requirement. See
[assignment-packets.md](assignment-packets.md) for packet creation and
validation.

The Luna implementer loads repository instructions, implements only the
approved scope, runs the configured checks, updates documentation, and commits
at checkpoints. Its receipt reports the exact checkout, branch, base/current
SHA, criteria and task coverage, check exit codes, docs, commits, blockers, and
scope hash. A no-change result is explicit and cannot fabricate a PR.
For each check, preserve its actual process exit code and log reference so the
coordinator can bind the result to immutable evidence files.

Before reviewer dispatch, prepare the implementation/review check actions that
will produce evidence. The coordinator freezes their IDs in the reviewer
action; when omitted from the dispatch request it discovers eligible current
actions for the same owned ticket. A completed reviewer result can name
additional coordinator-prepared check IDs in its top-level
`reviewCheckActionIds` array, but every ID is revalidated against the registry,
packet, command, criteria, and exact worker profile. Passing receipts cannot
bind evidence by receipt prose or by the reviewer dispatch ID alone.

The `gpt-6.1-sol`/`high` reviewer inspects the exact implementation checkout and
`base..HEAD` diff. The prompt requests no source edits and a structured receipt
following the shared [review receipt contract](review-receipts.md):
`pass`, `changes_requested`, or `blocked`, with reviewed SHA, scope/base, all
criteria/check coverage, stable finding IDs, evidence, canonical severity and
disposition, and requested changes. Prompt text is not an OS read-only
guarantee; the coordinator verifies the source state before and after review.

All corrections are follow-up messages to the same implementation thread. Never
route a result by title or by a ticket reference in free text alone. Correlate
thread/host IDs, run/action IDs, ticket key, scope hash, and reviewed SHA. A
commentary update, timeout, or idle state is not a receipt.

For a re-review, the result also carries immutable worker metadata in
`currentCoverage`: current revision/base, environment and dependency hashes,
the worker's `changedKind` (`unchanged`, `documentation_only`, or `code`), and
the changed paths. The coordinator validates the binding and delegates reuse
eligibility to `workflow-verification.ps1`; it does not infer whether source
changes are documentation-only.
