using System.ComponentModel;
using ModelContextProtocol.Server;
using TaigaMCP.Api;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class EpicTools
{
    private readonly EpicApi _epics;

    public EpicTools(EpicApi epics)
    {
        _epics = epics;
    }

    [McpServerTool(Name = "get_epic")]
    [Description("Retrieve one epic by its positive internal ID, not the displayed #ref. Returns the authoritative version, Markdown description, status and assignment, color, tags, and available server summaries. This is one detail read; related stories, progress calculation, comments, history, and status-metadata lookups are not included.")]
    public async Task<string> GetEpic(
        [Description("Positive internal epic ID, not the displayed #ref.")] int epicId,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _epics.GetEpicAsync(epicId, cancellationToken);
        return ToolResponseJson.Serialize(result);
    });

    [McpServerTool(Name = "list_epics")]
    [Description("List one page of epics in a project. By default only epics with open statuses are returned; explicit statusIds take precedence over includeClosed. Filters are project-scoped and allowlisted; the result always uses the items/page/total/next_page/has_more envelope. Related stories, progress aggregation, sorting, and all-page fetching are not included.")]
    public async Task<string> ListEpics(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Page number, starting at 1; requests one page only.")] int page = 1,
        [Description("Optional positive epic status IDs. When nonempty, these override the automatic open-only filter.")] int[]? statusIds = null,
        [Description("Optional positive internal assignee user ID.")] int? assignedTo = null,
        [Description("Optional epic tags; values are sent as Taiga's encoded multi-value filter.")] string[]? tags = null,
        [Description("Optional text query searched by Taiga.")] string? query = null,
        [Description("Include epics with closed statuses when true. Explicit nonempty statusIds take precedence.")] bool includeClosed = false,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _epics.ListEpicsPageAsync(projectId, new EpicListOptions
        {
            Page = page,
            StatusIds = statusIds,
            AssignedTo = assignedTo,
            Tags = tags,
            Query = query,
            IncludeClosed = includeClosed
        }, cancellationToken);

        return ToolResponseJson.SerializePage(
            result.Items,
            result.Page,
            result.Total,
            result.NextPage,
            result.HasMore);
    });
}
