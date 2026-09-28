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

    [McpServerTool(Name = "get_user_story")]
    [Description("Retrieve one user story by its positive internal ID, not the displayed #ref. Returns the authoritative version, description, assignment, status, tags, sprint, and available epic/source relationship metadata; comments and tasks are not loaded.")]
    public async Task<string> GetUserStory(
        [Description("Positive internal user story ID, not the displayed #ref.")] int userStoryId,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _userStories.GetUserStoryAsync(userStoryId, cancellationToken);
        return ToolResponseJson.Serialize(result);
    });

    [McpServerTool(Name = "create_user_story")]
    [Description("Create one user story for a project. Put acceptance criteria in description; omitted optional fields let Taiga apply project defaults. Use milestoneId to place the story in a sprint. Estimates, multiple assignees, swimlanes, epic links, bulk creation, and custom fields are not included.")]
    public async Task<string> CreateUserStory(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Nonblank story subject; meaningful whitespace is preserved.")] string subject,
        [Description("Optional story description; acceptance criteria belong here. Empty string is sent explicitly.")] string? description = null,
        [Description("Optional positive internal user-story status ID; null lets Taiga choose the project default.")] int? status = null,
        [Description("Optional positive internal assignee user ID; null lets Taiga choose the project default.")] int? assigned_to = null,
        [Description("Optional story tags; null lets Taiga apply its default, while an empty array is sent explicitly.")] string[]? tags = null,
        [Description("Optional positive internal milestone ID; null creates a backlog story and a value places it in that sprint.")] int? milestoneId = null,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var story = await _userStories.CreateUserStoryAsync(
            projectId,
            subject,
            description,
            status,
            assigned_to,
            tags,
            milestoneId,
            cancellationToken);
        return ToolResponseJson.Serialize(story);
    });

    [McpServerTool(Name = "update_user_story")]
    [Description("Update one user story using the caller-supplied version. Omitted nullable fields stay unchanged; empty description or tags are explicit clears. Use clearFields=[\"assigned_to\"] to unassign or [\"milestone\"] to return the story to the backlog. milestoneId selects a sprint. Requires a change or nonblank comment and does not automatically retry version conflicts.")]
    public async Task<string> UpdateUserStory(
        [Description("Positive internal user story ID, not the displayed #ref.")] int userStoryId,
        [Description("Required current story version, zero or greater; forwarded unchanged to Taiga.")] int version,
        [Description("Optional nonblank subject; omission or null leaves it unchanged.")] string? subject = null,
        [Description("Description; null leaves it unchanged, while an empty string clears it.")] string? description = null,
        [Description("Optional positive internal user-story status ID; null leaves it unchanged.")] int? status = null,
        [Description("Optional positive internal assignee user ID; null leaves it unchanged, while clearFields can unassign.")] int? assigned_to = null,
        [Description("Tags; null leaves them unchanged, while an empty array clears them.")] string[]? tags = null,
        [Description("Optional positive internal milestone ID; null leaves it unchanged, while clearFields can remove the sprint.")] int? milestoneId = null,
        [Description("Optional comment; a comment-only update requires nonblank text.")] string? comment = null,
        [Description("Optional fields to clear explicitly; only assigned_to and milestone are accepted, using these exact wire names.")] string[]? clearFields = null,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var story = await _userStories.UpdateUserStoryAsync(
            userStoryId,
            version,
            subject,
            description,
            status,
            assigned_to,
            tags,
            milestoneId,
            comment,
            clearFields,
            cancellationToken);
        return ToolResponseJson.Serialize(story);
    });

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
