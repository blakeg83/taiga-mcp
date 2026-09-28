# Goal 00: establish shared implementation and verification foundations

Status: planned.

## Objective

Give the 15 function goals a minimal reusable test harness, documented contracts, and a reliable way to verify MCP discovery and invocation without live Taiga credentials.

## Scope and prerequisites

Prerequisites: none. Read [execution instructions](execution-instructions.md) and [contracts](contracts.md). This goal adds no public Taiga tools and does not redesign authentication or upgrade the MCP SDK.

Repository facts: .NET 8; ModelContextProtocol 0.3.0-preview.4; no test project in the current solution; the main project already excludes tests/**/*.cs from compilation. Tools use concrete domain APIs. AuthClient performs an HTTP auth request and caches a token; fake it at the HTTP boundary.

## Step 1: establish a baseline and record contracts

- [x] Inspect AGENTS.md, git status, project/solution, domain APIs, DI, and all current tool names. Preserve the untracked command inventory if still present.
- [x] Run restore and Debug build; record results and whether dotnet test has any tests to execute.
- [x] Inventory the 11 existing public tool schemas and array/issue-detail response shapes; record representative sanitized examples.
- [x] Verify pagination headers, filter encodings, update errors, and installed MCP invocation APIs using primary sources/package metadata; record source versions.
- [x] Create docs/taiga_tools_reference.md with a clear implemented-versus-planned distinction and link it from README.md.
- [x] Update this goal's execution record and commit this step as: Document batch contracts and baseline.

## Step 2: add isolated HTTP contract testing

- [x] Create tests/TaigaMCP.Tests targeting net8.0 with xUnit and a reference to the application; add it to TaigaMCP.sln. Reuse the existing application test-file exclusion.
- [x] Add a queue/route-based fake HttpMessageHandler that captures method, URI, headers, and body and can return headers, JSON, failures, or transport exceptions.
- [x] Construct real domain APIs with a fake HTTP client and AuthClient configured with synthetic credentials; return a synthetic token from /auth.
- [x] Add meaningful baseline tests for issue comment filtering, issue version forwarding, story list mapping, and bearer attachment. Avoid testing only that the fake itself returns queued data.
- [x] Run the tests and build; document commands and fixture conventions in the tool reference and this goal.
- [x] Commit this step as: Add isolated Taiga API contract tests.

## Step 3: prove public schema and invocation behavior

- [ ] Add an integration fixture using the installed MCP SDK or STDIO protocol with a fake Taiga endpoint; verify tools/list contains all existing tool names.
- [ ] Invoke an existing read tool through MCP and assert its returned text parses as the expected JSON shape.
- [ ] Prove argument binding for optional values, empty arrays, explicit false, and required integers using existing tools where possible and a test-only tool for missing cases; do not ship a probe tool.
- [ ] Verify protocol output stays clean and a failed HTTP request is represented as a tool failure.
- [ ] Document the chosen test approach, schema/null limitations, and any necessary changes to contracts.md; run focused integration tests.
- [ ] Commit this step as: Verify MCP discovery and argument binding.

## Step 4: finalize reusable conventions and handoff

- [ ] Add only small shared helpers justified by tests: page metadata parsing/query encoding can be introduced here or owned by goal 01; do not scaffold unused domain APIs.
- [ ] Add version-error fixtures covering 400 field validation and 409 without asserting all stale versions are rejected.
- [ ] Run root restore, Debug build, and tests; confirm no live endpoint or credentials are required.
- [ ] Update quickstart version-conflict guidance, document how later goals add fixtures, and record final evidence.
- [ ] Review tracked files for generated artifacts/secrets and confirm the solution discovers the tests.
- [ ] Commit this step as: Finalize batch verification foundations.

## Definition of done

- [ ] The solution contains a runnable isolated test project and fake HTTP fixtures.
- [ ] Current 11 tools pass compatibility/discovery checks; at least one is invoked through MCP.
- [ ] Optional argument and error behavior are verified with the installed SDK.
- [ ] Documentation and shared contracts accurately distinguish decisions from deployed behavior.
- [ ] All four steps are committed and validated; root build/tests pass.

## Execution record

| Step | Status | Evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | `docs/taiga_tools_reference.md`; README link; inventory distinction; baseline and source versions recorded above. | `8a2f57d` — Document batch contracts and baseline |
| 2 | Complete | `tests/TaigaMCP.Tests`; solution registration; fake HTTP fixture; four focused contract tests; fixture commands documented in the tool reference. | Add isolated Taiga API contract tests |
| 3 | Not started | — | — |
| 4 | Not started | — | — |

Source/date: official Taiga REST API documentation and Taiga backend `main` at `4d11baef9027f5598f6341d6eb4261de2840688e`, plus installed ModelContextProtocol `0.3.0-preview.4` package metadata and SDK tag `15f8e89ac3aedb2bb4fa9232f6093f092b2ce956`, checked 2026-09-28.

Baseline: restore passed; the initial Debug build was blocked by four pre-existing server processes holding the apphost executable; `dotnet test` passed with no tests discovered. Development builds use `-p:UseAppHost=false` while those processes remain.

Deviation: the current source uses concrete domain APIs and bare-array list results, so this foundation records the compatibility gap rather than changing public behavior before the function-specific goals. Step 2 validation passed with 4 tests using a temporary output directory because the normal app output is held by pre-existing TaigaMCP processes. Remaining work is the SDK integration proof and final reusable verification conventions.
