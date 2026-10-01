# Scheduling and epic acceptance

Queue only the selected scope and approved relative priority/dependency edges.
Resolve identities, parent stories, repository mappings, cycles, missing
predecessors, and duplicate refs before dispatch. A child task belongs to its
story pipeline; a shared story is implemented once. An open prerequisite PR is
not integrated evidence. Eligible work has authorized scope, complete context,
no blocker, verified prerequisite merge in the configured base, and capacity.

The default is two active pipelines per repository plus a separate host
worker-turn limit. Preparing, implementation, correction, review, and
publication consume a pipeline slot. Dependency/merge waiting releases it but
retains ownership. Separate chats, worktrees, output directories, and fixture
resources are required. One session heartbeat fairly observes all runs; it is
not one schedule per ticket or tick. Unchanged observations stay quiet.

An epic has a parent record and linked story runs, not a giant shared branch.
Every required story must have reviewed and merged evidence. Re-read membership
and criteria before closure, capture the actual integrated base revision(s), and
run combined acceptance in a dedicated verification checkout. A selected
ordinary reviewer may perform this check within the host budget. Route defects
to an unmerged responsible story or a new explicit follow-up; never amend a
merged branch silently. Only then may the coordinator update the mapped epic Done
status.
