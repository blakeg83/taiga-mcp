using System.Text.Json;
using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>User story operations.</summary>
public sealed class UserStoryApi
{
    private readonly TaigaTransport _transport;

    public UserStoryApi(TaigaTransport transport)
    {
        _transport = transport;
    }

    public async Task<IReadOnlyList<UserStoryDto>> ListUserStoriesAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
        => (await ListUserStoriesPageAsync(
            projectId,
            new UserStoryListOptions { Page = page },
            cancellationToken)).Items;

    internal async Task<UserStoryListPage> ListUserStoriesPageAsync(
        int projectId,
        UserStoryListOptions options,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(options.Page, nameof(options.Page));
        ValidateListOptions(options);

        var statusMap = await LoadStatusMapAsync(projectId, cancellationToken);
        using var usReq = new HttpRequestMessage(
            HttpMethod.Get,
            UserStoryListQueryBuilder.Build(projectId, options));
        using var response = await _transport.ReadWithHeadersAsync(usReq, cancellationToken);
        using var doc = response.Document;
        if (doc.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid user story list data.");

        var items = new List<UserStoryDto>(64);
        foreach (var userStory in doc.RootElement.EnumerateArray())
            items.Add(MapUserStory(userStory, statusMap));

        var pageInfo = TaigaPagination.Parse(response.Headers, response.RequestUri);
        return new UserStoryListPage(
            items,
            options.Page,
            pageInfo.Total,
            pageInfo.NextPage,
            pageInfo.HasMore);
    }

    private async Task<IReadOnlyDictionary<int, string>> LoadStatusMapAsync(
        int projectId,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"userstory-statuses?project={projectId}");
        using var document = await _transport.ReadAsync(request, cancellationToken);
        if (document.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid user story status data.");

        var statusMap = new Dictionary<int, string>();
        foreach (var status in document.RootElement.EnumerateArray())
        {
            if (!status.TryGetProperty("id", out var idElement) ||
                !idElement.TryGetInt32(out var id) ||
                !status.TryGetProperty("name", out var nameElement) ||
                nameElement.ValueKind != JsonValueKind.String)
                continue;

            statusMap[id] = nameElement.GetString()!;
        }

        return statusMap;
    }

    private static void ValidateListOptions(UserStoryListOptions options)
    {
        if (options.StatusIds is not null)
            foreach (var id in options.StatusIds)
                InputValidation.Positive(id, "statusIds");

        InputValidation.OptionalIds(
            (options.AssignedTo, nameof(options.AssignedTo)),
            (options.MilestoneId, nameof(options.MilestoneId)));

        if (options.BacklogOnly && options.MilestoneId.HasValue)
            throw new ArgumentException("milestoneId cannot be combined with backlogOnly=true.");
    }

    private static UserStoryDto MapUserStory(
        JsonElement userStory,
        IReadOnlyDictionary<int, string> statusMap)
    {
        if (userStory.ValueKind != JsonValueKind.Object ||
            !userStory.TryGetProperty("id", out var idElement) ||
            !idElement.TryGetInt32(out var id))
            throw new TaigaRequestException("Taiga returned invalid user story data.");

        var statusId = ReadOptionalInt(userStory, "status");
        return new UserStoryDto
        {
            Id = id,
            Ref = ReadInt(userStory, "ref"),
            Project = ReadOptionalInt(userStory, "project"),
            Subject = ReadOptionalString(userStory, "subject"),
            StatusId = statusId,
            Status = statusId.HasValue && statusMap.TryGetValue(statusId.Value, out var status)
                ? status
                : null,
            AssignedTo = ReadOptionalInt(userStory, "assigned_to"),
            Modified = ReadOptionalString(userStory, "modified_date"),
            Milestone = ReadOptionalInt(userStory, "milestone"),
            Version = ReadOptionalInt(userStory, "version")
        };
    }

    private static int ReadInt(JsonElement element, string propertyName)
        => element.TryGetProperty(propertyName, out var value) && value.TryGetInt32(out var number)
            ? number
            : 0;

    private static int? ReadOptionalInt(JsonElement element, string propertyName)
        => element.TryGetProperty(propertyName, out var value) &&
           value.ValueKind == JsonValueKind.Number &&
           value.TryGetInt32(out var number)
            ? number
            : null;

    private static string? ReadOptionalString(JsonElement element, string propertyName)
        => element.TryGetProperty(propertyName, out var value) &&
           value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
}
