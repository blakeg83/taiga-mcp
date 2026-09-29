# Taiga command inventory

Reviewed September 29, 2026. This inventory includes the 33 commands already
implemented by the repository and the larger command set that remains planned;
it does not imply that planned commands are deployed.

The [first-batch summary](goals/first-batch/README.md) records all 15 delivered functions within their selected scope. The [second-batch plan index](goals/second-batch/README.md) defines the next 12 functions and their implementation checklists. Second-batch plans do not imply those functions are implemented.

## Scope and notation

- **Tickets** means user stories and tasks here. Taiga exposes issues, epics, user stories, and tasks as separate resources; command names preserve those distinctions.
- **Existing** means exposed by this repository today. **Extend** means an existing command needs broader behavior. **New** means a proposed command. Parameters below describe the intended interface, not exact current signatures. The exact current signatures and JSON shapes are in the [implemented tool reference](taiga_tools_reference.md).
- **Delivered subset** identifies implemented behavior with remaining inventory scope. **Planned — batch 2** links to an unimplemented second-batch goal; those functions are not part of today's 33-tool count.
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
| `get_current_user` | Delivered subset — [batch 2, goal 01](goals/second-batch/01-get-current-user.md) | No arguments; return the authenticated user's positive ID plus optional username, full name, and active state for assignment, ownership, and personal filters. |
| `list_project_members` | Delivered subset — [batch 2, goal 02](goals/second-batch/02-list-project-members.md) | `projectId, page?`; return one page of membership records with distinct `membership_id` and optional `user_id`, role/name/activity/admin/owner fields. Pending and inactive records remain visible; email and invitation fields are excluded. |
| `list_project_roles` | New | `projectId`; return role IDs and estimation participation for role-based story points. |
| `search_work_items` | New; composite | `projectId, query, kinds?, page?`; search selected resource lists using supported text filters and combine results with their kinds and references. Track each resource's pagination separately. |
| `resolve_work_item` | Delivered subset — [batch 2, goal 03](goals/second-batch/03-resolve-work-item.md) | `projectId, kind, ref`; use the known resource's `by_ref` lookup to return its internal ID plus available subject/version. The caller uses that ID with the matching detail tool before editing. |
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
| `get_epic` | New — delivered subset | `epicId`; retrieve description, status, assignment, color, tags, version, and server-supplied summary fields. Related-story listing and computed progress remain planned. |
| `create_epic` | New — delivered subset | `projectId, subject, description?, status?, assigned_to?, color?, tags?`; create one epic with optional fields sent only when supplied. Requirement flags and bulk creation remain planned; story linking is provided separately by `link_user_story_to_epic`. |
| `update_epic` | Delivered subset | `epicId, version, subject?, description?, status?, assigned_to?, color?, tags?, comment?, clearFields?`; versioned content/status/assignment/color/tag/comment edits with explicit assignee clearing. Epic order, requirement flags, blocking, dates, custom fields, project moves, and linked-story changes remain planned. |
| `delete_epic` | New | `epicId`; delete the epic grouping. Do not issue separate deletion requests for its related stories. |
| `bulk_create_epics` | New | `projectId, subjects[], statusId?`; create several epics through the bulk endpoint and return their identities. |
| `list_epic_user_stories` | Delivered subset — [batch 2, goal 09](goals/second-batch/09-list-epic-user-stories.md) | `epicId, page?`; list one page of linked story IDs and relationship order. Use `get_user_story` for selected details; project context, full story expansion, progress aggregation, and all-page fetching remain out of scope. |
| `get_epic_user_story_link` | New | `epicId, userStoryId`; retrieve one epic/story relationship and its ordering data. |
| `link_user_story_to_epic` | New — delivered subset | `epicId, userStoryId, order?`; associate an existing story with the epic, preserve Taiga's ability to relate stories from accessible projects, and make repeated calls idempotent without changing existing order. |
| `update_epic_user_story_link` | New | `epicId, userStoryId, order`; change the story's order within the epic without changing its backlog position. |
| `unlink_user_story_from_epic` | Delivered subset — [batch 2, goal 10](goals/second-batch/10-unlink-user-story-from-epic.md) | `epicId, userStoryId`; remove only the selected relationship after confirmed HTTP 204 while retaining the story, epic, and other links. A 404 is an error and ambiguous DELETE failures are not retried. |
| `bulk_create_epic_user_stories` | New | `epicId, projectId, subjects[]`; create new stories and associate them with the epic using the related-stories bulk endpoint. This endpoint is not a bulk linker for existing IDs. |
| `get_epic_progress` | New; composite | `epicId`; aggregate related stories by status and available estimates, showing completed/total counts and cross-project breakdowns. Label calculated totals and incomplete pagination. |
| `list_epic_statuses` | Delivered subset | `projectId, page?`; list one page of all project epic workflow statuses, including open and closed choices, with IDs, localized names, slug, order, color, and closure flags. Story-only archive and WIP fields are not exposed. |

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
| `list_user_story_statuses` | Delivered subset | `projectId, page?`; return one page of all project story statuses, including closed/archived choices, with IDs, localized names, order, color, flags, WIP, and pagination metadata where supplied. |
| `list_points` | New | `projectId`; list configured estimation options and their numeric values. |

API/source basis: [story endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/user-stories/endpoints.adoc), [story actions](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/userstories/api.py), [story validators](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/userstories/validators.py), [story fields](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/userstories/models.py), and the pinned [status viewset](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/api.py#L543-L556) and [status serializer](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/serializers.py#L44-L53).

## Tasks: implementation tickets

| Command | Coverage | Basic inputs and behavior |
| --- | --- | --- |
| `list_tasks` | New — delivered subset | `projectId, page, userStoryId?, milestoneId?, statusIds?, assignedTo?, tags?, query?, includeClosed?`; list one page with supported parent story, sprint, status, assignee, tag, and text filters, including closed tasks when requested. Date, sort, and arbitrary export filters remain planned; task detail is available through get_task. |
| `get_task` | Delivered subset | `taskId`; retrieve description, status, assignee, parent story, sprint, tags, due date, blocking information, and version. Comments, attachments, and parent details remain deferred. |
| `create_task` | Delivered subset | `projectId, subject, userStoryId?, milestoneId?, description?, status?, assigned_to?, tags?`; create a story task or standalone task, validate an optional parent, and return authoritative detail. Story-linked tasks inherit their story's sprint. Bulk fields, due dates, blockers, iocaine, and cross-project creation remain planned. |
| `update_task` | Delivered subset | `taskId, version, subject?, description?, status?, assigned_to?, tags?, isBlocked?, blockedNote?, comment?, clearFields?`; versioned task content/status/assignment/tag/blocking/comment edits with explicit clearing semantics. Due dates, reparenting, sprint moves, iocaine, and project changes remain planned. |
| `delete_task` | New | `taskId`; delete the task and report the result. |
| `bulk_create_tasks` | New | `projectId, milestoneId, subjects[], userStoryId?, statusId?`; use the native bulk endpoint, which currently requires a sprint. Tasks outside a sprint need individual creation if the deployed endpoint retains that restriction. |
| `set_task_user_story` | New | `taskId, version, userStoryId or null`; attach, reparent, or detach a task, then return its resulting parent and sprint. |
| `reorder_user_story_tasks` | New | `projectId, userStoryId, tasksWithOrder[]`; set task order within a story using `bulk_update_us_order`. |
| `reorder_taskboard` | New | `projectId, tasksWithOrder[], statusId?, userStoryId?, milestoneId?`; set board order with `bulk_update_taskboard_order`; scope to the relevant board context. |
| `promote_task_to_user_story` | New | `projectId, taskId`; invoke native promotion and return the created story. Current upstream promotion deletes the source task after conversion. |
| `list_task_statuses` | Delivered subset | `projectId, page?`; list one page of task status IDs, project/resource-specific names, slugs, order, color, and closure flags. Story-only archive/WIP fields are not exposed. |

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
| `list_work_item_comments` | Delivered subset — [batch 2, goal 11](goals/second-batch/11-list-work-item-comments.md) | `kind, id, page?`; return one upstream page of visible nonblank comments from history with opaque entry IDs, safe authors, timestamps, edit information, and upstream pagination metadata. Hidden/deleted comments, revisions, and later-page filling remain out of scope. Issue comments remain bundled into `get_issue` separately. |
| `add_work_item_comment` | Delivered subset | `kind, id, version, text`; submit a comment through the item's update API, preserving supported Markdown and mentions. The closed kind set is `issue`, `user_story`, `task`, or `epic`; the receipt returns the authoritative version and `comment_submitted=true`, not a fabricated history-entry ID. Comment revisions/editing/deletion, attachments, and watcher management remain planned. |
| `edit_work_item_comment` | New | `kind, id, historyEntryId, text`; edit the comment through the history API using its permissions and revision behavior. |
| `delete_work_item_comment` | New | `kind, id, historyEntryId`; hide/delete a comment through Taiga's history action. |
| `restore_work_item_comment` | New | `kind, id, historyEntryId`; restore a deleted comment through the undelete action when permitted. |
| `get_work_item_comment_versions` | New | `kind, id, historyEntryId`; return a comment's prior revisions. |
| `get_work_item_history` | Planned — [batch 2, goal 12](goals/second-batch/12-get-work-item-history.md) | `kind, id, page?`; return field changes and comments with authors/timestamps, preserving audit information beyond comment text. |
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
| `list_sprints` | Delivered subset — [batch 2, goal 07](goals/second-batch/07-list-sprints.md) | `projectId, page?, closed?`; list one page of Taiga milestones with `id`, project, name, slug, ISO date-only start/finish values, and closure state. Use the returned `id` as `milestoneId`; nested stories, point aggregates, statistics, and date filters remain out of scope. |
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

- The current 34 tool names are implemented across [IssueTools.cs](../Tools/IssueTools.cs), [UserStoryTools.cs](../Tools/UserStoryTools.cs), [TaskTools.cs](../Tools/TaskTools.cs), [EpicTools.cs](../Tools/EpicTools.cs), [SprintTools.cs](../Tools/SprintTools.cs), [WorkItemCommentTools.cs](../Tools/WorkItemCommentTools.cs), [WorkItemHistoryTools.cs](../Tools/WorkItemHistoryTools.cs), [WorkItemResolverTools.cs](../Tools/WorkItemResolverTools.cs), [ProjectTools.cs](../Tools/ProjectTools.cs), and [UserTools.cs](../Tools/UserTools.cs).
- [IssueApi.cs](../Api/IssueApi.cs) defaults to open issues; explicit statuses or includeClosed can retrieve closed work, and includePageInfo opts into page metadata. Issue detail still exposes a bounded field subset. [UserStoryApi.cs](../Api/UserStoryApi.cs) and [UserStoryTools.cs](../Tools/UserStoryTools.cs) deliver core list/detail/create/update behavior; ordering, estimates, swimlane, and epic filters remain planned.
- [IssueUpdateDto.cs](../Models/IssueUpdateDto.cs) uses a presence-aware PATCH representation: ordinary nulls are omitted, while the delivered issue update contract can explicitly clear `assigned_to`; create serialization still omits nulls.
- Task list/detail/create/update, epic list/detail/create/update/link/list/unlink, epic status discovery, shared comment submission, and visible shared comment reads are implemented. Full history, comment revision/edit/delete/restore, attachments, custom fields, and broader planning/admin operations remain later inventory work.
- Structured arbitrary dependencies, time logging, and nested epics are not assumed to be native Taiga capabilities. External references or custom fields should not be presented as equivalent native relationships.
