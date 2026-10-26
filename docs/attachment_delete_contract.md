# Work-item attachment deletion contract

This document defines the implemented attachment-delete boundary. It was checked on 2026-10-02 against the Taiga endpoint inventories
at `main` and Taiga backend revision
`4d11baef9027f5598f6341d6eb4261de2840688e`. The revision is source evidence,
not a claim about every deployed Taiga instance.

## Supported kinds and routes

The public kind set is exactly `epic`, `user_story`, `task`, and `issue`. The caller
selects one positive internal attachment ID; the client selects the route and
does not require a parent work-item ID or project ID:

| kind | delete route | backend content type |
| --- | --- | --- |
| `epic` | `/api/v1/epics/attachments/{attachmentId}` | `epics.epic` |
| `user_story` | `/api/v1/userstories/attachments/{attachmentId}` | `userstories.userstory` |
| `task` | `/api/v1/tasks/attachments/{attachmentId}` | `tasks.task` |
| `issue` | `/api/v1/issues/attachments/{attachmentId}` | `issues.issue` |

The operation is one authenticated `DELETE` with no request body. It does not
list attachments, fetch the parent work item, inspect sibling attachments, or
follow a file URL.

## Permission and server-side behavior

The pinned backend permits deletion for the corresponding project modify
permission or the attachment owner:

| kind | project permission | owner alternative |
| --- | --- | --- |
| `epic` | `modify_epic` | attachment owner |
| `user_story` | `modify_us` | attachment owner |
| `task` | `modify_task` | attachment owner |
| `issue` | `modify_issue` | attachment owner |

The server resolves the selected attachment within the kind-specific view set,
deletes that attachment record, and runs its attachment deletion history hook.
The client does not delete or patch the parent, sibling attachments, epic
relationships, or any local file downloaded from the attachment. Any server
storage cleanup remains server-side behavior and is not represented as a local
filesystem operation.

## Success receipt and failure policy

Taiga's documented destroy path returns HTTP `204 No Content`. The shared
transport confirms the status and does not parse or require a response body;
only that confirmed 204 response is success. The tool returns this small
receipt:

```json
{"kind":"task","attachment_id":901,"deleted":true}
```

The `kind` is the validated public kind and `attachment_id` is the caller's
positive internal attachment ID. A response with another 2xx status or an
otherwise unexpected successful response is not fabricated into a deletion
receipt. A body on a 204 response is ignored and is not exposed in the
receipt.

A missing attachment, including a repeated delete, remains a safe Taiga HTTP
404 error; it is not treated as an idempotent success. Permission failures,
blocked or archived project conditions, unexpected statuses, and transport
failures remain safe errors. An ambiguous DELETE failure is never retried.
Only a received HTTP 401 may use the shared transport's single authentication
replay. Cancellation remains cancellation and is passed through every layer.

## Evidence

- [Epic endpoint inventory](https://github.com/taigaio/taiga-doc/blob/main/api/epics/endpoints.adoc)
- [User-story endpoint inventory](https://github.com/taigaio/taiga-doc/blob/main/api/user-stories/endpoints.adoc)
- [Task endpoint inventory](https://github.com/taigaio/taiga-doc/blob/main/api/tasks/endpoints.adoc)
- [Pinned attachment view sets](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/api.py)
- [Pinned attachment permissions](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/permissions.py)
- [Pinned attachment model](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/models.py)
- [Pinned destroy mixin](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/base/api/mixins.py)
