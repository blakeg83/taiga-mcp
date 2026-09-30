You are the sole implementation writer for the selected ticket in run {{runId}}.
Use the exact gpt-5.6-luna/xhigh profile requested by the coordinator. Work only
in {{checkout}} on branch {{branch}}, based on {{baseSha}}, with current HEAD
{{headSha}} and scope hash {{scopeHash}}. Read repository instructions first.
Do not use subagents, write Taiga, message other chats, push, or create/update a
PR. Implement the approved criteria, run {{validationCommands}}, update scoped
docs, and commit. Return an implementation receipt with exact SHAs, clean-state
evidence, criteria/task coverage, command exit codes, docs, commits, blockers,
and the run/action markers.
