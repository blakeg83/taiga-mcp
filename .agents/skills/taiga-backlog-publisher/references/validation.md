## Local validation expectations

Validate this skill with a focused local/mock review, never with live Taiga
publishing writes:

- exercise a structured plan containing multiple stories and ordered tasks;
- exercise a less structured plan and confirm conservative hierarchy
  interpretation, preserved requirements, and deterministic task prefixes;
- inspect missing configuration, ambiguous role selection, exact duplicate
  candidates, partial write failure, and an ambiguous write outcome;
- confirm that a planning-only request performs no Taiga writes;
- confirm that publication uses the required preflight, creation, estimate,
  and authoritative read-back sequence; and
- confirm compatibility with `taiga-story-loop-lite`: no agents, no
  implementation/review/PR workflow, and numeric task ordering is preserved.

Record which checks were inspected from local instructions/examples and which
were actually exercised through native runtime capabilities. A read-only
walkthrough is not evidence that live publication succeeded.

### Concrete transient mock scenario

For a focused local/mock exercise, use this deterministic fixture in memory;
do not add a runner or helper to the repository and do not call live Taiga
write tools:

- Input project: slug `taiga-mcp`, ID `12`; known UI origin
  `https://taiga.example`; authenticated user ID `42`, active.
- Membership response: one active membership for user `42`, with
  `is_admin=true`; project roles contain one computable role `{ id: 7 }`;
  point options contain `{ id: 21, value: 1 }`, `{ id: 22, value: 3 }`, and
  `{ id: 23, value: 5 }`.
- Approved plan: epic `Release 1`; story `Import API` estimated at `3`, with
  tasks `01 Add endpoint` and `02 Add tests`; story `Verify UI` estimated at
  `5`, with task `01 Add browser check`.
- Duplicate scans return empty closed/archived-aware pages with
  `next_page=null` and `has_more=false`. Synthetic writes return epic
  `id=100, ref=50`, stories `id=200/ref=60` and `id=201/ref=61`, and tasks
  `id=300/ref=70`, `id=301/ref=71`, and `id=302/ref=72`, all assigned to `42`.
  Relationship writes return confirmed links. Estimate read-backs return
  role `7` mapped to point IDs `22` and `23`, with `total_points=3` and
  `total_points=5` respectively; relationship verification
  returns all story IDs.

The exercise must assert the exact safe sequence
`preflight → epic → stories → links → ordered tasks → fresh story reads →
estimate writes → estimate reads → relationship/identity/assignment reads`,
by consuming the supplied responses to decide whether each next action is
allowed. Do not assign an expected event list or report as a constant: record
each receipt from the response, stop when a response is blocking or ambiguous,
and derive the report fields from those receipts. Every assignment must be
`42`, no duplicate write may occur, and the generated report must include
fixture-backed direct links such as:

```text
Publication: SUCCESS
Project: taiga-mcp (12)
User: 42
Epic: Release 1 (#50) assigned_to=42 https://taiga.example/project/taiga-mcp/epic/50
Stories: Import API (#60)=3 points https://taiga.example/project/taiga-mcp/us/60; Verify UI (#61)=5 points https://taiga.example/project/taiga-mcp/us/61
Tasks: #70 https://taiga.example/project/taiga-mcp/task/70; #71 https://taiga.example/project/taiga-mcp/task/71; #72 https://taiga.example/project/taiga-mcp/task/72 — all assigned_to=42 and attached to their planned stories
Confirmed story-point total: 8
```

Then alter one supplied response at a time and expose the derived trace and
report: missing point/role configuration or two equally eligible computable
roles must stop at preflight with `BLOCKED` and zero create calls; an exact
matching closed or archived candidate must stop after the duplicate scan with
`BLOCKED` and zero create calls; and an ambiguous task-create transport result
must make exactly one attempted create, stop dependent work, and produce
`PARTIAL` with a note that the write may have applied. Record these mock
results separately from static inspection and native runtime execution. The
fixture is validation evidence only; it is not a publisher runtime, retry
framework, or recovery mechanism.

### Permission and total reconciliation checks

- Replace the admin membership with an active non-admin membership whose
  `role_id=7`. Supply role 7 permissions `view_epics`, `add_epic`,
  `modify_epic`, `view_us`, `add_us`, `modify_us`, `view_tasks`, and `add_task`.
  Preflight should proceed without another permission tool or trial write.
  Removing `modify_epic` must block linking before any create. Missing/null
  permissions remain unknown, while `[]` supplies no authority. A different
  estimation role's permissions must not authorize the member.
- Add point option `{ id: 24, value: 3 }` and return story `points={"7":23,"8":24}`,
  `total_points=8`. Report selected-role estimate 5 and whole-story total 8,
  flag the discrepancy against the approved 5, and mark publication partial.
  Preserve role 8 even if it is non-computable; no corrective write is allowed.
- With that same mapping, `total_points=5` is an inconsistent server total;
  do not report a verified whole-story total. An unknown point ID or missing
  total also leaves it unverified. Undefined values contribute nothing;
  numeric zero and fractional values must retain their meaning.
- A missing UI origin should leave otherwise verified publication successful
  with project/reference identifiers and links marked unavailable.
- Inspect the trace for one shared metadata/duplicate scan per resource type
  (plus pagination), and reuse the estimate read-back for final story checks.

### Upstream contract references

- [Permission codenames](https://github.com/taigaio/taiga-back/blob/main/taiga/permissions/choices.py),
  [epic/link permissions](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/epics/permissions.py),
  and [story/estimate permissions](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/userstories/permissions.py).
- [Whole-story totals](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/userstories/utils.py):
  `attach_total_points` sums defined values across all roles, without a
  `computable` filter.
- [Taiga webhook examples](https://docs.taiga.io/webhooks.html) use `/us/{ref}`
  in story permalinks.
