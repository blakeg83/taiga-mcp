# Story and task contracts

Use these contracts to turn the selected Taiga pages into a bounded workflow.
They describe what must be known and evidenced; they do not invent product
acceptance criteria or grant permission to perform external writes.

## Story contract

```markdown
# Story: <project> #<ref> — <subject>

## Codex agent goal
<One actionable outcome stated in user/product terms.>

## Scope
- In scope: <work covered by this story>
- Out of scope: <nearby work deliberately excluded>
- Repository/workspace: <resolved repository and path>
- Related epic: <resolved epic or “none”>

## Dependencies and execution order
1. <task ref> — <subject> — depends on <none or prior task refs>
2. <task ref> — <subject> — depends on <prior task refs>

Unresolved requirements: <none, or the exact questions to resolve before work>

## Definition of done
- [ ] <observable story outcome>
- [ ] <observable verification or delivery outcome>

## Verification and delivery
- Checks: <commands or other evidence appropriate to the changed artifacts>
- Review/approval boundary: <what remains unapproved or requires a separate decision>
```

The goal must be actionable without prescribing an implementation. Scope is
the selected story's boundary, not a license to expand into neighboring work.
Dependencies are explicit and ordered by the story or by a clarified user
decision; never infer execution order from the order returned by an API. A
definition-of-done item is complete only when its observable evidence is
available.

## Task contract

```markdown
## Task <position>/<total>: <project> #<ref> — <subject>

### Objective
<The concrete outcome of this task and its parent-story boundary.>

### Execution position
- Depends on: <none or completed task refs>
- May start when: <prerequisite and status gate>
- Expected result: <artifact or behavior that can be inspected>

### Completion checklist
- [ ] <observable implementation or documentation result>
- [ ] <focused check and evidence>
- [ ] <review/status/comment/commit handoff result, when applicable>
```

Keep each checklist item observable and specific enough to verify. A task is
ready for review when its implementation evidence is complete; that is distinct
from reviewer acceptance or a closed/done status.

## Discovery and clarification rules

1. Read the complete story page, its definition of done, and every associated
   task page before coding. Capture each task's internal ID, displayed ref,
   subject, description, status, version, parent story, and dependency cues.
2. Preserve the user's wording and the Taiga acceptance criteria. Translate
   them into the contract without silently weakening, broadening, or replacing
   them.
3. Use the story's ordered-task section when present. If order, repository,
   acceptance criteria, or a dependency is missing or materially ambiguous,
   ask the narrow clarification needed before starting the affected task. Do
   not fill the gap with broad speculative planning.
4. Keep setup permissions and engineering implementation separate: the
   contract records the intended scope and evidence, while the later setup
   confirmation records which external operations the user authorizes.
5. Keep the task status and checklist aligned with evidence. If a review finds
   a substantive defect, reopen the affected task and update the contract
   evidence rather than marking it done by momentum.
