# Goal 07: Start from the latest base and deliver reviewed PRs

Status: implemented offline; local bare-remote branch/push fixtures pass. Authenticated provider operation remains unverified.

## Objective

Give each executable ticket an isolated feature branch from freshly fetched master (or its configured base), then publish and track one reviewed PR without automatic merging.

## Prerequisites

Goals 01–06 complete. Use a local bare Git remote and fake GitHub/Taiga adapters for tests. Operational push/PR actions require the scoped authorization captured in the run.
Read [execution instructions](execution-instructions.md) and [shared contracts](contracts.md).

## Deliverables

Git start/update procedure, GitHub adapter contract, PR delivery/merge transitions, and publication/recovery fixtures.

## Ordered steps

### Step 1: Create the feature branch from a freshly fetched base

- [ ] Validate repository, fetch remote, base branch and push target. For TaigaMCP use verified origin/master; configure other repositories explicitly.
- [ ] Fetch under a short shared-ref lock, capture the resulting base SHA, and create a managed worktree from that immutable revision using supported app tools.
- [ ] Create and verify a unique codex/<kind>-<ref>-<slug>-<run-suffix> branch before coding. Record base, branch, checkout, clean state and worker identity.
- [ ] On fetch failure, wrong base, detached HEAD not yet branched, or branch collision, resolve before dispatch. Resume owned work without resetting it or the user's checkout.
- [ ] **Validate:** Use local bare remotes to test stale local master, fetch failure, a moving remote ref, detached worktree, branch collision, and preserving uncommitted user work.
- [ ] **Update documentation:** Document repository mapping, fresh-base receipts, branch naming, and resume behavior.
- [ ] **Commit before the next step:** `Start ticket branches from verified fresh bases`.

### Step 2: Refresh integration state and push the reviewed revision

- [ ] Recheck the remote target before publication; when it advanced, update the owned feature branch and resolve conflicts through the same Luna chat.
- [ ] Default to merging the target into published branches, avoiding force-push. Invalidate old approval, rerun relevant checks and review the resulting revision.
- [ ] Journal the authorized push, verify the remote branch equals the reviewed SHA, and reconcile ambiguous push results by reading that ref.
- [ ] Respect branch protections and check requirements; surface conflicts or incompatible linear-history policy instead of rewriting unrelated history.
- [ ] **Validate:** Test target advancement, conflict correction, stale approval, changed source during publication, non-fast-forward rejection, and response-lost after a successful local-remote push.
- [ ] **Update documentation:** Document base refresh, re-review requirements and uncertain-push recovery.
- [ ] **Commit before the next step:** `Publish only the reviewed feature revision`.

### Step 3: Create or update one PR and record delivery

- [ ] Select the authenticated GitHub CLI/connector after host preflight; document its actual structured inputs/outputs. Use safe body-file/structured arguments for multiline descriptions.
- [ ] Query the exact repository/head/base before creation. Create one PR after pass, or update the matching existing PR after corrections; preserve its identity.
- [ ] Include Taiga identity/link, run marker, summary, acceptance criteria, test evidence and reviewed SHA. Persist repository/number/URL/base/head receipt.
- [ ] Attach each created PR to the relevant Codex chat and link it in Taiga. Reconcile uncertain create/attachment/comment results; do not publish duplicate PRs because a response was lost.
- [ ] **Validate:** Fake GitHub cases: create success, existing matching PR, mismatched target/head, multiple matches, create-applied/response-lost, denied access, and later corrected head.
- [ ] **Update documentation:** Document the PR template, provider preflight, delivery status and recovery.
- [ ] **Commit before the next step:** `Create and reconcile ticket pull requests`.

### Step 4: Observe checks and merge without auto-merging

- [ ] Release execution capacity after delivery while retaining ticket ownership and PR observation. Keep open, closed-unmerged and merged states distinct.
- [ ] Track required checks, expected base and reviewed head provenance; new head/material feedback reacquires a slot and returns through the same correction/review loop.
- [ ] Handle merge, squash and rebase integration using provider provenance plus integrated-result evidence. Never equate a non-ancestor SHA or closed PR with failure/success by itself.
- [ ] Finalize mapped Done only under the configured policy and verified receipts; preserve merge evidence if a Taiga write fails. No automatic merge or force-push.
- [ ] **Validate:** Run Git/PR fixtures including failed/missing checks, closed-unmerged, squash/rebase, an unreviewed merged head, and delayed Taiga finalization; run git diff --check.
- [ ] **Update documentation:** Publish PR-delivery versus Done semantics and observed integration evidence.
- [ ] **Commit before the next step:** `Track pull request integration and ticket completion`.

## Definition of done

- [ ] Every new executable ticket starts on its own named branch at the recorded freshly fetched base.
- [ ] Published remote head matches the revision that passed review; later changes invalidate approval.
- [ ] One PR is created/reused per executable ticket with Taiga and Codex links.
- [ ] PR delivery, merge observation and Done are distinct; merge/check uncertainty does not fabricate completion.
- [ ] No tests push to a production remote or modify live Taiga/GitHub data.
- [ ] Every completed step has its own focused commit with documentation and validation evidence.

## Execution record

Record each commit hash in the following step or final handoff. Leave incomplete gates unchecked.

| Step | Result and evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Pending | Pending | Pending |
| 2 | Pending | Pending | Pending |
| 3 | Pending | Pending | Pending |
| 4 | Pending | Pending | Pending |

Record deviations, blockers and unverified behavior below.
