# Work-item conversation names

Conversation titles are stable, human-facing labels for the work item and
role. Use the project-local displayed reference (the number shown after `#`),
not the mutable subject, an internal UUID, or a generated title.

| Work-item scope | Coordinator chat | Implementer chat | Reviewer chat |
| --- | --- | --- | --- |
| User story #`<ref>` | `User Story #<ref> Coordinator` | `User Story #<ref> Implementer` | `User Story #<ref> Reviewer` |
| Epic #`<ref>` | `Epic #<ref> Coordinator` | `Epic #<ref> Implementer` | `Epic #<ref> Reviewer` |

The epic implementer and reviewer names apply to the fresh integrated-review
pair and to any epic-level implementation chats. A story worker pair inside
an epic uses the linked story's `User Story #<ref>` names. If an epic spans
repositories, each scoped epic worker still uses the same epic/role label;
repository and branch identity remain in the assignment and continuation
record.

Apply the contract at creation time:

1. After the user submits `Start`, rename the current coordinator chat once
   with `set_thread_title` using the matching coordinator name.
2. Pass the matching role name in the `title` field of every `create_thread`
   call. Keep the selected work item in the bootstrap and full assignment so
   the chat is linked to the scope as well as named for it.
3. When resuming, match an existing chat by its authoritative thread/host,
   work-item scope, and role. Do not create a duplicate solely to change a
   title.
4. Names are assigned when a conversation is created and do not change when
   the work-item subject changes.

Tasks do not receive separate conversations; they use the parent user-story
conversation. Issue conversations are not currently supported by this
workflow. No conversation may be created without a resolved work-item scope.

Titles are not correlation authority. Routing still uses the real thread and
host IDs, run/action identity, and scope hash described by the worker-pair and
handoff contracts.
