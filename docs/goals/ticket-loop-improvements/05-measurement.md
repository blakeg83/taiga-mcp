# 05: Measure time and model usage without equating tokens to cost

Status: implemented offline; actual-host usage and attributable cost remain pending an authorized trial.
Prerequisites: 02–04 in this batch and [execution instructions](execution-instructions.md).

## Objective

Provide useful phase and role measurements while distinguishing processing counters, model economics, and actual billed or subscription consumption.

## Expected touch points

A small local reporting helper, versioned run/evidence metadata, synthetic usage fixtures, and docs/automation measurement guidance.

Paths under scripts, references, and assets are relative to
`.agents/skills/taiga-ticket-loop/`. Keep changes within this goal's scope.

See the [measurement contract](../../../.agents/skills/taiga-ticket-loop/references/measurement-contract.md)
for timing, usage, cost, and comparison semantics.

## Ordered steps

### Step 1: Record phase and action timing

- [x] Capture dispatch, result observed, receipt accepted, phase change, wait, repair, publication, and pause timestamps with an injected clock.
- [x] Separate worker-reported execution duration from coordinator observation latency and wall-clock phase intervals; mark unavailable timings unknown.
- [x] Keep a bounded operational registry and an append-only local audit record or equivalent preserved events so long runs do not lose the measurement baseline.
- [x] Add configurable early elapsed-time alerts for stalled or repetitive phases; do not silently cancel active workers or change their models.
- [x] **Validate:** Test delayed observation, clock boundaries, repeated waits, long runs, and pause/resume without inventing execution durations.
- [x] **Update documentation:** Document timing definitions, retention, and escalation policy.
- [x] **Commit before the next step:** `Record ticket-loop phase measurements`.

### Step 2: Import usage snapshots accurately

- [x] Read explicitly selected chat usage exports or documented local record shapes; capture role, exact model/effort, timestamps, totals, and source provenance without message text.
- [x] Calculate cumulative deltas, detect duplicates, counter resets, missing samples, and inconsistent fields. Segment resets explicitly; never sum cumulative snapshots or fill missing usage with zero.
- [x] Respect the run's start/end boundaries and flag later chat activity. Treat cached input as part of input and reasoning as part of output where the source schema establishes that relationship.
- [x] Keep usage updates distinct from proven request counts. Summarize per role/phase and report attribution uncertainty.
- [x] **Validate:** Use synthetic duplicates, resets, compaction, multiple models, missing usage, partial boundaries, and post-run collection activity.
- [x] **Update documentation:** Document import formats and counter interpretation.
- [x] **Commit before the next step:** `Report token usage with correct boundaries`.

### Step 3: Separate cost and quota reporting

- [x] Always show raw usage and model profile. Do not rank worker efficiency by raw totals or replace Luna merely for using more tokens.
- [x] Show actual monetary or subscription consumption only when attributable data is supplied. Otherwise label it unavailable.
- [x] Optionally estimate API cost only with explicit dated model-specific input/cache/output rates and supported accounting semantics. Record rate source and assumptions; never apply API estimates to ChatGPT allowance as if equivalent.
- [x] Keep coordinator profile evaluation explicit and optional. No automatic model selection, effort reduction, or universal token ceiling for this batch.
- [x] **Validate:** Test different synthetic model rates, missing rates, cached input, already-inclusive reasoning, mixed models, and subscription runs with unknown attribution.
- [x] **Update documentation:** Document estimate versus measurement and the economics-aware comparison policy.
- [x] **Commit before the next step:** `Separate model usage from cost estimates`.

### Step 4: Produce a comparison report

- [x] Report completion quality, accepted defects, wall time, role/phase usage, coordination actions, repair counts, and available cost fields.
- [x] Compare only equivalent task scope, repository requirements, and worker profiles; disclose differences, caching, and test-environment effects.
- [x] Retain the audited run as a sanitized historical summary, not a precise monetary baseline. Use synthetic inputs in committed tests.
- [x] Provide actionable findings without declaring raw-token reduction a release gate.
- [x] **Validate:** Run the report on synthetic manual/automated pairs including a higher-token cheaper-model case and unavailable cost.
- [x] **Update documentation:** Publish the comparison template and limitations.
- [x] **Commit before the next step:** `Add model-aware workflow comparison reports`.

## Definition of done

- [x] Phase intervals and observation latency are clearly distinguished.
- [x] Usage arithmetic handles duplicate/reset/missing records and run boundaries.
- [x] Raw counts, estimated cost, actual cost, and subscription usage are separate.
- [x] Higher Luna token use alone cannot fail acceptance or trigger a model change.
- [x] Each completed step has validation evidence, documentation updates, and its own commit.

## Execution record

Record a step's hash in the next checkpoint or final handoff. Leave incomplete
gates unchecked; record deviations and blockers below the table.

| Step | Result and validation evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | `workflow-measure.ps1` records injected phase events, separates observation latency from worker duration, retains bounded recent state plus append-only audit, correlates action/worker timing, and emits advisory stall alerts. Timing and long-run audit fixtures passed. | Measurement contract and timing guidance | `5d7f9e7` |
| 2 | Usage import requires stream identity, detects reset segments and missing boundaries, excludes post-run deltas, and never zero-fills missing usage. Synthetic usage fixture passed. | Usage interpretation guidance | `3cd9110` |
| 3 | Cost reporting separates raw usage, model profiles, dated API estimates, actual monetary consumption, and subscription attribution; incomplete rates/counters stay unavailable. Synthetic rate/cached-input fixture passed. | Economics-aware reporting guidance | `c52f1b1` |
| 4 | Comparison reporting exposes quality, wall time, role usage, coordination, repairs, and cost availability, and refuses missing or unequal scope/profile comparisons. Higher-token equivalent runs remain acceptable. Synthetic comparison fixture passed. | Comparison template and limitations | `8e64b19` |
