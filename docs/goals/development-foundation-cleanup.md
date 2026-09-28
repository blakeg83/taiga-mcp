# Goal: prepare TaigaMCP for sustainable feature development

Status: in progress; Step 1 baseline verified.

## Objective

Harden the existing MCP server before expanding its tool set. Keep the current Tools -> domain APIs -> HTTP/auth architecture, remove redundant code, establish reliable shared infrastructure, and document a repeatable development workflow. Deliver working changes and evidence, not just a proposed architecture.

This is an implementation assignment for a Codex agent. Creating this document does not execute the assignment. When assigned, **complete the numbered steps in order and create a separate local Git commit after every step before starting the next**.

## Read first and respect existing work

- Read [AGENTS.md](../../AGENTS.md), [the implemented tool reference](../taiga_tools_reference.md), [batch contracts](first-batch/contracts.md), and [batch execution instructions](first-batch/execution-instructions.md).
- The [foundation review fixes](first-batch/00-foundation-review-fixes.md) are a prerequisite. Verify their definition of done and committed evidence before implementation. At planning time that work was in progress in the shared working tree. Do not duplicate it, commit another agent's edits, or infer completion from documentation alone. If it remains unfinished, report the dependency and leave implementation pending.
- Inspect current source, Git status, and recent history; the repository may have advanced since this plan. Preserve unrelated changes and running MCP processes. Never reset, clean, or stop another task's work to obtain a clean baseline.
- Use an appropriate branch; new branches use `codex/`. This assignment authorizes local implementation and step commits, not pushing, opening a PR, merging, or live Taiga writes.
- Tests must use synthetic credentials and fake HTTP. Verify upstream behavior against a pinned official Taiga reference when needed, recording URL, revision/version, and date. Verify MCP APIs against the installed SDK, not examples from a newer release.

## Scope and architectural decisions

- Keep one application project and one test project. Retain the current root project and `Api/`, `Tools/`, `Models/`, `Caching/`, `Config/`, and `Hosting/` folders. Moving to `src/` is optional future housekeeping and is excluded from this goal to avoid path churn.
- Introduce a small shared HTTP transport and retain domain-specific APIs. Do not add generic repositories, a mediator, domain base classes, or interfaces without an actual need.
- Remove the unused `ITaigaApi`/`TaigaApi` facade after checking callers. This deliberately supersedes the batch contract that asks agents to preserve it; update that contract in the same step.
- Preserve existing MCP names, parameter names, and response shapes except for the explicit default/filter corrections in Step 7. Internal C# namespace changes are intentional source changes, not MCP schema changes.
- Do not upgrade the target framework or MCP SDK in this goal. Pin the development SDK policy separately from changing runtime/package versions.
- Establish conventions for pagination and presence-aware updates; implementing new page envelopes, filters, `clearFields`, or additional tools remains owned by the existing feature goals.

## Required cycle for every step

1. Implement only the numbered step and its relevant tests.
2. Run its validation and fix regressions before continuing.
3. Update this checklist, the execution record, and affected user/developer documentation. Record actual commands, results, limitations, and deviations.
4. Review the diff and stage only the step's files/hunks. Inspect the staged diff for unrelated work, generated files, and secrets.
5. Create the step's local commit and verify its contents. **Do not begin the next step until the commit succeeds.** A checkpoint commit does not make an incomplete step complete.
6. Record the preceding step's hash in the next step's documentation. Report the final commit hash in the handoff; do not amend a commit just to put its own hash inside it.

If blocked, keep unfinished boxes unchecked and report the precise dependency or failure. Do not claim a pre-existing failing check passes. For locked default outputs, record the failure and use a unique temporary output directory outside the source tree; do not stop running servers. Ensure integration tests launch the newly built assembly from that output.

## Step 1: establish a verified baseline and compatibility inventory

- [x] Verify the prerequisite foundation-review work is complete and committed. Record its commit references and rerun its focused checks, including strict protocol-output and omitted-null response tests.
- [x] Record branch, baseline commit, working-tree changes, installed SDK (`dotnet --info`), target framework, and package versions without printing environment secrets.
- [x] Run root `dotnet restore`, `dotnet build -c Debug`, and `dotnet test -c Debug`. Record the actual test count and any output-lock workaround.
- [x] Capture the current public tools, parameter names/defaults, and representative JSON shapes in the tool reference. Identify intentional changes reserved for Step 7: project member default and English-name story filtering.
- [x] Search tracked source, tests, docs, and scripts for `ITaigaApi`/`TaigaApi` callers and startup/build-path assumptions. Record whether removing the facade affects any actual consumer; if a real consumer exists, document the migration before removing it.
- [x] Document layer responsibilities and the intended shared transport, authentication, and cache lifetimes in `docs/development.md`.
- [x] Update the execution record and commit as `Document cleanup baseline and compatibility boundaries`.

## Step 2: simplify structure and standardize serialization

- [x] Add file-scoped `TaigaMCP.*` namespaces matching the existing folders and update production/test imports. Keep the top-level entry point small.
- [x] Remove `Api/ITaigaApi.cs`, `Api/TaigaApi.cs`, their DI registration, and obsolete references after resolving the Step 1 caller audit. Keep tools injecting their concrete domain APIs.
- [x] Update the batch contracts and affected goal instructions to use domain APIs and stop requiring preservation of the removed facade.
- [x] Replace repeated tool serializer settings with one shared response-serialization policy preserving current snake_case property attributes and omitted nullable response properties.
- [x] Keep upstream request serialization distinct from tool response serialization. Preserve existing create/PATCH omission behavior and explicit empty arrays, empty strings, false, and zero when applicable. Do not implement field clearing or change public signatures here.
- [x] Make DTO mutability consistent where existing callers permit it; remove unused fields/usings and obsolete generated-looking comments without broad unrelated formatting churn.
- [x] Run the full test suite and compare MCP discovery/schema and representative result serialization to Step 1. Fix any unintended contract change.
- [x] Update docs/evidence and commit as `Simplify API layers and serialization conventions`.

## Step 3: centralize HTTP transport, disposal, and cancellation

- [x] Add a focused `Api/TaigaTransport.cs` (or equally clear name) for authenticated sends, bounded error-body processing, success checks, and JSON response reading. Define request/response/JSON-document ownership explicitly.
- [x] Migrate `ProjectApi`, `IssueApi`, `UserStoryApi`, and metadata requests to the transport. Domain APIs continue to own routes, payload construction, mapping, and domain behavior.
- [x] Dispose every request, response, retry request, and owned content on success and failure. Avoid returning JSON elements backed by disposed documents.
- [x] Pass `CancellationToken` from MCP tool methods through APIs, cache waits, auth, HTTP sends, and reads. Confirm the installed MCP SDK treats it as injected context, not a user-facing tool parameter.
- [x] Introduce a consistent error representation retaining HTTP status and useful, bounded, sanitized validation details. Remove the update path's unbounded raw-body exception. Verify the installed SDK's supported way to expose safe tool errors and preserve `IsError=true` behavior.
- [x] Distinguish cancellation from upstream failures. Do not introduce automatic retries for network errors, throttling, or server failures, especially for writes.
- [x] Ensure successful writes followed by metadata/mapping failure report that the write may already have applied; they must not look safe to repeat blindly.
- [x] Add focused tests for successful GET/POST/PATCH, disposal on success/error, cancellation propagation, safe 400/401/403/404/409/429/5xx errors, malformed JSON, and write-success followed by enrichment failure. Assert status and useful details without requiring unsafe upstream text.
- [x] Run focused HTTP tests and production MCP integration tests; update contracts to reference the new transport.
- [x] Update docs/evidence and commit as `Centralize Taiga HTTP handling and cancellation`.

## Step 4: coordinate authentication and correct HTTP lifetimes

- [x] Serialize initial login and token refresh with an async gate and recheck token state after acquiring it. Keep token and refresh-token state coherent.
- [x] On a 401, detect whether another request has already replaced the rejected token before starting another refresh. Permit at most one replay of the original request; if refresh fails, perform the existing full-login fallback within that bounded flow.
- [x] Stop mutating shared `HttpClient.DefaultRequestHeaders` during requests. Attach bearer tokens per request; auth and refresh requests must never receive the bearer header.
- [x] Preserve method, URI, content, content headers, and relevant request properties when replaying. Dispose retry requests and propagate cancellation while waiting for the auth gate.
- [x] Adjust DI so singleton token/cache state does not indefinitely capture a factory-created HTTP client. Use the named client factory at an appropriate operation boundary, or document an equivalent handler-lifetime strategy. Keep ownership explicit.
- [x] Test concurrent first calls with controlled barriers, simultaneous 401 responses, token reuse after another refresh, refresh rejection/full-login fallback, repeated 401, cancellation, and a PATCH replay retaining its original body/version. Avoid timing-dependent sleeps.
- [x] Assert writes are not replayed after ambiguous network failures; the bounded authentication replay applies only to a received 401 response.
- [x] Run auth/transport tests and the full integration suite.
- [x] Update docs/evidence and commit as `Coordinate authentication and HTTP client lifetimes`.

## Step 5: make metadata caching safe and refreshable

- [ ] Replace unsynchronized nested dictionaries with concurrency-safe cache entries keyed by metadata kind and project ID. Return read-only snapshots rather than mutable cached dictionaries.
- [ ] Coalesce simultaneous loads for the same key while allowing unrelated projects/kinds to load independently. A concurrent dictionary alone does not guarantee a single fetch.
- [ ] Add a configurable positive metadata TTL, defaulting to five minutes, through `TaigaOptions`. Document its environment variable and startup validation.
- [ ] Inject `TimeProvider` or an equivalent clock so expiry tests do not sleep. Expired values should be refreshed; failures must not be stored permanently or silently represented as current data.
- [ ] Ensure failed/cancelled loads release coordination state and allow a later request to retry. Bound retained expired entries or document and implement eviction so old projects do not accumulate forever.
- [ ] Test cache hits, expiry, concurrent same-key loads, project isolation, failure followed by success, cancellation, and immunity to caller mutation.
- [ ] Run cache tests plus representative issue reads/writes through fake HTTP.
- [ ] Update docs/evidence and commit as `Add concurrent expiring metadata caching`.

## Step 6: establish configuration and tool-boundary conventions

- [ ] Validate nonblank credentials, an absolute HTTP/HTTPS API base URL without embedded credentials/query/fragment, and the cache TTL at startup. Preserve self-hosted HTTP support and normalize the trailing slash.
- [ ] Test configuration binding using the documented `TAIGA__...` keys. Remove redundant configuration-provider wiring only after proving these keys and existing precedence still work.
- [ ] Add meaningful tool and parameter descriptions using APIs supported by the pinned SDK. Explain IDs versus refs, version requirements, pagination, filters, and omission semantics accurately.
- [ ] Reject nonpositive project/entity IDs, pages below one, blank required subjects/slugs, and negative update versions before sending HTTP. Preserve valid empty optional values and reject updates containing neither a real change nor a nonblank comment.
- [ ] Document shared future-feature rules: one page per call, allowlisted encoded query parameters, unknown pagination metadata remains unknown, caller-supplied versions, and explicit field-clearing semantics. Reconcile existing batch contracts; do not implement those future features here.
- [ ] Add parameterized validation tests asserting no HTTP calls for invalid input, plus real MCP invocation tests for omitted/default/null/empty values and safe error presentation. Ensure all existing tools remain discoverable and cancellation is absent from input schemas.
- [ ] Update tool reference, quickstart, developer guide, and evidence; commit as `Standardize configuration and tool contracts`.

## Step 7: remove account-specific defaults and label-dependent filters

- [ ] Change `list_projects`'s default `member` from `"6"` to `null`, meaning no member filter. Preserve explicit member filtering and URL encoding. Document how existing users retain the old behavior by passing `member="6"` explicitly.
- [ ] Replace story exclusions based on English names `Done`/`Archived` with verified API flags/status metadata. Preserve the intended default of excluding closed/archived stories without treating labels as workflow semantics.
- [ ] Verify existing issue list filters against pinned Taiga documentation/source. Remove unsupported or redundant restrictions while preserving the documented open-issue behavior; record the evidence. Do not invent issue archival support.
- [ ] Test omitted versus explicit project member and custom/localized story status names. Include an open status named `Done` and a closed status with a different name so the tests prove labels no longer control inclusion.
- [ ] Assert generated HTTP queries and returned mapping, and exercise the changed project default through actual MCP invocation. Replace tests that hardcode the old default with explicit compatibility/migration tests.
- [ ] Update README, tool reference, quickstart, and affected batch contracts/goals with an explicit behavior-change note. These changes are intentional and must not be described as behavior-preserving refactoring.
- [ ] Run the full suite; update evidence and commit as `Remove account-specific defaults and status-name assumptions`.

## Step 8: add development guardrails and verify the finished foundation

- [ ] Add `.editorconfig` for four-space C#, UTF-8, final newlines, and namespace/style conventions. Verify formatting for changed files without sweeping unrelated changes into the commit.
- [ ] Add `global.json` selecting an available SDK compatible with the current target and an explicit roll-forward policy. Document the decision without silently upgrading the runtime or package versions.
- [ ] Add a GitHub Actions workflow installing the selected SDK and running restore, Release build, and Release tests without live credentials. Run on pull requests and pushes to the repository's verified default branch. Keep permissions minimal.
- [ ] Update `AGENTS.md` and README to reflect actual startup/DI locations, existing tests, shared transport, namespaces, and how to add a tool. Add Windows PowerShell build/run examples and explain separate development/published outputs to avoid running-server locks.
- [ ] Link `docs/development.md` and this goal from the README. Ensure feature plans reference the final infrastructure and still distinguish proposed behavior from implemented behavior.
- [ ] Run root restore, Debug build/tests, and the Release commands used by CI. Verify strict STDOUT validation, all production tools, representative reads/writes, cancellation, auth races, cache expiry, and safe error cases remain covered.
- [ ] Review the final diff and commit history for accidental schema drift, credentials, generated artifacts, temporary test mutations, unrelated edits, and unfinished checklist items. Record any checks that could not run; do not claim remote CI passed without observing it.
- [ ] Complete the definition-of-done audit and execution record; commit as `Add development guardrails and finalize foundation cleanup`.

## Final definition of done

- [ ] All eight steps completed in order, each with its own successful local commit and validation evidence.
- [ ] Prerequisite protocol-output/null-response fixes are retained and pass.
- [ ] One application and one test project remain, with clear namespaces and documented layer responsibilities; no unused aggregate API facade remains.
- [ ] Domain APIs use shared HTTP handling with explicit disposal, end-to-end cancellation, consistent safe errors, and no ambiguous automatic write retries.
- [ ] Authentication handles concurrent login/refresh without token races; HTTP client lifetimes are deliberate and tested.
- [ ] Metadata caching has tested concurrency, expiry, isolation, failure recovery, and eviction behavior.
- [ ] Existing MCP names and response shapes remain compatible. Intentional project-default, filter, validation, and error-detail changes are documented and tested.
- [ ] Tool descriptions and configuration validation accurately describe runtime behavior. Future pagination/clearing features remain explicitly planned.
- [ ] Local root build/tests and CI-equivalent Release checks pass, or a precise environmental blocker is reported with equivalent isolated-output evidence where possible.
- [ ] CI configuration, SDK policy, formatting settings, and developer documentation are present and consistent.
- [ ] No unrelated work, live Taiga mutations, generated artifacts, credentials, package upgrades, or unrequested structural framework was introduced.

## Execution record

| Step | Status | Validation, decisions, and documentation evidence | Commit reference |
| --- | --- | --- | --- |
| 1. Baseline | Complete | Prerequisites 003fe00/b219e39 verified in history and 13 passing tests; root restore/Debug build/tests passed, zero warnings, no locks. SDK, package, caller/path audit and layer lifetimes recorded in docs/development.md. Existing reference matches all 11 signatures/shapes. | Document cleanup baseline and compatibility boundaries |
| 2. Structure/serialization | Complete | Previous commit c77e1c0. Namespaces, unused facade removal, shared response policy and init-only DTO; domain plan references updated. Full Debug suite: 13 passed. | Simplify API layers and serialization conventions |
| 3. Transport | Complete | Previous ffeba6b. Shared transport/disposal, cancellation and safe errors; 28 Debug tests passed including actual MCP safe errors/schema and write uncertainty. Details in developer guide. | Centralize Taiga HTTP handling and cancellation |
| 4. Authentication | Complete | Previous e2f9cc5. Gated coherent token state, bounded replay and per-operation factory clients. 33 Debug tests passed, including barrier-driven races and PATCH replay/ambiguity. | Coordinate authentication and HTTP client lifetimes |
| 5. Cache | Not started | Pending | Pending |
| 6. Contracts/configuration | Not started | Pending | Pending |
| 7. Defaults/filters | Not started | Pending | Pending |
| 8. Guardrails/final verification | Not started | Pending | Pending |

Final handoff: list completed steps and commit hashes, exact checks and outcomes, intentional compatibility changes and migration examples, outstanding limitations, and the definition-of-done result. Do not claim live integration or remote CI success from mocked/local tests.
