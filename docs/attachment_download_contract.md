# Work-item attachment download contract

This contract supports story #24, task #36, and the shared attachment API
boundary. It builds on the authoritative attachment detail response used by
`get_work_item_attachment`.

## Inputs and source selection

The public command is:

```text
download_work_item_attachment(kind, attachmentId, destination)
```

`kind` is exactly `epic`, `user_story`, or `task`; `attachmentId` is a
positive internal attachment ID. The server first performs the kind-specific,
authenticated detail GET. The response's `url` is the preferred binary source.
When `url` is absent, `attached_file` is accepted only as an absolute HTTP/HTTPS
URL. A storage path cannot be resolved without the server's media configuration
and is rejected instead of being appended to the API base URL. `preview_url` and
`thumbnail_card_url` are never used for downloads.

Only `http` and `https` sources are accepted. A source on the configured Taiga
origin is an authenticated API request. An absolute source on another origin
is treated as an external storage or signed URL and receives no Taiga bearer
token. Redirect handling is manual: same-origin redirects may retain
authentication, while redirects to another origin are followed without the
bearer. Redirects to unsupported schemes are rejected.

Malformed URLs, unsupported schemes, and an attachment without a usable source
are safe request errors. The upstream URL, query, and response body are not
copied into tool errors.

Use this command to access attachment contents, then inspect the local destination.
URLs returned by metadata tools may carry expiring signed tokens; the frontend's
`#_taiga-refresh` fragment does not refresh them for an HTTP client. The token
query is preserved when downloading. After a binary HTTP 403, the server fetches
metadata once more and retries the download only if its source URL changed.
A second media 403, or unchanged URL, ends recovery. This does not refresh API
authentication on a 403 or retry writes. Metadata errors identify the metadata
stage; binary 403 errors identify media access denial without claiming that
token expiry is the only possible cause. Bodies, URLs and tokens are omitted.

This behavior follows the official [attachment serializer](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/attachments/serializers.py)
and [protected storage URL generation](https://github.com/taigaio/taiga-contrib-protected/blob/main/taiga_contrib_protected/storage.py),
reviewed on 2026-10-26. Local tests use synthetic tokens and fake media responses;
they do not confirm a deployed server's configuration.

## Destination and file safety

`destination` is one explicit absolute local file path. Its parent directory
must already exist. The filename is never derived from upstream metadata, so
attachment names cannot select or escape the requested destination. Existing
destination files are rejected and are never overwritten.

The configured `TAIGA__MAXATTACHMENTBYTES` limit applies to downloads as well
as uploads. Its default is 10 MiB; a zero-byte file and a file exactly at the
limit are valid. The client rejects a known oversized attachment `size` or
`Content-Length` before writing, requires the received byte count to equal each
known declared size. The attachment metadata `size` is required to establish
a verifiable completion boundary; `Content-Length` is used as a safety bound
and consistency check but is not sufficient by itself. A missing
`Content-Length` is supported when metadata `size` is present.

Bytes are written to a uniquely named temporary file in the destination's
same directory. The temporary file is flushed and moved into place only after
the response completes successfully and the byte count is within the limit.
Failures, cancellation, and destination races remove the temporary file and
leave a pre-existing destination unchanged. The final receipt contains the
confirmed destination path, byte count, and available attachment metadata; it
does not contain binary content, bearer tokens, or raw upstream error bodies.

Issue attachments, preview downloads, bulk retrieval, overwrite controls,
directory creation, and attachment mutation are outside this command.
