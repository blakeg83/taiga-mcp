# Verification evidence contract

`workflow-evidence.ps1` stores small immutable records under the persistent
state root's `evidence/` directory. It never adds check output to
`registry.json`. Run metadata and evidence records are JSON files protected by
SHA-256; large console output is copied once to a content-addressed log file
under `evidence/logs/`. Records and logs remain in the state root until an
operator removes them. Preserve referenced files for as long as a receipt or
review depends on them.

## Trusted metadata

Prepare verification actions through `workflow-state.ps1` with an action kind
of `implementation_check`, `review_check`, `expected_red_fixture`, `assertion`,
or `intentional_host_shutdown`. Its bounded `evidenceContext` stores the
command, working directory, packet criterion IDs, and optional worker-supplied
input coverage. Coverage records revision, base SHA, covered files, environment
hash, and dependency hash; it is provenance, not a coordinator-generated
claim. `initialize-run` then
checks the packet hash and full-context hash, binds the prepared action to the
packet's run/session/ticket, and reads branch, base SHA, and current HEAD from
the committed Git worktree. It fills criterion IDs/text from the packet,
profile from the action role, and UTC time from the local clock. It rejects a
dirty checkout, branch drift, or a missing worktree.

`capture` takes the previously observed process exit code and an existing log
file. It confirms the metadata, action, packet, branch, and HEAD still match,
copies the log by content hash, and creates a new evidence ID with `CreateNew`.
It does not rerun the command or infer results from log text. The raw exit code
is retained. A captured record identifies its origin action, checked revision,
command, working directory, criterion IDs, exact profile, timestamp, optional
input coverage, log path, log hash, and byte length. Reusing an evidence ID or
changing a record/log causes validation to fail.

## Outcome classification

| Prepared action kind | Outcome rule | Counts as a passing check? |
| --- | --- | --- |
| `implementation_check`, `review_check` | Exit 0 is `passed`; any other raw exit is `failed`. | Only exit 0. |
| `expected_red_fixture` | Nonzero is `expected_red_failure`; zero is `unexpected_pass`. | Never. |
| `assertion` | `assertionPassed: true` with exit 0 is `assertion_passed`; otherwise `assertion_failed`. | No; counted separately. |
| `intentional_host_shutdown` | Exit 0 is `intentional_stop`; nonzero is `intentional_stop_failed`. | Never. |

Thus an exit 1 returned while intentionally stopping a test host remains an
intentional-stop failure with raw exit 1. It cannot turn the test run into a
pass. A real failed check stays distinct from an expected-red fixture failure.

## Validate and summarize

`validate` verifies the immutable evidence JSON hash, outcome derivation, log
path containment, log hash, and recorded byte length. `summarize` recomputes
counts from validated records only: check passes/failures, expected-red
outcomes, assertions, and intentional shutdowns remain separate totals.
Reported-only values require their source and report timestamp and stay in a
separate `reportedOnly` list; they are never added to structured counts or
converted into an invented precise total.

Evidence files live outside worktrees by default at
`%LOCALAPPDATA%/TaigaMCP/agent-review-automation/evidence/`. Pass `-StateRoot`
for isolated fixtures. The helper writes files with create-new semantics and
does not mutate worker source or ticket state.
