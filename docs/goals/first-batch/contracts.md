# Shared contracts for the first batch

These are proposed implementation decisions for this batch, not descriptions of current behavior. Goal 00 verifies that the installed MCP SDK can represent them; evidence-driven adjustments must update this file and affected goals before dependent work.

## Compatibility and layering

- Keep every existing MCP name, parameter name, default that matters to callers, and response shape unless an additive opt-in is specified below.
- Existing list tools return arrays by default. Add includePageInfo=false; when true, return the page envelope below. New list tools always return the envelope.
- Existing issue response status/type/priority/severity properties are labels. Keep them and add status_id/type_id/priority_id/severity_id, rather than changing their types. Story status labels likewise remain compatible.
- New resource DTOs use explicit JSON property names: id, ref, project, subject, status_id, status, assigned_to, and modified. Detail DTOs include description and version. Nullable fields remain nullable; never manufacture ID/version zero from absent required data.
- Reuse domain APIs directly in tools. Keep ITaigaApi/TaigaApi's existing methods source-compatible through forwarding overloads where needed; do not expand that legacy facade for every new tool without an actual caller.
- Use AuthClient and the configured HttpClient. New TaskApi/EpicApi registrations belong in Hosting/ServiceCollectionExtensions.cs; assembly tool discovery is already configured.
- Each goal owns its function-specific DTOs/tests. Share only proven reusable query, page, patch, and error behavior.

## Listing and pagination

- Require positive project/entity IDs and page >= 1. Request one page per call; never silently disable pagination or fetch every page.
- Public filter names must map through an allowlist to actual server query names. URL-encode values. Do not forward arbitrary query fragments.
- Default includeClosed=false. When explicit statusIds are supplied, those statuses override the automatic open-only restriction; includeClosed=true with no statusIds removes that restriction. State this in tool descriptions.
- Stories additionally expose includeArchived=false. Explicit statusIds override the automatic archived restriction. Use status metadata/verified API flags, not English status names.
- Do not assume issues, tasks, and epics support story-style archival filters. Reject unsupported filters or omit them from the public schema.
- Page envelope: { items: [...], page: 1, total: null, next_page: null, has_more: null }. Missing pagination headers mean unknown, not an empty collection or proof of completion. Preserve explicit JSON nulls in page metadata.
- Parse verified Taiga pagination headers. Do not forward credentials to a next-page URL; expose a page number and reconstruct requests against the configured base URL. Ignore malformed/untrusted pagination URLs safely.
- Existing array mode and opt-in envelope mode must share the same returned items and filters.
- The batch omits arbitrary sorting, date ranges, and automatic all-page aggregation.

## Creates and updates

- Create commands require nonblank subject and positive projectId. Omitted optional fields stay omitted so project defaults apply. Do not auto-create workflow options.
- Update commands require an explicit nonnegative version and at least one real change or nonblank comment. Send exactly the caller-supplied version; no automatic refresh-and-retry.
- Public update parameters are optional typed fields plus clearFields: string[]. Omission/null of a normal nullable argument means leave unchanged. Explicit clearFields is the way to request a JSON null. This preserves existing update_issue behavior.
- clearFields accepts only the fields listed in the goal. Reject unsupported clear names and a field that is both set and cleared. Internally serialize a presence-aware object/dictionary so explicit JSON null survives.
- Description is cleared with description=""; tags are cleared with tags=[]. False and zero must not be dropped just because they are default-valued. Required references/statuses cannot be cleared.
- Status inputs are internal IDs. The server enforces membership/project permissions; retain its useful validation details.
- Dates, custom attributes, multiple assignees, arbitrary external references, and project moves are deferred unless explicitly included in a goal.
- Return the server's authoritative result and version, not a fabricated merged object. A successful write followed by a failed read/mapping must be reported as potentially applied, not safe to retry.

## Errors and comments

- Check HTTP success on every request. Preserve status and safe validation details without exposing tokens, credentials, or unbounded response dumps.
- Distinguish invalid input, authentication/permission denial, missing resource, server validation/version rejection, throttling, and transport failure. Integrate with the MCP package's actual error response mechanism.
- Taiga version rejection is not guaranteed to be HTTP 409. Inspect field errors as well; tests should include a version-related 400 and a 409 response. Some server versions can accept stale versions when modified fields do not overlap.
- Do not retry creates, updates, links, or comments automatically after an ambiguous transport failure; this can duplicate work.
- Comments are submitted by PATCHing the resource with version and comment. Do not POST a new history entry or invent its ID from the updated resource response.
- The dedicated comment command returns kind, id, returned version, and comment_submitted=true only after a successful update. That flag means submission succeeded, not that a history-entry identifier was obtained.

Concurrency source: [Taiga OCC mixin](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/occ/mixins.py). API verification starting point: [official REST API](https://docs.taiga.io/api.html). Pin the actual reference used in the implementation evidence.

## Foundation verification notes

The installed `ModelContextProtocol` `0.3.0-preview.4` SDK was verified with
the test project on 2026-09-28. A successful `CallToolAsync` response can have
`CallToolResult.IsError == null`; a tool execution failure is represented by a
result with `IsError == true` and text content. The SDK's generated schema
omits the `required` property when no parameters are required. Defaults and
nullable parameters therefore need runtime call tests in addition to schema
inspection. The test-only probe confirmed that explicit `false`, empty arrays,
and explicit nulls survive binding, while omitting a required integer produces
a tool failure. The production STDIO fixture now tees raw child STDOUT before
the SDK sees it and validates every emitted line as a JSON-RPC 2.0 message;
negative tests reject blank, plain-text, and non-message JSON lines, and a
temporary contaminated application copy fails the end-to-end session.
