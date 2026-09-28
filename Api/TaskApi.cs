using System.Text.Json;
using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>Task operations.</summary>
public sealed class TaskApi
{
    private readonly TaigaTransport _transport;

    public TaskApi(TaigaTransport transport)
    {
        _transport = transport;
    }

    public async Task<TaskDetailDto> GetTaskAsync(
        int taskId,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(taskId, nameof(taskId));
        using var request = new HttpRequestMessage(HttpMethod.Get, $"tasks/{taskId}");
        using var document = await _transport.ReadAsync(request, cancellationToken);
        return MapTaskDetail(document.RootElement);
    }

    public async Task<IReadOnlyList<TaskDto>> ListTasksAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
        => (await ListTasksPageAsync(
            projectId,
            new TaskListOptions { Page = page },
            cancellationToken)).Items;

    internal async Task<TaskListPage> ListTasksPageAsync(
        int projectId,
        TaskListOptions options,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(options.Page, nameof(options.Page));
        ValidateListOptions(options);

        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            TaskListQueryBuilder.Build(projectId, options));
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;
        if (document.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid task list data.");

        var items = new List<TaskDto>(64);
        foreach (var task in document.RootElement.EnumerateArray())
            items.Add(MapTask(task));

        var pageInfo = TaigaPagination.Parse(response.Headers, response.RequestUri);
        return new TaskListPage(
            items,
            options.Page,
            pageInfo.Total,
            pageInfo.NextPage,
            pageInfo.HasMore);
    }

    private static void ValidateListOptions(TaskListOptions options)
    {
        if (options.StatusIds is not null)
            foreach (var id in options.StatusIds)
                InputValidation.Positive(id, "statusIds");

        InputValidation.OptionalIds(
            (options.UserStoryId, nameof(options.UserStoryId)),
            (options.MilestoneId, nameof(options.MilestoneId)),
            (options.AssignedTo, nameof(options.AssignedTo)));
    }

    private static TaskDto MapTask(JsonElement task)
    {
        if (task.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid task data.");

        return new TaskDto
        {
            Id = ReadRequiredPositiveInt(task, "id"),
            Ref = ReadRequiredPositiveInt(task, "ref"),
            Project = ReadOptionalPositiveInt(task, "project"),
            Subject = ReadOptionalString(task, "subject"),
            StatusId = ReadOptionalPositiveInt(task, "status"),
            Status = ReadStatusName(task),
            AssignedTo = ReadOptionalPositiveInt(task, "assigned_to"),
            UserStory = ReadOptionalPositiveInt(task, "user_story"),
            Milestone = ReadOptionalPositiveInt(task, "milestone"),
            Modified = ReadOptionalString(task, "modified_date"),
            Version = ReadOptionalNonnegativeInt(task, "version")
        };
    }

    private static TaskDetailDto MapTaskDetail(JsonElement task)
    {
        ValidateDetailIdentityAndVersion(task);

        return new TaskDetailDto
        {
            Id = ReadRequiredPositiveInt(task, "id"),
            Ref = ReadRequiredPositiveInt(task, "ref"),
            Project = ReadRequiredPositiveInt(task, "project"),
            Subject = ReadDetailOptionalString(task, "subject"),
            Description = ReadDetailOptionalString(task, "description"),
            StatusId = ReadDetailOptionalPositiveInt(task, "status"),
            Status = ReadStatusName(task),
            AssignedTo = ReadDetailOptionalPositiveInt(task, "assigned_to"),
            UserStory = ReadDetailOptionalPositiveInt(task, "user_story"),
            Milestone = ReadDetailOptionalPositiveInt(task, "milestone"),
            Tags = ReadTags(task),
            Modified = ReadDetailOptionalString(task, "modified_date"),
            DueDate = ReadDetailOptionalString(task, "due_date"),
            DueDateReason = ReadDetailOptionalString(task, "due_date_reason"),
            DueDateStatus = ReadDetailOptionalString(task, "due_date_status"),
            IsBlocked = ReadOptionalBoolean(task, "is_blocked"),
            BlockedNote = ReadDetailOptionalString(task, "blocked_note"),
            IsClosed = ReadOptionalBoolean(task, "is_closed"),
            Version = task.GetProperty("version").GetInt32()
        };
    }

    private static void ValidateDetailIdentityAndVersion(JsonElement task)
    {
        if (task.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid task detail data.");

        ReadRequiredPositiveInt(task, "id");
        ReadRequiredPositiveInt(task, "ref");
        ReadRequiredPositiveInt(task, "project");

        if (!task.TryGetProperty("version", out var version) ||
            version.ValueKind != JsonValueKind.Number ||
            !version.TryGetInt32(out var number) ||
            number < 0)
            throw new TaigaRequestException("Taiga returned invalid task version data.");
    }

    private static int? ReadDetailOptionalPositiveInt(JsonElement task, string propertyName)
    {
        if (!task.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid task {propertyName} data.");

        return number;
    }

    private static string? ReadDetailOptionalString(JsonElement task, string propertyName)
    {
        if (!task.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.String)
            throw new TaigaRequestException($"Taiga returned invalid task {propertyName} data.");

        return value.GetString();
    }

    private static bool? ReadOptionalBoolean(JsonElement task, string propertyName)
    {
        if (!task.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind is not JsonValueKind.True and not JsonValueKind.False)
            throw new TaigaRequestException($"Taiga returned invalid task {propertyName} data.");

        return value.GetBoolean();
    }

    private static IReadOnlyList<JsonElement>? ReadTags(JsonElement task)
    {
        if (!task.TryGetProperty("tags", out var tags) ||
            tags.ValueKind == JsonValueKind.Null)
            return null;

        if (tags.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid task tags data.");

        return tags.EnumerateArray().Select(tag => tag.Clone()).ToArray();
    }

    private static string? ReadStatusName(JsonElement task)
    {
        if (!task.TryGetProperty("status_extra_info", out var extraInfo) ||
            extraInfo.ValueKind != JsonValueKind.Object ||
            !extraInfo.TryGetProperty("name", out var name) ||
            name.ValueKind != JsonValueKind.String)
            return null;

        return name.GetString();
    }

    private static int ReadRequiredPositiveInt(JsonElement task, string propertyName)
    {
        if (!task.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid task {propertyName} data.");

        return number;
    }

    private static int? ReadOptionalPositiveInt(JsonElement task, string propertyName)
    {
        if (!task.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid task {propertyName} data.");

        return number;
    }

    private static int? ReadOptionalNonnegativeInt(JsonElement task, string propertyName)
    {
        if (!task.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number < 0)
            throw new TaigaRequestException($"Taiga returned invalid task {propertyName} data.");

        return number;
    }

    private static string? ReadOptionalString(JsonElement task, string propertyName)
        => task.TryGetProperty(propertyName, out var value) &&
           value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
}
