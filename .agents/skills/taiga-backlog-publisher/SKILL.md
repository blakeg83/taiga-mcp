---
name: taiga-backlog-publisher
description: Interpret an approved implementation plan into a faithful, estimated Taiga backlog and, when explicitly requested, publish, assign, estimate, and verify it without duplicate or ambiguous writes.
---

# Taiga Backlog Publisher

Turn an approved implementation plan into a faithful Taiga backlog plan. The
input may be ordinary prose, Markdown headings, tables, checklists, or a
mixture; do not require a rigid schema. Preserve the plan's requirements and
architectural decisions while making the work-item hierarchy and story
estimates explicit.

When the user explicitly requests publication and a configured Taiga MCP
connection is available, execute the publication workflow in this document.
Planning-only requests never mutate Taiga. A publication is successful only
when the created hierarchy, assignments, relationships, and native estimates
have been read back and verified.

## Boundaries

- This skill plans, estimates, and optionally publishes a Taiga backlog. It
  does not implement the planned software, review code, create a PR, or run
  Git commands.
- Do not use subagents, multi-agent orchestration, heartbeats, telemetry,
  recovery loops, or another external planning or publishing service.
- A planning-only request must not create, update, assign, link, comment on, or
  delete Taiga work items. Read-only project metadata may be used only when it
  is available and needed to select configured estimation options.
- Publication requires an explicit user request, a complete target project,
  and all required MCP tools. Do not silently change an approved plan to make
  it publishable.
- Do not invent IDs, point values, roles, project permissions, requirements,
  acceptance criteria, task order, or ticket links. Record an ambiguity or
  blocker instead.
- Never retry a write whose outcome is ambiguous. Read the relevant entity and
  report its state before a user decides whether to continue.

## Interpret the plan

1. Identify the source plan's epics, user stories, tasks, acceptance criteria,
   architectural decisions, ordering, dependencies, and explicit exclusions.
   Recognize common Markdown conventions such as headings, numbered sections,
   tables, and task checklists.
2. Preserve an existing hierarchy and wording. Keep task descriptions and
   checklist items intact, including completion markers where relevant. Keep
   acceptance criteria attached to their story; do not turn them into task
   estimates or new requirements.
3. For an unstructured plan, organize only what is present into a conservative
   epic/story/task hierarchy. Mark inferred boundaries or titles as inferred
   and explain the evidence. Keep source order unless the plan explicitly
   specifies another order.
4. Give tasks deterministic two-digit numeric prefixes (`01`, `02`, `03`, ...)
   within each story. Prefer an explicit order from the source; otherwise use
   source order. Do not use API response order, arbitrary priority, or task
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

Before selecting point values, discover the project's configured estimation
point options and computable roles through read-only Taiga metadata or
caller-provided configuration. Use each configured option's actual value and
ID; never invent an ID or a value. If the configured scale differs from the
default rubric, map the same relative complexity to the closest supported
configured value and state the mapping.

Select estimation roles from the story's work, never from the authenticated
user's project membership. For every story:

1. Analyze the requirements, acceptance criteria, architecture, and planned
   implementation tasks.
2. Identify every configured `computable` role with meaningful work in the
   story. A single-discipline story has one role mapping; a story spanning
   backend, frontend, design, testing, or other configured disciplines has one
   mapping for each relevant role.
3. Estimate each role's independent contribution, including role-specific
   implementation, integration, testing, and expected correction effort.
   Avoid double-counting work shared across roles.
4. Map each role to an existing configured point-option ID. Do not treat the
   existence of multiple computable roles as an ambiguity by itself.

Use role names only as semantic guidance and use the actual configured role and
point IDs. For example, API/business-logic/database/integration work generally
maps to a configured Back role; client UI/browser work to Front; UX or visual
design work to Design; and dedicated test infrastructure to QA/Testing when
that role is configured and relevant. If a story requires backend, frontend,
and design work, estimate all three when those configured roles are computable.
Ask for clarification only when the requirements are genuinely insufficient to
identify the relevant roles or estimate their work reliably, or when no
configured computable role reasonably matches.

Distinguish all of these states in the output:

- `undefined`: configuration or role information is unavailable, so no valid
  estimate can be selected;
- `0`: the project explicitly provides a zero-point option and the story is
  intentionally assigned it; and
- a supported positive option: the configured value and ID for one role's
  contribution. A story's estimate is the complete role-to-option mapping plus
  its reconciled whole-story total; do not collapse it to one role or value.

Evaluate decomposition at both the role and story levels. If an individual
role's contribution is at or beyond the largest supported configured value,
flag that role's work as a split candidate and explain the uncertainty or
integration risk. Also consider decomposition when the aggregate story is
too broad, cross-role coordination is substantial, or several individual
contributions are independently large. A multi-role story is not automatically
a split candidate merely because its combined total exceeds the largest
configured single-role value. A 13-point contribution may still be reported
when that option exists, but must carry the decomposition recommendation; do
not lower a large role estimate merely to avoid the flag.

## Publishing-plan output

Return a clear internal plan with these sections, adapting the presentation to
the input when a section is genuinely empty:

1. **Source fidelity and blockers** — source format, preserved decisions,
   inferred structure, unresolved gaps, and explicit exclusions.
2. **Hierarchy** — each epic, story, acceptance-criteria block, and ordered
   task list. Keep task descriptions/checklists and show deterministic
   prefixes.
3. **Story estimates** — one row or entry per story containing the complexity
   rationale, each relevant role-to-point mapping, the reconciled whole-story
   total, and any split or uncertainty flag. Never list task points.
4. **Publication inputs and verification** — the read-only data still needed
   before publication, the intended creation/linking order, and checks that a
   later publisher should perform, including assignment and read-back
   verification.

For a planning-only request, make the no-write result explicit. If required
configuration is absent, the plan may still describe the hierarchy, but the
affected story estimates must remain `undefined` and the missing configuration
must be a blocker; do not substitute comments, descriptions, or invented
values for native Taiga estimates.

## Publication mode

Publication mode is entered only after the user explicitly asks to publish the
approved plan. Treat the plan as immutable input. Preserve its epic/story/task
hierarchy, descriptions, acceptance criteria, checklist text, task order, and
chosen story estimates. Before any write, return or internally assemble a
preflight record containing the target project, authenticated user, selected
roles per story, point options, duplicate findings, required tools, and
blockers.

### Required tools

Confirm that the active Taiga MCP connection exposes every operation needed by
the selected plan before the first write. The normal publish path requires:

- `resolve_project`, `get_current_user`, and `list_project_members`;
- `list_points` and `list_project_roles`;
- `list_epics`, `list_user_stories`, and `list_tasks` for duplicate checks;
- `create_epic`, `create_user_story`, `link_user_story_to_epic`, and
  `create_task`;
- `get_epic`, `get_user_story`, `get_task`, and
  `list_epic_user_stories` for authoritative verification; and
- `set_user_story_estimates` for native story-point persistence.

If a required operation is unavailable, stop before writing and report the
exact missing tool. Do not replace a native estimate write with a comment,
description, custom field, or local state.

### Publishing preflight

Perform all of the following before creating anything:

1. Resolve the exact target project slug with `resolve_project`, or validate a
   caller-supplied positive project ID against the project context. Preserve
   both the slug and internal ID in the report.
2. Call `get_current_user`. Require a positive authenticated user ID and an
   active account when the response supplies `is_active`. This ID is the only
   assignee used for created epics, stories, and tasks.
3. Read every page of `list_project_members` for the target project. Require
   exactly one active membership for the authenticated user with a usable
   `user_id`. Treat pending, inactive, missing-user, duplicate, or conflicting
   membership records as a preflight blocker. Inspect the authoritative
   membership `role_id`, `role_name`, `is_admin`, and `is_owner` fields when
   supplied. Membership proves project association, but it is not by itself
   proof of write or assignment authority. Accept an administrative/owner
   flag as sufficient project-level evidence when the connection exposes it;
   otherwise match the membership's `role_id` to `list_project_roles.id` and
   inspect that role's `permissions`. For the normal epic/story/task workflow,
   require `view_epics`, `add_epic`, `modify_epic` (link stories), `view_us`,
   `add_us`, `modify_us` (estimates), `view_tasks`, and `add_task`. Check only
   capabilities used by the approved plan. Self-assignment uses the confirmed
   active membership and these create permissions; do not require an invented
   assignment permission or administrative status. The estimation role may
   differ from the member's role and does not grant the member authority.
   Missing/null permissions are unknown; an empty array grants none. If the
   required permissions are absent or evidence conflicts, stop and name them.
   Never use a trial mutation to discover permissions and never guess another
   assignee after a permission rejection.
4. Read every page of `list_project_roles` and `list_points`. For each planned
   story, identify all relevant configured computable roles from its
   requirements, acceptance criteria, architecture, and planned tasks, then
   map each role's estimate to an existing point-option ID. The authenticated
   user's membership role is used for access and permissions only, never to
   choose estimate roles. Preserve `value: null` as unestimated and
   distinguish it from a configured numeric zero. No write may begin while a
   story's relevant-role analysis or point mapping is ambiguous.
5. Confirm the required tool set listed above is available. Do not infer tool
   availability from documentation or from a previous invocation.
6. Check for possible duplicates before any create operation. For each
   needed work-item type, use the corresponding project-scoped list
   operation with closed/archived coverage and no unrelated restrictive
   filters: `list_epics(includeClosed=true)`,
   `list_user_stories(includeClosed=true, includeArchived=true,
   includePageInfo=true)`, and `list_tasks(includeClosed=true)`. Compare all
   planned subjects against these results locally. Follow every positive
   `next_page` until the server reports completion. If `next_page` is null and
   `has_more` is true, or if `total` proves that returned pages are incomplete,
   stop with an inconsistent-pagination blocker. If the available metadata is
   unknown (`next_page`, `has_more`, and `total` are all null), do not claim a
   complete duplicate scan; treat it as a no-write blocker unless the active
   connection contract explicitly defines null `next_page` as terminal.
   Report exact and near matches separately. An exact existing candidate is a
   blocker unless the user explicitly supplies a safe reuse decision; never
   create a second item merely because its reference differs.
   When a list row cannot establish the intended parent story or epic, read the
   candidate with `get_user_story` or `get_task` and inspect the relevant epic
   relationship with `list_epic_user_stories` before deciding whether it is a
   duplicate. Do not infer a relationship from subject text.
7. Validate that all planned stories have an unambiguous target epic and all
   planned tasks have an unambiguous parent story. Preserve the plan's order;
   do not infer missing relationships from subject text.

Fetch each metadata list once per publication, following its pages, and reuse
it for all items. Scan each needed work-item type once for the project and
compare all planned subjects locally; do not repeat full scans for each item.

A preflight failure is a no-write result. A preflight success is not a claim
that Taiga has accepted a future write; it only authorizes the ordered
publication sequence.

### Ordered creation and assignment

Create only after preflight succeeds, in this order:

1. Create each required epic with `create_epic`, supplying the authenticated
   user's ID through `assigned_to` and preserving supported description, tags,
   color, and explicitly selected status values. Capture the authoritative
   internal ID, project, displayed reference, assignment, and version from
   each response.
2. Create each story with `create_user_story`, supplying the authenticated
   user's ID through `assigned_to`. Preserve its subject, description,
   acceptance criteria, tags, and sprint placement when present. Capture the
   authoritative ID, reference, project, assignment, version, and estimate
   fields returned by Taiga.
3. Link every created story to its intended created epic with
   `link_user_story_to_epic`, using the captured internal IDs and the plan's
   explicit relationship order when supplied. A relationship response must be
   captured; do not treat story creation as proof of the link.
4. Create tasks in each story's deterministic numeric order with
   `create_task`, supplying `userStoryId` and the authenticated user's ID
   through `assigned_to`. Preserve task descriptions, checklist text, tags,
   and the parent story. Do not add task estimates. Capture each authoritative
   ID, reference, project, parent, assignment, and version.

After a failed or ambiguous write, stop dependent publication, do not repeat
the operation, and produce a partial-completion report. Already-created
independent items may be reported, but do not continue in a way that could
create children without a confirmed parent or relationship.

### Native estimate persistence

For every created story, use the complete role-to-point mapping selected during
planning and the configured role/point IDs from preflight:

1. Call `get_user_story` immediately before the estimate update and use its
   authoritative current version. Never assume the version in the create
   response is still current. Capture the returned `points` mapping as the
   baseline for roles outside the requested scope; if it is unavailable, do
   not claim that unrelated estimates were preserved.
2. Call `set_user_story_estimates` once with a `rolePoints` array containing
   one entry for every relevant computable role and no entries for roles
   outside the requested scope. The supplied version must be the fresh version
   read in step 1. This single partial update must preserve existing estimates
   for unrelated roles.
3. On any non-success or ambiguous result, do not retry or refresh-and-retry.
   Record the story as estimate-unverified and stop dependent estimate work.
4. Call `get_user_story` after the write. Verify every submitted role maps to
   its submitted point-option ID and that each numeric value matches the
   configured point option, not an untrusted total alone. Verify that every
   role outside the requested scope is unchanged from the pre-write baseline,
   and verify that the story's returned project and assignment remain correct.
5. Reconcile the entire returned `points` mapping against `list_points`:
   resolve every non-null point-option ID and sum all configured numeric
   values across roles, including non-computable roles. Null mappings and
   options with `value: null` contribute no numeric value; zero remains zero.
   Compare this sum with the returned `total_points` (allow normal floating
   point rounding). No numeric contributions means unestimated, not zero.
   Unknown point IDs, missing mappings/totals, or a mismatched server total
   leave the total unverified. Report every relevant role's estimate and the
   whole-story total separately, including preserved estimates from roles
   outside the requested scope. Flag any role value that differs from the
   approved mapping or any total that differs from the complete returned role
   mapping, and mark publication partial; never clear or overwrite another
   role's points to force agreement.

An estimate is not confirmed by a successful tool response alone; it is
confirmed only when every submitted role mapping, every preserved unrelated
mapping, and the reconciled whole-story total pass authoritative read-back.
Undefined role estimates remain undefined and are reported as blockers rather
than silently assigned.

### Authoritative verification and report

After the ordered writes and estimate updates, verify every result:

- `get_epic` each created epic and confirm identity, project, subject, and
  authenticated assignment.
- `get_user_story` each created story and confirm identity, project, subject,
  authenticated assignment, version, and confirmed native estimate. Use
  `list_epic_user_stories` for each created epic and verify every intended
  story relationship by internal ID and relationship order. Follow every
  positive `next_page` across the complete relationship listing; if pagination
  is inconsistent or its metadata is unknown, mark the relationship check
  incomplete and do not report the backlog as verified.
- `get_task` each created task and confirm identity, project, subject,
  authenticated assignment, and intended parent story.
- Reconcile the verified entities against the approved plan. Any missing,
  mismatched, or unreadable field is unverified; do not present it as success.

Reuse the post-estimate story read for final story verification when no later
write affects that story; avoid a second identical detail read.

Produce a concise report with separate sections for:

- preflight inputs and results;
- created epics, stories, links, tasks, and their Taiga references;
- confirmed assignments and native role estimates;
- per-role estimate values and reconciled whole-story totals, clearly
  distinguished when preserved or other-role contributions exist; never include
  unverified totals;
- failed, ambiguous, or unverified operations and whether a write may have
  applied; and
- direct Taiga UI links for every created item when the UI origin is known.

Construct links only from a known Taiga UI origin and the authoritative
project slug/reference: `/project/{slug}/epic/{ref}`,
`/project/{slug}/us/{ref}`, and `/project/{slug}/task/{ref}`. Use displayed
references, not internal IDs. Never turn an API `/api/v1/` URL into a UI link
by guesswork. If the UI origin is unavailable, include the project slug and
references and mark the link as unavailable rather than fabricating one.

The report is a success only when all intended items, relationships,
assignments, and estimates are confirmed. An unavailable UI origin alone does
not invalidate verified publication; report references with links unavailable.
Otherwise label it partial or blocked and list the exact next decision needed
from the user.

## Invocation and expected output

Invoke the skill with `$taiga-backlog-publisher` followed by the approved
implementation plan and, for publication, an explicit instruction such as
"publish this plan to project `<slug>`". A planning request returns the four
publishing-plan sections and an explicit no-write statement. A publication
request returns the preflight result first, then either a blocked/no-write
result or a report containing every created epic/story/task, relationship,
authenticated assignment, confirmed native estimate, numeric story-point
totals, direct UI links when available, and any failed or unverified step.

Do not treat a plan, a successful preflight, or a create response without
authoritative read-back as a completed publication.

## Skill maintenance

When changing or validating this skill, use [the local validation fixture](references/validation.md).
It is maintenance guidance; do not load or run it during ordinary publication.
