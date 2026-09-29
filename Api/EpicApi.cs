using System.Text.Json;
using System.Text;
using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>Epic operations.</summary>
public sealed class EpicApi
{
    private readonly TaigaTransport _transport;
    private readonly UserStoryApi _userStories;

    public EpicApi(TaigaTransport transport)
        : this(transport, new UserStoryApi(transport))
    {
    }

    public EpicApi(TaigaTransport transport, UserStoryApi userStories)
    {
        _transport = transport;
        _userStories = userStories;
    }

    public async Task<EpicDetailDto> GetEpicAsync(
        int epicId,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(epicId, nameof(epicId));
        using var request = new HttpRequestMessage(HttpMethod.Get, $"epics/{epicId}");
        using var document = await _transport.ReadAsync(request, cancellationToken);
        return MapEpicDetail(document.RootElement);
    }

    public async Task<EpicDetailDto> CreateEpicAsync(
        int projectId,
        string subject,
        string? description = null,
        int? status = null,
        int? assigned_to = null,
        string? color = null,
        string[]? tags = null,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Required(subject, nameof(subject));
        InputValidation.OptionalIds(
            (status, nameof(status)),
            (assigned_to, nameof(assigned_to)));

        var payload = new EpicCreateDto
        {
            Project = projectId,
            Subject = subject,
            Description = description,
            Status = status,
            AssignedTo = assigned_to,
            Color = color,
            Tags = tags
        };
        var json = JsonSerializer.Serialize(
            payload,
            new JsonSerializerOptions
            {
                DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
            });

        using var request = new HttpRequestMessage(HttpMethod.Post, "epics")
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
        using var document = await _transport.ReadAsync(request, cancellationToken);
        try
        {
            return MapEpicDetail(document.RootElement);
        }
        catch (OperationCanceledException)
        {
            throw new OperationCanceledException(
                "Taiga write may already have applied; response mapping was cancelled. Read the epic before retrying.",
                cancellationToken);
        }
        catch (Exception)
        {
            throw new TaigaRequestException(
                "Taiga write may already have applied; response mapping failed. Read the epic before retrying.");
        }
    }

    public async Task<EpicDetailDto> UpdateEpicAsync(
        int epicId,
        int version,
        string? subject = null,
        string? description = null,
        int? status = null,
        int? assigned_to = null,
        string? color = null,
        string[]? tags = null,
        string? comment = null,
        string[]? clearFields = null,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(epicId, nameof(epicId));
        InputValidation.OptionalIds((status, nameof(status)), (assigned_to, nameof(assigned_to)));
        InputValidation.Nonnegative(version, nameof(version));
        if (subject is not null) InputValidation.Required(subject, nameof(subject));

        var clearAssignedTo = ValidateClearFields(clearFields, assigned_to);
        if (subject is null && description is null && status is null && assigned_to is null &&
            color is null && tags is null && !clearAssignedTo && string.IsNullOrWhiteSpace(comment))
            throw new ArgumentException("An update requires a change or a nonblank comment.");

        var payload = new EpicUpdateDto
        {
            Subject = subject,
            Description = description,
            Status = status,
            AssignedTo = assigned_to,
            Color = color,
            Tags = tags,
            Comment = comment,
            Version = version
        };
        var json = JsonSerializer.Serialize(payload.ToPatchPayload(clearAssignedTo));

        using var request = new HttpRequestMessage(HttpMethod.Patch, $"epics/{epicId}")
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
        request.Headers.Accept.ParseAdd("application/json");

        using var document = await _transport.ReadAsync(request, cancellationToken);
        try
        {
            return MapEpicDetail(document.RootElement);
        }
        catch (OperationCanceledException)
        {
            throw new OperationCanceledException(
                "Taiga write may already have applied; response mapping was cancelled. Read the epic before retrying.",
                cancellationToken);
        }
        catch (Exception)
        {
            throw new TaigaRequestException(
                "Taiga write may already have applied; response mapping failed. Read the epic before retrying.");
        }
    }

    public Task<int> AddCommentAsync(
        int epicId,
        int version,
        string text,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(epicId, nameof(epicId));
        InputValidation.Nonnegative(version, nameof(version));
        InputValidation.Required(text, nameof(text));
        return WorkItemCommentPatch.SendAsync(
            _transport,
            $"epics/{epicId}",
            "epic",
            version,
            text,
            cancellationToken);
    }

    public async Task<EpicUserStoryLinkDto> LinkUserStoryToEpicAsync(
        int epicId,
        int userStoryId,
        long? order = null,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(epicId, nameof(epicId));
        InputValidation.Positive(userStoryId, nameof(userStoryId));

        var existing = await TryGetUserStoryLinkAsync(epicId, userStoryId, cancellationToken);
        if (existing is not null)
            return existing with { Created = false };

        // A nested 404 can mean an inaccessible parent rather than a missing link.
        // Confirm both resources before creating the relationship.
        await GetEpicAsync(epicId, cancellationToken);
        await _userStories.GetUserStoryAsync(userStoryId, cancellationToken);

        var payload = new Dictionary<string, object>
        {
            ["epic"] = epicId,
            ["user_story"] = userStoryId
        };
        if (order.HasValue)
            payload["order"] = order.Value;

        var json = JsonSerializer.Serialize(payload);
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"epics/{epicId}/related_userstories")
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };

        try
        {
            using var document = await _transport.ReadAsync(request, cancellationToken);
            try
            {
                return MapUserStoryLink(document.RootElement, created: true);
            }
            catch (OperationCanceledException)
            {
                throw new OperationCanceledException(
                    "Taiga write may already have applied; relationship response mapping was cancelled. Read the relationship before retrying.",
                    cancellationToken);
            }
            catch (Exception)
            {
                throw new TaigaRequestException(
                    "Taiga write may already have applied; relationship response mapping failed. Read the relationship before retrying.");
            }
        }
        catch (TaigaRequestException exception) when (exception.IsDuplicateRelationship)
        {
            var concurrent = await TryGetUserStoryLinkAsync(epicId, userStoryId, cancellationToken);
            if (concurrent is not null)
                return concurrent with { Created = false };

            throw;
        }
    }

    private async Task<EpicUserStoryLinkDto?> TryGetUserStoryLinkAsync(
        int epicId,
        int userStoryId,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"epics/{epicId}/related_userstories/{userStoryId}");
        try
        {
            using var document = await _transport.ReadAsync(request, cancellationToken);
            return MapUserStoryLink(document.RootElement, created: false);
        }
        catch (TaigaRequestException exception) when (exception.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    private static EpicUserStoryLinkDto MapUserStoryLink(JsonElement link, bool created)
    {
        var relationship = MapEpicUserStoryRelationship(link);

        return new EpicUserStoryLinkDto
        {
            EpicId = relationship.EpicId,
            UserStoryId = relationship.UserStoryId,
            Order = relationship.Order,
            Created = created
        };
    }

    private static EpicUserStoryRelationshipDto MapEpicUserStoryRelationship(JsonElement relationship)
    {
        if (relationship.ValueKind != JsonValueKind.Object ||
            !relationship.TryGetProperty("epic", out var epic) ||
            epic.ValueKind != JsonValueKind.Number ||
            !epic.TryGetInt32(out var epicId) || epicId <= 0 ||
            !relationship.TryGetProperty("user_story", out var userStory) ||
            userStory.ValueKind != JsonValueKind.Number ||
            !userStory.TryGetInt32(out var userStoryId) || userStoryId <= 0 ||
            !relationship.TryGetProperty("order", out var order) ||
            order.ValueKind != JsonValueKind.Number ||
            !order.TryGetInt64(out var relationshipOrder))
            throw new TaigaRequestException("Taiga returned invalid epic/user story relationship data.");

        return new EpicUserStoryRelationshipDto
        {
            EpicId = epicId,
            UserStoryId = userStoryId,
            Order = relationshipOrder
        };
    }

    public async Task<IReadOnlyList<EpicUserStoryRelationshipDto>> ListEpicUserStoriesAsync(
        int epicId,
        int page = 1,
        CancellationToken cancellationToken = default)
        => (await ListEpicUserStoriesPageAsync(epicId, page, cancellationToken)).Items;

    internal async Task<EpicUserStoryRelationshipListPage> ListEpicUserStoriesPageAsync(
        int epicId,
        int page = 1,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(epicId, nameof(epicId));
        InputValidation.Positive(page, nameof(page));

        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"epics/{epicId}/related_userstories?page={page}");
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;
        if (document.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid epic user story relationship list data.");

        var items = new List<EpicUserStoryRelationshipDto>(32);
        foreach (var relationship in document.RootElement.EnumerateArray())
        {
            var mapped = MapEpicUserStoryRelationship(relationship);
            if (mapped.EpicId != epicId)
                throw new TaigaRequestException("Taiga returned an epic user story relationship for a different epic.");

            items.Add(mapped);
        }

        var pageInfo = TaigaPagination.Parse(response.Headers, response.RequestUri);
        return new EpicUserStoryRelationshipListPage(
            items,
            page,
            pageInfo.Total,
            pageInfo.NextPage,
            pageInfo.HasMore);
    }

    public async Task<IReadOnlyList<EpicDto>> ListEpicsAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
        => (await ListEpicsPageAsync(
            projectId,
            new EpicListOptions { Page = page },
            cancellationToken)).Items;

    public async Task<IReadOnlyList<EpicStatusDto>> ListEpicStatusesAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
        => (await ListEpicStatusesPageAsync(projectId, page, cancellationToken)).Items;

    internal async Task<EpicStatusListPage> ListEpicStatusesPageAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(page, nameof(page));

        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"epic-statuses?project={projectId}&page={page}");
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;
        if (document.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid epic status list data.");

        var items = new List<EpicStatusDto>(32);
        foreach (var status in document.RootElement.EnumerateArray())
        {
            var mapped = MapEpicStatus(status);
            if (mapped.Project.HasValue && mapped.Project.Value != projectId)
                throw new TaigaRequestException("Taiga returned epic status data for a different project.");

            items.Add(mapped);
        }

        var pageInfo = TaigaPagination.Parse(response.Headers, response.RequestUri);
        return new EpicStatusListPage(items, page, pageInfo.Total, pageInfo.NextPage, pageInfo.HasMore);
    }

    internal async Task<EpicListPage> ListEpicsPageAsync(
        int projectId,
        EpicListOptions options,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(options.Page, nameof(options.Page));
        ValidateListOptions(options);

        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            EpicListQueryBuilder.Build(projectId, options));
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;
        if (document.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid epic list data.");

        var items = new List<EpicDto>(64);
        foreach (var epic in document.RootElement.EnumerateArray())
            items.Add(MapEpic(epic));

        var pageInfo = TaigaPagination.Parse(response.Headers, response.RequestUri);
        return new EpicListPage(
            items,
            options.Page,
            pageInfo.Total,
            pageInfo.NextPage,
            pageInfo.HasMore);
    }

    private static void ValidateListOptions(EpicListOptions options)
    {
        if (options.StatusIds is not null)
            foreach (var id in options.StatusIds)
                InputValidation.Positive(id, "statusIds");

        InputValidation.OptionalIds((options.AssignedTo, nameof(options.AssignedTo)));
    }

    private static EpicDto MapEpic(JsonElement epic)
    {
        if (epic.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid epic data.");

        return new EpicDto
        {
            Id = ReadRequiredPositiveInt(epic, "id"),
            Ref = ReadRequiredPositiveInt(epic, "ref"),
            Project = ReadOptionalPositiveInt(epic, "project"),
            Subject = ReadOptionalString(epic, "subject"),
            StatusId = ReadOptionalPositiveInt(epic, "status"),
            Status = ReadStatusName(epic),
            AssignedTo = ReadOptionalPositiveInt(epic, "assigned_to"),
            Color = ReadOptionalString(epic, "color"),
            Tags = ReadTags(epic),
            Modified = ReadOptionalString(epic, "modified_date"),
            Version = ReadOptionalNonnegativeInt(epic, "version")
        };
    }

    private static EpicStatusDto MapEpicStatus(JsonElement status)
    {
        if (status.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid epic status data.");

        return new EpicStatusDto
        {
            Id = ReadEpicStatusRequiredPositiveInt(status, "id"),
            Project = ReadEpicStatusOptionalPositiveInt(status, "project"),
            Name = ReadEpicStatusOptionalString(status, "name"),
            Slug = ReadEpicStatusOptionalString(status, "slug"),
            Order = ReadEpicStatusOptionalInt(status, "order"),
            Color = ReadEpicStatusOptionalString(status, "color"),
            IsClosed = ReadEpicStatusOptionalBoolean(status, "is_closed")
        };
    }

    private static int ReadEpicStatusRequiredPositiveInt(JsonElement status, string propertyName)
    {
        if (!status.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid epic status {propertyName} data.");

        return number;
    }

    private static int? ReadEpicStatusOptionalPositiveInt(JsonElement status, string propertyName)
    {
        if (!status.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid epic status {propertyName} data.");

        return number;
    }

    private static int? ReadEpicStatusOptionalInt(JsonElement status, string propertyName)
    {
        if (!status.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var number))
            throw new TaigaRequestException($"Taiga returned invalid epic status {propertyName} data.");

        return number;
    }

    private static string? ReadEpicStatusOptionalString(JsonElement status, string propertyName)
    {
        if (!status.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.String)
            throw new TaigaRequestException($"Taiga returned invalid epic status {propertyName} data.");

        return value.GetString();
    }

    private static bool? ReadEpicStatusOptionalBoolean(JsonElement status, string propertyName)
    {
        if (!status.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind is not JsonValueKind.True and not JsonValueKind.False)
            throw new TaigaRequestException($"Taiga returned invalid epic status {propertyName} data.");

        return value.GetBoolean();
    }

    private static EpicDetailDto MapEpicDetail(JsonElement epic)
    {
        ValidateDetailIdentityAndVersion(epic);

        return new EpicDetailDto
        {
            Id = ReadRequiredPositiveInt(epic, "id"),
            Ref = ReadRequiredPositiveInt(epic, "ref"),
            Project = ReadRequiredPositiveInt(epic, "project"),
            Subject = ReadOptionalString(epic, "subject"),
            Description = ReadOptionalString(epic, "description"),
            StatusId = ReadOptionalPositiveInt(epic, "status"),
            Status = ReadStatusName(epic),
            AssignedTo = ReadOptionalPositiveInt(epic, "assigned_to"),
            Color = ReadOptionalString(epic, "color"),
            Tags = ReadTags(epic),
            Modified = ReadOptionalString(epic, "modified_date"),
            IsClosed = ReadOptionalBoolean(epic, "is_closed"),
            IsBlocked = ReadOptionalBoolean(epic, "is_blocked"),
            BlockedNote = ReadOptionalString(epic, "blocked_note"),
            ClientRequirement = ReadOptionalBoolean(epic, "client_requirement"),
            TeamRequirement = ReadOptionalBoolean(epic, "team_requirement"),
            UserStoriesCounts = ReadOptionalJson(epic, "user_stories_counts"),
            Version = epic.GetProperty("version").GetInt32()
        };
    }

    private static void ValidateDetailIdentityAndVersion(JsonElement epic)
    {
        if (epic.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid epic detail data.");

        ReadRequiredPositiveInt(epic, "id");
        ReadRequiredPositiveInt(epic, "ref");
        ReadRequiredPositiveInt(epic, "project");

        if (!epic.TryGetProperty("version", out var version) ||
            version.ValueKind != JsonValueKind.Number ||
            !version.TryGetInt32(out var number) ||
            number < 0)
            throw new TaigaRequestException("Taiga returned invalid epic version data.");
    }

    private static string? ReadStatusName(JsonElement epic)
    {
        if (!epic.TryGetProperty("status_extra_info", out var extraInfo) ||
            extraInfo.ValueKind != JsonValueKind.Object ||
            !extraInfo.TryGetProperty("name", out var name) ||
            name.ValueKind != JsonValueKind.String)
            return null;

        return name.GetString();
    }

    private static IReadOnlyList<JsonElement>? ReadTags(JsonElement epic)
    {
        if (!epic.TryGetProperty("tags", out var tags) ||
            tags.ValueKind == JsonValueKind.Null)
            return null;

        if (tags.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid epic tags data.");

        return tags.EnumerateArray().Select(tag => tag.Clone()).ToArray();
    }

    private static int ReadRequiredPositiveInt(JsonElement epic, string propertyName)
    {
        if (!epic.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid epic {propertyName} data.");

        return number;
    }

    private static int? ReadOptionalPositiveInt(JsonElement epic, string propertyName)
    {
        if (!epic.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid epic {propertyName} data.");

        return number;
    }

    private static int? ReadOptionalNonnegativeInt(JsonElement epic, string propertyName)
    {
        if (!epic.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number < 0)
            throw new TaigaRequestException($"Taiga returned invalid epic {propertyName} data.");

        return number;
    }

    private static bool? ReadOptionalBoolean(JsonElement epic, string propertyName)
    {
        if (!epic.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind is not JsonValueKind.True and not JsonValueKind.False)
            throw new TaigaRequestException($"Taiga returned invalid epic {propertyName} data.");

        return value.GetBoolean();
    }

    private static JsonElement? ReadOptionalJson(JsonElement epic, string propertyName)
    {
        if (!epic.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        return value.Clone();
    }

    private static string? ReadOptionalString(JsonElement epic, string propertyName)
    {
        if (!epic.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.String)
            throw new TaigaRequestException($"Taiga returned invalid epic {propertyName} data.");

        return value.GetString();
    }

    private static bool ValidateClearFields(string[]? clearFields, int? assignedTo)
    {
        if (clearFields is null) return false;

        var clearAssignedTo = false;
        foreach (var field in clearFields)
        {
            if (!string.Equals(field, "assigned_to", StringComparison.Ordinal))
                throw new ArgumentException($"clearFields contains unsupported field '{field}'.");

            clearAssignedTo = true;
        }

        if (clearAssignedTo && assignedTo.HasValue)
            throw new ArgumentException("assigned_to cannot be set and cleared in the same update.");

        return clearAssignedTo;
    }
}

internal sealed record EpicStatusListPage(
    IReadOnlyList<EpicStatusDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);

internal sealed record EpicUserStoryRelationshipListPage(
    IReadOnlyList<EpicUserStoryRelationshipDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);
