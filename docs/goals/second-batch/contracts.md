# Second-batch implementation contracts

Status: proposed interfaces for 12 unimplemented tools. Existing 23-tool behavior
remains authoritative in the [tool reference](../../taiga_tools_reference.md).
The conventions below are deliberate design choices unless identified as source facts.

## Interfaces, identity, and response shapes

- Internal IDs and page numbers are positive; update versions are nonnegative.
  A displayed #ref is a project-local number and is not an internal ID.
- Reuse WorkItemKind (issue, user_story, task, epic). Validate undefined enum values
  before HTTP. History routes use userstory, not user_story; resource routes use
  userstories. Keep both mappings allowlisted and explicit.
- resolve_work_item returns a small identity receipt, not a union of full detail
  shapes: kind, id, ref, project, optional subject/version. Call the appropriate
  existing detail tool before a later versioned edit.
- New paged list tools return { items, page, total, next_page, has_more } through
  ToolResponseJson.SerializePage. DTO nulls are omitted; unknown page metadata
  remains literal null. Existing arrays and opt-in envelope defaults do not change.
- Status discovery includes all statuses, including closed and story-archived
  options. Never infer semantics from names, sort/filter by English labels, or
  invent an epic/task archival field. IDs are project- and resource-kind-specific.
- Missing optional fields remain absent; malformed required IDs/data produce safe
  errors. Clone JsonElement values before disposing their owning document.

## Pagination and source counts

Each list makes one page request; never send x-disable-pagination or fetch all pages.
Reuse TaigaPagination for headers and validate any body pagination shape against
the pinned API serializer. Do not follow arbitrary server URLs; expose a verified
next-page number and reconstruct requests on the configured API base.

History has its own viewset/pagination path. Explicitly send page even for page 1.
If a supported deployment returns a count/next/results body, handle it in the
history parser with fixtures; do not assume all resources have that shape or
change unrelated list behavior. Prefer valid header metadata; use verified body
metadata only when headers are absent, and treat malformed/conflicting metadata
as unknown. Only explicit valid evidence can establish the final page.

Comment/history reads may omit hidden/deleted content from a page. Their envelope's
total, next_page, and has_more describe the upstream selected history stream,
not the number of visible items after local filtering. Document that an empty
visible page can still have a next page. Do not scan later pages to fill it.

Membership pages include pending/inactive membership records when returned.
Keep membership ID distinct from user ID; absent user_id is not assignable.
Do not label any membership an authorization guarantee for a future write.

## Architecture

Extend ProjectApi for membership reads, UserStoryApi/TaskApi/EpicApi for their
status lists, and EpicApi for epic edits/relationships. A small UserApi owns
users/me, WorkItemResolverApi owns by_ref routing, SprintApi owns milestone
listing, and WorkItemHistoryApi owns shared comment/history reads. These are
proposed responsibilities, not a requirement to invent new abstraction layers.

All APIs use TaigaTransport; Tools use injected concrete APIs plus ToolErrors and
ToolResponseJson. Register new dependencies in Hosting/ServiceCollectionExtensions.cs.
Propagate CancellationToken through every async call. Preserve scoped client
ownership, auth gating, bounded error fields, and metadata cache semantics.
No new caches are needed for this batch's metadata discovery; do not pass a
one-page result into an existing cache as if it were complete.

Existing TaigaTransport JSON-read methods require a response body. Unlinking needs
an additional no-content send path for HTTP 204. Add it in goal 10, sharing existing
authentication/status/disposal rules without making every empty JSON read succeed.

## Epic updates and unlinking

update_epic mirrors current updates: optional typed fields plus clearFields.
Only assigned_to is clearable here. Omitted/null arguments leave fields unchanged;
description="" and tags=[] are explicit clears. Reject a set/clear collision.
Forward the exact supplied version and return mapped server detail. No implicit
changes to stories, project membership, linked-story order, or workflow options.

unlink_user_story_from_epic deletes only the nested relationship identified by
epicId and userStoryId. A confirmed HTTP 204 returns { epic_id, user_story_id,
removed: true }. Do not issue DELETE against the story or epic.

A 404 is an error, not proof of a prior successful unlink: it can conceal a missing
or inaccessible parent. Thus a repeated unlink after removal may fail with 404;
this deliberately differs from link_user_story_to_epic's already-linked handling.
Do not add catch-all idempotency or retry DELETE after an ambiguous transport error.

## History and comment visibility

list_work_item_comments uses history/<kind>/<id>?type=comment&page=N and returns
visible nonblank comments, string history-entry IDs, author identity, created
timestamp, and available edit timestamp. Preserve original Markdown/text.

get_work_item_history reads the same resource without type=comment and returns
visible entries with id/type/created_at/user plus optional diff, values_diff,
comment, edit/delete timestamps, and is_snapshot. The raw source type and diff
remain structured data; do not invent normalized English event names.

Omit entries marked is_hidden. Suppress deleted comment bodies when either
delete_comment_date or delete_comment_user is set; in history, preserve safe
non-comment activity and a comment_deleted flag if applicable. Filter comment
fields from diff/values_diff when the comment is deleted; do not expose raw
snapshot, values, comment_html, or comment_versions as a back door to deleted
text. If safe separation cannot be established, omit that entry and document it.
Unknown nested change structures must not be assumed safe carriers of deleted
comment content. No includeHidden option is in scope.

Existing get_issue keeps its current response shape and comment behavior; the new
shared reader must not silently change that interface. History-entry IDs are
opaque strings, unlike numeric work-item IDs. Exact historical versions and
deleted comment restoration/editing are future work.

## Compatibility and batch success

Adding all 12 tools should bring the count from 23 to 35, absent separately
authorized changes. Each goal updates the expected discovered tool set when
its tool ships; do not require future tools in today's passing suite.

End-to-end fake-HTTP flows must use returned IDs:
current user/members -> assignment; reference -> detail -> update/comment;
status list -> story/task/epic transition; sprint list -> story placement;
epic relationship list -> unlink; comment submission -> comments/history read.
Individual calls do not imply a multi-call transaction.
