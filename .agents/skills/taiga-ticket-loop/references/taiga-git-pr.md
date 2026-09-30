# Taiga, Git, and PR operations

The coordinator reads complete Taiga context before dispatch: project/ref/kind
resolution, detail, all relevant comment/history pages, all story task pages
including closed tasks, and for epics every linked story and its context. Each
captured page set must be contiguous from page 1 and end with authoritative
`hasMore=false` and `nextPage=null`; unknown or contradictory metadata is
incomplete context. Discover resource-specific statuses;
never infer IDs or English-label semantics across projects. Preserve assignees.

Only the coordinator writes milestone comments and statuses. Prepare each action
in the journal, use the authoritative returned version, and reconcile conflicts
or response loss through rereads/history/comments. Never replay a versioned
write blindly; the existing transport's one received-401 replay remains the
only auth retry.

Before every executable ticket, fetch the configured remote under a short lock,
capture the base branch SHA, and make a unique
`codex/<kind>-<ref>-<slug>-<run-suffix>` branch/worktree from that SHA. Verify
clean source, branch, HEAD, base, repository identity, and worker receipt. A
fetch failure or collision blocks dispatch. Before publication, fetch again;
target movement requires a non-force merge/update, checks, and the same review
loop on the resulting revision.

Before approving a refresh, compare the fetched target with the recorded base
or target SHA, not with the feature branch HEAD; only target movement triggers
a merge, invalidation, and another review. After a current pass, push only the
owned branch and verify its remote head. The push preflight requires a safe
`codex/...` branch, the checkout and local branch ref to match the reviewed
HEAD, and uses an explicit `refs/heads/branch:refs/heads/branch` refspec.
Query the exact repository/head/base, then create or update one matching PR with
Taiga identity, run marker, summary, criteria, tests, and reviewed SHA. Attach
created PRs to the relevant Codex chat and link them in Taiga. Open,
closed-unmerged, and merged are distinct. Default Done requires expected merge
provenance, required checks, integrated acceptance, and final Taiga receipts;
automatic merge and force-push are disabled.
