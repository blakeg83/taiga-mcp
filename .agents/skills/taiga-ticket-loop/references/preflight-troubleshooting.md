# Preflight troubleshooting

Preflight resolves host capability and explicit run configuration before
dispatch. It is not a code review, source investigation, test run, or browser
smoke test.

| Result | Action |
| --- | --- |
| Exact implementer or reviewer profile unavailable | Stop the affected dispatch and report the model/effort pair. Do not choose a fallback. Re-check the current host schema on the next run. |
| Current coordinator profile differs from the selected profile | Resolve the host/session setting before creating workers; preserve the user's profile. |
| Required chat, messaging, wait, worktree, Git, or provider capability missing | Block only the actions that depend on it and report the missing capability. Do not use a private API or alternate runner. |
| Repository requires visible-browser verification | Any supported browser provider is sufficient for capability preflight. The implementer performs the required visible interaction and returns evidence; no coordinator smoke click is required. |
| User authorization is missing or for another ticket | Ask for the missing scoped authority. Capability availability is not authorization. |
| Product requirement remains unclear | Ask one focused user question and record the answer in a new assignment packet before dispatch. Let the implementer investigate technical feasibility in source. |
| Taiga context pagination is unknown or contradictory | Fetch the missing page/evidence or stop with incomplete context. Never treat `hasMore=null` or `nextPage=null` as terminal by itself; a null next-page value needs explicit evidence that its source was observed. |

`workflow-preflight.ps1` evaluates a local JSON snapshot and returns `ready`,
profile availability, required capabilities, browser providers, missing
authorized actions, and blockers. The coordinator supplies observations from
the current host and does not represent this offline result as proof that a
provider action succeeded.
