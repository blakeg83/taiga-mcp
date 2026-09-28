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
