# Work-item attachment update contract

This contract supports story #25, task #39, and the shared attachment API
boundary. It was checked on 2026-10-02 against the Taiga documentation at
`main` and Taiga backend revision
`4d11baef9027f5598f6341d6eb4261de2840688e`. The revision is source evidence,
not a claim about every deployed Taiga instance.

## Supported kinds and routes

The public kind set is exactly `epic`, `user_story`, `task`, and `issue`. Each kind has
its own attachment endpoint, selected internally from the closed route map:

| kind | partial-update route | backend content type |
| --- | --- | --- |
| `epic` | `/api/v1/epics/attachments/{attachmentId}` | `epics.epic` |
| `user_story` | `/api/v1/userstories/attachments/{attachmentId}` | `userstories.userstory` |
| `task` | `/api/v1/tasks/attachments/{attachmentId}` | `tasks.task` |
| `issue` | `/api/v1/issues/attachments/{attachmentId}` | `issues.issue` |

The update operation uses one authenticated JSON `PATCH`. Taiga documents a
`200 OK` response containing the authoritative attachment detail object. The
client does not list the attachment first, fetch its parent, or follow a file
URL.

## Verified editable allowlist

Taiga's common `BaseAttachmentViewSet` and `AttachmentValidator` are shared by
the four supported kinds. The public contract therefore exposes the same
allowlist for each kind:

| field | JSON type | semantics |
| --- | --- | --- |
| `description` | string | Empty string is an explicit empty description. |
| `order` | integer | Zero is valid and is forwarded unchanged. |
| `is_deprecated` | boolean | Both `true` and `false` are valid and are forwarded unchanged. |

At least one allowlisted field must be present. Omitted fields are not sent and
remain unchanged. `null` is not a clear form for any field and is rejected
locally. The client does not read the current attachment to compare values;
an empty field set is the only locally detectable no-op and is rejected before
HTTP.

The following response or upload fields are intentionally not public update
fields: `id`, `project`, `owner`, `name`, `attached_file`, `size`, `object_id`,
`sha1`, `from_comment`, `created_date`, and `modified_date`. In particular, the
file bytes, parent association, and project cannot be changed by this command.
`PUT` is unsupported by the pinned backend because its attachment update
handler rejects non-partial updates; partial metadata changes use `PATCH`.

There are no per-kind field differences identified in the shared backend
validator. Permissions remain authoritative upstream: each kind permits an
appropriate project modify permission or attachment-owner update permission.

## Concurrency and failure behavior

The attachment model and validator do not expose or validate a resource
`version` field. Unlike work-item updates, this command therefore does not
accept a caller-supplied attachment version and does not invent one. Taiga's
database row lock serializes the update, but the client must not retry a
conflict or any ambiguous write. A received HTTP 401 may still use the shared
transport's one authentication replay; no other retry is allowed.

After a confirmed successful `PATCH`, the response is mapped and returned as
authoritative attachment metadata. If the write succeeds but response JSON or
mapping fails, the error must state that the update may already have applied
and direct the caller to inspect the attachment before retrying. Safe HTTP
errors expose only the repository's bounded status/category and allowlisted
field or conflict information; raw upstream bodies are not returned.

## Evidence

- [Epic attachment endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/epics/endpoints.adoc)
- [User-story attachment endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/user-stories/endpoints.adoc)
- [Task attachment endpoints](https://github.com/taigaio/taiga-doc/blob/main/api/tasks/endpoints.adoc)
- [Epic attachment edit](https://github.com/taigaio/taiga-doc/blob/main/api/epics/edit-attachment.adoc)
- [User-story attachment edit](https://github.com/taigaio/taiga-doc/blob/main/api/user-stories/edit-attachment.adoc)
- [Task attachment edit](https://github.com/taigaio/taiga-doc/blob/main/api/tasks/edit-attachment.adoc)
- [Pinned attachment view sets](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/api.py)
- [Pinned attachment serializer](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/serializers.py)
- [Pinned attachment validator](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/validators.py)
- [Pinned attachment model](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/models.py)
- [Taiga optimistic-concurrency notes](https://github.com/taigaio/taiga-doc/blob/main/api/general-notes.adoc)
