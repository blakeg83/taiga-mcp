using System.Text.Json;
using System.Text;
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

    public async Task<IReadOnlyList<UserStoryStatusDto>> ListUserStoryStatusesAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
        => (await ListUserStoryStatusesPageAsync(projectId, page, cancellationToken)).Items;

    internal async Task<UserStoryStatusListPage> ListUserStoryStatusesPageAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(page, nameof(page));

        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"userstory-statuses?project={projectId}&page={page}");
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;
        if (document.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid user story status list data.");

        var items = new List<UserStoryStatusDto>(32);
        foreach (var status in document.RootElement.EnumerateArray())
            items.Add(MapUserStoryStatus(status));

        var pageInfo = TaigaPagination.Parse(response.Headers, response.RequestUri);
        return new UserStoryStatusListPage(items, page, pageInfo.Total, pageInfo.NextPage, pageInfo.HasMore);
    }

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

    public async Task<UserStoryDetailDto> CreateUserStoryAsync(
        int projectId,
        string subject,
        string? description = null,
        int? status = null,
        int? assigned_to = null,
        string[]? tags = null,
        int? milestoneId = null,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Required(subject, nameof(subject));
        InputValidation.OptionalIds(
            (status, nameof(status)),
            (assigned_to, nameof(assigned_to)),
            (milestoneId, nameof(milestoneId)));

        var payload = new UserStoryCreateDto
        {
            Project = projectId,
            Subject = subject,
            Description = description,
            Status = status,
            AssignedTo = assigned_to,
            Tags = tags,
            Milestone = milestoneId
        };
        var json = JsonSerializer.Serialize(
            payload,
            new JsonSerializerOptions
            {
                DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
            });

        using var request = new HttpRequestMessage(HttpMethod.Post, "userstories")
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
        using var document = await _transport.ReadAsync(request, cancellationToken);
        try
        {
            var userStory = document.RootElement;
            var project = ReadDetailOptionalInt(userStory, "project");
            var statusId = ReadDetailOptionalInt(userStory, "status");
            var storyStatus = ReadStatusExtraInfoName(userStory);
            if (storyStatus is null && statusId.HasValue && project is > 0)
            {
                var statusMap = await LoadStatusMapAsync(project.Value, cancellationToken);
                storyStatus = statusMap.GetValueOrDefault(statusId.Value);
            }

            return MapUserStoryDetail(userStory, project, statusId, storyStatus);
        }
        catch (OperationCanceledException)
        {
            throw new OperationCanceledException(
                "Taiga write may already have applied; response enrichment was cancelled. Read the entity before retrying.",
                cancellationToken);
        }
        catch (Exception)
        {
            throw new TaigaRequestException(
                "Taiga write may already have applied; response enrichment failed. Read the entity before retrying.");
        }
    }

    public async Task<UserStoryDetailDto> UpdateUserStoryAsync(
        int userStoryId,
        int version,
        string? subject = null,
        string? description = null,
        int? status = null,
        int? assigned_to = null,
        string[]? tags = null,
        int? milestoneId = null,
        string? comment = null,
        string[]? clearFields = null,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(userStoryId, nameof(userStoryId));
        InputValidation.OptionalIds(
            (status, nameof(status)),
            (assigned_to, nameof(assigned_to)),
            (milestoneId, nameof(milestoneId)));
        if (version < 0) throw new ArgumentException("version must be nonnegative.");
        if (subject is not null) InputValidation.Required(subject, nameof(subject));

        var (clearAssignedTo, clearMilestone) = ValidateClearFields(clearFields, assigned_to, milestoneId);
        if (subject is null && description is null && status is null && assigned_to is null && tags is null &&
            milestoneId is null && !clearAssignedTo && !clearMilestone && string.IsNullOrWhiteSpace(comment))
            throw new ArgumentException("An update requires a change or a nonblank comment.");

        var payload = new UserStoryUpdateDto
        {
            Subject = subject,
            Description = description,
            Status = status,
            AssignedTo = assigned_to,
            Tags = tags,
            Milestone = milestoneId,
            Comment = comment,
            Version = version
        };
        var json = JsonSerializer.Serialize(payload.ToPatchPayload(clearAssignedTo, clearMilestone));

        using var request = new HttpRequestMessage(HttpMethod.Patch, $"userstories/{userStoryId}")
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
        request.Headers.Accept.ParseAdd("application/json");

        using var document = await _transport.ReadAsync(request, cancellationToken);
        try
        {
            var userStory = document.RootElement;
            var project = ReadDetailOptionalInt(userStory, "project");
            var statusId = ReadDetailOptionalInt(userStory, "status");
            var storyStatus = ReadStatusExtraInfoName(userStory);
            if (storyStatus is null && statusId.HasValue && project is > 0)
            {
                var statusMap = await LoadStatusMapAsync(project.Value, cancellationToken);
                storyStatus = statusMap.GetValueOrDefault(statusId.Value);
            }

            return MapUserStoryDetail(userStory, project, statusId, storyStatus);
        }
        catch (OperationCanceledException)
        {
            throw new OperationCanceledException(
                "Taiga write may already have applied; response enrichment was cancelled. Read the entity before retrying.",
                cancellationToken);
        }
        catch (Exception)
        {
            throw new TaigaRequestException(
                "Taiga write may already have applied; response enrichment failed. Read the entity before retrying.");
        }
    }

    public Task<int> AddCommentAsync(
        int userStoryId,
        int version,
        string text,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(userStoryId, nameof(userStoryId));
        InputValidation.Nonnegative(version, nameof(version));
        InputValidation.Required(text, nameof(text));
        return WorkItemCommentPatch.SendAsync(
            _transport,
            $"userstories/{userStoryId}",
            "user story",
            version,
            text,
            cancellationToken);
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

    private static UserStoryStatusDto MapUserStoryStatus(JsonElement status)
    {
        if (status.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid user story status data.");

        return new UserStoryStatusDto
        {
            Id = ReadStatusRequiredPositiveInt(status, "id"),
            Project = ReadStatusOptionalPositiveInt(status, "project"),
            Name = ReadStatusOptionalString(status, "name"),
            Slug = ReadStatusOptionalString(status, "slug"),
            Order = ReadStatusOptionalInt(status, "order"),
            Color = ReadStatusOptionalString(status, "color"),
            IsClosed = ReadStatusOptionalBoolean(status, "is_closed"),
            IsArchived = ReadStatusOptionalBoolean(status, "is_archived"),
            WipLimit = ReadStatusOptionalInt(status, "wip_limit")
        };
    }

    private static int ReadStatusRequiredPositiveInt(JsonElement status, string propertyName)
    {
        if (!status.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid user story status {propertyName} data.");

        return number;
    }

    private static int? ReadStatusOptionalPositiveInt(JsonElement status, string propertyName)
    {
        if (!status.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid user story status {propertyName} data.");

        return number;
    }

    private static int? ReadStatusOptionalInt(JsonElement status, string propertyName)
    {
        if (!status.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var number))
            throw new TaigaRequestException($"Taiga returned invalid user story status {propertyName} data.");

        return number;
    }

    private static string? ReadStatusOptionalString(JsonElement status, string propertyName)
    {
        if (!status.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.String)
            throw new TaigaRequestException($"Taiga returned invalid user story status {propertyName} data.");

        return value.GetString();
    }

    private static bool? ReadStatusOptionalBoolean(JsonElement status, string propertyName)
    {
        if (!status.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind is not JsonValueKind.True and not JsonValueKind.False)
            throw new TaigaRequestException($"Taiga returned invalid user story status {propertyName} data.");

        return value.GetBoolean();
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

    private static (bool ClearAssignedTo, bool ClearMilestone) ValidateClearFields(
        string[]? clearFields,
        int? assignedTo,
        int? milestoneId)
    {
        if (clearFields is null)
            return (false, false);

        var clearAssignedTo = false;
        var clearMilestone = false;
        foreach (var field in clearFields)
        {
            if (string.Equals(field, "assigned_to", StringComparison.Ordinal))
                clearAssignedTo = true;
            else if (string.Equals(field, "milestone", StringComparison.Ordinal))
                clearMilestone = true;
            else
                throw new ArgumentException($"clearFields contains unsupported field '{field}'.");
        }

        if (clearAssignedTo && assignedTo.HasValue)
            throw new ArgumentException("assigned_to cannot be set and cleared in the same update.");
        if (clearMilestone && milestoneId.HasValue)
            throw new ArgumentException("milestone cannot be set and cleared in the same update.");

        return (clearAssignedTo, clearMilestone);
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

internal sealed record UserStoryStatusListPage(
    IReadOnlyList<UserStoryStatusDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);
