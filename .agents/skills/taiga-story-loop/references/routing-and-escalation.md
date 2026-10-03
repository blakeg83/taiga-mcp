# Routing and substantive escalation

The pair remains stable across at least two task reviews and any ordinary
correction. The coordinator routes messages by worker identity and state, not
by opening a new chat or replaying all prior context. A short handoff points to
the stable revision and the authoritative story/task pages.

## Controlled scenarios

The companion `scripts/validate-routing.ps1` fixture exercises this sequence:

1. task A is ready, receives a finding, and returns a correction to the same
   reviewer;
2. task A is accepted, task B is ready, and task B receives a correction and a
   final story review; and
3. blocked work, unresolved technical disagreement, stale final approval, and
   missing destinations each route to the coordinator.

The fixture uses two persistent worker IDs and no sleeps, provider calls,
transcripts, JSON receipts, or real Taiga/Git writes. It asserts that ordinary
corrections do not create a third chat and that a reviewer only approves the
exact revision it inspected.

## Escalation rules

| Condition | Coordinator action | Do not do |
| --- | --- | --- |
| Worker blocked or check cannot proceed | preserve evidence and ask for the specific decision/external change | silently retry, skip the task, or claim readiness |
| Reviewer and implementer disagree on a substantive requirement | surface both concise positions and ask the user | choose a product decision from source code |
| Final approval names a stale HEAD | mark approval stale and route the changed revision back to the same reviewer | create a PR from the stale approval |
| Destination is absent, pending, or ambiguous | stop dispatch and report the missing worker identity to the coordinator | create a replacement chat automatically |

These routes have no arbitrary elapsed deadline or fixed correction-count
cutoff. A heartbeat may observe progress, but a timeout is not acceptance,
failure, or permission to start the next task. Repeated lack of progress is
evidence for escalation, not a reason to close the story automatically.
