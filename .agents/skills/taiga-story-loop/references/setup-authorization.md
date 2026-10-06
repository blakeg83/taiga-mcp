# Setup authorization input contract

The setup summary is one authorization gate for the resolved story or epic.
It is not a preference prompt, a readiness check, or a collection of
per-tool approvals. Discovery remains read-only until the gate has an
explicitly submitted `Start` decision.

## Capability intake

Before rendering the setup gate, record the actual input capability for the
current host and context. The record must identify:

| Field | Required value |
| --- | --- |
| Provider/context | The host, surface, and active conversation where the gate will be shown |
| Source | `documentation`, `tool_schema`, or an authorized `probe` |
| Supports selectable authorization | Whether the interface can present mutually exclusive choices and return a submitted choice event |
| Permits authorization | Whether that interface is allowed to collect permission for the listed external operations |
| Submission evidence | How an explicit human submission is distinguished from a default, empty value, timeout, or message |
| Limitation | The observed reason when either capability is false or unverified |

A preference-only or optional-question input tool is not an authorization
capability. Do not repurpose it for this gate.
For example, the current Codex `request_user_input` tool is an optional
question mechanism available only in Plan mode; it is not evidence that the
default runtime permits selectable authorization. Record that route as
prohibited for this workflow unless a separate authorization-capable interface
is documented or probed.

Choose the gate mode only after capability intake:

```text
selectable = supportsSelectableAuthorization
             and permitsAuthorization
             and explicit submission evidence is available
```

An unavailable, prohibited, or unverified capability selects the explicit
`plain-text` fallback. Do not hardcode a selectable tool name or claim live
selectable behavior from this offline contract or its fixtures.

The capability record must include explicit-submission evidence. A selector is
not sufficient when the host does not document or expose how a human-submitted
choice is distinguished from its default or from an empty/timeout result.
Missing submission evidence therefore selects the typed fallback.

## One gate and its decision record

Render exactly one setup gate for the current resolved scope. The selectable
form contains exactly two mutually exclusive choices, `Start` and `Cancel`,
with the concrete scope and allowed operations visible. It must not rely on a
preselected choice. A displayed default, an elapsed timeout, or a selection
that was never submitted is not authorization.

The fallback says why selectable authorization is unavailable or prohibited
and requests one explicit typed response:

```text
Selectable Start/Cancel is unavailable or not permitted in this interface.
Reply exactly Start or Cancel for the resolved scope above.
```

Accept only:

- a submitted selectable `Start` or `Cancel` event from the same gate; or
- an explicit typed `Start` or `Cancel` response to the fallback.

Each selectable decision carries the active gate identity, revision, and
resolved scope. Accept it only while that gate is open and only when all three
values match. `Start` and `Cancel` close the gate; duplicate, stale, or
post-Cancel events are rejected without changing the decision or dispatching
again. A scope change replaces the gate, increments its revision, clears the
prior authorization, and requires a fresh decision for the new scope.

Blank or invalid text, an empty response, a default-only response, a timeout,
unrelated text, and a worker message remain `awaiting_confirmation`. They do
not create chats, branches, worktrees, commits, pushes, Taiga writes, pull
requests, or recovery automations. An explicit `Cancel` ends setup with no
external writes.

For an accepted `Start`, persist one immutable authorization record and pass
the same record to every assignment:

```text
Authorization: decision=start | mode=<selectable/plain-text> |
scope=<resolved scope reference> | authorization=<resolved authorization
reference> | submitted=true
```

The record's scope reference, mode, decision, submission evidence, and
resolved authorization reference are part of the existing continuation note
and worker assignment; a worker or later message cannot replace or widen it.
The `Cancel` result may be retained as a local decision outcome, but it never
creates a run, assignment, or external mutation.

If the user makes a scope change to the project, work item, ordered tasks, repository,
branches, review mode, or permitted operations, invalidate the prior gate and
replace it with one new gate for the new scope. The old decision and
authorization reference cannot authorize the changed scope.

## Evidence boundary

The offline decision fixture may exercise both a synthetic permitted
selectable provider and unavailable/prohibited fallbacks. Its results are
`automated_assertion` evidence only. Actual selectable UI behavior requires a
separately authorized host observation and must be reported independently.
