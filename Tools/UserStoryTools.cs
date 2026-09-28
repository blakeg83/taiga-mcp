using System.ComponentModel;
using TaigaMCP.Api;
using ModelContextProtocol.Server;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class UserStoryTools
{
    private readonly UserStoryApi _userStories;

    public UserStoryTools(UserStoryApi userStories)
    {
        _userStories = userStories;
    }

    [McpServerTool(Name = "list_user_stories")]
    [Description("List one page of project user stories. By default only stories with open, non-archived statuses are returned; explicit statusIds take precedence over includeClosed and includeArchived. Set backlogOnly=true for stories with no milestone, or milestoneId for one sprint; those two selectors cannot be combined. Returns an array unless includePageInfo=true.")]
    public async Task<string> ListUserStories(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Page number, starting at 1; requests one page only.")] int page = 1,
        [Description("Optional positive user story status IDs. When nonempty, these override the automatic open and non-archived filters.")] int[]? statusIds = null,
        [Description("Optional positive internal assignee user ID.")] int? assignedTo = null,
        [Description("Optional positive internal milestone ID for one sprint; cannot be combined with backlogOnly=true.")] int? milestoneId = null,
        [Description("Limit results to stories whose milestone is null; cannot be combined with milestoneId.")] bool backlogOnly = false,
        [Description("Optional story tags; values are sent as Taiga's encoded multi-value filter.")] string[]? tags = null,
        [Description("Optional text query searched by Taiga.")] string? query = null,
        [Description("Include closed stories when true. Explicit nonempty statusIds take precedence.")] bool includeClosed = false,
        [Description("Include archived stories when true. Explicit nonempty statusIds take precedence.")] bool includeArchived = false,
        [Description("Return an object with items and pagination metadata instead of the legacy array.")] bool includePageInfo = false,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _userStories.ListUserStoriesPageAsync(projectId, new UserStoryListOptions
        {
            Page = page,
            StatusIds = statusIds,
            AssignedTo = assignedTo,
            MilestoneId = milestoneId,
            BacklogOnly = backlogOnly,
            Tags = tags,
            Query = query,
            IncludeClosed = includeClosed,
            IncludeArchived = includeArchived
        }, cancellationToken);
        return includePageInfo
            ? ToolResponseJson.SerializePage(result.Items, result.Page, result.Total, result.NextPage, result.HasMore)
            : ToolResponseJson.Serialize(result.Items);
    });
}
