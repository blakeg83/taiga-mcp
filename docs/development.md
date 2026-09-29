# Development guide

## Current state (2026-09-28)

All 15 selected first-batch functions are implemented within their documented
scope. The server exposes 31 tools; see the [tool reference](taiga_tools_reference.md)
for exact contracts and the [completed-batch summary](goals/first-batch/README.md)
for source/test pointers. The [second batch](goals/second-batch/README.md) has
delivered `get_current_user`, `list_project_members`, `resolve_work_item`,
`list_user_story_statuses`, `list_task_statuses`, `list_epic_statuses`,
`list_sprints`, and `update_epic`; goals 09–12 remain implementation plans.

Tools inject concrete domain APIs and use ToolResponseJson/ToolErrors.
TaigaTransport owns responses and obtains a factory client per operation;
callers own requests and returned documents. AuthClient is gated singleton
token state, and issue metadata uses immutable TTL-controlled snapshots.
Cancellation flows through every asynchronous layer. No aggregate API facade
is present. A received 401 permits one authentication replay; ambiguous writes
and entity version conflicts are not automatically retried.

Issue/story lists preserve legacy arrays and offer opt-in page envelopes;
task/epic lists always use envelopes. Page metadata preserves unknown nulls,
while resource DTOs omit null properties. Versioned updates support explicit
assignee clearing; story updates can also clear the milestone. See current
reference contracts before extending these features.

The sections below retain the historical foundation cleanup record. Their
11-tool counts, test totals, future-tense descriptions, and step-specific
limitations describe that earlier work, not the current release. This
documentation reconciliation checked source, schemas described in the reference,
and links; it did not rerun application tests or validate a live deployment.

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

The [tool reference](taiga_tools_reference.md) inventories all current names,
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
as safe MCP errors before HTTP requests. `update_issue.subject` is optional and
nullable; omit it when changing other fields. Use
`clearFields=["assigned_to"]` to explicitly unassign; ordinary null omission
leaves the assignee unchanged.

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

## Step 8: guardrails and final verification (2026-09-28)

Previous step: `c94eeb7`. `.editorconfig` defines four-space C#, UTF-8/final
newlines and file-scoped namespaces. Formatting was restricted to C# files
changed by this cleanup. `global.json` pins the baseline SDK 10.0.401 with
latestPatch and no prereleases; target net8.0 and all package versions remain
unchanged. CI installs that SDK plus .NET 8 (runtime needed by app/tests), uses
Windows for the existing cmd.exe contamination fixture, and grants contents:read
only. `git ls-remote --symref origin HEAD` confirmed refs/heads/master, matching
pull-request and master-push workflow triggers. Remote CI has not run here.

The initial attempt to use installed SDK 8.0.131 triggered automatic mobile
workload repair before tests: several local workload packages were installed by
dotnet, and the command was interrupted during the next download. No repository
packages/targets were changed. The final pin uses the already-working baseline
SDK instead. The SDK-8 attempted run is not counted as a passing check.

Final audit added a real MCP notifications/cancelled test reaching an in-flight
HTTP send through ProjectTools, and tests for the 4096-byte error-body bound,
response stream failures and post-write cancellation uncertainty. The installed
SDK client's local token cancellation did not transmit a server cancellation in
an initial experiment (that test timed out); the final test explicitly emits the
protocol cancellation notification and passes. Clients must send that MCP
notification to cancel server work. Cancellation stays OperationCanceledException;
after successful writes its message warns of potentially applied changes.
Auth refresh now also rejects non-object JSON cleanly. These small error-path
fixes were discovered during the final definition-of-done audit.

Final commands/results with SDK 10.0.401:

| Command | Result |
| --- | --- |
| `dotnet format whitespace TaigaMCP.sln --no-restore --include <changed C# files>` | Applied only within cleanup-touched files. |
| `dotnet format whitespace TaigaMCP.sln --no-restore --verify-no-changes --include <changed C# files>` | Passed. File list: `git diff --name-only f760583 -- '*.cs'` filtered to existing paths, plus untracked new C# files before commit. |
| `dotnet restore` | Passed. |
| `dotnet build -c Debug` | Passed; 0 warnings/errors. |
| `dotnet test -c Debug` | 74 passed, 0 failed/skipped. |
| `dotnet build -c Release --no-restore` | Passed; 0 warnings/errors. |
| `dotnet test -c Release --no-build --no-restore` | 74 passed, 0 failed/skipped. |
| `git diff --check` | Passed. |

No output locks/workarounds were needed for the final run. Final tests cover all
11 production tools, strict clean/contaminated STDOUT, null omission, request
payloads, safe HTTP statuses, transport disposal/bounds/cancellation, auth races
and bounded replay, cache expiry/coalescing/isolation/recovery/eviction, input
validation, config precedence and changed filters/defaults. This is fake-HTTP
and local MCP validation, not live Taiga or observed remote CI success.

Definition-of-done audit: one application/one test project retained; no facade,
new tools, envelopes, clearFields, package upgrades or structural frameworks.
All eight steps have separate local commits, with no push/PR/merge or live writes.
Diff/history review found no added generated output, temporary contamination,
real credentials or unrelated edits. SDK first-run side effects are documented
above. The Windows-only contamination test remains a portability limitation.
