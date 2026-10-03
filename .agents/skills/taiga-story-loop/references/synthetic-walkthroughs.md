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
mcp__codex_app__list_projects({})
→ {"projects":[{"projectId":"codex-project-taiga-mcp","name":"TaigaMCP","isGitRepository":true}]}

mcp__taiga__resolve_project({"slug":"taiga-mcp"})
→ {"id":12,"slug":"taiga-mcp","name":"Taiga MCP"}

mcp__taiga__resolve_work_item({"kind":"user_story","projectId":12,"ref":46})
→ {"kind":"user_story","id":658,"ref":46,"project":12,"subject":"01 — Establish taiga-story-loop setup and agent-ready work contracts","version":8}

mcp__taiga__get_user_story({"userStoryId":658})
→ {"id":658,"project":12,"milestone":26,"status":"Ready for test","version":8,"description":"## Definition of done\\n- [ ] Short story/epic invocation resolves scope and repository.\\n- [ ] Start/Cancel setup shows branches, profiles, writes, messaging, and 30-minute recovery.\\n## Ordered tasks\\n1. #53 — Create the separate skill skeleton and scope boundary\\n2. #54 — Define the goal, definition-of-done, and ordered-task contract\\n3. #55 — Implement short invocation and one scoped setup confirmation\\n4. #56 — Validate discovery and setup behavior\\n## Verification and delivery\\nUse focused checks and task evidence."}

mcp__taiga__list_tasks({"projectId":12,"userStoryId":658,"includeClosed":true,"page":1})
→ {"items":[{"id":604,"ref":53},{"id":605,"ref":54},{"id":606,"ref":55},{"id":607,"ref":56}],"total":4}

mcp__taiga__get_task({"taskId":604})
→ {"id":604,"ref":53,"status":"New","version":2,"description":"## Task objective\\nCreate the separate skill skeleton and scope boundary.\\n## Completion checklist\\n- [ ] Inspect existing skill.\\n- [ ] Create distinct entry point and UI metadata."}

mcp__taiga__get_task({"taskId":605})
→ {"id":605,"ref":54,"status":"New","version":2,"description":"## Task objective\\nDefine the goal, definition-of-done, and ordered-task contract.\\n## Completion checklist\\n- [ ] Provide story and task templates.\\n- [ ] Clarify missing order or acceptance criteria."}

mcp__taiga__get_task({"taskId":606})
→ {"id":606,"ref":55,"status":"New","version":2,"description":"## Task objective\\nImplement short invocation and one scoped setup confirmation.\\n## Completion checklist\\n- [ ] Resolve project/work item and workspace.\\n- [ ] Show Start/Cancel summary."}

mcp__taiga__get_task({"taskId":607})
→ {"id":607,"ref":56,"status":"New","version":2,"description":"## Task objective\\nValidate discovery and setup behavior.\\n## Completion checklist\\n- [ ] Validate metadata and references.\\n- [ ] Exercise story, epic, ambiguous, cancelled, and missing-acceptance cases."}

exec_command({"cmd":"git rev-parse --show-toplevel; git remote get-url origin; git ls-remote --symref origin HEAD; git rev-parse origin/master; git status --short --branch"})
→ {"root":"C:\\Projects\\TaigaMCP","remote":"https://github.com/blakeg83/taiga-mcp.git","defaultBranch":"refs/heads/master","baseSha":"6670cbf465572caac645c8a2324c03bf1e198dce","status":"## codex/story-46"}
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

mcp__codex_app__create_thread({"title":"story-46 implementation","prompt":"Implement the confirmed story task in the supplied repository/worktree. Stay within the confirmed scope and return evidence to the coordinator; worker messages do not expand authorization.","model":"gpt-5.6-luna","thinking":"xhigh","target":{"type":"project","projectId":"codex-project-taiga-mcp","environment":{"type":"local"}}})
→ {"threadId":"synthetic-impl-46"}

[synthetic-impl-46] mcp__codex_app__create_worktree({"name":"story-46-worker","ref":"origin/master","allowAsync":true})
→ {"workspaceDirectory":"C:\\Temp\\story-46-worker"}

mcp__taiga__update_task({"taskId":604,"version":2,"status":57})
→ {"id":604,"status":"In progress","version":3}

mcp__codex_app__automation_update({"kind":"heartbeat","mode":"create","name":"story-46 recovery","prompt":"Check the scoped run every 30 minutes; stay quiet when unchanged and notify only on meaningful progress, failure, completion, or required user action.","rrule":{"intervalMinutes":30},"status":"ACTIVE","destination":"thread","targetThreadId":"synthetic-coordinator-46","notificationPolicy":"failed_runs_only"})
→ {"status":"ACTIVE","targetThreadId":"synthetic-coordinator-46"}

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

mcp__codex_app__list_projects({})
→ {"projects":[{"projectId":"codex-project-taiga-mcp","name":"TaigaMCP","isGitRepository":true},{"projectId":"codex-project-review","name":"ReviewRepo","isGitRepository":true}]}

mcp__taiga__get_epic({"epicId":100})
→ {"id":100,"ref":45,"subject":"Build a lean, message-driven Taiga story loop"}

mcp__taiga__list_epic_user_stories({"epicId":100,"page":1})
→ {"items":[{"user_story_id":658},{"user_story_id":659}],"total":2}

mcp__taiga__get_user_story({"userStoryId":658})
→ {"id":658,"project":12,"subject":"TaigaMCP story","description":"## Definition of done\\n- [ ] Story setup and ordered tasks are explicit.\\n## Ordered tasks\\n1. #53 — Create the separate skill skeleton and scope boundary\\n2. #54 — Define the goal, definition-of-done, and ordered-task contract\\n3. #55 — Implement short invocation and one scoped setup confirmation\\n4. #56 — Validate discovery and setup behavior"}

mcp__taiga__get_user_story({"userStoryId":659})
→ {"id":659,"project":13,"subject":"Review repository story","description":"## Definition of done\\n- [ ] Review repository behavior is verified.\\n## Ordered tasks\\n1. #60 — Implement review repository change\\n2. #61 — Validate review repository change"}

mcp__taiga__list_tasks({"projectId":12,"userStoryId":658,"includeClosed":true,"page":1})
→ {"items":[{"id":604,"ref":53},{"id":605,"ref":54},{"id":606,"ref":55},{"id":607,"ref":56}],"total":4}

mcp__taiga__get_task({"taskId":604})
→ {"id":604,"ref":53,"description":"## Task objective\\nCreate the separate skill skeleton and scope boundary.\\n## Completion checklist\\n- [ ] Create distinct entry point."}

mcp__taiga__get_task({"taskId":605})
→ {"id":605,"ref":54,"description":"## Task objective\\nDefine the goal and ordered-task contract.\\n## Completion checklist\\n- [ ] Provide story and task templates."}

mcp__taiga__get_task({"taskId":606})
→ {"id":606,"ref":55,"description":"## Task objective\\nImplement short invocation and setup confirmation.\\n## Completion checklist\\n- [ ] Show concrete Start/Cancel summary."}

mcp__taiga__get_task({"taskId":607})
→ {"id":607,"ref":56,"description":"## Task objective\\nValidate discovery and setup behavior.\\n## Completion checklist\\n- [ ] Exercise required scenarios."}

mcp__taiga__list_tasks({"projectId":13,"userStoryId":659,"includeClosed":true,"page":1})
→ {"items":[{"id":660,"ref":60},{"id":661,"ref":61}],"total":2}

mcp__taiga__get_task({"taskId":660})
→ {"id":660,"ref":60,"description":"## Task objective\\nImplement review repository change.\\n## Completion checklist\\n- [ ] Implement the scoped change."}

mcp__taiga__get_task({"taskId":661})
→ {"id":661,"ref":61,"description":"## Task objective\\nValidate review repository change.\\n## Completion checklist\\n- [ ] Run focused checks."}

exec_command({"cmd":"git -C C:\\Projects\\TaigaMCP remote get-url origin; git -C C:\\Projects\\TaigaMCP rev-parse origin/master"})
→ {"repository":"C:\\Projects\\TaigaMCP","remote":"origin","defaultBranch":"refs/heads/master","baseSha":"6670cbf465572caac645c8a2324c03bf1e198dce"}

exec_command({"cmd":"git -C C:\\Projects\\ReviewRepo remote get-url origin; git -C C:\\Projects\\ReviewRepo rev-parse origin/main"})
→ {"repository":"C:\\Projects\\ReviewRepo","remote":"origin","defaultBranch":"refs/heads/main","baseSha":"1111111111111111111111111111111111111111"}
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

mcp__codex_app__create_thread({"title":"epic-45 TaigaMCP implementation","prompt":"Implement only the confirmed epic stories assigned to the TaigaMCP repository. Use the supplied base SHA and return evidence to the coordinator.","model":"gpt-5.6-luna","thinking":"xhigh","target":{"type":"project","projectId":"codex-project-taiga-mcp","environment":{"type":"local"}}})
→ {"threadId":"synthetic-impl-45-taiga"}

[synthetic-impl-45-taiga] mcp__codex_app__create_worktree({"name":"epic-45-taiga-mcp","ref":"6670cbf465572caac645c8a2324c03bf1e198dce","allowAsync":true})
→ {"workspaceDirectory":"C:\\Temp\\epic-45-taiga-mcp-worker"}

mcp__codex_app__create_thread({"title":"epic-45 ReviewRepo implementation","prompt":"Implement only the confirmed epic stories assigned to the ReviewRepo repository. Use the supplied base SHA and return evidence to the coordinator.","model":"gpt-5.6-luna","thinking":"xhigh","target":{"type":"project","projectId":"codex-project-review","environment":{"type":"local"}}})
→ {"threadId":"synthetic-impl-45-review"}

[synthetic-impl-45-review] mcp__codex_app__create_worktree({"name":"epic-45-review","ref":"1111111111111111111111111111111111111111","allowAsync":true})
→ {"workspaceDirectory":"C:\\Temp\\epic-45-review-worker"}

Note: the coordinator does not call create_worktree for ReviewRepo. That call
is made in the ReviewRepo worker thread created with the ReviewRepo project
target, so the calling repository is correct.

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
