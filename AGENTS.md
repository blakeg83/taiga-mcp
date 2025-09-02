# Repository Guidelines

## Project Structure & Modules
- Source: `Program.cs` hosts the MCP server, DI, and Taiga API wrapper.
- Project files: `TaigaMCP.csproj`, `TaigaMCP.sln`.
- Build artifacts: `bin/` and `obj/` (auto‑generated; do not commit).
- Tools are defined in `TaigaTools` via `[McpServerTool]` attributes.

## Build, Run, and Development
- Restore/build: `dotnet restore && dotnet build -c Debug`
- Run locally: `TAIGA_USERNAME=you TAIGA_PASSWORD=secret dotnet run`
  - Optional: `TAIGA_BASE_URL=https://api.taiga.io/api/v1/` (default shown).
- Clean: `dotnet clean`
- Format (if installed): `dotnet format` to enforce C# style.

## Coding Style & Naming
- C#: 4‑space indentation, UTF‑8, trailing newline.
- Types/methods: PascalCase (`TaigaApi`, `ListProjectsAsync`). Locals/params: camelCase.
- Private fields: `_camelCase`. Constants: `PascalCase`.
- MCP tool names: snake_case in `[McpServerTool(Name = "list_projects")]`.
- Prefer DI over `new`: request services via constructors.

## Testing Guidelines
- Framework: xUnit recommended in a separate test project (e.g., `tests/TaigaMCP.Tests`).
- Run tests: `dotnet test` from repo root once tests exist.
- Name tests clearly: `MethodName_Scenario_ExpectedResult`.
- For Taiga calls, mock HTTP using `HttpMessageHandler` or wrap via `TaigaApi` interface for isolation.

## Commit & Pull Requests
- Commits: short imperative subject (e.g., `Add project and issue resolution methods`).
- PRs: include summary, linked issues, repro/usage examples, and screenshots/logs when relevant.
- Keep changes focused; include notes on configuration/env vars if behavior depends on them.

## Security & Configuration
- Credentials come from env vars: `TAIGA_USERNAME`, `TAIGA_PASSWORD`; never commit secrets.
- Tokens are cached in memory per process; restart to clear.
- Validate network calls with `EnsureSuccessStatusCode()` and handle pagination where applicable.

## Agent‑Specific Notes
- Add a new tool by creating a method on `TaigaTools` and annotate with `[McpServerTool(Name = "your_tool")]`. Use `TaigaApi` via DI for Taiga access and return JSON strings.
