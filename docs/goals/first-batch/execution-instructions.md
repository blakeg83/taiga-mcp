# Instructions for coding agents executing this batch

These instructions apply to every goal in this directory. Read the repository's [AGENTS.md](../../../AGENTS.md) first. The current request that produced these files was planning only; the checklists describe later implementation work.

## Before starting a goal

- Read its dependencies, [shared contracts](contracts.md), and current source. Inspect git status and recent history; preserve unrelated staged, unstaged, and untracked files.
- Record baseline build/test results, then fill in the goal's execution record. A failing pre-existing check is not evidence that your change passes.
- Use an appropriate branch; if creating one, use the repository's codex/ prefix. Do not reset or discard another agent's work.
- Verify route, payload, pagination, and error assumptions against the deployed version when available, or a pinned upstream revision otherwise. Record the version/revision, source URL, and date. Never invent a deployment version.
- Reuse completed prerequisite work. If a prerequisite is missing, record the dependency and execute that prerequisite first only when included in the assigned scope; otherwise report the blocker.
- Follow the repository's DI/domain API pattern. Tools return JSON strings and use explicit snake_case MCP names. Avoid unrelated package upgrades or authentication redesign.

## Mandatory cycle for every numbered step

1. Complete the step's implementation and its relevant tests.
2. Run the step's validation. Fix regressions within scope before proceeding.
3. Update documentation in the same step: this goal's checklist and execution record, affected tool reference entries, and README/quickstart when public behavior changes. Clearly label unfinished behavior as planned.
4. Review the diff; stage only files/hunks for this step. Do not use an indiscriminate git add when unrelated work exists.
5. **Create a Git commit after this step**, using its suggested imperative subject or an equally clear subject. Include code, tests, and documentation together. Do not accumulate several completed steps into one final commit.
6. Verify that the commit contains the intended changes. In the next step's record, reference the previous commit hash; commit subjects identify the current step without needing a self-referential hash.

Each step's commit checkbox is an assertion that its commit must succeed before the agent starts the next step. The checkbox may be included in that commit; if committing fails, uncheck it and record the failure. Report the final step's hash in the final handoff. Do not rewrite a completed commit solely to add its own hash to its contents.

If a step cannot finish, keep unfinished boxes unchecked and record the failing check or missing input. A work-in-progress checkpoint is not step completion. Do not push, merge, open a PR, or change a live Taiga project merely because these instructions require local commits.

## Continuous documentation

- This goal: decisions, deviations, checks run and their results, remaining work, and step commit references.
- docs/taiga_tools_reference.md: accurate signatures, defaults, JSON examples, null/clearing semantics, pagination, errors, and compatibility notes. The foundation creates it.
- README.md: implemented capabilities, with a link to the detailed reference.
- docs/taiga_mcp_quickstart.md: runnable workflow examples when relevant; update outdated version-conflict guidance.
- docs/taiga_command_inventory.md: distinguish delivered subset from remaining planned behavior.
- Do not record credentials, tokens, private production payloads, or fabricated successful results.

## Validation and handoff

Run dotnet restore, dotnet build -c Debug, and dotnet test from the repository root at the goal's final step. Use focused tests while developing earlier steps. Tests use a fake HttpMessageHandler and a fake auth response; live credentials are unnecessary. Keep generated bin/obj directories out of commits.

Test actual serialized requests, pagination, error paths, and MCP discovery/invocation. Reflection alone cannot prove that optional/default/null arguments bind correctly. Use the SDK APIs available in the installed package or an automated STDIO client against fake HTTP; do not assume APIs from a newer MCP package.

Live smoke testing is optional and requires a user-designated test project. Do not create or alter production tickets for validation. Report mocked checks and live checks distinctly.

Final handoff: identify delivered tools, completed steps and commit hashes, validation results, documented compatibility changes, remaining limitations, and the definition-of-done result. Never claim completion solely because code compiles.
