# Review and correction loop

The reviewer profile is exactly `gpt-6.1-sol` with `high` effort. If the host
does not advertise that combination, stop with a capability report; never
silently substitute another review model.

Freeze a clean committed implementation revision before review. Validate the
implementation receipt against the current ticket scope hash, base SHA,
checkout, HEAD, criteria, and checks. A source edit, new commit, changed
requirements, changed integration base, or unexpected reviewer edit invalidates
the review input.

Initial review is round 0. A `changes_requested` receipt becomes one bounded
correction action in the same Luna chat; rounds 1 through 3 are allowed by
default. Preserve the requested model and effort. Stop with `needs_input` for a
blocker, exhausted budget, unavailable worker, malformed/stale receipt, or
unresolved disagreement. Do not invent passing checks or start a new worker to
evade the limit.

Before deciding on an invalid receipt, call
`workflow-review.ps1 -Operation route`. Lossless legacy normalization may be applied locally. Other format
errors return to the original reviewer action; semantic/evidence contradictions
also require a fresh independent reviewer decision after correction. Persist
each dispatched repair with `workflow-state.ps1 -Operation record-receipt-repair`.
Its default limit is two attempts per result and its
counter is separate from the production `correctionRound`. Repairs stop with
`needs_input` when that limit or the existing elapsed budget is exhausted.

Pass the prior reviewed SHA to `workflow-review.ps1 -Operation decide` on every
re-review. The receipt's `reviewDelta` must bind the prior and current SHA. A
documentation amendment must be committed at a new revision and include the
reviewer's documentation assessment. Reuse unchanged checks only by naming
their evidence IDs and giving an explicit reuse justification. Receipt-only
format repair does not create a production correction round; documentation or
source changes remain engineering changes and follow the ordinary correction
and review limits.

Use the shared [review receipt contract](review-receipts.md) and its
versioned JSON Schema. Findings have stable IDs, one of the canonical
severities (`blocker`, `critical`, `high`, `medium`, `low`, `info`), evidence,
file/line where useful, requested change, and a canonical disposition:
`open`, `fixed`, `rejected_accepted`, or `escalated`. A receipt must identify
the exact run, action, ticket, scope, base, reviewed SHA, and
`gpt-6.1-sol`/`high` reviewer. Every criterion must preserve the packet's exact
text, ID, and order; every check must identify its command, exit code, and
evidence. Failed criteria/checks are valid evidence for a `changes_requested`
or `blocked` verdict; a `pass` must contain only passing criteria and zero-exit
checks. Blocking findings cannot coexist with a pass.
Publishing requires current reviewed SHA equality, unchanged scope,
passing criteria/check evidence, and no unresolved blocking finding.
Code-complete, PR-delivered, integrated, and Taiga-finalized are separate
facts.
