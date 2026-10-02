# Work-item attachment list contract

This contract supports story #21, task #27, and is the shared boundary for
the attachment-list implementation in task #28. It was checked on 2026-10-02
against the Taiga documentation at `main` and Taiga backend revision
`4d11baef9027f5598f6341d6eb4261de2840688e`. The revision is source evidence,
not a claim about every deployed Taiga instance.

## Upstream routes and filters

Taiga documents one list route per supported resource:

| kind | route | verified filters | backend content type |
| --- | --- | --- | --- |
| `epic` | `epics/attachments` | `project`, `object_id` | `epics.epic` |
| `user_story` | `userstories/attachments` | `project`, `object_id` | `userstories.userstory` |
| `task` | `tasks/attachments` | `project`, `object_id` | `tasks.task` |

The client adds the positive `page` selector for the documented server
pagination convention. The outgoing query is limited to these three names,
with integer values encoded using invariant decimal formatting. The response
body is expected to be one JSON array; Taiga pagination headers are translated
to the repository's standard `{ items, page, total, next_page, has_more }`
envelope. Missing or invalid pagination headers remain explicit `null`.

Evidence:

- [Epic attachment list](https://github.com/taigaio/taiga-doc/blob/main/api/epics/list-attachments.adoc)
- [User-story attachment list](https://github.com/taigaio/taiga-doc/blob/main/api/user-stories/list-attachments.adoc)
- [Task attachment list](https://github.com/taigaio/taiga-doc/blob/main/api/tasks/list-attachments.adoc)
- [Pinned attachment view sets](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/api.py)
- [Pinned attachment serializer](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/serializers.py)
- [Pinned attachment model](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/models.py)

## Client scope and validation

- The public kind set is exactly `epic`, `user_story`, and `task`. `issue` is
  intentionally deferred to a later extension.
- `kind`, `id`, `projectId`, and `page` are validated before HTTP. IDs and page
  must be positive; kind comparison is ordinal and case-sensitive.
- The route mapping is shared and closed over the three supported kinds. It
  must not accept a caller-provided route or query name.
- The list operation performs no parent detail lookup, relationship expansion,
  status lookup, or all-page traversal. `project` and `object_id` are sent to
  Taiga together so its permission and ownership filters remain authoritative.
- This goal lists metadata and download locations only. It does not download
  file content or mutate attachments; URLs are returned as opaque upstream
  strings and are never followed by the client.

## DTO and null policy

The shared attachment DTO maps only fields verified by the pinned serializer:

`id`, `project`, `object_id`, `owner`, `name`, `description`, `order`, `size`,
`attached_file`, `url`, `preview_url`, `thumbnail_card_url`, `sha1`,
`is_deprecated`, `from_comment`, `created_date`, and `modified_date`.

`id`, `project`, and `object_id` are required positive response identities;
malformed values fail safely. Other fields are nullable where Taiga can omit or
return null, and public JSON omits those null properties. Empty strings,
including an empty description, remain meaningful values. No MIME/type field is
invented because the verified serializer does not expose one.

The API owns mapping and response validation. `TaigaTransport` owns HTTP
responses, bounded safe errors, JSON parsing, headers, and cancellation. The
MCP wrapper remains thin and serializes the standard page envelope.

## Explicit non-goals

This contract does not include attachment detail, upload, update, delete,
download-to-destination, file-content access, issue attachments, or bulk
export. A caller must request later pages explicitly.
