# Repository Guidelines

## Structure and responsibilities

- One net8.0 application project at the root and one xUnit project in `tests/TaigaMCP.Tests`.
- `Program.cs` creates the host. `Hosting/ServiceCollectionExtensions.cs` owns options, DI and MCP registration.
- `Tools/` contains `[McpServerToolType]` classes with snake_case `[McpServerTool]` names and descriptions. Tools inject concrete domain APIs and use ToolResponseJson/ToolErrors.
- `Api/` owns routes/payloads/mapping; TaigaTransport owns HTTP response disposal, bounded safe errors and JSON reads. Callers own requests and returned JsonDocuments.
- AuthClient is singleton gated token state; transport obtains and disposes a named factory client per operation. Never mutate bearer headers on a shared client.
- `Caching/IssueMetadataCache.cs` coalesces per-key loads, returns frozen snapshots and enforces TTL/idle eviction. `Models/` holds DTOs; `Config/` holds options.
- Do not commit generated `bin/`, `obj/`, `.vs/` or output artifacts.

## Build and test

`global.json` selects SDK 10.0.401 with latestPatch roll-forward. Install a .NET 8 runtime to run the net8.0 app/tests; the SDK pin does not upgrade the target or packages.

```powershell
dotnet restore
dotnet build -c Debug
dotnet test -c Debug
dotnet build -c Release --no-restore
dotnet test -c Release --no-build --no-restore
```

Tests use synthetic credentials, fake HTTP and real MCP protocol sessions. Windows is currently required by the cmd.exe contamination test; CI uses Windows. Never modify live Taiga data for tests. Use controlled barriers/TimeProvider instead of timing sleeps for concurrency/expiry tests.

For development runs, supply credentials through the process environment:

```powershell
$env:TAIGA__USERNAME = 'your-user'
$env:TAIGA__PASSWORD = 'your-password'
$env:TAIGA__BASEURL = 'https://api.taiga.io/api/v1/'
dotnet run --no-build
```

Do not stop running servers to release output locks. Use a unique external output:
`dotnet test -c Debug -p:OutputPath=C:\Temp\TaigaMCP-unique\ -p:UseAppHost=false`.
Keep long-running published servers in a separate, versioned publish directory.
Integration tests load the newly built assembly from the test output directory.

## Conventions

- Four-space C#, UTF-8, final newline, file-scoped `TaigaMCP.<Folder>` namespaces. Follow `.editorconfig`; avoid unrelated formatting churn.
- PascalCase types/methods, camelCase locals/parameters, `_camelCase` fields. DTO properties use explicit snake_case JSON attributes and init accessors.
- Add tools to `Tools/`, inject a concrete API, and pass injected CancellationToken through every async layer. Never expose it as a user argument.
- Preserve existing names/parameter names/response shapes. Tool responses omit null properties. Upstream request serialization is separate; null means omission, empty strings/arrays remain explicit.
- Validate positive IDs/pages, nonblank required text and nonnegative versions before HTTP. Updates require a real change or nonblank comment.
- Only a received 401 permits one authentication replay. Never retry ambiguous writes or automatically refresh entity versions.
- New list features request one page; use allowlisted encoded queries and preserve unknown page metadata. Explicit clearing/page envelopes remain planned; see batch contracts.

## Security and configuration

Credentials: `TAIGA__USERNAME`, `TAIGA__PASSWORD` (nonblank; never commit secrets).
Optional `TAIGA__BASEURL` accepts HTTP/HTTPS without credentials/query/fragment.
Optional `TAIGA__METADATATTLSECONDS` is positive, default 300. Startup validates
these options. Tokens live only in memory. Safe errors expose status/category
and allowlisted rejected fields, never raw bodies. Logs belong on stderr.

## Commits and PRs

Use short imperative subjects, focused changes, relevant validation and migration
notes. Follow each assigned goal's ordered commit cycle. Local implementation
does not authorize push/PR/merge or live writes. Read [development](docs/development.md)
and [tool reference](docs/taiga_tools_reference.md) before changing contracts.
