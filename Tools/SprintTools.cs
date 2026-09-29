using System.ComponentModel;
using ModelContextProtocol.Server;
using TaigaMCP.Api;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class SprintTools
{
    private readonly SprintApi _sprints;

    public SprintTools(SprintApi sprints)
    {
        _sprints = sprints;
    }

    [McpServerTool(Name = "list_sprints")]
    [Description("List one page of project sprints. Taiga calls sprints milestones; use a returned id as milestoneId when creating or updating a user story or creating a standalone task. Omit closed, or pass null, to include both open and closed sprints; pass false for open only or true for closed only. The result uses the items/page/total/next_page/has_more envelope and does not expand stories, point totals, statistics, or date filters.")]
    public async Task<string> ListSprints(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Page number, starting at 1; requests one page only.")] int page = 1,
        [Description("Optional closed filter: omit or pass null for all sprints, false for open sprints, or true for closed sprints.")] bool? closed = null,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _sprints.ListSprintsPageAsync(projectId, page, closed, cancellationToken);
        return ToolResponseJson.SerializePage(
            result.Items,
            result.Page,
            result.Total,
            result.NextPage,
            result.HasMore);
    });
}
