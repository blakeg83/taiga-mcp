# Deliberate local installation and trial

The repository skill lives at `.agents/skills/taiga-ticket-loop/`. Identify its
version with `git log -1 --format=%H -- .agents/skills/taiga-ticket-loop` and
identify a personal installed copy by inspecting the exact configured skill
path before use. Preserve local configuration and state roots; do not copy a
registry or the audited run between machines.

This batch does not install the skill, create chats, schedule a heartbeat, or
perform external writes. A future authorized trial must explicitly name the
ticket and repository, ordinary implementation/reviewer chats, exact worker
profiles (`gpt-5.6-luna`/`xhigh` and `gpt-6.1-sol`/`high`), permitted Taiga/Git/PR
writes, one coordinator heartbeat, and stop conditions. Automatic merge,
force-push, deployment, credentials, and unrelated tickets stay excluded.

Example future invocation:

```text
Use $taiga-ticket-loop with the standard authorized-run profile for issue 42 in
project GroceryRecipeWizard. Use the ordinary implementation and reviewer chats,
the exact worker profiles, one quiet coordinator heartbeat, and stop before
publication unless the authorized PR scope is still unchanged.
```

Validate the trial plan offline first. Report offline acceptance, actual-host
behavior, and publication separately; do not claim savings or quality
equivalence from a plan or raw token count.
