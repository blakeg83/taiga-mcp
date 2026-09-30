# Ordinary chat roles and handoffs

The coordinator creates or reuses one ordinary implementation chat per
executable ticket and one ordinary reviewer chat for that ticket. The initial
prompt carries the run/action marker, ticket identity, scope hash, repository,
absolute checkout, branch, captured base SHA, current HEAD, validation commands,
and explicit no-subagent/no-independent-write rules.

The Luna implementer loads repository instructions, implements only the
approved scope, runs the configured checks, updates documentation, and commits
at checkpoints. Its receipt reports the exact checkout, branch, base/current
SHA, criteria and task coverage, check exit codes, docs, commits, blockers, and
scope hash. A no-change result is explicit and cannot fabricate a PR.

The `gpt-6.1-sol`/`high` reviewer inspects the exact implementation checkout and
`base..HEAD` diff. The prompt requests no source edits and a structured receipt:
`pass`, `changes_requested`, or `blocked`, with reviewed SHA, scope/base, all
criteria/check coverage, stable finding IDs, evidence, severity, and requested
changes. Prompt text is not an OS read-only guarantee; the coordinator verifies
the source state before and after review.

All corrections are follow-up messages to the same implementation thread. Never
route a result by title or by a ticket reference in free text alone. Correlate
thread/host IDs, run/action IDs, ticket key, scope hash, and reviewed SHA. A
commentary update, timeout, or idle state is not a receipt.
