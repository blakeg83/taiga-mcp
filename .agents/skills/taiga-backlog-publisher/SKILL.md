---
name: taiga-backlog-publisher
description: Interpret a completed natural-language or Markdown implementation plan into a faithful, estimated Taiga backlog publishing plan. Do not use for implementation, review, Git operations, or live backlog mutation.
---

# Taiga Backlog Publisher

Turn an approved implementation plan into an internal publishing plan that is
ready for a later Taiga publishing workflow. The input may be ordinary prose,
Markdown headings, tables, checklists, or a mixture; do not require a rigid
schema. Preserve the plan's requirements and architectural decisions while
making the work-item hierarchy and story estimates explicit.

## Boundaries

- This skill plans and estimates. It does not implement the plan, review code,
  create a PR, run Git commands, or mutate Taiga.
- Do not create, update, assign, link, comment on, or delete Taiga work items
  during a planning-only request. Read-only project metadata may be used only
  when it is available and needed to select configured estimation options.
- Do not use subagents, multi-agent orchestration, heartbeats, telemetry,
  recovery loops, or another external planning service.
- Do not add architecture, dependencies, acceptance criteria, or unrelated
  work that the source plan does not support. If a decision is missing, record
  the gap or blocker instead of inventing an answer.

## Interpret the plan

1. Identify the source plan's epics, user stories, tasks, acceptance criteria,
   architectural decisions, ordering, and explicit exclusions. Recognize
   common Markdown conventions such as headings, numbered sections, tables,
   and task checklists.
2. Preserve an existing hierarchy and wording. Keep task descriptions and
   checklist items intact, including their completion markers where relevant.
   Keep acceptance criteria attached to their story; do not turn them into
   task estimates or new requirements.
3. For an unstructured plan, organize only what is present into a conservative
   epic/story/task hierarchy. Mark inferred boundaries or titles as inferred
   and explain the evidence. Keep the source order unless the plan explicitly
   specifies another order.
4. Give tasks deterministic two-digit numeric prefixes (`01`, `02`, `03`, ...)
   within each story. Prefer an explicit order from the source; otherwise use
   the source order. Do not use API response order, arbitrary priority, or task
   references as a substitute for an absent ordering decision.
5. Report missing information that prevents reliable publication, such as an
   ambiguous story boundary, an unresolved dependency, contradictory
   architecture, or an unavailable project estimation configuration. Do not
   silently resolve a material ambiguity.

## Estimate stories

Estimate the whole story, including implementation, integration, testing, and
expected correction effort. Never sum task estimates and never produce
task-level point estimates. Use this relative rubric when the project supports
these values:

| Points | Guidance |
| --- | --- |
| 1 | Trivial, isolated implementation |
| 2 | Small, straightforward change |
| 3 | Moderate implementation with limited complexity |
| 5 | Substantial implementation involving several components |
| 8 | Complex work involving meaningful integration or uncertainty |
| 13 | Very large story; recommend decomposition |

Before selecting a point value, discover the project's configured estimation
point options and computable roles through available read-only Taiga metadata or
caller-provided configuration. Use the configured option's actual value and
ID; never invent an ID or a value. If the configured scale differs from the
default rubric, map the same relative complexity to the closest supported
configured value and state the mapping.

Select exactly one role for a computable estimate. Prefer an unambiguous role
associated with the caller or explicitly configured for the project. If more
than one role is equally eligible, or no computable role is available, report
the ambiguity and leave the estimate unresolved rather than guessing.

Distinguish all of these states in the output:

- `undefined`: configuration or role information is unavailable, so no valid
  estimate can be selected;
- `0`: the project explicitly provides a zero-point option and the story is
  intentionally assigned it; and
- a supported positive option: the selected configured value and its ID.

If a story is at or beyond the largest supported value, flag it as a split
candidate and explain the uncertainty or integration risk. A 13-point story
may still be reported as 13 when that option exists, but must carry the
decomposition recommendation. Do not lower a large estimate merely to avoid
the flag.

## Publishing-plan output

Return a clear internal plan with these sections, adapting the presentation to
the input when a section is genuinely empty:

1. **Source fidelity and blockers** — source format, preserved decisions,
   inferred structure, unresolved gaps, and explicit exclusions.
2. **Hierarchy** — each epic, story, acceptance-criteria block, and ordered
   task list. Keep task descriptions/checklists and show deterministic prefixes.
3. **Story estimates** — one row or entry per story containing the complexity
   rationale, configured point value, point-option ID, selected role, and any
   split or uncertainty flag. Never list task points.
4. **Publication inputs and verification** — the read-only data still needed
   before publication, the intended creation/linking order, and checks that a
   later publisher should perform, including assignment and read-back
   verification when that workflow is implemented.

For a planning-only request, make the no-write result explicit. If required
configuration is absent, the plan may still describe the hierarchy, but the
affected story estimates must remain `undefined` and the missing configuration
must be a blocker; do not substitute comments, descriptions, or invented
values for native Taiga estimates.
