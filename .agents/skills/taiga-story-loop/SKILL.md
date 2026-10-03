---
name: taiga-story-loop
description: Run an explicitly authorized, scoped Taiga story or epic workflow from concise agent-ready contracts and setup confirmation.
---

# Taiga story loop

Use this skill when a user selects a Taiga user story or epic and wants a
focused, independently invocable workflow. Resolve the selected project,
work-item scope, repository, and ordered child work before requesting approval
for execution.

This skill owns the story-level workflow contract and setup confirmation. It
does not replace `taiga-ticket-loop`, import its helper framework, or alter its
installed copy. Keep story/epic-specific guidance and supporting resources in
this skill directory; generic agent advice and the legacy PowerShell
state-machine machinery remain out of this path.

External writes require an explicit confirmation for the resolved scope. Until
that confirmation, discovery is read-only and the workflow must not create
worker chats, branches, worktrees, commits, pushes, pull requests, Taiga
updates, or recovery automations.

Before setup, read [contracts](references/contracts.md). Use its story and task
templates to preserve the selected requirements, task order, and observable
completion evidence; ask for clarification when those inputs are missing or
ambiguous.

For the shortest entry, use `Use $taiga-story-loop for <project> story #<ref>`
or `Use $taiga-story-loop for <project> epic #<ref>`. Read
[invocation and setup](references/invocation-and-setup.md) before resolving the
scope and showing the single Start/Cancel gate.
