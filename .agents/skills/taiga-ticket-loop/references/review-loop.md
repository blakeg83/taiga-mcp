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

Findings have stable IDs, severity, evidence/file/line where useful, requested
change, and a disposition: fixed, rejected with evidence and reviewer accepted,
or escalated. A receipt must identify the exact run, action, ticket, scope,
base, reviewed SHA, and `gpt-6.1-sol`/`high` reviewer. Every criterion must be
an identified passing result with evidence, and every check must identify its
command, exit code `0`, and evidence. Blocking findings cannot coexist with a
pass. Publishing requires current reviewed SHA equality, unchanged scope,
criteria/check evidence, and no unresolved blocking finding. Code-complete,
PR-delivered, integrated, and Taiga-finalized are separate facts.
