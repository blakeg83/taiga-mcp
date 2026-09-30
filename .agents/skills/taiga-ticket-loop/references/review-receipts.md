# Review receipt contract

`review-receipt-v1.schema.json` is the authoritative review receipt contract.
Both `workflow-state.ps1 -Operation validate-receipt` and
`workflow-review.ps1 -Operation validate|route|decide` call the same validator in
`scripts/receipt-contract.ps1`. The reviewer handoff template points to this
schema. The contract is versioned independently from the mutable workflow
registry.

## Version 1

A canonical receipt has `schemaVersion: 1` and `kind: "review"`. It binds the
verdict to `runId`, `actionId`, `ticketKey`, `scopeHash`, `baseSha`, and
`reviewedSha`; it also records the exact `reviewerModel: "gpt-6.1-sol"` and
`reviewerEffort: "high"` profile. Criteria include the exact packet `id` and
`text`, a boolean `passed`, and evidence. Checks include a command, nonnegative
exit code, and evidence. Findings include an ID, severity, evidence, requested
change, and one canonical disposition:

| Field | Allowed values |
| --- | --- |
| `verdict` | `pass`, `changes_requested`, `blocked` |
| `severity` | `blocker`, `critical`, `high`, `medium`, `low`, `info` |
| `disposition` | `open`, `fixed`, `rejected_accepted`, `escalated` |

The `expectedCriteria` supplied to either helper must come from the validated
assignment packet. Its ordered IDs and exact text are compared with the entire
receipt set. Missing, extra, reordered, or reworded criteria are field errors;
a receipt with no expected set cannot pass validation. A pass also requires all
criteria to pass, every check to exit zero, and no unresolved blocker, critical,
or high finding. A `changes_requested` or `blocked` receipt may preserve failed
checks and criteria as evidence.

### Re-review delta

When `workflow-review.ps1 -Operation decide` receives `previousReviewedSha`,
the receipt must include `reviewDelta` bound from that revision to its current
`reviewedSha`. This keeps follow-up reviews tied to the change since the prior
verdict. The reviewer lists changed paths and explicitly assesses documentation
changes. A documentation amendment requires a distinct committed revision,
nonempty `documentationPaths`, and a substantive `documentationAssessment`.
Reused checks list their evidence IDs and require a `reuseJustification`;
otherwise checks are rerun and reported as usual. An unbound or incomplete
delta returns `needs_input` or a field-level validation error and cannot pass.

### Repair routing

`workflow-review.ps1 -Operation route` accepts the receipt, trusted criteria,
stable `resultId` equal to the trusted `expectedActionId` from the pending
review action, current repair count, and remaining wall-clock minutes. It returns an
already-valid receipt unchanged, applies only the shared lossless
legacy normalizations locally, or routes the malformed receipt to its original
`actionId`. Contradictory evidence is classified as semantic and always
requires independent review after the author returns a corrected receipt. It
is never resolved by coordinator inference. Missing author binding, an expired
budget, or two exhausted attempts returns `needs_input`.

Persist each dispatched repair with
`workflow-state.ps1 -Operation record-receipt-repair`. Its per-result ledger is
separate from `correctionRound`; state requires the original result action to be
observed and bound to the owned ticket. The default limit is two attempts,
including format and evidence repairs. A repair does not authorize publication. The
repaired result returns through ordinary receipt validation and review.

## Legacy adapter

Receipts without `schemaVersion` are treated as legacy v0 input. The adapter
returns both `sourceReceipt` (an unchanged copy) and `normalizedReceipt`; it
never rewrites the input file. It records each normalization in `normalizations`.
Legacy `kind` and schema version are filled in, and missing criterion text may
be copied only from the corresponding trusted packet criterion.

Legacy findings that omit `disposition` become `open`, which keeps them
unresolved. The audited legacy alias `resolved` maps to `fixed` only when the
same finding has no contradictory unresolved evidence. Explicit
`unresolved: true`, `isUnresolved: true`, or a legacy status of `open`,
`unresolved`, `needs_work`, or `not_fixed` blocks that mapping. Unknown
disposition aliases and unknown legacy status values return a compact error
with the field path. Version 1 receipts must use canonical dispositions and
cannot use the legacy alias.

## Compatibility examples

Legacy high-severity finding with an unambiguous resolved disposition:

```json
{
  "runId": "run-7",
  "actionId": "review-0",
  "ticketKey": "project:1:issue:42",
  "scopeHash": "scope-sha256",
  "baseSha": "base-sha",
  "reviewedSha": "head-sha",
  "verdict": "pass",
  "reviewerModel": "gpt-6.1-sol",
  "reviewerEffort": "high",
  "criteria": [{ "id": "criterion-1", "passed": true, "evidence": "verified" }],
  "checks": [{ "command": "dotnet test", "exitCode": 0, "evidence": "all checks passed" }],
  "findings": [{ "id": "F1", "severity": "high", "evidence": "fix verified", "requestedChange": "repair issue", "disposition": "resolved" }]
}
```

The adapter reports `findings[0].disposition: resolved -> fixed`; the input
remains intact. Adding `"status": "open"` or `"unresolved": true` to that
finding makes it invalid instead of silently treating it as fixed.

New receipts should follow the JSON Schema and include the full expected
criterion text. Helpers return errors such as
`receipt.criteria[1].text: does not match the trusted packet text`, without
requiring the coordinator to inspect source or infer what failed.
