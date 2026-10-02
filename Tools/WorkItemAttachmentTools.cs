using System.ComponentModel;
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
    [Description("Retrieve one file attachment's metadata and available download locations for an epic, user story, or task. The kind is closed to epic, user_story, and task; issue attachments, binary download, parent-detail enrichment, and attachment mutation are not included. The response is one authoritative attachment object and nullable fields are omitted.")]
    public async Task<string> GetWorkItemAttachment(
        [Description("Attachment parent kind: epic, user_story, or task; issue is not supported by this tool.")] string kind,
        [Description("Positive internal attachment ID, not a work-item or displayed #ref ID.")] int attachmentId,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _attachments.GetAsync(kind, attachmentId, cancellationToken);
        return ToolResponseJson.Serialize(result);
    });

    [McpServerTool(Name = "list_work_item_attachments")]
    [Description("List one page of file attachments for an epic, user story, or task. The kind is closed to epic, user_story, and task; issue attachments, all-page export, file-content download, parent-detail fan-out, and attachment mutation are not included. The result always uses the items/page/total/next_page/has_more envelope and preserves unknown pagination values as null.")]
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
}
