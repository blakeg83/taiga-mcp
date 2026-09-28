# Development guide

## Verified cleanup baseline (2026-09-28)

Baseline: `f760583` on `goal-00`, clean working tree. Implementation branch:
`codex/development-foundation-cleanup`. Prerequisites are committed in `003fe00`
(strict protocol output) and `b219e39` (nullable response contracts).
Root `dotnet restore`, `dotnet build -c Debug`, and `dotnet test -c Debug`
passed: zero build warnings/errors, 13 tests passed, none skipped. No output
lock workaround was needed. Tests include the contaminated-copy negative
experiment and the real IssueTools omitted-assignee serialization check.

`dotnet --info`: Windows x64; selected SDK 10.0.401, MSBuild 18.9.11;
SDKs 3.1.426, 5.0.303, 5.0.408, 6.0.203, 6.0.321, 6.0.428,
8.0.131, 9.0.318, 10.0.112, 10.0.401 installed. Target remains net8.0.
Application packages: Hosting/Http 9.0.8, ModelContextProtocol 0.3.0-preview.4.
Test packages: Microsoft.NET.Test.Sdk 17.12.0, xunit 2.9.2,
xunit.runner.visualstudio 2.8.2. No version upgrades are planned.

## Layers and intended lifetimes

Program creates the host; Hosting/ServiceCollectionExtensions owns DI and
STDIO registration. Tools own public signatures and JSON responses. Domain
APIs own routes, request payloads and mapping. Models define wire properties.
The cleanup will introduce a shared transport owning HTTP sends, response
checks and JSON reads. AuthClient will remain singleton token state with an
async login/refresh gate; it will use operation-scoped factory clients rather
than retain a client forever. The singleton metadata cache will hold immutable,
expiring snapshots and coalesce loads per metadata kind/project. Domain APIs
will depend on that infrastructure; no aggregate facade is required.

## Compatibility and caller audit

The [tool reference](taiga_tools_reference.md) inventories all 11 current names,
parameter names/defaults and representative JSON. Null response properties are
omitted; request null omission is a separate policy. Step 7 deliberately changes
member default `"6"` to null and removes English-label-based story exclusions.
Until that step the baseline behavior stays unchanged.

`git grep` of tracked source/tests/docs found ITaigaApi/TaigaApi only in their
own declarations, DI registration, AGENTS examples and feature-plan instructions.
The similarly named test class exercises concrete APIs, not the facade. No
actual consumer needs migration. Step 2 will remove the unused registration and
files and revise the plans. Startup paths in README/quickstart point to the root
project's published net8.0 binary; retain that project layout. Integration tests
launch `AppContext.BaseDirectory/TaigaMCP.dll`, so isolated OutputPath builds test
the newly built application. The contamination experiment currently requires
Windows cmd.exe; CI must account for that platform dependency.

Use fake HTTP and synthetic credentials for tests. Never stop running MCP
servers to free build outputs. If locked, use a unique output directory outside
the checkout, for example `dotnet test -c Debug -p:OutputPath=C:\Temp\TaigaMCP-unique\ -p:UseAppHost=false`.

## Step 2: structure and serialization

After baseline commit `c77e1c0`, production classes now use file-scoped
TaigaMCP folder namespaces. Tools inject concrete APIs; the unused aggregate
facade and its DI registration are removed. ToolResponseJson centralizes
response null omission. Request serializers remain independent and unchanged.
IssueDto.Project is init-only, matching other DTO properties; no caller mutates
it. Feature plans now reference domain APIs. `dotnet test -c Debug` passed all
13 tests, including production 11-tool discovery/schema checks, representative
mapping, request version forwarding, and null response omission.

## Step 3: HTTP ownership, cancellation and errors

After `ffeba6b`, domain APIs/cache use TaigaTransport. Callers own requests and
returned JsonDocuments; transport disposes responses/streams, including errors.
Auth retry requests/content are disposed. Cancellation flows from injected MCP
CancellationToken through APIs/cache/auth/send/read; cancellation is not an HTTP
failure. No network/status retries were added (the existing one-401 replay is
retained for Step 4). Writes followed by JSON/mapping/metadata failures warn
that they may have applied; inspect the entity before retrying.

Error processing reads at most 4096 bytes and exposes HTTP status, category and
allowlisted rejected field names/version conflict. It deliberately does not echo
arbitrary upstream validation text, even in recognized fields, because it can
contain credentials or user data. TaigaRequestException retains StatusCode;
ToolErrors converts only those safe messages to the installed McpException API.
Installed 0.3.0-preview.4 XML documents that exception messages may be exposed;
real MCP tests confirm IsError=true and safe 500 details. This is an intentional
error-detail change from the old unbounded PATCH body.

`dotnet build -c Debug`: zero warnings/errors. `dotnet test -c Debug`: 28 passed.
Coverage adds GET/POST/PATCH response disposal, usable owned documents, seven
HTTP error statuses, secret suppression, malformed JSON, pre-cancellation and
write enrichment failure; all production schemas exclude cancellationToken.

## Step 4: authentication and client lifetimes

After `e2f9cc5`, AuthClient publishes an immutable token/refresh pair under an
async gate. Waiting callers recheck state; a delayed 401 reuses a newer token.
Only a received 401 permits one replay; rejected/malformed refresh responses
fall back to login inside the same gate. Network exceptions do not replay writes.
Headers are per request; auth/refresh never attach bearer headers. Replay copies
method, URI, bytes/content headers, request headers, version/policy and options.
AuthClient owns/disposes the gate; auth requests, responses and retries are scoped.
The singleton transport retains IHttpClientFactory, creates/disposes a named
client per operation, and lets the factory rotate pooled handlers. No singleton
captures a factory-created HttpClient.

`dotnet test -c Debug`: 33 passed. Controlled TaskCompletionSource barriers prove
single initial login, concurrent 401 refresh coalescing, later token reuse and
cancelled gate waits. PATCH tests prove refresh rejection/login fallback,
bounded repeated 401, exact body/version/header/options replay, and no replay on
ambiguous network failure. Production STDIO tests remain green.

## Step 5: metadata caching

After `9a2b80c`, metadata is keyed by kind/project with one cancellable load gate
per entry. A short dictionary lock pins active/waiting entries; HTTP runs outside
that lock so unrelated keys load independently. Frozen dictionaries prevent
caller mutation. Injected TimeProvider drives expiry without sleeping in tests.
`TAIGA__METADATATTLSECONDS` sets a positive integer TTL (default 300 seconds);
startup validation rejects zero/negative values. Failed/cancelled loads never
become current values and release their gate for a subsequent attempt. A cancelled
waiter does not cancel another caller's load. Idle entries are capped at 256;
access/completion sweeps expired idle entries and evicts oldest idle entries over
that cap. Active entries remain pinned; at rest retained entries are bounded even
when no later traffic triggers expiry cleanup.

`dotnet test -c Debug`: 38 passed. Cache tests cover hits, exact-boundary expiry,
immutable old snapshots, coalescing, kind/project isolation, loader and waiter
cancellation, failure recovery and capacity eviction. Existing fake-HTTP issue
read/write and production MCP tests passed.

## Configuration and tool validation

Set `TAIGA__USERNAME`, `TAIGA__PASSWORD`, optionally `TAIGA__BASEURL` and
`TAIGA__METADATATTLSECONDS` (positive integer; default 300). Credentials must be
nonblank. Base URL must be absolute HTTP/HTTPS with no embedded credentials,
query or fragment; a trailing slash is normalized. Self-hosted HTTP is supported.
Host defaults bind double-underscore environment keys to the Taiga section;
command-line configuration overrides environment values. The extra `TAIGA_`
provider was redundant for these documented keys and is removed.

IDs must be positive, pages start at one, slugs/subjects must be nonblank, update
versions are nonnegative. An update must contain a change or nonblank comment.
Optional null values leave defaults/fields unchanged; empty descriptions and
empty tag arrays are valid explicit values. These validation errors now arrive
as safe MCP errors before HTTP requests. `subject` remains a required nullable
update parameter for schema compatibility; pass null when changing other fields.

## Future feature conventions (not implemented by cleanup)

Request one page per call; build allowlisted, encoded queries. Unknown pagination
headers remain unknown, never fabricated zero/false. Current list results remain
arrays. Future page envelopes must preserve explicit null metadata. Updates use
caller-supplied versions without retry; planned clearFields uses presence-aware
payloads and is separate from nullable omission. No new page envelopes, clearing
parameters or tools are introduced here. See the reconciled batch contracts.

Step 6 follows `59ca19f`. `dotnet test -c Debug --filter FullyQualifiedName~ConfigurationTests`
passed 12 checks before removing redundant wiring, proving the same documented
binding/CLI precedence with and without it. Full `dotnet test -c Debug` passed
65 tests afterwards: 14 invalid-input/no-HTTP cases plus configuration and real
MCP calls of all 11 production tools, descriptions/schema, explicit null, omitted
create fields, empty string/array, version zero, validation errors and null output.

## Step 7: verified list behavior changes

After `8a2b5ac`, member defaults to null; pass `member="6"` to preserve the old
selection. Story filtering uses server flags only, with no English-label
exclusions. Issue filtering retains only status__is_closed=false, dropping the
unsupported archival parameter and redundant status lookup/exclusions.

Verified 2026-09-28 against official taiga-back revision
`4d11baef9027f5598f6341d6eb4261de2840688e` (not a claimed deployed version):

- [IssueViewSet filter_fields](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/issues/api.py#L58-L61)
  supports project and status__is_closed, not status__is_archived.
- [UserStoryViewSet filter_fields](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/userstories/api.py#L69-L75)
  supports both status flags.
- [Status models](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/models.py#L546-L556)
  define independent story closed/archive booleans; IssueStatus has only is_closed
  (lines 750-758). Names are labels, not semantics.

`dotnet test -c Debug`: 70 passed. Fake routes assert exact queries and simulate
flag filtering for open Done/Archived and localized closed/archive statuses;
returned labels remain mapped. Issue tests assert no redundant status fetch or
archive query. MCP tests exercise omitted member and explicit legacy member 6;
contract tests verify encoded member values. No live Taiga writes were performed.
