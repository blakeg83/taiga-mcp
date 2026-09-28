# Goal 00 follow-up: fix foundation review findings

Status: in progress; Step 1 is complete and Step 2 remains.

## Objective and scope

Address the two findings from [PR #31](https://github.com/blakeg83/taiga-mcp/pull/31), reviewed at commit `e6e72f94305f8f29850ed43bbd7764172d87129a`: prove that production STDOUT contains only MCP protocol messages, and correct the documented representation of absent nullable issue fields.

Read [AGENTS.md](../../../AGENTS.md), [execution instructions](execution-instructions.md), [shared contracts](contracts.md), and [goal 00](00-foundation.md). Follow the per-step validation, documentation, and commit cycle. Preserve unrelated changes. This document is an assignment for later execution, not authorization to create another chat, push, merge, or modify live Taiga data.

Keep the installed MCP SDK and production tool behavior unchanged. Do not introduce a production probe tool or logging switch just for testing. Use synthetic credentials and fake HTTP only.

## Review evidence

- **P2: STDOUT cleanliness is not asserted.** `McpIntegrationTests` successfully calls the server and parses the returned content, but the installed SDK catches malformed JSON lines and continues. A temporary copy with `Console.WriteLine("REVIEW: non-JSON stdout contamination")` before host creation still passed the integration test. See the pinned SDK's [StreamClientSessionTransport.ProcessMessageAsync](https://github.com/modelcontextprotocol/csharp-sdk/blob/15f8e89ac3aedb2bb4fa9232f6093f092b2ce956/src/ModelContextProtocol.Core/Client/StreamClientSessionTransport.cs#L155-L179). Successful invocation therefore does not prove clean STDOUT.
- **P3: the issue JSON example misstates null behavior.** `docs/taiga_tools_reference.md` includes `assigned_to: null`, while `IssueTools` serializes with `JsonIgnoreCondition.WhenWritingNull`. An unassigned issue omits this property. Preserve that behavior and correct the example.
- Review validation: all 8 tests passed with `dotnet test -c Release`. Debug validation with `UseAppHost=false` was blocked by running server processes locking `bin/Debug/net8.0/TaigaMCP.dll`.

## Step 1: enforce clean production STDOUT

- [x] Inspect the installed SDK transport APIs and existing production integration fixture before choosing the smallest supported approach.
- [x] Capture the production child process's raw STDOUT and assert that every emitted line is a valid MCP JSON-RPC message; do not rely solely on successful tool calls or parsing tool-result text. A stream wrapper that observes bytes before forwarding them to the SDK, or a small strict STDIO fixture, is acceptable. If using SDK diagnostics instead, demonstrate that the assertion rejects non-protocol output, including blank lines and valid JSON that is not a protocol message.
- [x] Continue testing actual production discovery, read invocation, fake upstream failure, and bearer authentication. Keep stderr separate and allow normal diagnostics there.
- [x] Add meaningful negative coverage showing that the same validation rejects a plain-text log line and a JSON value that is not an MCP message. Verify the end-to-end fixture fails when startup STDOUT is deliberately contaminated in a temporary copy, then restore/remove the temporary mutation. The committed production source must remain unchanged.
- [x] Ensure child processes and streams are disposed on assertion failure; bound protocol waits so regressions cannot hang the test run indefinitely.
- [x] Correct the STDOUT verification claims in `contracts.md`, `docs/taiga_tools_reference.md`, and goal 00's execution evidence to describe the actual new check.
- [x] Run focused integration tests and record both the clean-server pass and contaminated-server failure.
- [x] Commit as: `Assert clean MCP protocol output`.

## Step 2: correct null-response documentation and finalize

- [ ] Remove `assigned_to: null` from the unassigned-issue example in `docs/taiga_tools_reference.md`; explain that null-valued response properties are omitted under the current tool serializers.
- [ ] Clearly distinguish current response omission from the planned page envelope's explicit-null metadata and from request-side clearing semantics. Do not change serializer settings to fit the example.
- [ ] Check the other representative examples against the existing DTOs and tool serializers, correcting any related null-shape inconsistencies.
- [ ] Verify a representative unassigned issue through the real `IssueTools` serialization path with fake HTTP, asserting that `assigned_to` is absent; a direct DTO null assertion alone is insufficient. Keep this coverage focused on the public compatibility contract.
- [ ] Run root restore, Debug build, and tests. If default Debug outputs are locked, record that failure and use a unique temporary output directory, as documented in the foundation reference. Do not stop running MCP servers without user authorization, and do not claim `UseAppHost=false` alone resolves a DLL lock.
- [ ] Record commands, outcomes, limitations, and the first step's commit hash here; update goal 00's evidence to link this follow-up and distinguish original checks from corrected verification.
- [ ] Review the diff for generated files, temporary mutations, and secrets; commit as: `Correct nullable issue response contracts`.

## Definition of done

- [ ] The production integration test detects non-protocol STDOUT; the negative end-to-end experiment proves the previously passing mutation now fails.
- [ ] Existing discovery, invocation, binding, HTTP-contract, and error tests still pass.
- [ ] Documentation matches emitted nullable issue fields without changing production behavior.
- [ ] Root validation and any output-lock workaround are accurately recorded.
- [ ] Both steps are committed with evidence, and no temporary production mutation is included.

## Execution record

| Step | Status | Validation and documentation evidence | Commit |
| --- | --- | --- | --- |
| 1 | Complete | `StrictMcpProcess` tees raw child STDOUT into the SDK only after validating JSON-RPC 2.0 lines; 5 focused integration tests passed, including clean production discovery/read/failure/bearer coverage, three validator negatives, and temporary-copy contamination failure. `contracts.md`, the tool reference, and goal 00 evidence now describe the strict check. | Assert clean MCP protocol output |
| 2 | Not started | Pending | Pending |

Step 1 validation command:

```text
dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Release -p:OutputPath=C:\Temp\TaigaMCP-review-fixes-step1\ -p:UseAppHost=false --no-restore --filter FullyQualifiedName~McpIntegrationTests
```

Result: 5 passed in approximately 5 seconds. The contaminated temporary copy emitted the expected `REVIEW: non-JSON stdout contamination` line; the strict validator raised `InvalidDataException`, and the bounded MCP initialization failed within the five-second deadline. Temporary files were removed and no production source was mutated.

Final handoff: report both findings addressed, commit hashes, clean/contaminated protocol results, null-serialization verification, root validation results, and any remaining limitations.
