# Operational invocation template

Use this short form when the standard permissions are appropriate:

```text
Use $taiga-ticket-loop with the standard authorized-run profile for
ticket/epic {{TAIGA_REF_OR_ID}} in the {{TAIGA_PROJECT}} project.
```

The profile authorizes, only for that selected scope:

- creating or reusing the implementation and reviewer chats;
- messaging those chats and creating managed worktrees/feature branches;
- Taiga milestone comments and status updates;
- pushing the owned reviewed branch and creating/updating its PR;
- attaching the PR to the relevant Codex chat; and
- creating/reusing one coordinator heartbeat for continuation and merge observation.

It excludes automatic merge, force-push, deployment, branch deletion,
credentials, unrelated tickets/chats, and writes outside the selected scope.
The coordinator still discovers the current repository and verifies the fresh
configured base automatically. Add dependencies, validation commands, or a
repository mapping only when discovery cannot resolve them or the defaults do
not apply.
