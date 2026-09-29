# Taiga MCP tool reference

This document describes the behavior that is implemented in the current
repository. It is deliberately separate from the larger command inventory:
the inventory contains proposed future coverage, while this page records what
clients can call today and the compatibility constraints future batches must
preserve.

## Implemented versus planned

The current server exposes 32 tools:

- 3 project tools: `list_projects`, `list_project_members`, and `resolve_project`.
- 1 sprint tool: `list_sprints`.
- 1 identity tool: `get_current_user`.
- 8 issue tools: `list_issues`, `get_issue`, `create_issue`, `update_issue`,
  `list_issue_statuses`, `list_issue_severities`, `list_issue_types`, and
  `list_issue_priorities`.
- 5 user-story tools: `list_user_stories`, `list_user_story_statuses`,
  `get_user_story`, `create_user_story`, and `update_user_story`.
- 5 task tools: `list_tasks`, `list_task_statuses`, `get_task`, `create_task`, and `update_task`.
- 7 epic tools: `list_epics`, `list_epic_statuses`, `get_epic`, `create_epic`,
  `update_epic`, `link_user_story_to_epic`, and `list_epic_user_stories`.
- 2 shared work-item tools: `add_work_item_comment` and `resolve_work_item`.

All 15 selected first-batch functions are implemented within their defined
scope: three existing tools were expanded and twelve were added, bringing the
first-batch total to 23. Goals 01 through 07 of the [second batch](goals/second-batch/README.md)
add `get_current_user`, `list_project_members`, `resolve_work_item`,
`list_user_story_statuses`, `list_task_statuses`, `list_epic_statuses`, and
`list_sprints`; goal 08 adds `update_epic`; goal 09 adds
`list_epic_user_stories`; 3 batch functions remain planned. The broader
inventory still includes deferred fields and operations.
`update_user_story`
uses `userStoryId`, a nonnegative `version`, optional `subject`, `description`,
`status`, `assigned_to`, `tags`, `milestoneId`, and `comment`, plus
`clearFields` containing only the wire names `assigned_to` and `milestone`.
Omitted nullable fields remain untouched; explicit clear fields send JSON null;
`description=""` and `tags=[]` are explicit clears. A sprint move is sent once
to the story and Taiga determines any effects on child tasks; the MCP tool does
not patch child tasks separately. Invalid IDs, blank subjects, empty updates,
unsupported clear names, and set/clear collisions fail before HTTP; write
failures are not replayed.

The shared comment command is implemented for all four work-item kinds and is
documented below.
The `list_epics` and `get_epic` contracts are source-verified and their
domain APIs/MCP wrappers are implemented. `list_epics` has the signature
`list_epics(projectId, page=1, statusIds?, assignedTo?, tags?, query?,
includeClosed=false)`, and it will always return the page envelope
`{ items, page, total, next_page, has_more }`. The default wire filter is
`status__is_closed=false`; nonempty `statusIds` or `includeClosed=true` omit
that restriction. The allowlisted filters are `status`, `assigned_to`,
`tags`, and `q`, with encoded values. Epic list items will expose
`id`, `ref`, `project`, `subject`, `status_id`, `status`, `assigned_to`,
`color`, `tags`, `modified`, and optional `version`; no related-story
lookups or progress aggregation are part of this list operation. Invalid
project/page/filter IDs fail before HTTP, malformed list data is a safe Taiga
request failure, and missing pagination headers remain unknown (`null`).

This contract was checked on 2026-09-28 against pinned taiga-back revision
`4d11baef9027f5598f6341d6eb4261de2840688e` in the [epic API source](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/api.py)
and [epic serializer source](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/serializers.py).

Use the returned internal `id` with the `get_epic` command and the epic story
relationship tools; the displayed `ref` is for human-facing project context
only.

The `create_epic` MCP wrapper is implemented for goal 13. Its signature is
`create_epic(projectId, subject, description?, status?, assigned_to?, color?,
tags?)`. The request maps to `POST /api/v1/epics` with `project`, `subject`,
`description`, `status`, `assigned_to`, `color`, and `tags`; omitted optional
values stay omitted so Taiga can apply project defaults. The response will use
the existing epic detail mapping and expose the server's authoritative `id`,
`ref`, and nonnegative `version`. This call creates one epic only; linking
stories and setting requirement flags remain separate operations.

The contract was checked on 2026-09-28 against pinned taiga-back revision
`4d11baef9027f5598f6341d6eb4261de2840688e`: the epic validator accepts the
model's writable fields and the model supplies a generated default color when
one is omitted. The model stores color as a string with a 32-character limit,
so this client does not impose a narrower color format; Taiga remains the
authority for color validation. The endpoint is documented at the pinned
taiga-doc revision `7455fd37cb164bbf80198c1517fd0ef414e2a7b9`.

The `link_user_story_to_epic` contract was source-verified on
2026-09-28 against taiga-back revision
`c8264ac6775103cbcc2a3a145978f2b475e9ff05` ([nested API viewset](https://github.com/taigaio/taiga-back/blob/c8264ac6775103cbcc2a3a145978f2b475e9ff05/taiga/projects/epics/api.py#L185-L232), [relationship serializer](https://github.com/taigaio/taiga-back/blob/c8264ac6775103cbcc2a3a145978f2b475e9ff05/taiga/projects/epics/serializers.py#L68-L71), and [relationship model](https://github.com/taigaio/taiga-back/blob/c8264ac6775103cbcc2a3a145978f2b475e9ff05/taiga/projects/epics/models.py#L96-L107)). The nested route is
`/api/v1/epics/{epicId}/related_userstories/{userStoryId}`: the story ID is
the nested lookup key, and creation sends `epic`, `user_story`, and optional
`order`. A successful response contains `epic`, `user_story`, and the
server-selected or requested `order`; the public result will rename those
identifiers to `epic_id` and `user_story_id` and add `created`.

The implementation will first read the nested relationship. A confirmed
existing link returns `created=false` with its current order and ignores a new
order request. A 404 is not treated as an absent link until the existing epic
and story readers confirm that both resources are accessible. A recognized
concurrent uniqueness validation is followed by the same relationship read and
is reported as `created=false` only when that read confirms the link; unrelated
validation, permission, missing-resource, and transport failures propagate.
Cross-project linking is left to Taiga's permission and validation rules.
The domain implementation and public MCP wrapper now follow this wire
behavior.

### `link_user_story_to_epic` contract

The signature is `link_user_story_to_epic(epicId, userStoryId, order?)`. It
returns JSON with `epic_id`, `user_story_id`, `order`, and `created`, for
example:

```json
{"epic_id":301,"user_story_id":102,"order":9001,"created":true}
```

The call first performs `GET
/api/v1/epics/{epicId}/related_userstories/{userStoryId}`. If the link exists,
it returns `created=false` and the current server order, ignoring any supplied
`order`. If the link is absent, it confirms the epic and story detail reads
before sending one `POST /api/v1/epics/{epicId}/related_userstories` with
`{"epic": epicId, "user_story": userStoryId}` and an `order` property only
when supplied. The operation does not require a story or epic version and does
not update the story, its project, or any other epic relationships. Taiga
decides whether an accessible cross-project relationship is permitted.

A recognized concurrent uniqueness response is read back and reported as
`created=false` only when the relationship read confirms it. Unrelated 400
responses, permission failures, missing resources, transport failures, and
ambiguous writes are returned as safe MCP errors; no POST retry is performed.

### `list_epic_user_stories` contract

The signature is `list_epic_user_stories(epicId, page=1)`. It validates positive
`epicId` and `page`, then sends exactly one authenticated
`GET /api/v1/epics/{epicId}/related_userstories?page={page}` request. The result
is always the standard page envelope:

```json
{"items":[{"epic_id":301,"user_story_id":102,"order":9001}],"page":1,"total":1,"next_page":null,"has_more":false}
```

Each item is only a relationship identity and its server order. The response
does not include the link tool's `created` receipt, full story details, story
project data, or calculated epic progress. Preserve the returned order and use
`get_user_story(userStoryId)` when a selected story needs inspection. The call
does not write or fetch one detail object per relationship, and Taiga remains
the authority for accessible cross-project links.

Missing pagination headers remain literal `null`; a `next_page` number must be
requested explicitly. Malformed relationship data, a returned `epic` that does
not match the requested epic, invalid IDs, permission failures, and transport
failures are safe MCP errors. For example, a forbidden read exposes its status
and category without echoing the upstream body:

```text
Taiga HTTP 403: permission denied.
```

The relationship fields were checked on 2026-09-29 against pinned taiga-back
revision `4d11baef9027f5598f6341d6eb4261de2840688e` in the [nested epic viewset](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/api.py)
and [relationship serializer](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/serializers.py). The serializer supplies `epic`, `user_story`, and `order`; the nested lookup is by story ID. This is pinned source evidence, not a deployed-version claim.

### `get_epic` contract

The signature is `get_epic(epicId)`. It performs one authenticated `GET
/api/v1/epics/{epicId}` detail read. The result exposes the authoritative
`id`, `ref`, `project`, `version`, description, subject, status ID/label,
assignment, color, tags, and modified timestamp. It also preserves
server-supplied scalar context (`is_closed`, `is_blocked`, `blocked_note`,
`client_requirement`, and `team_requirement`) and the optional raw
`user_stories_counts` summary when the server provides it. Missing optional
values are omitted from tool JSON; unknown upstream fields are ignored.

The client will preserve Markdown/Unicode description text and the numeric
status ID even when no inline status label is available. It will not fetch
related stories, history, comments, or status metadata, and it will not
compute progress. The detail mapping was checked on 2026-09-28
against taiga-back revision
`4d11baef9027f5598f6341d6eb4261de2840688e` ([epic API](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/api.py),
[epic serializers](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/serializers.py),
[epic model](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/models.py))
and taiga-doc revision
`7455fd37cb164bbf80198c1517fd0ef414e2a7b9` ([epic endpoints](https://github.com/taigaio/taiga-doc/blob/7455fd37cb164bbf80198c1517fd0ef414e2a7b9/api/epics/endpoints.adoc)).
This is pinned source evidence, not a deployed-version claim.

The public `get_epic` wrapper now exposes the domain mapping with the
signature `get_epic(epicId)`. It accepts the positive internal epic ID, not the
displayed `#ref`, and returns one detail object rather than a page envelope.

See the [command inventory](taiga_command_inventory.md)
and [second-batch plan index](goals/second-batch/README.md) for remaining
planned coverage.

### `get_current_user` contract

The signature is `get_current_user()` with no user-supplied arguments. It sends
one authenticated `GET /api/v1/users/me` and returns an allowlisted identity
object:

```json
{"id":42,"username":"synthetic-user","full_name":"Synthetic User","is_active":true}
```

`id` is required and must be a positive integer. `username`, `full_name`, and
`is_active` are optional; absent values are omitted from public JSON, while
`is_active=false` is preserved. Use the returned numeric ID as `assigned_to` or
`assignedTo` in existing work-item calls, or convert it to a string for the
existing `list_projects(member)` filter. Email, roles, tokens, UUIDs, and other
upstream profile properties are not returned. A missing or malformed ID, 401,
403, invalid JSON, cancellation, or another transport failure is surfaced as a
safe MCP error; no credentials or raw upstream body is included. The injected
`cancellationToken` is not a public argument.

### `list_project_members` contract

The signature is `list_project_members(projectId, page=1)`. It sends exactly
one authenticated `GET /api/v1/memberships?project={projectId}&page={page}` and
returns the standard page envelope:

```json
{
  "items":[
    {"membership_id":501,"project":123,"user_id":42,"role_id":7,"role_name":"Product Owner","full_name":"Active User","is_user_active":true,"is_admin":true,"is_owner":true},
    {"membership_id":503,"project":123,"role_id":8,"role_name":"Developer","is_user_active":false}
  ],
  "page":1,
  "total":3,
  "next_page":2,
  "has_more":true
}
```

`projectId` and `page` must be positive. `membership_id` is the membership
record ID; `user_id` is the Taiga account ID to use as `assigned_to` or
`assignedTo` in a later work-item call. A pending invitation may have no
`user_id`, and an inactive user remains visible with `is_user_active=false`;
neither case is silently converted into an active assignable user. Optional
role, name, activity, admin, and owner fields are omitted when the upstream
value is absent. Admin-only `email`, `user_email`, and invitation text are
discarded. The tool does not filter by name, read individual user profiles,
follow pages automatically, or claim that membership guarantees permission for
a future write. Unknown pagination headers remain explicit `null` values.

Invalid IDs, malformed required membership/project IDs, 401/403 responses,
invalid JSON, cancellation, and other transport failures are returned as safe
MCP errors without raw upstream bodies. The injected `cancellationToken` is
not a public argument. At the installed MCP boundary, omitting `projectId`,
sending `projectId:null`, or sending `page:null` produces an `IsError=true`
tool result before HTTP; an explicit `page=4` is accepted and requests page 4.

### `list_sprints` contract

The signature is `list_sprints(projectId, page=1, closed=null)`. Taiga calls
sprints **milestones**. The tool sends exactly one authenticated page request:

```text
GET /api/v1/milestones?project={projectId}&page={page}
GET /api/v1/milestones?project={projectId}&page={page}&closed=false
GET /api/v1/milestones?project={projectId}&page={page}&closed=true
```

The first form is used when `closed` is omitted or explicitly null; false selects
open milestones and true selects closed milestones. The result is always the
standard page envelope. Only the lightweight fields below are returned; dates
remain ISO date-only strings and are not converted to timestamps:

```json
{
  "items":[
    {"id":55,"project":123,"name":"Sprint 2026-09","slug":"sprint-2026-09","estimated_start":"2026-09-01","estimated_finish":"2026-09-14","closed":false}
  ],
  "page":1,
  "total":null,
  "next_page":null,
  "has_more":null
}
```

Use each returned `id` as `milestoneId` with `create_user_story`,
`update_user_story`, or standalone `create_task`. Nested `user_stories`, point
aggregates, statistics, date filters, and sprint creation/editing are not
included. Taiga's project-wide open/closed summary headers are not used as the
page `total`; unknown standard pagination headers remain explicit `null`.
Positive `projectId`/`page`, malformed identity/date data, 401/403 responses,
invalid JSON, cancellation, and other transport failures produce safe errors.
The injected `cancellationToken` is not a public argument.

This contract was checked on 2026-09-29 against pinned taiga-back revision
`4d11baef9027f5598f6341d6eb4261de2840688e`: the [milestone viewset](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/milestones/api.py)
allows `project` and `closed`, orders by descending estimated start, and emits
separate open/closed summary headers; the [milestone serializer](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/milestones/serializers.py)
also supplies nested stories and point aggregates that are deliberately ignored.
The [official REST documentation](https://docs.taiga.io/api.html) confirms the
milestone route and `closed=true|false` filter. This is pinned source evidence,
not a deployed-version claim.

### `resolve_work_item` contract

The signature is `resolve_work_item(projectId, kind, ref)`. It sends exactly one
authenticated GET to the selected resource's project-local by-reference route:

```text
GET /api/v1/issues/by_ref?project={projectId}&ref={ref}
GET /api/v1/userstories/by_ref?project={projectId}&ref={ref}
GET /api/v1/tasks/by_ref?project={projectId}&ref={ref}
GET /api/v1/epics/by_ref?project={projectId}&ref={ref}
```

`kind` is closed to `issue`, `user_story`, `task`, and `epic`. `projectId` and
`ref` are positive numeric values; `ref` is the displayed project-local number
without a leading `#`, not an internal ID. A successful result is a small
identity receipt, for example:

```json
{"kind":"task","id":203,"ref":42,"project":12,"subject":"Implement saved-search endpoint","version":2}
```

The returned `id` is the value to pass to `get_task` (or the matching existing
`get_*` tool). Use the version from that subsequent detail response for a later
versioned edit; the resolver's optional version is informational and must not
replace the detail read. The resolver does not fetch full details, scan lists, search other
projects, infer the kind, parse slugs/URLs, or modify Taiga. The response's
positive `id`, `ref`, and `project` are required; a ref/project mismatch is a
safe lookup error rather than a fallback. Missing optional `subject` or
`version` values remain omitted. A 404 is returned as a safe resource-not-found
error, and the client does not retry or issue a write.

The route and response contract was checked on 2026-09-29 against pinned
taiga-back revision `4d11baef9027f5598f6341d6eb4261de2840688e`: the
[ByRefMixin](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/mixins/by_ref.py),
[issue viewset](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/issues/api.py),
[story viewset](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/userstories/api.py),
[task viewset](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/api.py),
and [epic viewset](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/api.py).
This is pinned source evidence, not a deployed-version claim.

All tool methods return a string whose contents are JSON. The examples below
show the JSON contents, not an MCP `content` wrapper.

## Current tool contracts

| Tool | Parameters and defaults | Current result |
| --- | --- | --- |
| `list_projects` | `member` string?, default `null`; `page` integer, default `1` | Array of `{ id, slug, name }` project objects. |
| `resolve_project` | `slug` string, required | `{ "project": 123 }`. |
| `resolve_work_item` | `projectId`, `kind`, and `ref` required; `kind` is one of `issue`, `user_story`, `task`, or `epic` | `{ kind, id, ref, project, subject?, version? }`; identity is checked against the requested project/ref. |
| `get_current_user` | No arguments | One identity object with required positive `id` and optional `username`, `full_name`, and `is_active`. |
| `list_project_members` | `projectId` integer, required; `page` integer, default `1` | `{ items, page, total, next_page, has_more }`; member items expose `membership_id`, `project`, optional `user_id`, `role_id`, `role_name`, `full_name`, `is_user_active`, `is_admin`, and `is_owner`. |
| `list_sprints` | `projectId` integer, required; `page` integer, default `1`; `closed` boolean?, default `null` | `{ items, page, total, next_page, has_more }`; sprint items expose `{ id, project, name, slug, estimated_start, estimated_finish, closed }`. Omitted/null `closed` sends no filter; false selects open milestones and true selects closed milestones. Use `id` as `milestoneId`; nested stories, point aggregates, statistics, and date filters are not included. |
| `list_issues` | `projectId` integer, required; `page` integer, default `1`; `statusIds`, `assignedTo`, `typeId`, `priorityId`, `severityId`, `tags`, `query`, `includeClosed=false`, `includePageInfo=false` optional | Bare array by default; when `includePageInfo=true`, `{ items, page, total, next_page, has_more }`. Classification IDs accompany labels. |
| `get_issue` | `issueId` integer, required | `{ "issue": <issue>, "comments": <visible comments> }`. |
| `create_issue` | `projectId`, `subject` required; `description`, `status`, `type`, `priority`, `severity`, `assigned_to`, and `tags` optional and default null | One issue object returned by Taiga after mapping metadata IDs to labels. |
| `update_issue` | `issueId` and `version` required; `subject`, `description`, `status`, `type`, `priority`, `severity`, `assigned_to`, `tags`, `comment`, and `clearFields` optional. `clearFields` accepts only `assigned_to`. | One issue object returned by Taiga after the PATCH. |
| `add_work_item_comment` | `kind`, `id`, `version`, and `text` required; `kind` is one of `issue`, `user_story`, `task`, or `epic`; `id` is positive; `version` is nonnegative; `text` is nonblank | `{ "kind": "task", "id": 203, "version": 3, "comment_submitted": true }` after one confirmed comment-only PATCH. |
| `list_issue_statuses` | `projectId` integer, required | Array of `{ id, name, slug, is_closed }`. |
| `list_issue_severities` | `projectId` integer, required | Array of `{ id, name, slug, color }`. |
| `list_issue_types` | `projectId` integer, required | Array of `{ id, name, slug, color }`. |
| `list_issue_priorities` | `projectId` integer, required | Array of `{ id, name, slug, color }`. |
| `list_user_stories` | `projectId` integer, required; `page` integer, default `1`; `statusIds`, `assignedTo`, `milestoneId`, `backlogOnly=false`, `tags`, `query`, `includeClosed=false`, `includeArchived=false`, and `includePageInfo=false` optional | Bare array of `{ id, ref, project?, subject, status_id?, status, assigned_to, modified, milestone?, version? }`; with `includePageInfo=true`, `{ items, page, total, next_page, has_more }`. Explicit status IDs override automatic closed/archive restrictions. |
| `list_user_story_statuses` | `projectId` integer, required; `page` integer, default `1` | `{ items, page, total, next_page, has_more }`; status items expose `{ id, project?, name?, slug?, order?, color?, is_closed?, is_archived?, wip_limit? }`. All returned choices are included, including closed and archived statuses; IDs are specific to the project and user-story resource. |
| `list_task_statuses` | `projectId` integer, required; `page` integer, default `1` | `{ items, page, total, next_page, has_more }`; status items expose `{ id, project?, name?, slug?, order?, color?, is_closed? }`. All returned choices are included, including closed statuses; IDs are specific to the project and task resource. Story-only `is_archived` and `wip_limit` fields are not exposed. |
| `list_epic_statuses` | `projectId` integer, required; `page` integer, default `1` | `{ items, page, total, next_page, has_more }`; status items expose `{ id, project?, name?, slug?, order?, color?, is_closed? }`. All returned choices are included, including closed statuses; IDs are specific to the project and epic resource. Story-only `is_archived` and `wip_limit` fields are not exposed. |
| `get_user_story` | `userStoryId` integer, required | One detail object with `{ id, ref?, project?, subject?, description?, status_id?, status?, assigned_to?, tags?, milestone?, modified?, version, origin_issue?, origin_task?, epics? }`. `userStoryId` is the internal ID, not displayed `#ref`; comments and tasks are not loaded. |
| `create_user_story` | `projectId`, `subject` required; `description`, `status`, `assigned_to`, `tags`, and `milestoneId` optional and default null | One server-created story detail with authoritative `id`, `ref`, and `version`. `description` is the place for acceptance criteria; `milestoneId` selects a sprint, while omitted optional fields let Taiga apply project defaults. |
| `update_user_story` | `userStoryId`, `version` required; `subject`, `description`, `status`, `assigned_to`, `tags`, `milestoneId`, `comment`, and `clearFields` optional | One authoritative updated story detail. Omitted fields stay unchanged; `clearFields` accepts only `assigned_to` and `milestone` and emits explicit JSON null. Only the primary `assigned_to` field is supported; multiple assignees remain planned. |
| `list_tasks` | `projectId` integer, required; `page` integer, default `1`; `userStoryId`, `milestoneId`, `statusIds`, `assignedTo`, `tags`, `query`, and `includeClosed=false` optional | Always `{ items, page, total, next_page, has_more }`, with task items `{ id, ref, project?, subject?, status_id?, status?, assigned_to?, user_story?, milestone?, modified?, version? }`. Explicit status IDs override the automatic open-only restriction. |
| `list_epics` | `projectId` integer, required; `page` integer, default `1`; `statusIds`, `assignedTo`, `tags`, `query`, and `includeClosed=false` optional | Always `{ items, page, total, next_page, has_more }`, with epic items `{ id, ref, project?, subject?, status_id?, status?, assigned_to?, color?, tags?, modified?, version? }`. Explicit status IDs override the automatic open-only restriction. |
| `get_epic` | `epicId` integer, required | One detail object with `{ id, ref, project, subject?, description?, status_id?, status?, assigned_to?, color?, tags?, modified?, is_closed?, is_blocked?, blocked_note?, client_requirement?, team_requirement?, user_stories_counts?, version }`. `epicId` is the internal ID, not displayed `#ref`; related stories and computed progress are not loaded. |
| `create_epic` | `projectId`, `subject` required; `description`, `status`, `assigned_to`, `color`, and `tags` optional and default null | One server-created epic detail with authoritative `id`, `ref`, and `version`. Omitted optional fields use project defaults; `description=""` and `tags=[]` are explicit values. Use the separate `link_user_story_to_epic` tool for existing stories. Requirement flags, bulk creation, and custom fields remain planned. |
| `update_epic` | `epicId`, `version` required; `subject`, `description`, `status`, `assigned_to`, `color`, `tags`, `comment`, and `clearFields` optional. `clearFields` accepts only `assigned_to`. | One authoritative epic detail after a versioned PATCH. Omitted fields stay unchanged; empty description/tags are explicit clears, and `clearFields=["assigned_to"]` emits JSON null. Use `list_epic_statuses` for project-specific status IDs; ordering, requirement flags, blocking, dates, custom fields, project moves, and linked-story changes remain planned. |
| `list_epic_user_stories` | `epicId` integer, required; `page` integer, default `1` | `{ items, page, total, next_page, has_more }`, where items are `{ epic_id, user_story_id, order }`. This is a one-page relationship index; use `get_user_story` for selected details. Creation state, project enrichment, progress aggregation, reordering, and all-page fetching remain out of scope. |
| `get_task` | `taskId` integer, required | One detail object with `{ id, ref, project, subject?, description?, status_id?, status?, assigned_to?, user_story?, milestone?, tags?, modified?, due_date?, due_date_reason?, due_date_status?, is_blocked?, blocked_note?, is_closed?, version }`. `taskId` is the internal ID, not displayed `#ref`; comments, attachments, and parent details are not loaded. |
| `create_task` | `projectId`, `subject` required; `userStoryId`, `milestoneId`, `description`, `status`, `assigned_to`, and `tags` optional | One authoritative task detail. A story parent is read and must belong to `projectId`; omitted `milestoneId` inherits the parent's sprint, while an explicit value must match it. Standalone tasks may omit or select a sprint. |
| `update_task` | `taskId`, `version` required; `subject`, `description`, `status`, `assigned_to`, `tags`, `isBlocked`, `blockedNote`, `comment`, and `clearFields` optional | One authoritative task detail after a versioned PATCH. `clearFields` accepts only `assigned_to`; description/tags/blocked note can be explicitly cleared with empty values. The client does not add compensating writes, and Taiga clears `blocked_note` whenever the saved task is unblocked. Parent story, sprint, due dates, and iocaine are unchanged and out of scope. |

### `list_user_story_statuses` contract

The signature is `list_user_story_statuses(projectId, page=1)`. It validates
positive IDs, sends one request per call as
`GET userstory-statuses?project={projectId}&page={page}`, and returns a standard
page envelope. Use the returned status `id` with `create_user_story` or
`update_user_story`; IDs are project- and resource-specific. Request a later
page when `next_page` is a number. The result includes closed and archived
choices without filtering by status name, and preserves supplied false, zero,
null, localized/custom-name, color, order, and WIP values. Unknown pagination
headers remain literal `null`; response DTO nulls are omitted.

Invalid nonpositive `projectId` or `page` values fail before HTTP. Permission,
transport, malformed JSON, and malformed required status data are returned as
safe MCP errors without raw upstream bodies; the tool never writes story data.

The route and fields were checked on 2026-09-29 against pinned taiga-back
revision `4d11baef9027f5598f6341d6eb4261de2840688e`: the [user-story status
viewset](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/api.py#L543-L556)
filters by project with project-view permissions, and the [status
serializer](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/serializers.py#L44-L53)
exposes the mapped metadata. This is pinned source evidence, not a deployed
version claim.

### `list_task_statuses` contract

The signature is `list_task_statuses(projectId, page=1)`. It validates positive
IDs, sends one request per call as
`GET task-statuses?project={projectId}&page={page}`, and returns a standard page
envelope. Use a returned status `id` with `create_task` or `update_task`; IDs are
project- and resource-specific. Request a later page when `next_page` is a
number. The result includes open and closed choices without filtering by status
name and preserves supplied false, zero, null, localized/custom-name, color,
and order values. Unknown pagination headers remain literal `null`; response
DTO nulls are omitted. Story-only `is_archived` and `wip_limit` properties are
never fabricated or exposed.

The workflow is to read a task, discover the task statuses, choose a returned
task status ID, and pass that ID with the task's current version to
`update_task`:

```json
{"id":203,"project":123,"status_id":11,"version":2}
{"items":[{"id":11,"project":123,"name":"Ready","slug":"ready","order":0,"color":"#00aa00","is_closed":false},{"id":12,"project":123,"name":"Terminé","slug":"termine","order":1,"is_closed":true}],"page":1,"total":null,"next_page":null,"has_more":null}
{"taskId":203,"version":2,"status":12}
```

Invalid nonpositive `projectId` or `page` values fail before HTTP. Permission,
transport, malformed JSON, and malformed required status data are returned as
safe MCP errors without raw upstream bodies; the tool never writes task data.

The route and fields follow the pinned taiga-back source evidence recorded in
[the second-batch sources](goals/second-batch/sources.md), revision
`4d11baef9027f5598f6341d6eb4261de2840688e`. This is pinned source evidence,
not a deployed version claim.

### `list_epic_statuses` contract

The signature is `list_epic_statuses(projectId, page=1)`. It validates positive
IDs, sends one request per call as
`GET epic-statuses?project={projectId}&page={page}`, and returns a standard page
envelope. Use a returned status `id` with `create_epic` or `update_epic`; IDs
are project- and resource-specific. Request a later page when
`next_page` is a number. The result includes open and closed choices without
filtering by status name and preserves supplied false, zero, null, localized or
custom names, colors, and order values. Unknown pagination headers remain
literal `null`; response DTO nulls are omitted. Epic statuses do not expose
story-only `is_archived` or `wip_limit` fields.

The workflow is to discover statuses before creating an epic, choose the returned
epic-specific ID, and pass it as `status`:

```json
{"projectId":123,"page":1}
{"items":[{"id":7,"project":123,"name":"Ready","slug":"ready","order":0,"color":"#336699","is_closed":false},{"id":8,"project":123,"name":"Terminé","slug":"termine","order":1,"color":"#cc0000","is_closed":true}],"page":1,"total":null,"next_page":null,"has_more":null}
{"projectId":123,"subject":"Saved-search delivery","status":8}
```

Invalid nonpositive `projectId` or `page` values fail before HTTP. Permission,
transport, malformed JSON, and malformed required status data are returned as
safe MCP errors without raw upstream bodies; the tool never writes epic data.

The route and fields were checked on 2026-09-29 against pinned taiga-back
revision `4d11baef9027f5598f6341d6eb4261de2840688e`: the [epic status viewset](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/api.py#L523-L541)
filters by project with project-view permissions, and the [EpicStatusSerializer](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/serializers.py#L34-L41)
exposes exactly the mapped fields. This is pinned source evidence, not a
deployed version claim.

### `add_work_item_comment` contract

The signature is `add_work_item_comment(kind, id, version, text)`. Before
calling it, read the resource detail and use its current `version`; IDs are
the internal numeric IDs, not displayed `#ref` values. `kind` is closed to
`issue`, `user_story`, `task`, and `epic` and is dispatched to the matching
route:

```text
PATCH /api/v1/issues/{id}
PATCH /api/v1/userstories/{id}
PATCH /api/v1/tasks/{id}
PATCH /api/v1/epics/{id}
```

The request body contains exactly `version` and `comment`. Nonblank text is
preserved through JSON serialization, including Markdown, mentions, line
breaks, Unicode, and meaningful surrounding whitespace. A successful response
is reduced to its returned nonnegative `version`; the tool returns
`comment_submitted=true` to confirm the update was accepted. It does not fetch
history and does not claim a history-entry ID.

Invalid IDs, negative versions, and blank text fail before HTTP. HTTP errors
retain safe status/category/version details, while malformed success responses
and ambiguous transport failures report that the write may already have
applied. The client does not retry comments after ambiguous failures. The
wire behavior was checked on 2026-09-28 against Taiga backend revision
`4d11baef9027f5598f6341d6eb4261de2840688e`: [history snapshot comment handling](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/history/mixins.py), [OCC version handling](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/occ/mixins.py), and the [issue](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/issues/api.py), [story](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/userstories/api.py), [task](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/api.py), and [epic](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/api.py) viewsets. This is pinned source evidence, not a deployed-version claim.

### `list_epics` contract

The signature is `list_epics(projectId, page=1, statusIds?, assignedTo?,
tags?, query?, includeClosed=false)`. It requests exactly one project-scoped
page. With no explicit statuses, the default request includes
`status__is_closed=false`; nonempty `statusIds` and `includeClosed=true` remove
that automatic restriction. The tool does not fetch epic statuses, related
stories, or progress data for each item.

For example:

```json
{"projectId":12,"page":1,"includeClosed":true,"query":"saved search"}
```

The result is always an envelope, even for an empty page:

```json
{"items":[{"id":301,"ref":12,"project":123,"subject":"Saved search epic","status_id":7,"status":"Ready","assigned_to":42,"color":"#336699","tags":[["search","#336699"]],"modified":"2026-09-28T12:03:00Z","version":4}],"page":1,"total":null,"next_page":null,"has_more":null}
```

The `id` is the internal epic identifier for the `get_epic` and future
story-linking commands; `ref` is the displayed project reference.

Parameter names are the public names generated from the C# method signatures;
the issue update method intentionally retains the existing `assigned_to`
spelling for compatibility. The MCP SDK schema and runtime binding are
verified by the integration tests added by this foundation goal.

### `get_epic` usage

Start with `list_epics` to obtain a project-scoped page, then pass the item's
internal `id` to `get_epic`; the displayed `ref` is not accepted as the detail
identifier:

```json
{"projectId":123,"page":1,"includeClosed":false}
{"epicId":301}
```

The result is one detail object, for example:

```json
{"id":301,"ref":12,"project":123,"subject":"Saved search epic","description":"**Acceptance:** preserve Markdown and Unicode — ✓","status_id":7,"status":"Ready","color":"#336699","tags":[["search","#336699"]],"is_closed":false,"is_blocked":true,"client_requirement":true,"team_requirement":false,"user_stories_counts":{"total":3,"closed":1},"version":4}
```

Optional null properties such as `assigned_to` and `blocked_note` are omitted
from tool JSON. Use the returned `version` for a later versioned edit. This
read does not enumerate linked stories, fetch history/comments, or calculate
progress.

### `create_epic` usage

Create one epic with project defaults:

```json
{"projectId":123,"subject":"Saved search experience"}
```

Provide optional project-specific values when needed:

```json
{"projectId":123,"subject":"Saved search experience","description":"Group saved-search delivery work.","status":7,"assigned_to":42,"color":"#336699","tags":["search","saved"]}
```

The result is the authoritative created epic detail, including its internal
`id`, display `ref`, and `version`. Use that internal ID with `get_epic` or the
separate `link_user_story_to_epic` tool.
This command creates only the epic and does not alter stories or project
settings. Taiga validates project membership, status, assignee, and color.
Invalid positive-ID/subject inputs fail before HTTP. HTTP validation and
permission failures preserve only safe status/category and allowlisted field
names such as `status`, `project`, and `color`; upstream text is not echoed.
The client does not retry an ambiguous POST or a malformed success response,
and reports that the write may already have applied so callers can read the
entity before retrying.

### `update_epic` contract

The signature is `update_epic(epicId, version, subject?, description?, status?,
assigned_to?, color?, tags?, comment?, clearFields?)`. Read the epic first and
pass its current nonnegative `version`. The update sends one authenticated
`PATCH /api/v1/epics/{epicId}` with only the supplied fields and the exact
caller version:

```json
{"epicId":301,"version":4,"status":8,"clearFields":["assigned_to"],"comment":"Delivery complete."}
```

Omitted or null optional values remain unchanged. An empty description or tag
array is explicit. `clearFields` accepts only the exact wire name
`assigned_to`, which emits `"assigned_to":null`; setting `assigned_to` and
clearing it in the same call is rejected. A nonblank subject is required when
provided, and an update must contain a real change or a nonblank comment.
Status IDs are project- and epic-specific; use `list_epic_statuses` to discover
them and select a closed status to close or an open status to reopen an epic.
For assignment, use `list_project_members` and pass an active member's
`user_id` as `assigned_to`; `membership_id` identifies the membership record
and is not an assignee ID. Use the new returned `version` with
`clearFields=["assigned_to"]` to unassign.

The result is the authoritative `EpicDetailDto`, including the server's
returned version. The client does not refresh versions, retry ambiguous writes,
change project settings, reorder epics, or modify linked stories. HTTP errors
retain only safe status/category and allowlisted rejected-field or version
details. Malformed successful responses and ambiguous transport failures report
that the write may already have applied; read the epic before retrying. Color
format validation remains Taiga-owned.

This contract was checked on 2026-09-29 against pinned taiga-back revision
`4d11baef9027f5598f6341d6eb4261de2840688e`: the [epic serializer](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/serializers.py),
[epic validator](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/validators.py),
[epic model](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/models.py),
and [OCC mixin](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/occ/mixins.py)
confirm the writable fields and version behavior. This is pinned source
evidence, not a deployed-version claim.

### `create_task` contract

The signature is `create_task(projectId, subject, userStoryId?, milestoneId?,
description?, status?, assigned_to?, tags?)`. `projectId` must be positive and
`subject` must be nonblank. Optional IDs must be positive; omitted optional
fields are omitted from the request so Taiga project defaults apply, while an
empty description or tag array is explicit.

For a standalone task, use either of these forms:

```json
{"projectId":12,"subject":"Capture deployment checklist"}
{"projectId":12,"subject":"Prepare release notes","milestoneId":55}
```

For a story-linked task, the server reads the parent story before creation to
validate its project. If `milestoneId` is omitted, the parent's current sprint
is authoritative. If it is supplied, it must equal the parent's sprint,
including the null case; a matching value is omitted from the POST and Taiga
still validates the relationship at save time. If the parent changes sprint
between the lookup and POST, Taiga uses the parent's sprint at save time; the
client cannot guarantee that it is the sprint observed during the lookup.

```json
{"projectId":12,"subject":"Implement saved-search endpoint","userStoryId":102}
```

The tool performs one `POST /api/v1/tasks` and returns the server's task detail,
including the resulting `user_story`, `milestone`, and `version`. It does not
use Taiga's native bulk-create endpoint, so standalone creation is not subject
to that endpoint's sprint requirement. Bulk creation, due dates, blockers,
iocaine, and cross-project creation remain planned. A transport or response
mapping failure after the POST is reported as potentially applied and is never
automatically retried.

### `get_task` contract

The signature is `get_task(taskId)`, where `taskId` is the positive
internal task ID rather than the displayed `#ref`. It requests exactly
`GET /api/v1/tasks/{taskId}` and return one detail object rather than a page
envelope. The required identity/version fields are `id`, `ref`, `project`, and
`version`; optional fields include `subject`, Markdown `description`,
`status_id`/`status`, `assigned_to`, `user_story`, `milestone`, `tags`,
`modified`, `due_date`, `due_date_reason`, `due_date_status`, `is_blocked`,
and `blocked_note`. Unknown upstream fields are ignored. Comments,
attachments, and parent-detail requests are outside this command.
The concrete `TaskApi.GetTaskAsync` implementation and `get_task` MCP tool
follow this wire contract.
For a later edit, use `list_tasks` to find the internal ID, call `get_task` to
obtain a fresh authoritative `version`, and pass that version to
`update_task`; this read does not load comments, attachments, or the parent
object.

### `update_task` contract

The available `update_task` tool has the signature
`update_task(taskId, version, subject?, description?, status?, assigned_to?,
tags?, isBlocked?, blockedNote?, comment?, clearFields?)`. Omitted fields remain
unchanged; `description=""`,
`tags=[]`, `isBlocked=false`, and `blockedNote=""` are explicit updates.
`clearFields` accepts only `assigned_to`, and emits `assigned_to: null` for an
explicit unassignment. The client keeps omitted fields absent and does not add
compensating writes, but Taiga's task save clears `blocked_note` whenever
`isBlocked=false`, whether the note is omitted or nonempty. The caller supplies
the nonnegative version from a fresh `get_task` result, and a PATCH returns the
server's authoritative task detail.

Unblock workflow example:

```json
{"taskId":203,"version":2,"isBlocked":false,"blockedNote":"","comment":"Dependency resolved."}
```

The result is the server's updated detail, for example:

```json
{"id":203,"ref":17,"project":123,"subject":"Integration task","is_blocked":false,"blocked_note":"","version":3}
```

## Representative sanitized JSON

Project and lookup results:

```json
[{"id":123,"slug":"demo","name":"Demo"}]
{"project":123}
```

Issue list/detail results:

```json
[{
  "id":456,
  "ref":7,
  "project":123,
  "subject":"Fix login",
  "status":"Open",
  "status_id":1,
  "severity":"Normal",
  "severity_id":2,
  "type":"Bug",
  "type_id":3,
  "priority":"Normal",
  "priority_id":4,
  "modified":"2026-09-28T12:00:00Z",
  "version":3
}]
```

```json
{
  "items":[{"id":456,"ref":7,"project":123,"subject":"Fix login","status":"Open","status_id":1}],
  "page":1,
  "total":null,
  "next_page":null,
  "has_more":null
}
```

```json
{
  "issue":{"id":456,"ref":7,"project":123,"subject":"Fix login","version":3},
  "comments":[{
    "id":"history-entry",
    "comment":"Reproduced locally",
    "created_at":"2026-09-28T12:01:00Z",
    "user":{"name":"Example User"}
  }]
}
```

User-story and metadata results:

```json
[{"id":789,"ref":12,"project":123,"subject":"Ship the fix","status_id":1,"status":"Ready","assigned_to":42,"modified":"2026-09-28T12:02:00Z","milestone":55,"version":7}]
```

```json
{"items":[{"id":10,"project":123,"name":"Terminado","slug":"terminado","order":0,"color":"#cc0000","is_closed":true,"is_archived":false,"wip_limit":0}],"page":1,"total":null,"next_page":null,"has_more":null}
```

Task list results:

```json
{"items":[{"id":203,"ref":17,"project":12,"subject":"Implement saved-search endpoint","status_id":11,"status":"Ready","assigned_to":42,"user_story":102,"milestone":55,"modified":"2026-09-28T12:00:00Z","version":2}],"page":1,"total":null,"next_page":null,"has_more":null}
```

Task detail result:

```json
{"id":203,"ref":17,"project":12,"subject":"Implement saved-search endpoint","description":"**Acceptance:** preserve Markdown and Unicode — ✓","status_id":11,"status":"Ready","user_story":102,"milestone":55,"tags":[["search","#336699"]],"due_date":"2026-10-15","due_date_reason":"Release readiness review","due_date_status":"set","is_blocked":false,"version":2}
```

```json
{"id":102,"ref":18,"project":12,"subject":"Allow saved searches","description":"**Acceptance:** preserve Markdown and Unicode — ✓","status_id":7,"status":"Ready","tags":[["search","#336699"]],"version":4,"origin_issue":{"id":201,"ref":9,"subject":"Saved search"},"epics":[]}
```

```json
{"id":102,"ref":18,"project":12,"subject":"Allow saved searches","description":"Acceptance: saved searches can be reopened.","status_id":7,"status":"Ready","assigned_to":42,"tags":[["search","#336699"]],"milestone":55,"version":4}
```

An update returns the server's authoritative detail, for example:

```json
{"id":102,"ref":18,"project":12,"subject":"Allow saved searches","status_id":7,"status":"Ready","version":5}
```

```json
{"items":[{"id":789,"ref":12,"project":123,"subject":"Ship the fix","status_id":1,"status":"Ready"}],"page":1,"total":null,"next_page":null,"has_more":null}
```

```json
[{"id":1,"name":"Open","slug":"open","is_closed":false}]
[{"id":2,"name":"Bug","slug":"bug","color":"#cc0000"}]
```

## Compatibility notes observed in the current implementation

- List methods request one Taiga page per call. `projectId` and `page` are
  inserted as numeric query values. `member` and project slugs are escaped
  with `Uri.EscapeDataString`; the existing issue and story filters are fixed
  query names assembled by the domain APIs, not arbitrary caller-provided
  query fragments.
- Issue list requests use Taiga's verified `status`, `assigned_to`, `type`,
  `priority`, `severity`, `tags`, and `q` filters. ID and tag collections are
  comma-separated in the wire value and then percent-encoded. The default
  `status__is_closed=false` restriction is omitted when nonempty explicit
  statuses or `includeClosed=true` are selected. Invalid positive-ID/page
  inputs fail before HTTP.
- Current list methods request one page and return bare arrays by default.
  `list_issues` and `list_user_stories` additionally support the opt-in page
  envelope; missing or malformed pagination headers remain explicit `null`
  values rather than being treated as zero totals or a completed result.
- `list_user_stories` maps `statusIds`, `assignedTo`, `milestoneId`,
  `backlogOnly`, `tags`, and `query` to Taiga's allowlisted `status`,
  `assigned_to`, `milestone`, `milestone__isnull`, `tags`, and `q` filters.
  `milestoneId` and `backlogOnly=true` are mutually exclusive. Empty or
  missing status IDs use the automatic open/non-archived restrictions unless
  the corresponding include flag is enabled; nonempty status IDs suppress
  both restrictions. The story list never infers filtering from translated
  status names.
- `list_tasks` maps `statusIds`, `userStoryId`, `milestoneId`, `assignedTo`,
  `tags`, and `query` to Taiga's allowlisted `status`, `user_story`,
  `milestone`, `assigned_to`, `tags`, and `q` filters. With no explicit status
  IDs, `includeClosed=false` sends `status__is_closed=false`; explicit statuses
  or `includeClosed=true` omit that restriction. Task status labels come only
  from inline `status_extra_info.name`; an unavailable label leaves the
  numeric `status_id` intact. Standalone tasks preserve null parent/sprint
  values, and listing makes no parent or detail requests.
- `list_epics` maps `statusIds`, `assignedTo`, `tags`, and `query` to Taiga's
  verified `status`, `assigned_to`, `tags`, and `q` filters. With no explicit
  status IDs, `includeClosed=false` sends `status__is_closed=false`; explicit
  statuses or `includeClosed=true` omit that restriction. Epic status labels
  come only from inline `status_extra_info.name`; an unavailable label leaves
  the numeric `status_id` intact. Listing makes no status-metadata, related
  story, or progress requests.
- `get_epic` requests exactly `epics/{epicId}` and returns one detail object.
  It validates positive `epicId` input and required positive `id`, `ref`, and
  `project` plus nonnegative `version` in the response. It preserves
  Markdown/Unicode descriptions, nullable assignment and color, tags, inline
  status labels, numeric status IDs, and optional server summaries including
  `user_stories_counts`; unknown properties and unavailable summaries are not
  fabricated. It performs no status-metadata, relationship, history, or
  progress reads.
- `get_task` requests exactly `tasks/{taskId}` and returns one detail object.
  It validates positive `taskId` input and required positive `id`, `ref`, and
  `project` plus nonnegative `version` in the response. It preserves Markdown,
  colored tags, nullable assignment/parent/sprint fields, numeric status IDs,
  due-date and blocking fields, and ignores unfamiliar upstream fields. It
  performs no metadata, parent, history, comment, or attachment reads.
- `create_task` maps `userStoryId` to `user_story` and standalone `milestoneId`
  to `milestone`. It validates an optional parent story before POST, omits a
  matching or inherited parent milestone, preserves empty description/tag
  values, and returns the authoritative task detail. No retry follows an
  ambiguous create failure.
- `get_user_story` requests exactly `userstories/{userStoryId}`. It uses the
  returned `status_extra_info.name` when present and otherwise performs one
  project-scoped `userstory-statuses?project=...` lookup; if no usable project
  or label exists, the numeric `status_id` is retained and the label remains
  unknown. It preserves Markdown/Unicode descriptions, nullable assignment and
  sprint fields, empty tag arrays, and the server's `epics`, `origin_issue`, and
  `origin_task` JSON. It does not request comments, tasks, or history.
- Issue and story labels are derived from project metadata calls. Story list
  results additionally preserve `project` and `status_id`, and expose
  `milestone` and `version` only when the list response supplies them. A
  missing list version is not fabricated as zero.
- The public tool serializers use `JsonIgnoreCondition.WhenWritingNull`, so
  null-valued response properties such as an unassigned issue's `assigned_to`
  are omitted from current tool JSON. This response omission is distinct from
  the page envelope, whose missing pagination values are explicit JSON `null`.
- Nullable create/update fields use separate request policies. Create fields
  still omit nulls so project defaults apply. `create_user_story` sends
  `project`, `subject`, and only supplied `description`, `status`,
  `assigned_to`, `tags`, and `milestone` values; `milestoneId` maps to Taiga's
  `milestone`. Empty description strings and empty tag arrays remain explicit.
  It validates positive IDs and a nonblank subject without trimming supplied
  text, lets Taiga validate project membership, and never retries a POST after
  a transport or response-enrichment failure. For `update_issue`, omitted or
  null optional values leave fields unchanged; `description=""` and `tags=[]`
  remain explicit values; and `clearFields=["assigned_to"]` deliberately
  emits JSON `"assigned_to":null` to unassign. Supplying an assignee and
  clearing it in the same call, or naming another clear field, is rejected
  before HTTP.
- `update_issue` requires a nonnegative caller-supplied `version`, sends it
  unchanged in the PATCH body, and does not refresh and retry on a version
  error. An update must select a real field change, an explicit clear, or a
  nonblank comment. Non-success responses retain HTTP status/category and
  allowlisted rejected field names through safe MCP errors. Arbitrary upstream
  text is not echoed; at most 4096 error bytes are read. Writes whose responses
  cannot be mapped report that they may already have applied. Cancellation
  propagates separately.
- The isolated contract suite includes version-related fixtures for both a
  400 field-validation response and a 409 conflict response. These fixtures
  verify propagation of each status; they do not claim that every stale
  version is rejected, because Taiga can accept non-overlapping stale edits.
- Issue history filtering currently omits hidden entries, entries without a
  string comment, and empty comments. The domain APIs and shared MCP wrapper
  now support comment-only PATCH behavior for `issue`, `user_story`, `task`,
  and `epic`: only `comment` and the supplied `version` are written, and the
  returned resource version is parsed without fetching history.
- Authentication is performed against `/auth`, cached in memory per process,
  and attached as `Authorization: Bearer <token>` to Taiga requests. Tests use
  synthetic credentials and a fake `/auth` response; no live credentials are
  required.

## Verified external and package contracts

The following sources were checked on 2026-09-28:

- The [official Taiga REST API documentation](https://docs.taiga.io/api.html)
  documents `x-paginated`, `x-paginated-by`, `x-pagination-count`,
  `x-pagination-current`, `x-pagination-next`, and `x-pagination-prev`, plus
  the `x-disable-pagination` request header. It also documents optimistic
  concurrency through a required version for modifying requests, including the
  possibility that non-overlapping stale changes can be accepted.
- Taiga backend main was pinned for source review at
  [`4d11baef9027f5598f6341d6eb4261de2840688e`](https://github.com/taigaio/taiga-back/tree/4d11baef9027f5598f6341d6eb4261de2840688e),
  the `main` ref observed on the date above. The OCC mixin is at
  [`taiga/projects/occ/mixins.py`](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/occ/mixins.py).
- Task listing was checked against the same pinned backend revision in the
  [TaskViewSet filters](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/api.py#L36-L60)
  and [TaskListSerializer](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/serializers.py#L22-L57).
- Task detail was checked on 2026-09-28 against the pinned [task GET route](https://github.com/taigaio/taiga-doc/blob/7455fd37cb164bbf80198c1517fd0ef414e2a7b9/api/tasks/endpoints.adoc#L191-L199), [detail command](https://raw.githubusercontent.com/taigaio/taiga-doc/7455fd37cb164bbf80198c1517fd0ef414e2a7b9/api/generated/tasks-get-cmd.adoc), and backend [TaskSerializer](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/serializers.py#L59-L73). The backend's task serializer supplies description and the shared task serializer supplies parent/sprint IDs, tags, version, blocking, and due-date fields. This is pinned source evidence, not a deployed-version claim.
- Task creation was checked on 2026-09-28 against the pinned backend [TaskViewSet save and pre-condition logic](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/api.py#L91-L122). The normal `POST /tasks` path copies a parent story's sprint and rejects cross-project or mismatched parent/sprint values. This is pinned source evidence, not a deployed-version claim.
- The story detail route and serializer fields were checked against pinned
  `taiga-doc` revision
  [`7455fd37cb164bbf80198c1517fd0ef414e2a7b9`](https://github.com/taigaio/taiga-doc/blob/7455fd37cb164bbf80198c1517fd0ef414e2a7b9/api/user-stories/endpoints.adoc)
  and the pinned backend serializer at
  [`4d11baef9027f5598f6341d6eb4261de2840688e`](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/userstories/serializers.py).
- The installed C# MCP package is `ModelContextProtocol`
  `0.3.0-preview.4`. Its local package README/XML metadata provides
  `WithStdioServerTransport`, `WithToolsFromAssembly`,
  `McpClientFactory.CreateAsync`, `StdioClientTransport`, `ListToolsAsync`,
  and `CallToolAsync`. The matching SDK tag was observed at
  [`15f8e89ac3aedb2bb4fa9232f6093f092b2ce956`](https://github.com/modelcontextprotocol/csharp-sdk/tree/15f8e89ac3aedb2bb4fa9232f6093f092b2ce956).

## Foundation baseline

Commands run before adding the test harness on 2026-09-28:

| Command | Result |
| --- | --- |
| `dotnet restore` | Passed; packages were already restored. |
| `dotnet build -c Debug` | Blocked by four pre-existing `TaigaMCP.exe` processes locking `bin/Debug/net8.0/TaigaMCP.exe`; the compiler was not reached for a clean apphost copy. A lock-free build property is used during development validation. |
| `dotnet test` | Passed with no test project/tests discovered. |

The foundation fixture conventions are: fake HTTP at the `HttpMessageHandler`
boundary, a queued/route-based response handler that records each request, a
synthetic auth response, and no live endpoint access. Later goals should add
only fixtures that assert their actual serialized request, response mapping,
pagination, or error behavior.

The reusable fixture lives in `tests/TaigaMCP.Tests/FakeHttpMessageHandler.cs`.
It matches method and path, captures headers/body/query strings, and can return
JSON/text responses, response headers, HTTP failures, or transport exceptions.
`TaigaTestClient` registers a synthetic `/auth` route and creates the real
`AuthClient` with synthetic credentials. The focused command is:

```text
dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug
```

If a local TaigaMCP server process holds the normal output files, use a
temporary output directory without stopping that process:

```text
dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug -p:OutputPath=C:\Temp\TaigaMCP-validation\ -p:UseAppHost=false
```

The MCP integration fixture launches the built application with
`StdioClientTransport`, points its configured base URL at a local fake HTTP
listener, and uses `McpClientFactory.CreateAsync` with the installed
`0.3.0-preview.4` SDK. It verifies the complete 11-name `tools/list` result,
the required/optional schema entries, a real `list_projects` `tools/call`, and
that a fake HTTP 500 is returned as a tool result with `IsError=true`. The
fixture also tees the child process's raw STDOUT before the SDK sees it and
validates every nonblank line as a JSON-RPC 2.0 request, notification, or
response. A separate negative test rejects blank lines, plain-text logs, and
JSON values that are not MCP messages. The end-to-end contamination test runs
a temporary copied application behind a launcher that writes a plain-text
startup line; the strict fixture fails before the SDK can accept the session.
A separate test-only stream server probes argument binding for explicit
`false`, an empty array, an explicit null, and a missing required integer; the
probe type is compiled only in the test project.

The original foundation validation on 2026-09-28 used the repository root and
an explicit temporary output directory because pre-existing `TaigaMCP.exe`
processes held the default apphost file:

```text
dotnet restore
dotnet build TaigaMCP.sln -c Debug -p:OutputPath=C:\Temp\TaigaMCP-validation-final\ -p:UseAppHost=false --no-restore
dotnet test TaigaMCP.sln -c Debug -p:OutputPath=C:\Temp\TaigaMCP-validation-final\ -p:UseAppHost=false --no-restore
```

Restore passed; the alternate-output solution build passed with 0 warnings and
the solution test run passed all 8 tests. The default commands were also run
and stopped before compilation/test execution when MSBuild could not replace
the locked default apphost. No server process was stopped, and no generated
`bin/`, `obj/`, `.vs/`, credential, or live Taiga payload was added to the
foundation commits.

The corrected review validation reran the root commands after the output lock
was no longer present:

```text
dotnet restore
dotnet build -c Debug
dotnet test
```

All three commands passed; the Debug build had 0 warnings and the solution
test run passed all 13 tests. The focused strict STDIO run also passed its 5
integration tests, including the expected failure of the contaminated
temporary-copy experiment. The nullable issue contract was verified through
the real `IssueTools.GetIssue` path, with `assigned_to` absent from the public
JSON when the upstream value is null.

Cleanup compatibility: production C# types now live in `TaigaMCP.Api`,
`TaigaMCP.Tools`, and other folder namespaces. The unused aggregate facade is
removed; internal consumers use domain APIs. MCP signatures, defaults, JSON
property names and response omission are unchanged at this stage.

## Input validation and configuration

Positive internal IDs and pages >= 1 are required. Slugs and supplied subjects
must be nonblank. Update versions must be >= 0; an update needs a real change
or nonblank comment. Empty description/tag arrays remain valid. These are
intentional validation changes: invalid calls now fail before contacting Taiga.
`update_issue.subject` is optional and nullable; omit it for other edits.
`clearFields=["assigned_to"]` explicitly unassigns the issue, while a missing
or null `assigned_to` leaves it unchanged. The supplied version is always sent
unchanged and version failures are not retried.
Cancellation is injected by MCP and is not a tool argument.

Credentials must be nonblank. `TAIGA__BASEURL` accepts an absolute HTTP/HTTPS URL
without credentials/query/fragment and normalizes a trailing slash.
`TAIGA__METADATATTLSECONDS` is positive, defaults to 300, and controls metadata
refresh. See [development](development.md) for lifetimes and future contracts.

## Intentional list behavior changes

`list_projects` now defaults to `member=null` (no member filter). To retain the
previous account-specific selection, call `list_projects(member="6")`, or send
`{"member":"6"}` over MCP. Explicit member values remain URL-encoded.
Story lists use Taiga's `status__is_closed=false` and
`status__is_archived=false` by default; nonempty status IDs override both,
and the include flags selectively remove them. `backlogOnly=true` uses
`milestone__isnull=true`, while `milestoneId` selects a sprint. English labels
such as Done/Archived never determine filtering. Issue lists use
`status__is_closed=false` only: unsupported issue archive filtering and
redundant status-exclusion requests were removed. These are behavior
corrections, not behavior-preserving refactoring.
