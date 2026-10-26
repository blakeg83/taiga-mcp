# Work-item examples

These examples show tool arguments and representative responses after you have
completed the [quickstart](taiga_mcp_quickstart.md). IDs, names, and versions
are illustrative. Discover IDs in your project and read the current version
before editing. Create, update, link, unlink, and comment calls change Taiga
data; use them only for work you intend to perform.

Each section names the relevant tools in its prose. JSON blocks can show
successive calls or a response; they are examples, not a script to paste as a
single request. The [tool reference](taiga_tools_reference.md#current-tool-contracts)
is the complete source for argument names, defaults, and result shapes.

## Identify the current account

Call the no-argument `get_current_user` tool:

```json
{}
```

It returns an identity object such as:

```json
{"id":42,"username":"synthetic-user","full_name":"Synthetic User","is_active":true}
```

Use the returned numeric `id` as `assigned_to` or `assignedTo` in existing
work-item operations. When using the existing `list_projects` member filter,
pass the same ID as a string, for example `{"member":"42"}`. The tool does
not return email, roles, tokens, or other private profile fields.

## List project members before assignment

Read one project-membership page before choosing an assignee:

```json
{"projectId":123,"page":1}
```

The result distinguishes the membership record from the account:

```json
{"items":[{"membership_id":501,"project":123,"user_id":42,"role_id":7,"role_name":"Product Owner","full_name":"Active User","is_user_active":true,"is_admin":true,"is_owner":true}],"page":1,"total":1,"next_page":null,"has_more":false}
```

Use the returned `user_id` as `assigned_to` in a later work-item call. Do not
send `membership_id` as the assignee. Pending invitations can omit `user_id`,
and inactive users remain visible for context; neither is silently treated as
an active assignable account. Email and invitation text are not returned.

## Resolve a work-item reference before editing

Use a numeric project-local `ref` and a known kind to get the internal ID. Do
not include the human-facing `#` and do not pass the ref to a detail or update
tool:

```json
{"projectId":123,"kind":"task","ref":42}
```

The result is an identity receipt such as
`{"kind":"task","id":203,"ref":42,"project":123,"subject":"Implement saved-search endpoint","version":2}`.
Then read the authoritative detail and use its returned version for a later
edit:

```json
{"taskId":203}
{"taskId":203,"version":2,"status":11}
```

The same ref can identify different kinds or occur in another project. The
resolver never guesses the kind, searches other projects, scans lists, or
performs the subsequent read/update automatically.

## Create a user story

Use the required arguments for a minimal backlog story:

```json
{"projectId":123,"subject":"Allow saved searches"}
```

Put acceptance criteria in `description`. To place the story in a sprint and
assign it, provide project-specific internal IDs:

```json
{"projectId":123,"subject":"Allow saved searches","description":"Acceptance: saved searches can be reopened.","status":7,"assigned_to":42,"tags":["search","saved"],"milestoneId":55}
```

Taiga applies project defaults for omitted optional fields. The returned JSON
contains the server-created story detail, including its `id`, `ref`, and
`version`. Status, assignee, and milestone membership are validated by Taiga.

## Create a task

Create a standalone task with project defaults, or select a sprint explicitly:

```json
{"projectId":123,"subject":"Capture deployment checklist"}
{"projectId":123,"subject":"Prepare release notes","milestoneId":55}
```

To break down a story, provide its internal ID. The server reads the parent,
validates the project, and returns the authoritative inherited sprint. Omit
`milestoneId` for inheritance; if supplied, it must match the parent's sprint
and is omitted from the wire request. Ordinary creation uses `POST /tasks`, so
it does not inherit the sprint-only restriction of Taiga's native bulk-create
endpoint:

```json
{"projectId":123,"subject":"Implement saved-search endpoint","userStoryId":102,"description":"Acceptance: preserve the search filters.","status":11,"assigned_to":42,"tags":["search"]}
```

The response is the created task detail with server-generated `id`, `ref`, and
`version`, plus the resulting parent and sprint.

## Read an epic

Use `list_epics` to obtain a project-scoped page. Pass an item's internal `id`
to `get_epic`; the displayed `ref` is not accepted as the detail identifier:

```json
{"projectId":123,"page":1,"includeClosed":false}
{"epicId":301}
```

The detail result preserves the server's description, status, assignment,
color, tags, version, and optional summary fields such as
`user_stories_counts`. It does not enumerate related stories or calculate
progress. Use the returned internal epic ID for later story-linking commands.

## Create an epic

Create one epic with Taiga's project defaults, then use its returned internal
ID for reads or a later story link:

```json
{"projectId":123,"subject":"Saved search experience"}
```

Optional values are project-specific status and assignee IDs. Color is passed
to Taiga for validation, while an omitted color lets Taiga generate its
default:

```json
{"projectId":123,"subject":"Saved search experience","description":"Group saved-search delivery work.","status":7,"assigned_to":42,"color":"#336699","tags":["search","saved"]}
```

This creates only the epic. It does not create stories or change project
settings. To organize an existing story under the new epic, call the separate
link tool:

```json
{"epicId":301,"userStoryId":102,"order":9001}
```

The response is `{"epic_id":301,"user_story_id":102,"order":9001,"created":true}`
when the relationship is new. A repeat call returns the existing order with
`created=false`, even if a different order is requested.

## Create a story and link it to an epic

Use the returned story `id` from `create_user_story`, not its displayed `ref`,
in the link call. The workflow is:

```json
{"projectId":123,"subject":"Allow saved searches"}
{"epicId":301,"userStoryId":102}
```

The link operation does not move or update the story. Cross-project links are
left to Taiga's permissions and validation.

## Inspect stories linked to an epic

After linking or when auditing an existing epic, list one relationship page and
use a returned `user_story_id` with `get_user_story` when full story details are
needed:

```json
{"epicId":301,"page":1}
{"items":[{"epic_id":301,"user_story_id":102,"order":9001}],"page":1,"total":1,"next_page":null,"has_more":false}
{"userStoryId":102}
```

The list is a lightweight relationship index. It does not return full story
objects, creation state, calculated epic progress, or project data for each
story; Taiga decides whether accessible cross-project links are valid.

## Discover sprints before scheduling work

Taiga calls sprints **milestones**. List a page, then use a returned `id` as
`milestoneId` when creating a story or standalone task. Omit `closed` (or pass
`null`) to include both open and closed sprints; pass `false` or `true` to select
one state:

```json
{"projectId":123,"page":1}
{"items":[{"id":55,"project":123,"name":"Sprint 2026-09","slug":"sprint-2026-09","estimated_start":"2026-09-01","estimated_finish":"2026-09-14","closed":false}],"page":1,"total":null,"next_page":null,"has_more":null}
{"projectId":123,"page":1,"closed":false}
{"projectId":123,"subject":"Prepare release notes","milestoneId":55}
```

The result keeps ISO date-only values and does not expand user stories or point
summaries. If `next_page` is present, request that page explicitly. The separate
Taiga summary counts for all open/closed milestones are not substituted for the
page envelope's `total`.

## Discover story workflow statuses

Before creating or transitioning a story, call `list_user_story_statuses` with
the project ID. It returns a page envelope, including closed and archived
choices, for example:

```json
{"items":[{"id":10,"project":123,"name":"Terminado","slug":"terminado","order":0,"is_closed":true,"is_archived":false,"wip_limit":0}],"page":1,"total":null,"next_page":null,"has_more":null}
```

Pass the returned status `id` as `status` to `create_user_story` or
`update_user_story`; status IDs are specific to this project and the story
resource. If `next_page` is present, call the same tool with that page number.
Do not match statuses by English names.

## Discover task workflow statuses

Read the task first, call `list_task_statuses` for its project, choose one of
the returned task-specific IDs, and pass it with the task's current version to
`update_task`:

```json
{"taskId":203}
{"projectId":123,"page":1}
{"items":[{"id":11,"project":123,"name":"Ready","slug":"ready","order":0,"color":"#00aa00","is_closed":false},{"id":12,"project":123,"name":"Terminé","slug":"termine","order":1,"is_closed":true}],"page":1,"total":null,"next_page":null,"has_more":null}
{"taskId":203,"version":2,"status":12}
```

Task status IDs are not interchangeable with story status IDs. The task status
reader includes closed choices and does not expose story-only archive or WIP
fields. If `next_page` is present, call the same tool with that page number.

## Discover epic workflow statuses

Before creating or changing an epic, call `list_epic_statuses` for its project
and pass a returned epic-specific `id` as `status`:

```json
{"projectId":123,"page":1}
{"items":[{"id":7,"project":123,"name":"Ready","slug":"ready","order":0,"color":"#336699","is_closed":false},{"id":8,"project":123,"name":"Terminé","slug":"termine","order":1,"color":"#cc0000","is_closed":true}],"page":1,"total":null,"next_page":null,"has_more":null}
{"projectId":123,"subject":"Saved-search delivery","status":8}
```

Epic status IDs are not interchangeable with story or task status IDs. The
reader includes closed choices and does not expose story-only archive or WIP
fields. If `next_page` is present, call the same tool with that page number.

## Update an epic

Read an epic first, discover its project-specific statuses, and pass the
returned `version` and a selected status ID to `update_epic`. Omitted fields
stay unchanged; empty description or tags are explicit clears, and
`clearFields=["assigned_to"]` unassigns the primary assignee:

```json
{"epicId":301}
{"projectId":123,"page":1}
{"epicId":301,"version":4,"status":8,"clearFields":["assigned_to"],"comment":"Delivery complete."}
```

The result is the server's authoritative epic detail, including its new
version. A comment-only update is valid when the comment is nonblank. The
client does not refresh a version or retry an ambiguous write; read the epic
again before retrying after an uncertain transport or response failure.

For assignment, call `list_project_members` first and use an active member's
`user_id` as `assigned_to`; `membership_id` identifies the membership record
and is not an assignee ID. To unassign later, fetch the new epic `version` and
send `clearFields=["assigned_to"]`:

```json
{"projectId":123,"page":1}
{"epicId":301,"version":4,"assigned_to":42}
{"epicId":301,"version":5,"clearFields":["assigned_to"]}
```

## Update a user story

Read the story first and pass its returned `version` to the update. Omitted
fields remain unchanged; use exact wire names in `clearFields` for explicit
nulls:

```json
{"userStoryId":102,"version":4,"clearFields":["milestone"],"comment":"Move back to backlog."}
```

`milestoneId` places a story in a sprint, `clearFields=["milestone"]` returns
it to the backlog, and `clearFields=["assigned_to"]` unassigns it. Empty
`description` or `tags` values are explicit clears. The returned `version` and
other fields are authoritative; the server is not blindly retried after a
conflict or ambiguous write failure. `status` is a project-specific internal
status ID, so use an open or closed status ID from Taiga to reopen or close a
story. Only the primary assignee is supported; multiple assignees remain
planned.

## Add a work-item comment

Read the item first and use its current `version`. Select the internal ID and
one of the four closed `kind` values. The comment text can contain Markdown,
mentions, line breaks, and Unicode:

```json
{"kind":"task","id":203,"version":2,"text":"**Implementation complete**\n@reviewer — ready for review ✓"}
```

The result is a small receipt such as
`{"kind":"task","id":203,"version":3,"comment_submitted":true}`.
The command confirms the versioned PATCH succeeded; it does not return a
history-entry ID or perform a separate history read. A version conflict,
permission error, missing item, malformed success response, or ambiguous
transport failure is surfaced as an error and is not automatically retried.

## Read work-item comments

Use the internal work-item ID and a `kind` of `issue`, `user_story`, `task`, or
`epic` to read one visible comment page. History-entry IDs are opaque strings;
they are not the numeric work-item ID or displayed `#ref`:

```json
{"kind":"task","id":203,"page":1}
```

The result is a page envelope. Hidden, deleted, blank, and whitespace-only
comments are omitted, but `total`, `next_page`, and `has_more` describe the
upstream history page, so `items` can be empty while another page exists:

```json
{"items":[{"id":"history-entry","comment":"Reproduced locally","created_at":"2026-09-28T12:01:00Z","user":{"id":42,"name":"Example User","username":"example","is_active":true}}],"page":1,"total":3,"next_page":2,"has_more":true}
```

Call `add_work_item_comment` with the current item version, then call
`list_work_item_comments` to read the resulting visible conversation. This
read does not edit, delete, restore, or fetch comment revisions.

## Read work-item history

Use `get_work_item_history` when you need field changes as well as visible
comments. It uses the same internal ID and four-kind set, but requests the full
history stream without `type=comment`:

```json
{"kind":"task","id":203,"page":1}
```

The page preserves numeric event `type`, actor/time data, structured
`diff`/`values_diff`, and available edit/delete metadata. Hidden entries are
omitted. Deleted comment bodies are suppressed and reported with
`comment_deleted=true`; comment-labelled or matching text is also removed from
structured changes. Use a later page explicitly when `next_page` is present:

```text
Call the tool get_work_item_history with kind="task", id=203, and page=2
```


## Set native story estimates

Call `list_project_roles` and `list_points` for the story's project (with
`projectId` and `page=1`), then read `get_user_story` for its current version.
Use a role with the appropriate native estimation configuration and select a
returned point-option ID. A point's ID is not its numeric estimate value.

For example, if project role 7 and point option 21 are the desired choices,
call `set_user_story_estimates`:

```json
{"userStoryId":102,"version":4,"rolePoints":[{"roleId":7,"pointId":21}]}
```

Only supplied roles are updated; omitted roles retain their estimates. To
mark a role unestimated, select a configured point option whose `value` is
null. The server returns the authoritative story detail and does not calculate
point totals itself. Request subsequent metadata pages explicitly if needed.

## Read and manage attachments

All six attachment tools accept `kind` values `issue`, `user_story`, `task`,
and `epic`. Paths refer to the filesystem visible to the MCP server process.
For an issue with internal ID 201 in project 123, call
`list_work_item_attachments`:

```json
{"kind":"issue","id":201,"projectId":123,"page":1}
```

Select an attachment ID from the returned page; it is distinct from the issue
ID. For an illustrative attachment ID 901, call `download_work_item_attachment`:

```json
{"kind":"issue","attachmentId":901,"destination":"C:\\Temp\\taiga-attachment-901.pdf"}
```

The destination's parent directory must exist and the file must not already
exist. On Linux/WSL use an absolute server-local path such as
`/tmp/taiga-attachment-901.pdf`. Inspect the downloaded file to read its contents;
metadata URLs can contain expiring signed tokens and are not durable links.

To upload a file you explicitly select, call `upload_work_item_attachment`:

```json
{"kind":"issue","id":201,"projectId":123,"file":"C:\\Temp\\reproduction.txt","description":"Steps to reproduce"}
```

Uploads and downloads default to a 10 MiB limit, configurable with
`TAIGA__MAXATTACHMENTBYTES`. To update metadata on a selected attachment, call
`update_work_item_attachment`:

```json
{"kind":"issue","attachmentId":901,"fields":{"description":"Updated reproduction steps","is_deprecated":false}}
```

Attachment metadata updates do not accept a version and cannot replace file
bytes. To delete a deliberately selected attachment, use
`delete_work_item_attachment` with `kind` and `attachmentId`; success returns
`deleted=true`, while a repeated delete is a 404 error. These mutations do not
change the parent work item or local downloaded files. See the
[attachment contracts](taiga_tools_reference.md#list_work_item_attachments-contract)
for exact limits, URL handling, receipts, and failure behavior.
