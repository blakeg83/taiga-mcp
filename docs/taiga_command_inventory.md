# Taiga command inventory

Reviewed September 28, 2026. This inventory includes the 15 commands already
implemented by the repository and the larger command set that remains planned;
it does not imply that planned commands are deployed.

Detailed agent goal documents for the first 15-function implementation batch are in [the first-batch plan index](goals/first-batch/README.md). The `list_issues` expansion and `list_tasks` are delivered subsets; the remaining planned entries remain unimplemented until their checklists are completed.

## Scope and notation

- **Tickets** means user stories and tasks here. Taiga exposes issues, epics, user stories, and tasks as separate resources; command names preserve those distinctions.
- **Existing** means exposed by this repository today. **Extend** means an existing command needs broader behavior. **New** means a proposed command. Parameters below describe the intended interface, not exact current signatures. The exact current signatures and JSON shapes are in the [implemented tool reference](taiga_tools_reference.md).
- Shared commands take `kind = issue | epic | user_story | task` and an internal numeric `id`. A displayed `#ref` must first be resolved within its project.
- List commands should expose pagination, supported filters, ordering, and an explicit choice to include completed work. Return JSON with IDs, references, useful labels, versions where available, and pagination information.
- Updates should distinguish omitted fields from explicit clearing, use Taiga's version checks where required, and report conflicts. Closing and reopening mean selecting a project status; status names must not be hardcoded.
- New commands below are proposed wrappers over Taiga APIs unless marked **composite**. Source-backed features must be checked against the deployed Taiga version before eventual implementation; this inventory did not test a live instance.

## Project context and discovery

| Command | Coverage | Basic inputs and behavior |
| --- | --- | --- |
| `list_projects` | Existing | `member?, page?`; list accessible projects, using the configured numeric member ID when filtering by a user. |
| `resolve_project` | Existing | `slug`; return the internal project ID. |
| `get_project` | New | `projectId`; return project details, enabled modules, defaults, and available permission information needed to interpret work items. |
| `get_current_user` | New | No arguments; return the authenticated user's ID for assignment, ownership, and personal filters. |
| `list_project_members` | New | `projectId, page?`; return membership, user, and role IDs for assigning work and selecting watchers. |
| `list_project_roles` | New | `projectId`; return role IDs and estimation participation for role-based story points. |
| `search_work_items` | New; composite | `projectId, query, kinds?, page?`; search selected resource lists using supported text filters and combine results with their kinds and references. Track each resource's pagination separately. |
| `resolve_work_item` | New | `projectId, kind, ref`; use the resource's `by_ref` lookup to return its internal ID and details. |
| `get_work_item_filters` | New | `projectId, kind, filters?`; use `filters_data` to return available filter choices and counts where supplied by Taiga. |

API basis: [Taiga REST API: projects, users, memberships, roles, and resource lookups](https://docs.taiga.io/api.html).

## Issues: intake, triage, and resolution

| Command | Coverage | Basic inputs and behavior |
| --- | --- | --- |
| `list_issues` | Extend — delivered subset | `projectId, page, statusIds?, assignedTo?, typeId?, priorityId?, severityId?, tags?, query?, includeClosed?, includePageInfo?`; supports status, type, severity, priority, assignee, tags, and text filters plus an opt-in page envelope. Date, owner, sprint, sort, and all-page export behavior remain planned. |
| `get_issue` | Extend | `issueId, includeComments?`; retain existing issue/comment retrieval and expose full useful fields, including metadata IDs, tags, sprint, due date, blocking information, and version. |
| `create_issue` | Extend | `projectId, subject, fields?`; retain description, classification, assignment, and tags; add supported sprint, due-date, blocking, and watcher fields. |
| `update_issue` | Extend — delivered subset | `issueId, version, subject?, description?, status?, type?, priority?, severity?, assigned_to?, tags?, comment?, clearFields?`; supports versioned partial edits, explicit assignee clearing, and description/tag clearing. Due dates, sprints, blocking fields, and project moves remain planned. |
| `delete_issue` | New | `issueId`; delete the issue and report the result. |
| `bulk_create_issues` | New | `projectId, subjects[], milestoneId?`; submit Taiga's bulk creation format and return created IDs/references. Rich per-item fields would require separate creates/updates. |
| `promote_issue_to_user_story` | New | `projectId, issueId`; invoke native promotion and return the new story and its source relationship. The source issue remains; any desired closing status is a separate change. |
| `move_issue_to_project` | New | `issueId, version, targetProjectId`; use Taiga's project-change behavior and return resulting classification, assignment, and sprint values so remapping is visible. |
| `list_issue_statuses` | Existing | `projectId`; list available issue statuses and whether each closes an issue. |
| `list_issue_types` | Existing | `projectId`; list classification IDs and names, such as bug or enhancement when configured. |
| `list_issue_priorities` | Existing | `projectId`; list priority IDs and names for triage. |
| `list_issue_severities` | Existing | `projectId`; list severity IDs and names for impact assessment. |

API/source basis: [issue endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/issues/endpoints.adoc), [issue actions and filters](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/issues/api.py), and [native promotion](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/mixins/promote.py). Bulk creation and promotion are supported by current upstream source even where the published API narrative is incomplete.

## Epics: grouping and progress

| Command | Coverage | Basic inputs and behavior |
| --- | --- | --- |
| `list_epics` | New — delivered subset | `projectId, page, statusIds?, assignedTo?, tags?, query?, includeClosed?`; list one page with verified status, assignee, tag, and text filters, including closed epics when requested. Related-story progress aggregation remains planned. |
| `get_epic` | New | `epicId`; retrieve description, status, assignment, color, tags, version, and available progress information. |
| `create_epic` | New | `projectId, subject, fields?`; create an epic with description, status, assignee, color, tags, and requirement flags. |
| `update_epic` | New | `epicId, version, fields`; edit epic fields, including status, assignment, color, and ordering. |
| `delete_epic` | New | `epicId`; delete the epic grouping. Do not issue separate deletion requests for its related stories. |
| `bulk_create_epics` | New | `projectId, subjects[], statusId?`; create several epics through the bulk endpoint and return their identities. |
| `list_epic_user_stories` | New | `epicId, page?`; list linked stories and their relationship order, including project context. |
| `get_epic_user_story_link` | New | `epicId, userStoryId`; retrieve one epic/story relationship and its ordering data. |
| `link_user_story_to_epic` | New | `epicId, userStoryId, order?`; associate an existing story with the epic. Preserve Taiga's ability to relate stories from accessible projects. |
| `update_epic_user_story_link` | New | `epicId, userStoryId, order`; change the story's order within the epic without changing its backlog position. |
| `unlink_user_story_from_epic` | New | `epicId, userStoryId`; remove the relationship while retaining the story. |
| `bulk_create_epic_user_stories` | New | `epicId, projectId, subjects[]`; create new stories and associate them with the epic using the related-stories bulk endpoint. This endpoint is not a bulk linker for existing IDs. |
| `get_epic_progress` | New; composite | `epicId`; aggregate related stories by status and available estimates, showing completed/total counts and cross-project breakdowns. Label calculated totals and incomplete pagination. |
| `list_epic_statuses` | New | `projectId`; list epic workflow status IDs, names, order, and closure flags. |

API/source basis: [epic endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/epics/endpoints.adoc), [epic actions](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/epics/api.py), and [epic fields and relationships](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/epics/models.py).

## User stories: backlog and delivery tickets

| Command | Coverage | Basic inputs and behavior |
| --- | --- | --- |
| `list_user_stories` | Extend — delivered subset | `projectId, page?, statusIds?, assignedTo?, milestoneId?, backlogOnly?, tags?, query?, includeClosed?, includeArchived?, includePageInfo?`; backlog/sprint, status, assignment, tags, and text filters are delivered. Ordering, swimlane, and epic filters remain planned. |
| `get_user_story` | Delivered subset | `userStoryId`; retrieve core detail fields, authoritative version, assignment, tags, sprint, and available epic/source relationships. Comments, tasks, estimates, and swimlane data remain deferred. |
| `create_user_story` | Delivered subset | `projectId, subject, description?, status?, assigned_to?, tags?, milestoneId?`; creates one backlog or sprint story and returns authoritative detail. Acceptance criteria belong in `description`; estimates, multiple assignees, swimlanes, epic links, bulk creation, and custom fields remain planned. |
| `update_user_story` | Delivered subset | `userStoryId, version, subject?, description?, status?, assigned_to?, tags?, milestoneId?, comment?, clearFields?`; updates content, status, primary assignment, tags, sprint placement/removal, and comments. Blocking, due dates, swimlanes, requirement flags, estimates, multiple assignees, and project moves remain planned. |
| `delete_user_story` | New | `userStoryId`; delete the story and report Taiga's result, including any documented effects on child tasks for the deployed version. |
| `bulk_create_user_stories` | New | `projectId, subjects[], statusId?, swimlaneId?`; create stories from a batch of titles using Taiga's bulk format. |
| `set_user_story_estimates` | New | `userStoryId, version, rolePoints`; map role IDs to configured point IDs and return updated estimates. Values are point IDs, not arbitrary numeric estimates. |
| `set_user_story_assignees` | New | `userStoryId, version, assignedUsers[], primaryAssignee?`; manage multiple story assignees and the primary assignment where supported. |
| `reorder_backlog` | New | `projectId, userStoryIds[], beforeId? or afterId?`; use native backlog ordering within the selected backlog/sprint context. |
| `reorder_kanban` | New | `projectId, statusId, userStoryIds[], swimlaneId?, beforeId? or afterId?`; use native Kanban ordering and its target column/lane semantics. Return resulting positions and statuses. |
| `reorder_sprint_user_stories` | New; version-dependent | `projectId, milestoneId, orderedStoryIds[]`; change sprint order. The published documentation lists a bulk sprint-order endpoint; if absent in the deployment, use versioned `sprint_order` updates. |
| `list_user_story_statuses` | New | `projectId`; list workflow columns/statuses with closure, archival, ordering, and WIP information where available. |
| `list_points` | New | `projectId`; list configured estimation options and their numeric values. |

API/source basis: [story endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/user-stories/endpoints.adoc), [story actions](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/userstories/api.py), [story validators](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/userstories/validators.py), and [story fields](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/userstories/models.py).

## Tasks: implementation tickets

| Command | Coverage | Basic inputs and behavior |
| --- | --- | --- |
| `list_tasks` | New — delivered subset | `projectId, page, userStoryId?, milestoneId?, statusIds?, assignedTo?, tags?, query?, includeClosed?`; list one page with supported parent story, sprint, status, assignee, tag, and text filters, including closed tasks when requested. Detail, date, sort, and arbitrary export filters remain planned. |
| `get_task` | Delivered subset | `taskId`; retrieve description, status, assignee, parent story, sprint, tags, due date, blocking information, and version. Comments, attachments, and parent details remain deferred. |
| `create_task` | Delivered subset | `projectId, subject, userStoryId?, milestoneId?, description?, status?, assigned_to?, tags?`; create a story task or standalone task, validate an optional parent, and return authoritative detail. Story-linked tasks inherit their story's sprint. Bulk fields, due dates, blockers, iocaine, and cross-project creation remain planned. |
| `update_task` | Delivered subset | `taskId, version, subject?, description?, status?, assigned_to?, tags?, isBlocked?, blockedNote?, comment?, clearFields?`; versioned task content/status/assignment/tag/blocking/comment edits with explicit clearing semantics. Due dates, reparenting, sprint moves, iocaine, and project changes remain planned. |
| `delete_task` | New | `taskId`; delete the task and report the result. |
| `bulk_create_tasks` | New | `projectId, milestoneId, subjects[], userStoryId?, statusId?`; use the native bulk endpoint, which currently requires a sprint. Tasks outside a sprint need individual creation if the deployed endpoint retains that restriction. |
| `set_task_user_story` | New | `taskId, version, userStoryId or null`; attach, reparent, or detach a task, then return its resulting parent and sprint. |
| `reorder_user_story_tasks` | New | `projectId, userStoryId, tasksWithOrder[]`; set task order within a story using `bulk_update_us_order`. |
| `reorder_taskboard` | New | `projectId, tasksWithOrder[], statusId?, userStoryId?, milestoneId?`; set board order with `bulk_update_taskboard_order`; scope to the relevant board context. |
| `promote_task_to_user_story` | New | `projectId, taskId`; invoke native promotion and return the created story. Current upstream promotion deletes the source task after conversion. |
| `list_task_statuses` | New | `projectId`; list task status IDs, names, order, and closure flags. |

API/source basis: [task endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/tasks/endpoints.adoc), [task actions](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/tasks/api.py), [task validators](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/tasks/validators.py), and [promotion behavior](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/mixins/promote.py).

## Shared daily work commands

These are proposed common commands across the four resource kinds. Fields that a kind does not support should return a clear validation error rather than being silently ignored.

| Command | Coverage | Basic inputs and behavior |
| --- | --- | --- |
| `set_work_item_status` | New | `kind, id, version, statusId, comment?`; transition to a valid project status. This covers closing and reopening. |
| `assign_work_item` | New | `kind, id, version, userId or null`; assign or unassign the primary responsible person. Use the story-specific command for multiple assignees. |
| `set_work_item_blocked` | New | `kind, id, version, blocked, reason?`; set/clear blocking information for supported kinds. A blocked flag is not a structured dependency relationship. |
| `set_work_item_due_date` | New | `kind, id, version, date or null, reason?`; set or clear due-date fields for kinds that support them. |
| `update_work_item_tags` | New; composite | `kind, id, version, add?, remove?`; read current tags and patch the merged set, retaining tag colors and unrelated tags. |
| `list_work_item_comments` | New | `kind, id, page?`; return visible comments from history with history-entry IDs, authors, timestamps, and edit information. Issue comments are currently bundled into `get_issue`. |
| `add_work_item_comment` | New | `kind, id, version, text`; submit a comment through the item's update API, preserving supported Markdown and mentions. Issue comments currently use `update_issue`. |
| `edit_work_item_comment` | New | `kind, id, historyEntryId, text`; edit the comment through the history API using its permissions and revision behavior. |
| `delete_work_item_comment` | New | `kind, id, historyEntryId`; hide/delete a comment through Taiga's history action. |
| `restore_work_item_comment` | New | `kind, id, historyEntryId`; restore a deleted comment through the undelete action when permitted. |
| `get_work_item_comment_versions` | New | `kind, id, historyEntryId`; return a comment's prior revisions. |
| `get_work_item_history` | New | `kind, id, page?`; return field changes and comments with authors/timestamps, preserving audit information beyond comment text. |
| `watch_work_item` | New | `kind, id`; subscribe the current user to the item. |
| `unwatch_work_item` | New | `kind, id`; unsubscribe the current user. |
| `list_work_item_watchers` | New | `kind, id, page?`; return subscribers. |
| `set_work_item_watchers` | New | `kind, id, version, userIds[]`; update the editable watcher list where permitted; unlike watch/unwatch, this can affect other users. |
| `vote_work_item` | New | `kind, id`; add the current user's vote/star through `upvote`. |
| `remove_work_item_vote` | New | `kind, id`; remove the current user's vote through `downvote`; this is not a negative vote. |
| `list_work_item_voters` | New | `kind, id, page?`; return voters and available totals. |

API/source basis: the four resource endpoint inventories above, [history actions](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/history/api.py), and resource validators. Epic history should be checked against the deployed routes because older published history documentation lists fewer resource kinds.

## Attachments and custom field values

| Command | Coverage | Basic inputs and behavior |
| --- | --- | --- |
| `list_work_item_attachments` | New | `kind, id, projectId, page?`; list file IDs, names, descriptions, ordering, and download locations. |
| `get_work_item_attachment` | New | `kind, attachmentId`; retrieve one attachment's metadata and available URL. |
| `upload_work_item_attachment` | New | `kind, id, projectId, file, description?`; upload multipart file data and associate it with the item. |
| `download_work_item_attachment` | New; composite | `kind, attachmentId, destination`; retrieve metadata and download the file to an explicit destination using required authentication. |
| `update_work_item_attachment` | New | `kind, attachmentId, fields`; edit supported description, order, or deprecation metadata. |
| `delete_work_item_attachment` | New | `kind, attachmentId`; delete the attachment and return its identity. |
| `list_custom_field_definitions` | New | `projectId, kind`; list custom attribute IDs, names, types, choices, and ordering. |
| `get_work_item_custom_fields` | New | `kind, id`; retrieve attribute values and their separate version where provided. |
| `update_work_item_custom_fields` | New | `kind, id, version, valuesByAttributeId`; validate against definitions and patch values, supporting explicit clearing. |

API basis: the resource attachment inventories above and [custom attribute value endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/epic-custom-attributes-values/endpoints.adoc). Each kind has its own attribute definitions and value resource.

## Sprints and Kanban context

| Command | Coverage | Basic inputs and behavior |
| --- | --- | --- |
| `list_sprints` | New | `projectId, filters?, page?`; list Taiga milestones with dates and closure state. |
| `get_sprint` | New | `milestoneId`; return sprint details and available work-item summary information. |
| `create_sprint` | New | `projectId, name, startDate, endDate`; create a milestone for planned work. |
| `update_sprint` | New | `milestoneId, fields`; edit name, dates, and supported closure fields. |
| `delete_sprint` | New | `milestoneId`; delete a milestone and return the result; account for deployed Taiga behavior for contained work. |
| `set_work_item_sprint` | New | `kind, id, version, milestoneId or null`; schedule an issue, story, or standalone task, or return it to unscheduled work. Story-linked tasks follow their parent story. |
| `bulk_set_work_item_sprint` | New | `projectId, kind, milestoneId, items[]`; use the kind-specific bulk milestone action for issues, stories, or tasks. Supply order where required; bulk clearing may require individual updates. |
| `get_sprint_stats` | New | `milestoneId`; retrieve native progress and estimation statistics. |
| `list_swimlanes` | New | `projectId`; return Kanban swimlane IDs, names, and ordering for story placement. |
| `get_project_issue_stats` | New | `projectId`; retrieve native issue statistics for triage and resolution reporting. |
| `get_project_work_summary` | New; composite | `projectId, filters?`; aggregate issues, epics, stories, and tasks by status, assignment, blocking, and due date where available. Report item counts separately to avoid double-counting story estimates and tasks. |

API/source basis: [milestone endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/milestones/endpoints.adoc), [project statistics endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/projects/endpoints.adoc), and the issue, story, and task action sources linked above. Swimlane support is present in [story validators](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/userstories/validators.py); verify the deployment's swimlane routes.

## Workflow and field administration

These complete project-specific configuration for the work items. They require the relevant project administration permissions. Generic metadata commands below supplement the existing issue lookup command names.

| Command | Coverage | Basic inputs and behavior |
| --- | --- | --- |
| `get_workflow_option` | New | `category, optionId`; retrieve one status, issue type, priority, severity, or point option. Status categories distinguish the four work-item kinds. |
| `create_workflow_option` | New | `projectId, category, fields`; create a status or classification/point option with supported name, color, value, order, and closure/archive/WIP settings. |
| `update_workflow_option` | New | `category, optionId, fields`; edit supported workflow metadata. Changing closure flags can affect many items. |
| `delete_workflow_option` | New | `category, optionId`; delete an option, surfacing Taiga's constraints or reassignment behavior for items using it. |
| `reorder_workflow_options` | New | `projectId, category, optionsWithOrder[]`; use the appropriate bulk order action. |
| `get_custom_field_definition` | New | `kind, attributeId`; retrieve a custom attribute definition. |
| `create_custom_field_definition` | New | `projectId, kind, name, type, fields?`; add a field with supported choices, description, and order. |
| `update_custom_field_definition` | New | `kind, attributeId, fields`; edit the field's supported definition properties. |
| `delete_custom_field_definition` | New | `kind, attributeId`; remove a custom field, including its associated value implications. |
| `reorder_custom_field_definitions` | New | `projectId, kind, attributesWithOrder[]`; change custom field display order. |
| `create_swimlane` | New; verify routes | `projectId, name, order?`; create a Kanban lane for grouping stories. |
| `update_swimlane` | New; verify routes | `swimlaneId, fields`; edit the lane's name/order using deployed API support. |
| `delete_swimlane` | New; verify routes | `swimlaneId`; remove a lane and report the server's handling of stories placed in it. |
| `list_project_tags` | New | `projectId`; return available tags and color data for consistent labeling. |
| `create_project_tag` | New | `projectId, name, color?`; register a reusable project tag. |
| `delete_project_tag` | New | `projectId, name`; remove the project tag using Taiga's tag action and report its effect on existing usages. |
| `rename_project_tag` | New | `projectId, oldName, newName`; invoke project-level tag rename so existing usages are updated consistently. |
| `merge_project_tags` | New | `projectId, sourceTags[], targetTag`; consolidate duplicate tags through the project tag operation. |
| `update_project_tag_color` | New | `projectId, tag, color`; change a tag's project color metadata. |
| `update_project_work_settings` | New | `projectId, fields`; enable relevant modules and change supported defaults for statuses, issue classifications, or points. Return effective settings. |

API basis: [status administration](https://github.com/taigaio/taiga-doc/blob/main/api/epic-statuses/endpoints.adoc), [epic fields](https://github.com/taigaio/taiga-doc/blob/main/api/epic-custom-attributes/endpoints.adoc), [story fields](https://github.com/taigaio/taiga-doc/blob/main/api/user-story-custom-attributes/endpoints.adoc), [task fields](https://github.com/taigaio/taiga-doc/blob/main/api/task-custom-attributes/endpoints.adoc), [issue fields](https://github.com/taigaio/taiga-doc/blob/main/api/issue-custom-attributes/endpoints.adoc), and [project/tag endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/projects/endpoints.adoc). Each category maps to its own Taiga endpoint; unsupported properties must not be forwarded indiscriminately.

## Optional convenience commands

| Command | Coverage | Basic inputs and behavior |
| --- | --- | --- |
| `list_my_work` | New; composite | `projectIds?, kinds?, includeClosed?, page?`; resolve the current user and combine assigned work across accessible projects with explicit pagination. |
| `bulk_update_work_items` | New; composite | `items[{kind, id, version, changes}]`; apply individual updates and report success/conflict/failure per item. Do not promise a cross-item transaction. |
| `duplicate_work_item` | New; composite | `kind, id, targetProjectId?, overrides?`; create a copy from supported fields. Explicitly select whether tasks, attachments, or epic relationships are copied; history and votes are not ordinary writable fields. |
| `export_work_items` | New; composite | `projectId, kinds, filters?, format`; read all requested pages and export JSON or CSV, labeling partial results if any page fails. |

## Repository coverage notes

- The current 13 tool names were inventoried from [IssueTools.cs](../Tools/IssueTools.cs), [UserStoryTools.cs](../Tools/UserStoryTools.cs), and [ProjectTools.cs](../Tools/ProjectTools.cs).
- [IssueApi.cs](../Api/IssueApi.cs) currently filters issue lists to open work and reduces details to a limited DTO. [UserStoryApi.cs](../Api/UserStoryApi.cs) and [UserStoryTools.cs](../Tools/UserStoryTools.cs) now deliver the goal 03 story filter subset, optional page envelope, and goal 04 core detail read; ordering, estimates, swimlane, and epic filters remain planned.
- [IssueUpdateDto.cs](../Models/IssueUpdateDto.cs) uses a presence-aware PATCH representation: ordinary nulls are omitted, while the delivered issue update contract can explicitly clear `assigned_to`; create serialization still omits nulls.
- Epic and task command groups, shared collaboration commands, attachments, custom fields, and planning/admin commands are new coverage. `EpicApi` and `EpicTools` now deliver the `list_epics` subset; later epic operations remain planned. Shared wrappers can reuse underlying resource operations during a future implementation.
- Structured arbitrary dependencies, time logging, and nested epics are not assumed to be native Taiga capabilities. External references or custom fields should not be presented as equivalent native relationships.
