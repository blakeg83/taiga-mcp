# Second implementation batch: discovery and complete daily workflows

Status: in progress. Goals 01 (`get_current_user`), 02
(`list_project_members`), 03 (`resolve_work_item`), 04
(`list_user_story_statuses`), and 05 (`list_task_statuses`) are delivered; the remaining 7 functions below
are planned and are not callable until their goals ship. Prepared 2026-09-29
against the current 28-tool repository baseline after goal 05.

## Objective

Remove manual ID lookup from daily work, complete basic epic editing and membership
management, and let agents read conversations and change history before acting.
The [first batch](../first-batch/README.md) is complete within its selected scope.

## Ordered goal list

| Order | Goal | User-visible outcome | Dependencies within this batch |
| --- | --- | --- | --- |
| 01 | [get_current_user](01-get-current-user.md) | Let an agent identify the authenticated account and use its numeric user ID in existing assignment and member filters. | None; reuse implemented baseline |
| 02 | [list_project_members](02-list-project-members.md) | Let agents identify project members for assignment without confusing membership records with user accounts. | 01 |
| 03 | [resolve_work_item](03-resolve-work-item.md) | Translate a human-facing project #ref into the correct internal issue, story, task, or epic ID. | None; reuse implemented baseline |
| 04 | [list_user_story_statuses](04-list-user-story-statuses.md) | Expose the project's complete selectable story workflow options, including closed/archived columns. | None; reuse implemented baseline |
| 05 | [list_task_statuses](05-list-task-statuses.md) | Let agents discover task workflow IDs before changing task progress. | 04 |
| 06 | [list_epic_statuses](06-list-epic-statuses.md) | Provide valid epic workflow IDs for creation and the planned epic update command. | 04 |
| 07 | [list_sprints](07-list-sprints.md) | Let agents find existing sprints and use their IDs to schedule stories or standalone tasks. | None; reuse implemented baseline |
| 08 | [update_epic](08-update-epic.md) | Complete routine epic management: edit content, change ownership, update appearance/tags, and close or reopen through a chosen status. | 02, 06 |
| 09 | [list_epic_user_stories](09-list-epic-user-stories.md) | Expose the existing stories linked to an epic so agents can inspect or correct its membership. | None; reuse implemented baseline |
| 10 | [unlink_user_story_from_epic](10-unlink-user-story-from-epic.md) | Remove a mistaken epic/story association while preserving both work items and their other relationships. | 09 |
| 11 | [list_work_item_comments](11-list-work-item-comments.md) | Let agents read prior discussion on issues, stories, tasks, and epics before making changes or adding comments. | 03 |
| 12 | [get_work_item_history](12-get-work-item-history.md) | Expose who changed a work item, when, and what changed, alongside safe visible comment context. | 11, 08, 10 |

Default execution order is 01 through 12. Dependencies identify reusable work or
acceptance workflows; none requires recreating the removed first-batch goal files.
Goal 10 owns the new transport support for empty DELETE responses. Goal 11 owns
shared history read/pagination infrastructure reused by goal 12. The three status
goals remain separate public tools with separate completion evidence.

## Assigning a goal

Read [execution instructions](execution-instructions.md),
[shared contracts](contracts.md), and [pinned source evidence](sources.md).
Each function has its own target interface, four ordered steps, tests, documentation
tasks, commit checkpoints, acceptance scenarios, and definition of done.

Suggested coding-agent assignment:

> Execute docs/goals/second-batch/NN-function.md. Follow current AGENTS.md and the
> linked batch instructions/contracts. Reuse implemented prerequisites. Complete
> and validate one step at a time, update documentation during each step, and
> commit after each completed step. Preserve unrelated work; report all step
> commit hashes, validation results, and definition-of-done evidence.

These documents do not start agents, create chats, or authorize implementing
unassigned goals, live writes, push, PR, or merge.

## Selected behavior and boundaries

New functions build on the existing 28 tools; completing the remaining 7 yields
35 tools unless separately authorized changes alter that count. No separate foundation
goal is needed: transport/auth/cache/validation/protocol tests already exist.

The new list functions use page envelopes. Reference lookup returns an identity
receipt, status readers expose all choices, sprint lookup selects existing
milestones, linked-story listing returns relationship IDs/order, and unlinking
deletes only that relationship. Comment/history reads preserve source-page
continuation even when local visibility filtering removes entries.

Deferred: sprint create/edit/stats, workflow administration, estimates, multiple
assignees, attachments, custom fields, bulk operations, arbitrary sorting, epic
progress aggregation, work-item deletion, and comment edit/delete/restore.
The [full inventory](../../taiga_command_inventory.md) remains the broader roadmap.
No remaining function is added to the implemented reference until its MCP tool
ships.

## Batch acceptance workflow (fake HTTP only)

1. Read the current user and project members; use returned user IDs in existing assignment tools.
2. Resolve a project #ref, retrieve item detail, and use its version for an update.
3. Discover story/task/epic statuses and use their IDs in corresponding transitions.
4. List sprints and place a story into a returned milestone.
5. Create/edit an epic, link stories, list those relationships, and unlink one while preserving the story.
6. Submit comments, read visible conversation pages, and inspect field-change history.
7. Verify all existing names, arguments, JSON shapes, safe errors, cancellation, and one-401 replay contracts.

## Completion checklist

- [ ] All 12 function definitions of done are met; every step has its own local commit.
- [ ] 35 expected public tools are discoverable with descriptions and correct argument schemas.
- [ ] Actual MCP invocations cover the batch workflow and the 24 baseline contracts.
- [ ] Debug and Release builds/tests pass with fake data only; no generated outputs are committed.
- [ ] Documentation, inventory coverage, current counts, and local links match delivered behavior.
- [ ] Goal records contain source revisions, test results, deviations, and commit evidence.

The completion boxes for the remaining 8 goals are intentionally unchecked.
Goals 01 through 04 are delivered and have their own four-step evidence
records; the remaining goal entries are still planning documents and do not
claim implementation or new application test results.
