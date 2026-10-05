# Issue #82: message-driven review handoffs

The repo-local `taiga-story-loop` now explicitly ends initial and
correction-ready implementer turns in `awaiting_review`, forbids implementer
reviewer polling, and resumes the same chat on authorized reviewer messages.
Resume checks bind actions to the assigned reviewer, current task, pending
revision, branch HEAD, and prior outcome. Stale and duplicate outcomes cannot
release a gate or duplicate writes. Coordinator recovery treats idle review
waits as healthy and reconciles genuinely interrupted or missing handoffs.

## Live Codex evidence (2026-10-04, America/La_Paz)

The user separately authorized two temporary ordinary chats and messages
between them for this controlled trial:

- [Issue 82 live trial implementer](codex://threads/01a10a16-386a-7621-8b0a-a0c36c896993), `gpt-5.6-luna` / `xhigh`.
- [Issue 82 live trial reviewer](codex://threads/01a10a16-33ef-74f1-aa48-3db95d37fd3c), `gpt-6.1-sol` / `medium`.
- [Coordinator](codex://threads/01a10a12-ad06-7381-b296-6f989b659956).

The pair read the changed repo-local prompt/handoff guidance and worked only
in a disposable Git repository on `codex/issue82-live-trial`. Synthetic task
`TRIAL-82-A` required exactly five ASCII bytes `fixed` in `result.txt` and no
`next.txt`. Task lifecycle counters were stored in untracked `trial-state.json`.
There were no live Taiga task writes, pushes, PRs, or production-run migration.
The coordinator observed final responses as its handoffs and held reviewer
delivery until each implementer turn was confirmed completed/idle. This tests
actual chat turn termination and message-triggered resumption, independently
of offline state fixtures; it does not test a full live Taiga story lifecycle.

| Observed implementer turn | Revision/result |
| --- | --- |
| `01a10a16-ca0f-7470-abc2-092c46fca579` | Initial ready handoff at `3ac44d3c188dd3a13da74b8466ecad038cd4b791`, then final response and idle `awaiting_review`. |
| `01a10a18-96e3-7f02-9e42-17fdf133bffc` | Reviewer finding resumed the same chat; correction at `8fdb5e01b89364de27f866d04cc94efdcfab4915`, handoff, final response, idle again. |
| `01a10a1a-450f-71f0-9fea-fa0e5584234e` | Labeled stale acceptance for the first revision ignored; state stayed `awaiting_review`, acceptance transitions 0. |
| `01a10a1a-d7f9-7850-97ce-a667fee03fe6` | Reviewer caught a trailing newline; second correction at `58e613b5b8e9ad0f7e515dac55d2fb8ee42988c2`, handoff, final response, idle again. |
| `01a10a1d-9f67-79e2-aec3-ac0d760f016d` | Current exact-revision acceptance resumed the same chat; state became `accepted`, acceptance transitions 1, reopen transitions 2. |
| `01a10a1e-92e9-7171-9abc-33051d9a981b` | Controlled duplicate acceptance ignored; all counters and state remained unchanged. |

Inspected implementer tool traces contain only one outgoing reviewer message
per ready/correction turn, immediately followed by the final response. There
are zero implementer `wait_threads`/reviewer-read calls and no actions after
those handoffs within their turns. Each incoming reviewer message identifies
the assigned reviewer's source chat. Only `result.txt` changed in trial
commits; `next.txt` remained absent throughout. Final bytes were
`66-69-78-65-64`. The accepted SHA remained HEAD. The trial state SHA-256 before
and after duplicate delivery was
`873A58306AF33046F971D0B13B1DA28DBF3AD31BF9D756CD0F57CA4CBFE143C3`.

The first correction handoff accidentally shortened its SHA and relaxed its
newline check; the reviewer resolved the actual commit and rejected the
remaining defect. The final handoff and acceptance used the full exact SHA.
The guidance now instructs copying the SHA directly from `git rev-parse HEAD`.
A transient trial-state JSON error was repaired before the second handoff.
These trial mistakes did not release the review gate.

## Offline checks and rollout

All nine `scripts/validate-*.ps1` checks in `taiga-story-loop` passed, along with
the skill-creator `quick_validate.py` and `git diff --check`. Ordered-task,
selective-reopening, version-safe reconciliation, and advancement checks remain
offline fixtures; they are not evidence of live Taiga mutations. The .NET
server is unchanged, so application builds/tests were not rerun for this
workflow-guidance change. Token usage/cost savings are unknown.

New assignments must use these updated repo-local prompts. Existing worker
assignments, installed copies, and recovery automation prompts need an
authorized refresh; this fix does not silently migrate an active run. No live
recovery heartbeat was created or exercised in the trial.
