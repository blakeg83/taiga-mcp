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
