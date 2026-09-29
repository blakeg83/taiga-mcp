# Completed first implementation batch

Status: all 15 selected functions are implemented within their defined scope.
Reconciled against the current checkout on 2026-09-28.

The batch expanded three existing tools and added twelve, bringing the server
from 11 to 23 public tools. This records delivered functionality; it does not
assert that every broader entry in the [command inventory](../../taiga_command_inventory.md)
is complete.

## Delivered functions

| Original goal | Function | Delivered behavior | Source | Test coverage source |
| --- | --- | --- | --- | --- |
| 01 | `list_issues` | Filters, closed-work selection, classification IDs, optional page envelope | [IssueTools](../../../Tools/IssueTools.cs) | [IssueListTests](../../../tests/TaigaMCP.Tests/IssueListTests.cs) |
| 02 | `update_issue` | Versioned edits, optional subject, explicit unassignment | [IssueTools](../../../Tools/IssueTools.cs) | [IssueUpdateTests](../../../tests/TaigaMCP.Tests/IssueUpdateTests.cs) |
| 03 | `list_user_stories` | Backlog/sprint and status filters, optional page envelope | [UserStoryTools](../../../Tools/UserStoryTools.cs) | [UserStoryListTests](../../../tests/TaigaMCP.Tests/UserStoryListTests.cs) |
| 04 | `get_user_story` | Core detail and authoritative version | [UserStoryTools](../../../Tools/UserStoryTools.cs) | [UserStoryDetailTests](../../../tests/TaigaMCP.Tests/UserStoryDetailTests.cs) |
| 05 | `create_user_story` | Backlog/sprint creation with assignment and tags | [UserStoryTools](../../../Tools/UserStoryTools.cs) | [UserStoryCreateTests](../../../tests/TaigaMCP.Tests/UserStoryCreateTests.cs) |
| 06 | `update_user_story` | Content, status, primary assignment, sprint placement/clearing, comments | [UserStoryTools](../../../Tools/UserStoryTools.cs) | [UserStoryUpdateTests](../../../tests/TaigaMCP.Tests/UserStoryUpdateTests.cs) |
| 07 | `list_tasks` | Project/story/sprint filters and page envelope | [TaskTools](../../../Tools/TaskTools.cs) | [TaskListTests](../../../tests/TaigaMCP.Tests/TaskListTests.cs) |
| 08 | `get_task` | Core detail, parent/sprint, blocking/due-date information, version | [TaskTools](../../../Tools/TaskTools.cs) | [TaskDetailTests](../../../tests/TaigaMCP.Tests/TaskDetailTests.cs) |
| 09 | `create_task` | Standalone or story-linked creation with sprint inheritance | [TaskTools](../../../Tools/TaskTools.cs) | [TaskCreateTests](../../../tests/TaigaMCP.Tests/TaskCreateTests.cs) |
| 10 | `update_task` | Content, status, assignment, tags, blocking, comments | [TaskTools](../../../Tools/TaskTools.cs) | [TaskUpdateTests](../../../tests/TaigaMCP.Tests/TaskUpdateTests.cs) |
| 11 | `list_epics` | Project/status/assignee/tag/text filters and page envelope | [EpicTools](../../../Tools/EpicTools.cs) | [EpicListTests](../../../tests/TaigaMCP.Tests/EpicListTests.cs) |
| 12 | `get_epic` | Core detail, version, available server summaries | [EpicTools](../../../Tools/EpicTools.cs) | [EpicDetailTests](../../../tests/TaigaMCP.Tests/EpicDetailTests.cs) |
| 13 | `create_epic` | One epic with optional status, assignee, color, tags | [EpicTools](../../../Tools/EpicTools.cs) | [EpicCreateTests](../../../tests/TaigaMCP.Tests/EpicCreateTests.cs) |
| 14 | `link_user_story_to_epic` | Existing-story linking with repeat-call behavior | [EpicTools](../../../Tools/EpicTools.cs) | [EpicStoryLinkTests](../../../tests/TaigaMCP.Tests/EpicStoryLinkTests.cs) |
| 15 | `add_work_item_comment` | Versioned comment submission to all four kinds | [WorkItemCommentTools](../../../Tools/WorkItemCommentTools.cs) | [WorkItemCommentTests](../../../tests/TaigaMCP.Tests/WorkItemCommentTests.cs) |

## Infrastructure and verification records

The foundation and cleanup established transport ownership, gated authentication,
safe errors, cancellation, metadata caching, fake HTTP tests, and real MCP
protocol sessions. The [development guide](../../development.md) retains the
historical cleanup record. [McpIntegrationTests](../../../tests/TaigaMCP.Tests/McpIntegrationTests.cs)
and the function-specific tests above describe the current checks.

The original numbered goal/checklist files and cleanup goal files are no longer
present in this checkout. This summary links to existing evidence rather than
recreating completion checklists or claiming historical commit hashes.
Use Git history to inspect the original plans and implementation commits.
No fresh build, test result, or live deployment verification is claimed by this
documentation-only reconciliation.

## Remaining scope and next work

The [tool reference](../../taiga_tools_reference.md) is authoritative for callable
signatures. The retained [first-batch contracts](contracts.md) and
[execution instructions](execution-instructions.md) explain historical design
intent; current source/reference and the active goal take precedence where
implementation decisions changed.

Proceed to the [second-batch plans](../second-batch/README.md) for the next 12
functions: identity/member/status/sprint lookup, reference resolution, epic
editing and relationship reads/removal, and shared comments/history reads.
Attachments, estimates, bulk operations, and workflow administration remain
outside both selected batches.
