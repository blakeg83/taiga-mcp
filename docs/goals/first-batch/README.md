# First implementation batch: agent goal documents

Status: feature goals 01-15 remain planned. Goal 00, its review fixes and the development foundation cleanup are complete; their test/transport/auth/cache infrastructure is available.

## Selected batch

The 15 functions below prioritize the daily cycle of finding work, reading its current version, creating tickets, updating progress, grouping stories under epics, and leaving comments. This ranking is a product judgment based on typical workflows and repository gaps; no usage telemetry was available. Existing project lookup, issue creation, issue detail, and issue metadata tools remain useful prerequisites.

| Order | Goal | Reason for inclusion | Prerequisites |
| --- | --- | --- | --- |
| 00 | [Shared foundation](00-foundation.md) | Consistent tests, contracts, and MCP verification | None |
| 01 | [list_issues](01-list-issues.md) | Daily triage and finding completed issues | 00 |
| 02 | [update_issue](02-update-issue.md) | Assignment, status, classification, and clearing values | 00, 01 |
| 03 | [list_user_stories](03-list-user-stories.md) | Find backlog and sprint work without hidden closed stories | 00, 01 |
| 04 | [get_user_story](04-get-user-story.md) | Read full context and version before editing | 03 |
| 05 | [create_user_story](05-create-user-story.md) | Capture planned delivery work | 04 |
| 06 | [update_user_story](06-update-user-story.md) | Maintain story progress and ownership | 02, 04, 05 |
| 07 | [list_tasks](07-list-tasks.md) | Find implementation work and establish TaskApi | 00, 03 |
| 08 | [get_task](08-get-task.md) | Read task context and version before editing | 07 |
| 09 | [create_task](09-create-task.md) | Break stories into actionable work | 04, 08 |
| 10 | [update_task](10-update-task.md) | Move tasks through delivery | 02, 08, 09 |
| 11 | [list_epics](11-list-epics.md) | Find large work groups and establish EpicApi | 00, 03 |
| 12 | [get_epic](12-get-epic.md) | Read epic context and identity | 11 |
| 13 | [create_epic](13-create-epic.md) | Capture larger initiatives | 12 |
| 14 | [link_user_story_to_epic](14-link-user-story-to-epic.md) | Group existing delivery tickets without duplication | 04, 12, 13 |
| 15 | [add_work_item_comment](15-add-work-item-comment.md) | Record decisions and progress across all four kinds | 02, 06, 10, 12 |

## How to use these documents

Foundation review follow-up: [Goal 00 review fixes](00-foundation-review-fixes.md) addresses PR #31's protocol-output verification and nullable-response documentation findings. It is complete and retained by the [development cleanup](../development-foundation-cleanup.md). Use the final infrastructure described in [development](../../development.md).

Assign one goal document to a coding agent, along with access to this repository. Tell it to read [the execution instructions](execution-instructions.md), [the shared contracts](contracts.md), and the linked prerequisites before editing. Implement in the order above by default. Documents are task specifications, not instructions to start separate chats or delegate automatically.

Each function has its own objective, bounded scope, target interface, four implementation steps, acceptance scenarios, and definition of done. All completion boxes deliberately start unchecked. The foundation is a prerequisite goal, not a sixteenth public function.

Suggested assignment:

> Execute docs/goals/first-batch/NN-function.md. Follow its linked execution instructions and contracts. Complete and validate one step at a time, update documentation during each step, and commit after each step. Preserve unrelated work and report completion evidence against the definition of done.

## Batch boundary

Keep the batch focused. Defer deletes, bulk operations, epic editing, attachments, custom fields, workflow administration, reference resolution, new metadata lookup tools, estimates, multiple story assignees, and general cross-project moves. Existing IDs can be supplied by users or read from Taiga. Do not claim these 15 goals complete the entire [command inventory](../../taiga_command_inventory.md).

Some inventory entries describe broader eventual behavior. Completing these goals delivers only the fields and behaviors named in each goal. Update inventory notes to state any remaining scope; do not mark a broad entry fully implemented when only this batch's subset exists.

## Batch completion checklist

- [ ] Foundation and all 15 function definitions of done are satisfied.
- [ ] Existing 11 MCP tools remain callable with their established names and compatible inputs/outputs.
- [ ] New tools are discoverable through MCP and examples match emitted schemas.
- [ ] A fake-HTTP workflow covers epic creation, story creation/linking, task creation/update, issue update, and comments.
- [ ] Root solution build and tests pass; documentation examples and links are checked.
- [ ] Every completed step has a commit and evidence; unfinished inventory scope remains explicit.
