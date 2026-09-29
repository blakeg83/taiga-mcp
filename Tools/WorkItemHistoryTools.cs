using System.ComponentModel;
using ModelContextProtocol.Server;
using TaigaMCP.Api;
using TaigaMCP.Models;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class WorkItemHistoryTools
{
    private readonly WorkItemHistoryApi _history;

    public WorkItemHistoryTools(WorkItemHistoryApi history)
    {
        _history = history;
    }

    [McpServerTool(Name = "list_work_item_comments")]
    [Description("Read one page of visible nonblank comments from an issue, user story, task, or epic history stream. The kind is closed to issue, user_story, task, or epic; id is the positive internal work-item ID, and history entry ids are opaque strings. Hidden or deleted comments are omitted without filling the page from later history, so the visible items array can be empty while next_page is present. The page envelope metadata describes the upstream comment stream.")]
    public async Task<string> ListWorkItemComments(
        [Description("Work-item kind: issue, user_story, task, or epic.")] WorkItemKind kind,
        [Description("Positive internal work-item ID, not the displayed #ref.")] int id,
        [Description("Page number, starting at 1; requests one history page only.")] int page = 1,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _history.ListWorkItemCommentsPageAsync(kind, id, page, cancellationToken);
        return ToolResponseJson.SerializePage(
            result.Items,
            result.Page,
            result.Total,
            result.NextPage,
            result.HasMore);
    });

    [McpServerTool(Name = "get_work_item_history")]
    [Description("Read one page of visible field-change and comment history for an issue, user story, task, or epic. The kind is closed to issue, user_story, task, or epic; id is the positive internal work-item ID, and history entry ids are opaque strings. Structured diff and values_diff data is preserved, hidden entries are omitted, and deleted comment text is suppressed with comment_deleted=true when safe non-comment activity remains. The page envelope metadata describes the upstream history stream.")]
    public async Task<string> GetWorkItemHistory(
        [Description("Work-item kind: issue, user_story, task, or epic.")] WorkItemKind kind,
        [Description("Positive internal work-item ID, not the displayed #ref.")] int id,
        [Description("Page number, starting at 1; requests one history page only.")] int page = 1,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _history.ListWorkItemHistoryPageAsync(kind, id, page, cancellationToken);
        return ToolResponseJson.SerializePage(
            result.Items,
            result.Page,
            result.Total,
            result.NextPage,
            result.HasMore);
    });
}
