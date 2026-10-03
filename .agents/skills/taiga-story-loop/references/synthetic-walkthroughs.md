# Recorded synthetic skill walkthroughs

These are recorded, synthetic, non-live walkthroughs of the documented
taiga-story-loop behavior. They are the behavioral evidence for task #56; no
call below was sent to Taiga, GitHub, Codex, or a real repository. Tool names
and argument shapes are the tools the coordinator would use. Discovery calls
are read-only. Mutation calls appear only after a synthetic `Start` reply.

The walkthroughs use concrete inputs, the exact setup/clarification prompt
shown to the user, the observed outcome, and the tool-call trace. The static
PowerShell file in `scripts/validate-scenarios.ps1` checks contract text only;
it is not used as behavioral evidence.

## Summary

| Case | Setup prompt | Observed outcome | Mutation calls before confirmation |
| --- | --- | --- | --- |
| Single-repository story | Emitted | `Start` accepted; scoped run authorized | None |
| Multi-repository epic | Emitted with two mapping rows | `Start` accepted; both repository scopes authorized | None |
| Ambiguous scope | Not emitted | Clarification requested for missing project | None |
| Cancelled setup | Emitted | `Cancel`; external systems unchanged | None |
| Missing acceptance criteria | Not emitted | Clarification requested for acceptance criteria | None |

## 1. Single-repository story — Start

Synthetic input:

```text
Use $taiga-story-loop for taiga-mcp story #46
```

Read-only discovery calls and observed results:

```text
mcp__taiga__resolve_project({"slug":"taiga-mcp"})
→ {"id":12,"slug":"taiga-mcp","name":"Taiga MCP"}

mcp__taiga__resolve_work_item({"kind":"user_story","projectId":12,"ref":46})
→ {"kind":"user_story","id":658,"ref":46,"project":12,"subject":"01 — Establish taiga-story-loop setup and agent-ready work contracts","version":8}

mcp__taiga__get_user_story({"userStoryId":658})
→ {"id":658,"project":12,"milestone":26,"status":"Ready for test","version":8}

mcp__taiga__list_tasks({"projectId":12,"userStoryId":658,"includeClosed":true,"page":1})
→ {"items":[{"ref":53},{"ref":54},{"ref":55},{"ref":56}],"total":4}

exec_command({"cmd":"git rev-parse --show-toplevel; git remote get-url origin; git status --short --branch"})
→ {"root":"C:\\Projects\\TaigaMCP","remote":"origin","status":"## codex/story-46"}
```

Setup prompt shown:

```text
Taiga story loop setup — taiga-mcp story #46
Subject: 01 — Establish taiga-story-loop setup and agent-ready work contracts
Scope: tasks #53, #54, #55, #56 in the story's declared order

Repositories and branch/worktree mapping:
| Repository/workspace | Remote | Verified base ref/SHA | Coordinator branch | Worker worktrees |
| C:\Projects\TaigaMCP | origin | origin/master / 6670cbf | codex/story-46 | create one scoped worker worktree |

Workers and review cadence:
- Implementation: gpt-5.6-luna, xhigh
- Story/task reviews: gpt-6.1-sol, medium, after each task
- Final epic review: gpt-6.1-sol, high, when the epic gate is reached

Start authorizes the scoped worker chats, messages, worktree/branch,
commits, pushes, Taiga updates, pull request, and 30-minute recovery
automation. Each story merge requires its own Yes; final master merge is
separate. Reply Start or Cancel.
```

Synthetic user reply and trace:

```text
User → Start

Mutation calls before Start: []

mcp__codex_app__create_thread({"title":"story-46 implementation","model":"gpt-5.6-luna","thinking":"xhigh"})
→ {"threadId":"synthetic-impl-46"}

mcp__codex_app__create_worktree({"name":"story-46-worker","ref":"origin/master","allowAsync":true})
→ {"workspaceDirectory":"C:\\Temp\\story-46-worker"}

mcp__taiga__update_task({"taskId":604,"version":4,"status":57})
→ {"id":604,"status":"In progress","version":5}

mcp__codex_app__automation_update({"kind":"heartbeat","name":"story-46 recovery","status":"ACTIVE"})
→ {"status":"ACTIVE"}

Observed outcome: SetupReady; the confirmed scope record is passed to the
worker and the listed scoped operations may proceed.
```

## 2. Multi-repository epic — Start

Synthetic input:

```text
Use $taiga-story-loop for multi-repository epic #45
```

Read-only discovery calls and observed results:

```text
mcp__taiga__resolve_project({"slug":"multi-repository"})
→ {"id":20,"slug":"multi-repository","name":"Multi Repository Demo"}

mcp__taiga__get_epic({"epicId":100})
→ {"id":100,"ref":45,"subject":"Build a lean, message-driven Taiga story loop"}

mcp__taiga__list_epic_user_stories({"epicId":100,"page":1})
→ {"items":[{"user_story_id":658},{"user_story_id":659}],"total":2}

mcp__taiga__get_user_story({"userStoryId":658})
→ {"id":658,"project":12,"subject":"TaigaMCP story"}

mcp__taiga__get_user_story({"userStoryId":659})
→ {"id":659,"project":13,"subject":"Review repository story"}

exec_command({"cmd":"git -C C:\\Projects\\TaigaMCP remote get-url origin; git -C C:\\Projects\\TaigaMCP rev-parse origin/master"})
→ {"repository":"C:\\Projects\\TaigaMCP","remote":"origin","base":"6670cbf"}

exec_command({"cmd":"git -C C:\\Projects\\ReviewRepo remote get-url origin; git -C C:\\Projects\\ReviewRepo rev-parse origin/main"})
→ {"repository":"C:\\Projects\\ReviewRepo","remote":"origin","base":"1111111"}
```

Setup prompt shown:

```text
Taiga story loop setup — multi-repository epic #45
Subject: Build a lean, message-driven Taiga story loop
Scope: linked stories #46 and #47, each with its ordered child tasks

Repositories and branch/worktree mapping:
| Repository/workspace | Remote | Verified base ref/SHA | Coordinator branch | Worker worktrees |
| C:\Projects\TaigaMCP | origin | origin/master / 6670cbf | codex/epic-45-taiga-mcp | C:\Temp\epic-45-taiga-mcp-worker |
| C:\Projects\ReviewRepo | origin | origin/main / 1111111 | codex/epic-45-review | C:\Temp\epic-45-review-worker |

Workers and review cadence:
- Implementation: gpt-5.6-luna, xhigh
- Story/task reviews: gpt-6.1-sol, medium, after each task
- Final epic review: gpt-6.1-sol, high, after all linked stories are ready

Start authorizes only these mapped repositories and their scoped workers,
messages, commits, pushes, Taiga updates, pull requests, and 30-minute
recovery automation. Each story merge requires its own Yes; final master
merge is separate. Reply Start or Cancel.
```

Synthetic user reply and trace:

```text
User → Start

Mutation calls before Start: []

mcp__codex_app__create_worktree({"name":"epic-45-taiga-mcp","ref":"6670cbf","allowAsync":true})
→ {"workspaceDirectory":"C:\\Temp\\epic-45-taiga-mcp-worker"}

mcp__codex_app__create_worktree({"name":"epic-45-review","ref":"1111111","allowAsync":true})
→ {"workspaceDirectory":"C:\\Temp\\epic-45-review-worker"}

mcp__codex_app__create_thread({"title":"epic-45 implementation","model":"gpt-5.6-luna","thinking":"xhigh"})
→ {"threadId":"synthetic-impl-45"}

Observed outcome: SetupReady; two repository mappings are retained and no
worker receives authority for an unmapped repository.
```

## 3. Ambiguous scope — clarify before setup

Synthetic input:

```text
Use $taiga-story-loop for story #46
```

Read-only context call:

```text
exec_command({"cmd":"git rev-parse --show-toplevel"})
→ {"root":"C:\\Projects\\TaigaMCP"}
```

Clarification shown:

```text
I found repository C:\Projects\TaigaMCP, but story #46 is project-local.
Which Taiga project contains story #46? I need that project before resolving
the work item and showing Start/Cancel.
```

Observed outcome: `ClarifyRequired(project)`. No setup prompt was emitted and
mutation calls were `[]`.

## 4. Valid scope — Cancel

Synthetic input and read-only discovery are the same as case 1. The concrete
setup prompt is the case-1 prompt above, including its repository mapping and
approval boundaries.

Synthetic user reply and trace:

```text
User → Cancel

Mutation calls after Cancel: []
Observed outcome: Cancelled; external systems unchanged.
```

## 5. Missing acceptance criteria — clarify before setup

Synthetic input:

```text
Use $taiga-story-loop for taiga-mcp story #88
```

Read-only discovery calls and observed results:

```text
mcp__taiga__resolve_work_item({"kind":"user_story","projectId":12,"ref":88})
→ {"kind":"user_story","id":700,"ref":88,"subject":"Unspecified workflow","version":1}

mcp__taiga__get_user_story({"userStoryId":700})
→ {"id":700,"description":"","status":"New","version":1}

mcp__taiga__list_tasks({"projectId":12,"userStoryId":700,"includeClosed":true,"page":1})
→ {"items":[],"total":0}
```

Clarification shown:

```text
Story taiga-mcp #88 has no acceptance criteria or definition of done. Please
provide the intended observable outcome and any ordered tasks before I create
a setup summary or request Start.
```

Observed outcome: `ClarifyRequired(acceptance criteria)`. No setup prompt was
emitted and mutation calls were `[]`.
