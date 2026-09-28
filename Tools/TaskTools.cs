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

    [McpServerTool(Name = "create_task")]
    [Description("Create one task in a project. A story-linked task validates the parent project and inherits the parent's sprint; a matching milestoneId is redundant and is omitted from the create request. Standalone tasks may omit milestoneId or select a sprint. Omitted optional fields use Taiga project defaults; bulk creation, due dates, blockers, and iocaine are not included.")]
    public async Task<string> CreateTask(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Nonblank task subject.")] string subject,
        [Description("Optional positive internal parent user story ID; its project and sprint are validated before creation.")] int? userStoryId = null,
        [Description("Optional positive internal sprint ID for a standalone task; when a parent story is supplied it must match the parent's sprint.")] int? milestoneId = null,
        [Description("Optional task description; an empty string is sent explicitly.")] string? description = null,
        [Description("Optional positive internal task status ID.")] int? status = null,
        [Description("Optional positive internal assignee user ID.")] int? assigned_to = null,
        [Description("Optional task tags; an empty array is sent explicitly.")] string[]? tags = null,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var task = await _tasks.CreateTaskAsync(
            projectId,
            subject,
            userStoryId,
            milestoneId,
            description,
            status,
            assigned_to,
            tags,
            cancellationToken);
        return ToolResponseJson.Serialize(task);
    });

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

    [McpServerTool(Name = "update_task")]
    [Description("Update one task using the caller-supplied version. Omitted nullable fields stay unchanged; empty description or tags are explicit clears, and isBlocked=false is sent explicitly. Use clearFields=[\"assigned_to\"] to unassign. The client does not add a compensating note write; Taiga clears blockedNote whenever a task is saved unblocked, including when a note is omitted or nonempty. Pass blockedNote=\"\" when clearing it explicitly. Requires a change or nonblank comment and does not automatically retry version conflicts. Parent story, sprint, due dates, and iocaine are not included.")]
    public async Task<string> UpdateTask(
        [Description("Positive internal task ID, not the displayed #ref.")] int taskId,
        [Description("Required current task version, zero or greater; forwarded unchanged to Taiga.")] int version,
        [Description("Optional nonblank subject; omission or null leaves it unchanged.")] string? subject = null,
        [Description("Description; null leaves it unchanged, while an empty string clears it.")] string? description = null,
        [Description("Optional positive internal task status ID; null leaves it unchanged.")] int? status = null,
        [Description("Optional positive internal assignee user ID; null leaves it unchanged, while clearFields can unassign.")] int? assigned_to = null,
        [Description("Tags; null leaves them unchanged, while an empty array clears them.")] string[]? tags = null,
        [Description("Optional blocking flag; null leaves it unchanged, while false explicitly unblocks the task. Taiga clears the note when the saved task is unblocked.")] bool? isBlocked = null,
        [Description("Optional blocking note; null omits this request field and an empty string sends an explicit clear. Taiga clears any note when the saved task is unblocked, even if this is nonempty.")] string? blockedNote = null,
        [Description("Optional comment; a comment-only update requires nonblank text.")] string? comment = null,
        [Description("Optional fields to clear explicitly; only assigned_to is accepted, using this exact wire name.")] string[]? clearFields = null,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var task = await _tasks.UpdateTaskAsync(
            taskId,
            version,
            subject,
            description,
            status,
            assigned_to,
            tags,
            isBlocked,
            blockedNote,
            comment,
            clearFields,
            cancellationToken);
        return ToolResponseJson.Serialize(task);
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
