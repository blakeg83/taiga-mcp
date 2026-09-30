# Goal 03: Build the skill and ordinary-chat handoffs

Status: not started.

## Objective

Package the procedure so a coordinator can create or reuse ordinary implementation and reviewer chats while preserving identity, settings, and workspace context.

## Prerequisites

Goals 01–02 complete. Use the available skill-creator instructions when actually authoring the skill; this goal document is not the skill.
Read [execution instructions](execution-instructions.md) and [shared contracts](contracts.md).

## Deliverables

An explicitly invoked taiga-ticket-loop skill, role templates, host-tool reference, and offline handoff exercises.

## Ordered steps

### Step 1: Author the coordinator skill

- [ ] Create the proposed repo-local skill with concise entry instructions and linked detailed contracts; disable implicit invocation in its metadata.
- [ ] Define ticket-set/epic start, status, resume, pause, and cancel requests with session-versus-ticket scope and required authority; gate advanced dispatch until goals 07–09 ship.
- [ ] Keep the current coordinator model and exact requested worker profiles. State no subagents in the skill and every role template.
- [ ] Make the helper responsible for bookkeeping and the coordinator responsible for actual tool calls; document unavailable-tool behavior.
- [ ] **Validate:** Validate skill metadata and walk a synthetic invocation through input validation without side effects.
- [ ] **Update documentation:** Document installation/discovery, invocation, and supported host scope.
- [ ] **Commit before the next step:** `Add explicit ticket coordinator skill`.

### Step 2: Define implementation-chat setup and worktree receipt

- [ ] Use actual list_projects results and create_thread arguments in the host procedure; include authorized run/role markers in the initial prompt.
- [ ] Reuse only a verified chat/worktree owned by this run; preserve unrelated work. Track pending clientThreadId separately until a real threadId is established.
- [ ] Explicitly request gpt-5.6-luna/xhigh and the freshly fetched configured base revision/worktree. Goal 07 implements fetch/feature-branch enforcement; no operational start may bypass it. Require the worker to report absolute checkout, branch, base and HEAD.
- [ ] Specify repository instruction loading, tests, docs, local commit checkpoints, handoff format, no independent Taiga writes or unjournaled push/PR actions, and no subagents.
- [ ] **Validate:** Exercise fake immediate/pending creation, wrong base, unavailable model, wrong checkout, and interrupted creation; all ambiguity must stop duplicate creation.
- [ ] **Update documentation:** Document worker setup and workspace verification.
- [ ] **Commit before the next step:** `Define persistent implementation chat handoff`.

### Step 3: Define reviewer setup and follow-up routing

- [ ] Create/reuse the ordinary reviewer chat with the selected Sol/high or Astra/medium profile and scope-limited review prompt.
- [ ] Point the reviewer at that ticket's actual implementation checkout and captured base/HEAD; do not assume another checkout contains the changes. Other ticket chats must use their own branch/worktree.
- [ ] Require no source edits, no additional agents, and a structured review receipt; document that prompts alone do not enforce filesystem read-only access.
- [ ] Route all correction assignments through the coordinator to the same implementation thread. Persist action receipts before further dispatch.
- [ ] **Validate:** Use synthetic transcripts to prove stable worker identities and exact model fields across repeated handoffs; reject unknown or unrelated target IDs.
- [ ] **Update documentation:** Document reviewer access, result shape, and same-chat correction routing.
- [ ] **Commit before the next step:** `Add ordinary reviewer chat routing`.

### Step 4: Validate the complete handoff procedure

- [ ] Walk a fake ticket through create, wait, read, implementer receipt, review dispatch, and correction message. Include two ticket identities to detect feedback routed to the wrong worker.
- [ ] Verify commentary/timeouts/idle status alone cannot become a completed implementation or passing review.
- [ ] Ensure bounded result summaries retain actionable findings and evidence without duplicating entire conversations.
- [ ] Record which behavior is fixture-tested and which needs the authorized goal-06 host smoke exercise.
- [ ] **Validate:** Run helper tests plus all handoff fixture checks; validate skill links/metadata and git diff --check.
- [ ] **Update documentation:** Update the operator guide and goal record with supported and unverified behavior.
- [ ] **Commit before the next step:** `Validate coordinator handoff contracts`.

## Definition of done

- [ ] The skill can be invoked explicitly with no implicit operational activation.
- [ ] Procedures preserve ordinary chat IDs, exact model settings, and real worktree context; story tasks route through their story pipeline.
- [ ] The same implementation conversation receives each correction request; IDs, checkout paths and review results cannot cross ticket boundaries.
- [ ] No subagent, private desktop API, or shell call pretending to be an app tool is used.
- [ ] Every completed step has its own focused commit with documentation and validation evidence.

## Execution record

Complete this table as work proceeds. Record each commit hash in the following step or final handoff.

| Step | Result and evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Pending | Pending | Pending |
| 2 | Pending | Pending | Pending |
| 3 | Pending | Pending | Pending |
| 4 | Pending | Pending | Pending |

Record deviations, blockers, and unverified behavior below; do not replace missing evidence with a checked box.
