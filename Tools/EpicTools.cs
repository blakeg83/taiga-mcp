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

    [McpServerTool(Name = "create_epic")]
    [Description("Create one epic for a project. Omitted description, status, assignee, color, and tags let Taiga apply project defaults; status and assignee are project-specific internal IDs. This creates only the epic: story linking, requirement flags, bulk creation, and custom fields are not included.")]
    public async Task<string> CreateEpic(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Nonblank epic subject; meaningful whitespace is preserved.")] string subject,
        [Description("Optional epic description; empty string is sent explicitly.")] string? description = null,
        [Description("Optional positive internal epic status ID; null lets Taiga choose the project default.")] int? status = null,
        [Description("Optional positive internal assignee user ID; null lets Taiga choose the project default.")] int? assigned_to = null,
        [Description("Optional epic color string; null lets Taiga generate its default color. Taiga validates the accepted format.")] string? color = null,
        [Description("Optional epic tags; null lets Taiga apply its default, while an empty array is sent explicitly.")] string[]? tags = null,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var epic = await _epics.CreateEpicAsync(
            projectId,
            subject,
            description,
            status,
            assigned_to,
            color,
            tags,
            cancellationToken);
        return ToolResponseJson.Serialize(epic);
    });

    [McpServerTool(Name = "update_epic")]
    [Description("Update one epic using the caller-supplied version. Omitted nullable fields stay unchanged; empty description or tags are explicit clears, and clearFields=[\"assigned_to\"] explicitly unassigns. Status IDs are epic-specific and can close or reopen the epic. Requires a change or nonblank comment and does not automatically retry version conflicts. Linked stories, epic order, requirement flags, blocking, dates, custom fields, and project moves are not included.")]
    public async Task<string> UpdateEpic(
        [Description("Positive internal epic ID, not the displayed #ref.")] int epicId,
        [Description("Required current epic version, zero or greater; forwarded unchanged to Taiga.")] int version,
        [Description("Optional nonblank subject; omission or null leaves it unchanged.")] string? subject = null,
        [Description("Description; null leaves it unchanged, while an empty string clears it.")] string? description = null,
        [Description("Optional positive internal epic status ID; null leaves it unchanged. Use list_epic_statuses for project-specific choices.")] int? status = null,
        [Description("Optional positive internal assignee user ID; null leaves it unchanged, while clearFields can unassign.")] int? assigned_to = null,
        [Description("Optional epic color string; null leaves it unchanged. Taiga validates the accepted format.")] string? color = null,
        [Description("Tags; null leaves them unchanged, while an empty array clears them.")] string[]? tags = null,
        [Description("Optional comment; a comment-only update requires nonblank text.")] string? comment = null,
        [Description("Optional fields to clear explicitly; only assigned_to is accepted, using this exact wire name.")] string[]? clearFields = null,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var epic = await _epics.UpdateEpicAsync(
            epicId,
            version,
            subject,
            description,
            status,
            assigned_to,
            color,
            tags,
            comment,
            clearFields,
            cancellationToken);
        return ToolResponseJson.Serialize(epic);
    });

    [McpServerTool(Name = "link_user_story_to_epic")]
    [Description("Associate an existing user story with an epic. Both IDs are positive internal IDs, not displayed refs. If the relationship already exists, returns its current server order with created=false and ignores a new order request; otherwise confirms both resources are accessible and creates the relationship. Cross-project eligibility is decided by Taiga; this does not move, update, or duplicate the story.")]
    public async Task<string> LinkUserStoryToEpic(
        [Description("Positive internal epic ID, not the displayed #ref.")] int epicId,
        [Description("Positive internal user story ID, not the displayed #ref.")] int userStoryId,
        [Description("Optional relationship order used only when creating a new link; an existing link keeps its server order.")] long? order = null,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var link = await _epics.LinkUserStoryToEpicAsync(
            epicId,
            userStoryId,
            order,
            cancellationToken);
        return ToolResponseJson.Serialize(link);
    });

    [McpServerTool(Name = "list_epic_user_stories")]
    [Description("List one page of the stories already linked to an epic. Returns only epic_id, user_story_id, and the server relationship order; it does not imply creation, load full story details, calculate progress, or modify membership. Use get_user_story with a returned user_story_id when full story details are needed. Cross-project eligibility remains Taiga's decision.")]
    public async Task<string> ListEpicUserStories(
        [Description("Positive internal epic ID, not the displayed #ref.")] int epicId,
        [Description("Page number, starting at 1; requests one relationship page only.")] int page = 1,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _epics.ListEpicUserStoriesPageAsync(epicId, page, cancellationToken);
        return ToolResponseJson.SerializePage(
            result.Items,
            result.Page,
            result.Total,
            result.NextPage,
            result.HasMore);
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

    [McpServerTool(Name = "list_epic_statuses")]
    [Description("List one page of every selectable epic status for a project, including open and closed choices. Each result includes its project/resource-specific status ID and available name, slug, order, color, and closed flag; use a returned id with create_epic or the planned update_epic and request later pages when page metadata indicates more results. Epic statuses do not expose story-only archive or WIP fields.")]
    public async Task<string> ListEpicStatuses(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Page number, starting at 1; requests one page only.")] int page = 1,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _epics.ListEpicStatusesPageAsync(projectId, page, cancellationToken);
        return ToolResponseJson.SerializePage(
            result.Items,
            result.Page,
            result.Total,
            result.NextPage,
            result.HasMore);
    });
}
