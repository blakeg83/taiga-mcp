# Acceptance evidence and capability intake

Acceptance evidence is a claim about a particular story revision and a
particular execution environment. It is not a restatement of the ticket, a
wrapper result, or a promise to run a check later. Before implementation, the
worker records a short evidence plan in the task endpoint or assignment.

## Decide whether UI evidence applies

First classify the changed behavior. Documentation-only, service-only, and
non-UI changes do not receive invented browser, viewport, focus, or console
acceptance criteria. A UI criterion is included only when the real story or
repository requires a rendered interaction.

When UI evidence is applicable, record the required host/data setup, the
interaction cases, and which results must be automated assertions versus
visible observations. Keep required capabilities conditional on the actual
criterion; do not turn a generic browser checklist into a universal gate.

## Capability discovery comes before a limitation claim

Before a required browser check, read the applicable installed skill/tool
documentation and inspect the current host's advertised browser capabilities.
Probe the relevant capability in the authorized environment when the
documentation or schema does not settle the question. Record:

- the capability and why the story needs it;
- the documentation, schema, or probe used as the source;
- the provider/context observed and the result (`available`, `unavailable`,
  or `unverified`); and
- the resulting check, fallback, or limitation.

An unavailable claim is valid only when its source or probe is recorded. A
wrapper that lacks a convenience method is not evidence that the underlying
host lacks the capability. A capability listing proves availability of a
route to attempt a check, not that the check succeeded. Report those facts
separately, and never silently replace a required check with an assumption.

## Prove the production path

Acceptance harnesses, fakes, and browser wrappers must preserve the
production arguments, evidence hints, validation, and result semantics that
matter to the change. The evidence plan names:

- the production entry point and a control that proves it was reached;
- the exact required arguments and evidence hints forwarded to it;
- the validation that must run before the operation; and
- the result fields or side effects that demonstrate the production behavior.

Inspect interception and stubs for bypasses. A fixture that returns a canned
result without reaching the production entry point is wrapper evidence only
and cannot establish acceptance. A focused control (for example, a recorded
call with an argument sentinel) must fail when the wrapper drops an argument,
skips validation, or short-circuits the production path.

## Measure the intended operation

Metrics name the intended operation, counter, unit, sample size, warm-up and
controlled conditions, baseline, and limitations. Count the target operation
separately from adjacent stages and caches. A cache hit is not evidence reuse;
it is evidence reuse only when the recorded operation actually reused the
intended evidence. Do not infer speedup from incomparable timings or omit the
baseline and sample conditions.

## Record scenario evidence honestly

Use a small scenario matrix. Every required scenario records its setup,
action, expected result, observed result, evidence kind, and status. The
evidence kind must distinguish:

- `automated_assertion` — a repeatable assertion or check output;
- `visible_observation` — an observation made through the authorized visible
  UI; and
- `unavailable` — a required check that could not be performed, with the
  capability source, reason, and owner or next action.

Automated assertions do not become visible observations, and synthetic
fixtures do not become browser execution. An unavailable case remains
unavailable in the report; it is not marked passed because a different case
passed. Include normal, stale, cancellation, dirty-edit, responsive, focus,
or console cases only when the selected story/repository requires them.

## Make smoke instructions executable and safe

For a required smoke check, provide executable setup, start, actions, expected
results, and cleanup. Name the working directory, required capabilities, and
the data scope. Setup must be paired with cleanup; writes must use authorized
disposable data, and the instructions must not retain database mutations or
perform a live crawl. A generic skill validator may validate the shape and
capabilities of these instructions, but it does not start services, open a
browser, or claim that the smoke run happened.

The final report identifies the exact revision, commands, exit codes, visible
observations, automated assertions, unavailable checks, and limitations. The
offline fixtures in this skill are synthetic review examples only and are
never browser, database, or live-provider evidence.
