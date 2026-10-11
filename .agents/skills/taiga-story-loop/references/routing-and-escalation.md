# Routing and substantive escalation

The story pair remains stable across at least two task reviews and any ordinary
correction. Story-worker routine findings go directly from reviewer to
implementer, and story correction-ready handoffs go directly from implementer
to the same reviewer. The coordinator observes durable workflow state and
routes only assignments or exceptional escalations; it does not relay or
restate routine findings. The integrated epic pair uses the distinct routes
below.

## Integrated epic-review destinations

The fresh integrated epic-review pair uses a distinct destination boundary:

| Event | Sender | Destination | Meaning |
| --- | --- | --- | --- |
| Correctable finding / changes requested | epic reviewer | same epic-fix implementer | Routine correction request; no coordinator copy or relay. |
| Correction ready for integration | epic-fix implementer | coordinator | Actionable integration request, not acceptance; it must bind the finding/review request, reviewed and corrected full revisions, correction branch/worktree, clean source, delta, checks, and next action. |
| Final exact-HEAD approval | epic reviewer | coordinator | Acceptance of the exact integrated feature HEAD after all required re-reviews. |
| Exceptional escalation | epic reviewer or epic-fix implementer | coordinator | Blocked verification, unknown delivery, stale/conflicting revision, missing destination, or scope/authorization decision. |

The coordinator owns the existing reviewed integration path after an
integration-ready event: verify the packet, incorporate the correction into the
feature branch, capture the resulting exact feature HEAD, persist continuation,
and dispatch exact-HEAD re-review to the same fresh pair. A correction receipt
alone never becomes epic acceptance. Ordinary correction and re-review rounds
reuse the pair; they do not create a new chat.

Use destination-bearing result templates. A `changes requested` result names
the same epic-fix implementer and the correction request. An `accepted` or
exceptional result names the coordinator and the exact approval or escalation
action. Story-worker routing remains unchanged.

## Controlled scenarios

The companion `scripts/validate-routing.ps1` fixture exercises this sequence:

1. task A is ready, receives a direct finding, and returns a correction to the
   same reviewer;
2. task A is accepted, task B is ready, and task B receives a direct correction
   and a final story review; and
3. blocked work, unresolved technical disagreement, stale final approval,
   missing destinations, unknown delivery, and revision conflicts each route
   to the coordinator.

The fixture uses two persistent worker IDs and no sleeps, provider calls,
transcripts, JSON receipts, or real Taiga/Git writes. It asserts that routine
findings and corrections never reach the coordinator, ordinary corrections do
not create a third chat, and a reviewer only approves the exact revision it
inspected.

## Escalation rules

| Condition | Coordinator action | Do not do |
| --- | --- | --- |
| Worker blocked or check cannot proceed | preserve evidence and ask for the specific decision/external change | silently retry, skip the task, or claim readiness |
| Reviewer and implementer disagree on a substantive requirement | surface both concise positions and ask the user | choose a product decision from source code |
| Proposed major architectural expansion before implementation | preserve the approved boundary and ask the user using the requirement, simpler alternative, proposed approach, and tradeoff | implement the expansion or add a new approval gate for routine choices |
| Implementer and reviewer agree on expanding scope | route the unresolved requirement or architectural decision to the user | treat worker consensus as authorization to enlarge scope |
| Message destination is missing, pending, or ambiguous | stop dispatch and report the unresolved worker identity | create a replacement chat automatically |
| Message delivery outcome is unknown | reconcile the provider/thread state before retrying | send a duplicate or infer delivery from idle status |
| Current revision conflicts with the pending review binding | reconcile the branch HEAD and review evidence, then re-review the correct revision | overwrite the binding or advance the task |
| Final approval names a stale HEAD | mark approval stale and route the changed revision back to the same reviewer | create a PR from the stale approval |

These routes have no arbitrary elapsed deadline or fixed correction-count
cutoff. A heartbeat may observe progress, but a timeout is not acceptance,
failure, or permission to start the next task. Repeated lack of progress is
evidence for escalation, not a reason to close the story automatically.
