# Work-item attachment detail contract

This contract supports story #22, task #30, and the shared attachment API
boundary. It was checked on 2026-10-02 against the Taiga endpoint
documentation at `main` and Taiga backend revision
`4d11baef9027f5598f6341d6eb4261de2840688e`. The revision is source evidence,
not a claim about every deployed Taiga instance.

## Detail routes and kind mapping

The public kind is closed to `epic`, `user_story`, and `task`. The detail route
is selected internally and the caller supplies only the positive attachment
ID:

| kind | detail route | backend content type |
| --- | --- | --- |
| `epic` | `epics/attachments/{attachmentId}` | `epics.epic` |
| `user_story` | `userstories/attachments/{attachmentId}` | `userstories.userstory` |
| `task` | `tasks/attachments/{attachmentId}` | `tasks.task` |

The request is one authenticated `GET`. It does not list attachments, fetch
the parent work item, expand relationships, or follow a returned file URL.
The route's permission checks remain authoritative; project and parent
identity are read from the returned attachment rather than supplied as
additional filters.

Evidence:

- [Epic endpoint inventory](https://github.com/taigaio/taiga-doc/blob/main/api/epics/endpoints.adoc)
- [User-story endpoint inventory](https://github.com/taigaio/taiga-doc/blob/main/api/user-stories/endpoints.adoc)
- [Task endpoint inventory](https://github.com/taigaio/taiga-doc/blob/main/api/tasks/endpoints.adoc)
- [Pinned attachment view sets](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/api.py)
- [Pinned attachment serializer](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/serializers.py)
- [Pinned attachment model](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/models.py)

## Response contract

The shared serializer supplies these fields:

- Required positive identity: `id`.
- Required positive ownership context: `project` and `object_id`. The detail
  route identifies the parent kind; `object_id` identifies the parent within
  that kind. No parent title or other work-item data is supplied by this
  endpoint.
- Optional ownership/file metadata: `owner`, `name`, `attached_file`, `size`,
  `sha1`, `description`, `order`, `is_deprecated`, `from_comment`,
  `created_date`, and `modified_date`.
- Optional locations: `url`, `preview_url`, and `thumbnail_card_url`. These
  are opaque upstream URLs/fragments and are returned as metadata only; the
  client does not download or validate their contents.

The client validates the requested kind and positive attachment ID before
HTTP. It rejects a non-object response, a missing/nonpositive identity, or a
response whose `id` does not equal the requested attachment ID. Invalid
required `project` or `object_id` values are also rejected safely. Optional
null properties remain null internally and are omitted from public tool JSON;
present empty strings remain meaningful values.

## Explicit non-goals

This contract does not include binary download, URL refresh, upload, update,
delete, issue attachments, parent-detail enrichment, or bulk retrieval.
