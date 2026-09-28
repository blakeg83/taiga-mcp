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

    public async Task<UserStoryDetailDto> GetUserStoryAsync(
        int userStoryId,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(userStoryId, nameof(userStoryId));
        using var request = new HttpRequestMessage(HttpMethod.Get, $"userstories/{userStoryId}");
        using var document = await _transport.ReadAsync(request, cancellationToken);
        var userStory = document.RootElement;
        ValidateDetailIdentityAndVersion(userStory);

        var projectId = ReadDetailOptionalInt(userStory, "project");
        var statusId = ReadDetailOptionalInt(userStory, "status");
        var status = ReadStatusExtraInfoName(userStory);
        if (status is null && statusId.HasValue && projectId is > 0)
        {
            var statusMap = await LoadStatusMapAsync(projectId.Value, cancellationToken);
            status = statusMap.GetValueOrDefault(statusId.Value);
        }

        return MapUserStoryDetail(userStory, projectId, statusId, status);
    }

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

    private static UserStoryDetailDto MapUserStoryDetail(
        JsonElement userStory,
        int? projectId,
        int? statusId,
        string? status)
    {
        ValidateDetailIdentityAndVersion(userStory);

        if (!userStory.TryGetProperty("id", out var idElement) ||
            !idElement.TryGetInt32(out var id))
            throw new TaigaRequestException("Taiga returned invalid user story identity data.");
        var version = userStory.GetProperty("version").GetInt32();

        return new UserStoryDetailDto
        {
            Id = id,
            Ref = ReadDetailOptionalInt(userStory, "ref"),
            Project = projectId,
            Subject = ReadDetailOptionalString(userStory, "subject"),
            Description = ReadDetailOptionalString(userStory, "description"),
            StatusId = statusId,
            Status = status,
            AssignedTo = ReadDetailOptionalInt(userStory, "assigned_to"),
            Tags = ReadTags(userStory),
            Milestone = ReadDetailOptionalInt(userStory, "milestone"),
            Modified = ReadDetailOptionalString(userStory, "modified_date"),
            Version = version,
            OriginIssue = ReadDetailOptionalJson(userStory, "origin_issue"),
            OriginTask = ReadDetailOptionalJson(userStory, "origin_task"),
            Epics = ReadDetailOptionalJson(userStory, "epics")
        };
    }

    private static void ValidateDetailIdentityAndVersion(JsonElement userStory)
    {
        if (userStory.ValueKind != JsonValueKind.Object ||
            !userStory.TryGetProperty("id", out var idElement) ||
            idElement.ValueKind != JsonValueKind.Number ||
            !idElement.TryGetInt32(out var id) ||
            id <= 0)
            throw new TaigaRequestException("Taiga returned invalid user story identity data.");

        if (!userStory.TryGetProperty("version", out var versionElement) ||
            versionElement.ValueKind != JsonValueKind.Number ||
            !versionElement.TryGetInt32(out var version) ||
            version < 0)
            throw new TaigaRequestException("Taiga returned invalid user story version data.");
    }

    private static string? ReadStatusExtraInfoName(JsonElement userStory)
    {
        if (!userStory.TryGetProperty("status_extra_info", out var extraInfo) ||
            extraInfo.ValueKind != JsonValueKind.Object ||
            !extraInfo.TryGetProperty("name", out var name) ||
            name.ValueKind != JsonValueKind.String)
            return null;

        return name.GetString();
    }

    private static int? ReadDetailOptionalInt(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var number))
            throw new TaigaRequestException($"Taiga returned invalid user story {propertyName} data.");

        return number;
    }

    private static string? ReadDetailOptionalString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.String)
            throw new TaigaRequestException($"Taiga returned invalid user story {propertyName} data.");

        return value.GetString();
    }

    private static IReadOnlyList<JsonElement>? ReadTags(JsonElement userStory)
    {
        if (!userStory.TryGetProperty("tags", out var tags) ||
            tags.ValueKind == JsonValueKind.Null)
            return null;

        if (tags.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid user story tags data.");

        return tags.EnumerateArray().Select(tag => tag.Clone()).ToArray();
    }

    private static JsonElement? ReadDetailOptionalJson(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        return value.Clone();
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
