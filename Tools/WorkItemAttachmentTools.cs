using System.ComponentModel;
using System.Text.Json;
using ModelContextProtocol.Server;
using TaigaMCP.Api;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class WorkItemAttachmentTools
{
    private readonly WorkItemAttachmentApi _attachments;

    public WorkItemAttachmentTools(WorkItemAttachmentApi attachments)
    {
        _attachments = attachments;
    }

    [McpServerTool(Name = "get_work_item_attachment")]
    [Description("Retrieve one file attachment's metadata and available download locations for an epic, user story, or task. To read file contents, use download_work_item_attachment and inspect its local destination; metadata URLs may contain expiring signed tokens and must not be reused as durable links. The kind is closed to epic, user_story, and task; issue attachments, binary download, parent-detail enrichment, and attachment mutation are not included. The response is one authoritative attachment object and nullable fields are omitted.")]
    public async Task<string> GetWorkItemAttachment(
        [Description("Attachment parent kind: epic, user_story, or task; issue is not supported by this tool.")] string kind,
        [Description("Positive internal attachment ID, not a work-item or displayed #ref ID.")] int attachmentId,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _attachments.GetAsync(kind, attachmentId, cancellationToken);
        return ToolResponseJson.Serialize(result);
    });

    [McpServerTool(Name = "update_work_item_attachment")]
    [Description("Partially update one epic, user story, or task attachment's metadata with one JSON PATCH. fields must be an object containing one or more of description (string, including empty), order (32-bit integer, including zero), and is_deprecated (boolean, including false). Omitted fields remain unchanged; attachment bytes, parent association, project, and issue attachments are not supported. The authoritative attachment metadata is returned and ambiguous writes are never retried.")]
    public async Task<string> UpdateWorkItemAttachment(
        [Description("Attachment parent kind: epic, user_story, or task; issue is not supported by this tool.")] string kind,
        [Description("Positive internal attachment ID, not a work-item or displayed #ref ID.")] int attachmentId,
        [Description("JSON object with one or more allowlisted fields: description (string), order (32-bit integer), and is_deprecated (boolean). Null and unknown fields are rejected; omitted fields remain unchanged.")] JsonElement fields,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _attachments.UpdateAsync(kind, attachmentId, fields, cancellationToken);
        return ToolResponseJson.Serialize(result);
    });

    [McpServerTool(Name = "delete_work_item_attachment")]
    [Description("Delete one explicitly selected epic, user story, or task attachment with one kind-specific DELETE request. Only a confirmed HTTP 204 returns { kind, attachment_id, deleted: true }; repeated deletion/not-found is an error, ambiguous writes are never retried, and issue attachments, parent work items, sibling attachments, relationships, and local files are not affected by this tool.")]
    public async Task<string> DeleteWorkItemAttachment(
        [Description("Attachment parent kind: epic, user_story, or task; issue is not supported by this tool.")] string kind,
        [Description("Positive internal attachment ID selected by the caller, not a work-item or displayed #ref ID.")] int attachmentId,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _attachments.DeleteAsync(kind, attachmentId, cancellationToken);
        return ToolResponseJson.Serialize(result);
    });

    [McpServerTool(Name = "download_work_item_attachment")]
    [Description("Download one epic, user story, or task attachment to an explicit absolute local destination. Use this tool to read attachment contents, then inspect the local destination. The server retrieves fresh metadata, refreshes it once after a media 403 and retries only with a changed URL, applies the configured attachment size limit, never overwrites an existing file, keeps bearer authentication on the configured Taiga origin, and does not include binary data or secrets in the receipt.")]
    public async Task<string> DownloadWorkItemAttachment(
        [Description("Attachment parent kind: epic, user_story, or task; issue is not supported by this tool.")] string kind,
        [Description("Positive internal attachment ID, not a work-item or displayed #ref ID.")] int attachmentId,
        [Description("Absolute local destination file path; the server never derives or accepts a destination from the upstream filename and never overwrites an existing file.")] string destination,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _attachments.DownloadAsync(kind, attachmentId, destination, cancellationToken);
        return ToolResponseJson.Serialize(result);
    });

    [McpServerTool(Name = "list_work_item_attachments")]
    [Description("List one page of file attachments for an epic, user story, or task. To read selected file contents, pass its attachment ID to download_work_item_attachment and inspect the local destination; metadata URLs may contain expiring signed tokens. The kind is closed to epic, user_story, and task; issue attachments, all-page export, file-content download, parent-detail fan-out, and attachment mutation are not included. The result always uses the items/page/total/next_page/has_more envelope and preserves unknown pagination values as null.")]
    public async Task<string> ListWorkItemAttachments(
        [Description("Attachment parent kind: epic, user_story, or task; issue is not supported by this tool.")] string kind,
        [Description("Positive internal work-item ID, not the displayed #ref.")] int id,
        [Description("Positive internal project ID, not a slug; sent as the attachment project filter.")] int projectId,
        [Description("Page number, starting at 1; exactly one upstream page is requested.")] int page = 1,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _attachments.ListPageAsync(kind, id, projectId, page, cancellationToken);
        return ToolResponseJson.SerializePage(
            result.Items,
            result.Page,
            result.Total,
            result.NextPage,
            result.HasMore);
    });

    [McpServerTool(Name = "upload_work_item_attachment")]
    [Description("Upload one explicitly selected local file as a multipart attachment to an epic, user story, or task. The file must be an absolute path visible to the stdio server and must be within the configured maximum size; URLs, directories, bulk upload, and issue attachments are not supported. The response is authoritative attachment metadata.")]
    public async Task<string> UploadWorkItemAttachment(
        [Description("Attachment parent kind: epic, user_story, or task; issue is not supported by this tool.")] string kind,
        [Description("Positive internal work-item ID, not the displayed #ref.")] int id,
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Absolute local file path selected by the caller; the server derives the filename and media type from this path.")] string file,
        [Description("Optional attachment description; omitted when absent and empty text is preserved.")] string? description = null,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _attachments.UploadAsync(kind, id, projectId, file, description, cancellationToken);
        return ToolResponseJson.Serialize(result);
    });
}
