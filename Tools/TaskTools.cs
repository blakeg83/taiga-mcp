using System.ComponentModel;
using ModelContextProtocol.Server;
using TaigaMCP.Api;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class TaskTools
{
    private readonly TaskApi _tasks;

    public TaskTools(TaskApi tasks)
    {
        _tasks = tasks;
    }

    [McpServerTool(Name = "get_task")]
    [Description("Retrieve one task by its positive internal ID, not the displayed #ref. Returns one detail object with the authoritative version, description, status, assignment, parent story, sprint, tags, due-date, and blocking fields. Comments, attachments, and parent details are not loaded.")]
    public async Task<string> GetTask(
        [Description("Positive internal task ID, not the displayed #ref.")] int taskId,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _tasks.GetTaskAsync(taskId, cancellationToken);
        return ToolResponseJson.Serialize(result);
    });

    [McpServerTool(Name = "list_tasks")]
    [Description("List one page of tasks in a project. By default only tasks with open statuses are returned; explicit statusIds take precedence over includeClosed. userStoryId and milestoneId select parent story and sprint filters. The result always uses the items/page/total/next_page/has_more envelope. Standalone tasks and tasks with unavailable status labels are preserved; detail, sorting, dates, and closed-status metadata filters are not included.")]
    public async Task<string> ListTasks(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Page number, starting at 1; requests one page only.")] int page = 1,
        [Description("Optional positive internal user story ID; filters tasks linked to that story.")] int? userStoryId = null,
        [Description("Optional positive internal milestone ID; filters tasks in that sprint.")] int? milestoneId = null,
        [Description("Optional positive task status IDs. When nonempty, these override the automatic open-only filter.")] int[]? statusIds = null,
        [Description("Optional positive internal assignee user ID.")] int? assignedTo = null,
        [Description("Optional task tags; values are sent as Taiga's encoded multi-value filter.")] string[]? tags = null,
        [Description("Optional text query searched by Taiga.")] string? query = null,
        [Description("Include tasks with closed statuses when true. Explicit nonempty statusIds take precedence.")] bool includeClosed = false,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _tasks.ListTasksPageAsync(projectId, new TaskListOptions
        {
            Page = page,
            UserStoryId = userStoryId,
            MilestoneId = milestoneId,
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
