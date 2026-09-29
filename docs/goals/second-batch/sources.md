# Source evidence for the second batch

Reviewed 2026-09-28. Implementation baseline: the current repository's 23 exposed
tools and existing tests. API evidence is pinned upstream source, not a claim
about the version of any live Taiga deployment. No live data was read or changed
to prepare these plans.

Pinned taiga-back revision: `4d11baef9027f5598f6341d6eb4261de2840688e`.

| Area | Primary source | Planning implication |
| --- | --- | --- |
| Current user | [users API](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/users/api.py), [serializer](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/users/serializers.py) | users/me returns the authenticated user; map only identity fields needed for workflows. |
| Memberships and statuses | [project viewsets](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/api.py), [serializers](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/serializers.py) | Membership user ID differs from membership ID. Admin responses may add email fields. Story statuses have archive/WIP fields; task/epic statuses do not. |
| Reference lookup | [ByRefMixin](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/mixins/by_ref.py) | by_ref requires ref plus project ID or slug and delegates to retrieval permissions. |
| Sprints | [milestone API](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/milestones/api.py), [serializer](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/milestones/serializers.py) | Taiga calls sprints milestones; list filters include project and closed. Summary headers are not necessarily pagination counts. |
| Epics and relationships | [epic API](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/api.py), [serializer](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/epics/serializers.py) | Nested relationships use the story ID for lookup; list entries are epic/user_story/order, not full story details. |
| Versions | [OCC mixin](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/occ/mixins.py) | Forward caller versions; errors are not uniformly 409 and nonoverlapping stale edits may be accepted. |
| History | [history API](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/history/api.py), [serializer](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/history/serializers.py), [model](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/history/models.py) | Four work-item kinds are supported. type=comment filters nonempty comments; deletion/hidden flags still need handling. Entry IDs are strings. |
| Pagination | [pagination mixin](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/base/api/pagination.py) | page selects a page; headers expose continuation/count information. Explicitly sending page is important for history. |

[Official REST documentation](https://docs.taiga.io/api.html) is a route-discovery
aid. Before coding, recheck the exact request/response contract and record fixtures
from these pinned serializers or the supported deployment's documented version.
If an endpoint shape differs, update the goal and contracts with evidence; do not
invent compatibility or loosen unrelated response validation.
