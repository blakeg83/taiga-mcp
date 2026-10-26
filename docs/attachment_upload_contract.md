# Work-item attachment upload contract

This document defines the implemented streamed-upload boundary. It was verified on 2026-10-02 against the Taiga
documentation at `main` and Taiga backend revision
`4d11baef9027f5598f6341d6eb4261de2840688e`. The revision is source evidence,
not a claim about every deployed Taiga instance.

## Supported kinds and routes

The public kind set is exactly `epic`, `user_story`, `task`, and `issue`. The client
selects the route internally:

| kind | POST route | `object_id` content type |
| --- | --- | --- |
| `epic` | `/api/v1/epics/attachments` | epic ID |
| `user_story` | `/api/v1/userstories/attachments` | user story ID |
| `task` | `/api/v1/tasks/attachments` | task ID |
| `issue` | `/api/v1/issues/attachments` | issue ID |

Each request is one authenticated `multipart/form-data` POST. The required
parts are:

| part | representation | contract |
| --- | --- | --- |
| `object_id` | text | positive requested work-item ID |
| `project` | text | positive requested project ID |
| `attached_file` | file | bytes from the caller-selected local file |
| `description` | text | optional; omitted when not supplied, empty text preserved |

The tool does not expose `is_deprecated` or `from_comment`; their server
defaults remain authoritative. A successful response is the authoritative
attachment detail object and must contain the attachment identity plus its
positive project and parent object IDs.

## Local file input

`file` is one explicit absolute path on the local filesystem visible to the
stdio server process. URLs, relative paths, directories, wildcards, directory
enumeration, and bulk upload are not accepted. The server derives the
multipart filename from the selected path's final component; callers cannot
inject a separate filename or route.

The default maximum is 10 MiB. It is configurable with
`TAIGA__MAXATTACHMENTBYTES` and must be positive. Empty files are valid; a file
whose inspected length equals the limit is valid, while a larger file is
rejected before any HTTP request. The upload re-checks the stream while it is
read so a file that grows after validation cannot exceed the configured limit.

The media type is inferred from a small extension allowlist (`.png`, `.jpg`,
`.pdf`, `.txt`, `.json`, and other common types); unknown extensions use
`application/octet-stream`. The caller does not supply a media type.

## Safety and ownership

Positive kind-specific IDs and the project ID are validated before opening the
network request. Missing, unreadable, inaccessible, or over-limit files fail
locally before authentication or any upload request is sent.
The upload is streamed from disk and is never automatically replayed after an
ambiguous POST. HTTP response disposal, bounded safe errors, authentication,
and the single received-401 replay remain owned by `TaigaTransport` and
`AuthClient`. A successful POST with an unreadable or malformed response is
reported as possibly applied.

## Evidence

- [Epic create-attachment contract](https://github.com/taigaio/taiga-doc/blob/main/api/epics/create-attachment.adoc)
- [User-story create-attachment contract](https://github.com/taigaio/taiga-doc/blob/main/api/user-stories/create-attachment.adoc)
- [Task create-attachment contract](https://github.com/taigaio/taiga-doc/blob/main/api/tasks/create-attachment.adoc)
- [Epic generated multipart example](https://github.com/taigaio/taiga-doc/blob/main/api/generated/epics-attachments-create-cmd.adoc)
- [Pinned attachment view set](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/api.py)
- [Pinned attachment validator](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/validators.py)
- [Pinned attachment serializer](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/attachments/serializers.py)

Binary-content, disposal, cancellation, and MCP binding tests live in the
attachment test suites. Download, update, and delete use separate tools; bulk
upload is outside this command.
