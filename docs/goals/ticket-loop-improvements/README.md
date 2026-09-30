# Ticket-loop improvements

Status: implemented offline; actual-host behavior, personal skill installation,
publication, and an operational comparison remain pending separate explicit
authorization. No operational ticket run or live service write was performed
by this implementation.
Prepared 2026-09-30 after auditing the first authorized ticket-loop trial.

## Objective

Make the coordinator a dispatcher and result relay. Keep engineering work in
the existing ordinary implementation and review chats, and automate mechanical
state/evidence handling. Preserve review quality, required verification, and
safe publication while reducing coordination work and avoidable correction cycles.

This work lives in TaigaMCP alongside the existing skill and PowerShell helpers.
No new repository, .NET project, MCP endpoints, subagents, or standalone runner
are required. Each machine continues to handle its own projects independently.

## Decisions carried into this batch

- The coordinator resolves ticket context, prepares the worktree, dispatches,
  waits, routes findings, and handles authorized PR/Taiga updates.
- The implementer investigates source, implements, selects relevant checks under
  repository instructions, documents, commits, and corrects findings.
- The reviewer assesses correctness and evidence, chooses independent focused
  checks, and owns technical acceptance. The coordinator does not become a
  second reviewer or resolve technical disagreements itself.
- Keep the same ordinary implementation and reviewer chats through corrections.
  Preserve the currently selected worker profiles: Luna 5.6/xhigh and
  Sol 6.1/high for the audited configuration. Do not silently change models or
  efforts. The coordinator uses the user's selected profile.
- Raw token counts measure processing, not monetary cost or subscription
  consumption. Luna is intended to be economical despite higher token volume;
  a larger raw share is not evidence that it should be replaced.
- Script bookkeeping and receipt construction; retain native desktop tools for
  chat and heartbeat operations. Helpers cannot invoke those tools themselves.
- Preserve fresh-base branches, one writer per ticket, exact-revision review,
  bounded corrections, explicit authorization, PR reconciliation, manual merge,
  dependencies, concurrent independent tickets, and epic integration gates.

## Audit baseline and limits

The supplied three conversation exports, registry, and usage export show:

| Observation | Recorded result |
| --- | --- |
| Registry claim through pause | Approximately 123 minutes; chat preflight/final response add time outside this interval. |
| Implementer token processing | 51,014,213; Luna 5.6/xhigh. |
| Coordinator token processing | 19,458,028; Sol 6.1/high. |
| Reviewer token processing | 5,358,827; Sol 6.1/high. |
| Total processing | 75,831,068, including 74,199,296 cached input tokens. |
| Uncached input / output | 1,393,180 / 238,592; reasoning output is included in output. |
| Final documentation/evidence correction interval | Approximately 12 minutes and 5,017,269 tokens across chats; production code unchanged during these corrections. |
| Receipt contract failure | A passed high-severity finding used resolved; validators recognized fixed or rejected_accepted. |
| Coordinator export | 74 wait calls, 122 shell-command entries, 75 helper-operation mentions; counts alone do not establish waste or cost. |

Totals use cumulative-counter differences, omit duplicate updates, and exclude
later coordinator activity after the ticket run. Phase attribution uses event
timestamps, not measurements of model execution time. The review found a real
production defect; retaining meaningful independent review is a requirement.
The run ended at the user's requested pause without a push or PR.

Do not commit the actual chats, registry, private ticket content, local paths,
or account records. Build synthetic reproductions of the observed failures.

## Ordered goals

Read [execution instructions](execution-instructions.md) before implementing.

| Goal | Deliverable | Depends on | Status |
| --- | --- | --- | --- |
| [01: Coordinator boundaries](01-coordinator-boundaries.md) | Minimal context packet, explicit role limits, routing scenarios. | None | Implemented offline; actual-host behavior pending |
| [02: Receipt and evidence contracts](02-receipts-and-evidence.md) | Shared schema, immutable evidence references, bounded format repair. | 01 | Implemented offline |
| [03: Scripted coordination and quiet waits](03-coordination-and-waits.md) | High-level local operations, recovery-safe handoffs, minimal observation. | 01–02 | Implemented offline |
| [04: Worker-owned verification](04-worker-verification.md) | Verification handoff, evidence reuse, optional repository smoke entry point. | 01–03 | Implemented offline |
| [05: Measurement that distinguishes usage from cost](05-measurement.md) | Phase timing, model-aware usage, optional sourced estimates. | 02–04 | Implemented offline |
| [06: Regression acceptance and rollout](06-acceptance-and-rollout.md) | Offline replay, compatibility checks, deployment instructions, separately authorized trial. | 01–05 | Implemented offline |

Six goals, four ordered steps each: 24 implementation checkpoints. Every step
has validation and documentation evidence in its goal record. All 24
checkpoints are implemented offline; actual-host and publication gates remain
explicitly separate.

Historical execution note: the implementation was delivered through the
recorded focused commits, but later documentation reconciliation and the
offline review corrections were not committed as a strict one-step-at-a-time
cycle. The commit hashes in each goal are provenance checkpoints, not a claim
that every later documentation edit landed before the next historical step.

## Release acceptance

- [x] Coordinator scenario traces contain no production-source investigation,
  diff interpretation, test execution, or independent technical findings.
- [x] Workers retain responsibility for verification and correctness; required
  checks, uncertain writes, stale reviews, and unresolved defects still block.
- [x] Unchanged waits do not trigger worker messages, source reads, repeated
  full transcripts, or repeated state mutations.
- [x] Valid results advance with compact file references and deterministic
  decisions; no model-authored copy of an entire receipt is necessary.
- [x] Documentation/evidence amendments have bounded routing and preserve
  truthful history without consuming production correction rounds.
- [x] Reports separate elapsed time, cached/uncached usage, model profiles,
  estimates, and unknown cost. No raw-token-only optimization gate exists.
- [x] Existing concurrency, pause/recovery, PR, and epic fixtures remain green.
- [x] Offline implementation and actual-host verification are reported separately.
- [ ] An authorized comparison uses equivalent task scope and acceptance;
  no savings or quality equivalence are claimed before measurement.

## Assignment

> Implement goal NN in docs/goals/ticket-loop-improvements. Follow its execution
> instructions, validate each numbered step, update documentation, and commit
> each completed step before proceeding. Use this ordinary chat without
> subagents. Use synthetic external observations and local test repositories.
> Do not start an operational ticket run, publish, or modify live services.

Existing [automation goals](../agent-review-automation/README.md) remain the
historical baseline. This batch supersedes overlapping coordinator, receipt,
waiting, and measurement behavior only as each goal is implemented. Board
intake, estimation, cross-machine claims, automatic merge, skill distribution
tooling, and application-specific bug fixes remain outside this batch.
