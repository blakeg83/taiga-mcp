using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>Reads visible comments from the history stream of a work item.</summary>
public sealed class WorkItemHistoryApi
{
    private readonly TaigaTransport _transport;

    public WorkItemHistoryApi(TaigaTransport transport)
    {
        _transport = transport;
    }

    public async Task<IReadOnlyList<WorkItemCommentEntryDto>> ListWorkItemCommentsAsync(
        WorkItemKind kind,
        int id,
        int page = 1,
        CancellationToken cancellationToken = default)
        => (await ListWorkItemCommentsPageAsync(kind, id, page, cancellationToken)).Items;

    public async Task<IReadOnlyList<WorkItemHistoryEntryDto>> ListWorkItemHistoryAsync(
        WorkItemKind kind,
        int id,
        int page = 1,
        CancellationToken cancellationToken = default)
        => (await ListWorkItemHistoryPageAsync(kind, id, page, cancellationToken)).Items;

    internal async Task<WorkItemCommentListPage> ListWorkItemCommentsPageAsync(
        WorkItemKind kind,
        int id,
        int page = 1,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(id, nameof(id));
        InputValidation.Positive(page, nameof(page));
        var route = WorkItemHistoryContract.GetRoute(kind);

        var query = string.Create(
            CultureInfo.InvariantCulture,
            $"history/{route}/{id}?type=comment&page={page}");
        using var request = new HttpRequestMessage(HttpMethod.Get, query);
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;

        var parsed = ParseResponse(document.RootElement, response.Headers, response.RequestUri);
        return new WorkItemCommentListPage(
            parsed.Items,
            page,
            parsed.Total,
            parsed.NextPage,
            parsed.HasMore);
    }

    internal async Task<WorkItemHistoryListPage> ListWorkItemHistoryPageAsync(
        WorkItemKind kind,
        int id,
        int page = 1,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(id, nameof(id));
        InputValidation.Positive(page, nameof(page));
        var route = WorkItemHistoryContract.GetRoute(kind);

        var query = string.Create(
            CultureInfo.InvariantCulture,
            $"history/{route}/{id}?page={page}");
        using var request = new HttpRequestMessage(HttpMethod.Get, query);
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;

        var parsed = ParseHistoryResponse(document.RootElement, response.Headers, response.RequestUri);
        return new WorkItemHistoryListPage(
            parsed.Items,
            page,
            parsed.Total,
            parsed.NextPage,
            parsed.HasMore);
    }

    private static ParsedCommentResponse ParseResponse(
        JsonElement root,
        IReadOnlyDictionary<string, string[]> headers,
        Uri requestUri)
    {
        var entries = ReadEntries(root, requestUri, out var bodyInfo, "comment");

        var items = new List<WorkItemCommentEntryDto>(entries.GetArrayLength());
        foreach (var entry in entries.EnumerateArray())
        {
            var comment = MapVisibleComment(entry);
            if (comment is not null)
                items.Add(comment);
        }

        var headerInfo = TaigaPagination.Parse(headers, requestUri);
        return new ParsedCommentResponse(
            items,
            MergeTotal(headers, headerInfo.Total, bodyInfo),
            MergeNextPage(headers, headerInfo.NextPage, bodyInfo),
            MergeHasMore(headers, headerInfo.HasMore, bodyInfo));
    }

    private static ParsedHistoryResponse ParseHistoryResponse(
        JsonElement root,
        IReadOnlyDictionary<string, string[]> headers,
        Uri requestUri)
    {
        var entries = ReadEntries(root, requestUri, out var bodyInfo, "history");
        var items = new List<WorkItemHistoryEntryDto>(entries.GetArrayLength());
        foreach (var entry in entries.EnumerateArray())
        {
            var historyEntry = MapVisibleHistoryEntry(entry);
            if (historyEntry is not null)
                items.Add(historyEntry);
        }

        var headerInfo = TaigaPagination.Parse(headers, requestUri);
        return new ParsedHistoryResponse(
            items,
            MergeTotal(headers, headerInfo.Total, bodyInfo),
            MergeNextPage(headers, headerInfo.NextPage, bodyInfo),
            MergeHasMore(headers, headerInfo.HasMore, bodyInfo));
    }

    private static JsonElement ReadEntries(
        JsonElement root,
        Uri requestUri,
        out BodyPageInfo bodyInfo,
        string dataKind)
    {
        bodyInfo = default;
        if (root.ValueKind == JsonValueKind.Array)
            return root;

        if (root.ValueKind == JsonValueKind.Object &&
            root.TryGetProperty("results", out var results) &&
            results.ValueKind == JsonValueKind.Array)
        {
            bodyInfo = ParseBodyPageInfo(root, requestUri);
            return results;
        }

        throw new TaigaRequestException($"Taiga returned invalid work-item {dataKind} history data.");
    }

    private static BodyPageInfo ParseBodyPageInfo(JsonElement root, Uri requestUri)
    {
        var hasCount = root.TryGetProperty("count", out var countElement);
        var count = 0;
        var countIsValid = hasCount &&
            countElement.ValueKind == JsonValueKind.Number &&
            countElement.TryGetInt32(out count) &&
            count >= 0;

        var hasNext = root.TryGetProperty("next", out var nextElement);
        var nextIsValid = false;
        int? nextPage = null;
        if (hasNext)
        {
            if (nextElement.ValueKind == JsonValueKind.Null)
            {
                nextIsValid = true;
            }
            else if (nextElement.ValueKind == JsonValueKind.String &&
                     TaigaPagination.TryParseNextPage(nextElement.GetString()!, requestUri, out nextPage))
            {
                nextIsValid = true;
            }
        }

        return new BodyPageInfo(
            hasCount,
            countIsValid ? count : null,
            hasNext,
            nextIsValid,
            nextPage,
            nextIsValid ? nextPage.HasValue : null);
    }

    private static int? MergeTotal(
        IReadOnlyDictionary<string, string[]> headers,
        int? headerValue,
        BodyPageInfo bodyInfo)
        => MergeValue(
            HasHeader(headers, "x-pagination-count"),
            headerValue,
            bodyInfo.HasCount,
            bodyInfo.CountIsValid,
            bodyInfo.Total);

    private static int? MergeNextPage(
        IReadOnlyDictionary<string, string[]> headers,
        int? headerValue,
        BodyPageInfo bodyInfo)
        => MergeValue(
            HasHeader(headers, "x-pagination-next"),
            headerValue,
            bodyInfo.HasNext,
            bodyInfo.NextIsValid,
            bodyInfo.NextPage);

    private static bool? MergeHasMore(
        IReadOnlyDictionary<string, string[]> headers,
        bool? headerValue,
        BodyPageInfo bodyInfo)
        => MergeValue(
            HasMeaningfulHasMoreHeader(headers),
            headerValue,
            bodyInfo.HasNext,
            bodyInfo.NextIsValid,
            bodyInfo.HasMore);

    private static bool HasMeaningfulHasMoreHeader(IReadOnlyDictionary<string, string[]> headers)
    {
        if (HasHeader(headers, "x-pagination-next"))
            return true;

        if (!headers.TryGetValue("x-paginated", out var values) || values.FirstOrDefault() is not { } value)
            return false;

        return bool.TryParse(value, out var paginated) && !paginated;
    }

    private static T? MergeValue<T>(
        bool headerPresent,
        T? headerValue,
        bool bodyPresent,
        bool bodyIsValid,
        T? bodyValue)
        where T : struct
    {
        if (headerPresent)
        {
            if (bodyPresent && (!bodyIsValid || !Nullable.Equals(headerValue, bodyValue)))
                return null;

            return headerValue;
        }

        return bodyPresent && bodyIsValid ? bodyValue : null;
    }

    private static WorkItemCommentEntryDto? MapVisibleComment(JsonElement entry)
    {
        if (entry.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid work-item comment history entry data.");

        if (entry.TryGetProperty("is_hidden", out var hidden) &&
            hidden.ValueKind is not JsonValueKind.False and not JsonValueKind.True)
            return null;
        if (hidden.ValueKind == JsonValueKind.True)
            return null;

        if (IsSet(entry, "delete_comment_date") || IsSet(entry, "delete_comment_user"))
            return null;

        if (!entry.TryGetProperty("comment", out var commentElement) ||
            commentElement.ValueKind != JsonValueKind.String)
            return null;
        var comment = commentElement.GetString();
        if (string.IsNullOrWhiteSpace(comment))
            return null;

        return new WorkItemCommentEntryDto
        {
            Id = ReadRequiredNonblankString(entry, "id"),
            Comment = comment,
            CreatedAt = ReadRequiredNonblankString(entry, "created_at"),
            User = MapUser(entry),
            EditCommentDate = ReadOptionalString(entry, "edit_comment_date")
        };
    }

    private static WorkItemHistoryEntryDto? MapVisibleHistoryEntry(JsonElement entry)
    {
        if (entry.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid work-item history entry data.");

        if (entry.TryGetProperty("is_hidden", out var hidden) &&
            (hidden.ValueKind == JsonValueKind.True ||
             hidden.ValueKind != JsonValueKind.False))
            return null;

        var id = ReadRequiredNonblankString(entry, "id", "work-item history");
        var type = ReadRequiredInt(entry, "type", "work-item history");
        var createdAt = ReadRequiredNonblankString(entry, "created_at", "work-item history");
        var deleted = IsSet(entry, "delete_comment_date") || IsSet(entry, "delete_comment_user");
        var comment = ReadOptionalString(entry, "comment");
        JsonElement? diff = ReadOptionalJson(entry, "diff");
        JsonElement? valuesDiff = ReadOptionalJson(entry, "values_diff");
        if (deleted)
        {
            if (!TryRedactDeletedChange(diff, comment, out diff) ||
                !TryRedactDeletedChange(valuesDiff, comment, out valuesDiff))
                return null;
            comment = null;
        }

        return new WorkItemHistoryEntryDto
        {
            Id = id,
            Type = type,
            CreatedAt = createdAt,
            User = MapUser(entry),
            Diff = diff,
            ValuesDiff = valuesDiff,
            Comment = comment,
            EditCommentDate = ReadOptionalString(entry, "edit_comment_date"),
            DeleteCommentDate = ReadOptionalString(entry, "delete_comment_date"),
            DeleteCommentUser = MapDeleteCommentUser(entry),
            CommentDeleted = deleted ? true : null,
            IsSnapshot = ReadOptionalBoolean(entry, "is_snapshot")
        };
    }

    private static bool TryRedactDeletedChange(
        JsonElement? value,
        string? deletedComment,
        out JsonElement? redacted)
    {
        redacted = null;
        if (!value.HasValue || value.Value.ValueKind == JsonValueKind.Null)
            return true;
        if (value.Value.ValueKind is not JsonValueKind.Object and not JsonValueKind.Array)
            return false;

        var node = JsonNode.Parse(value.Value.GetRawText());
        if (node is null)
            return false;

        if (!TryRedactDeletedNode(node, deletedComment, out var safeNode) || safeNode is null)
            return true;

        using var document = JsonDocument.Parse(safeNode.ToJsonString());
        redacted = document.RootElement.Clone();
        return true;
    }

    private static bool TryRedactDeletedNode(
        JsonNode node,
        string? deletedComment,
        out JsonNode? redacted)
    {
        if (node is JsonObject obj)
        {
            foreach (var property in obj.ToList())
            {
                if (IsCommentField(property.Key))
                {
                    obj.Remove(property.Key);
                    continue;
                }

                if (property.Value is null)
                    continue;
                if (!TryRedactDeletedNode(property.Value, deletedComment, out var safeValue))
                {
                    redacted = null;
                    return false;
                }

                if (safeValue is null)
                    obj.Remove(property.Key);
                else if (!ReferenceEquals(safeValue, property.Value))
                    obj[property.Key] = safeValue;
            }

            redacted = obj.Count == 0 ? null : obj;
            return true;
        }

        if (node is JsonArray array)
        {
            for (var index = array.Count - 1; index >= 0; index--)
            {
                var child = array[index];
                if (child is null)
                    continue;
                if (!TryRedactDeletedNode(child, deletedComment, out var safeChild))
                {
                    redacted = null;
                    return false;
                }

                if (safeChild is null)
                    array.RemoveAt(index);
                else if (!ReferenceEquals(safeChild, child))
                    array[index] = safeChild;
            }

            redacted = array.Count == 0 ? null : array;
            return true;
        }

        if (node is JsonValue value && value.TryGetValue<string>(out var text) &&
            IsDeletedCommentText(text, deletedComment))
        {
            redacted = null;
            return true;
        }

        redacted = node;
        return true;
    }

    private static bool IsCommentField(string name)
        => name.Contains("comment", StringComparison.OrdinalIgnoreCase);

    private static bool IsDeletedCommentText(string value, string? deletedComment)
    {
        if (string.IsNullOrEmpty(deletedComment))
            return false;
        if (value.Contains(deletedComment, StringComparison.Ordinal))
            return true;

        try
        {
            var decoded = JsonSerializer.Deserialize<string>($"\"{value.Replace("\"", "\\\"", StringComparison.Ordinal)}\"");
            return decoded?.Contains(deletedComment, StringComparison.Ordinal) == true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool IsSet(JsonElement entry, string propertyName)
        => entry.TryGetProperty(propertyName, out var value) && value.ValueKind != JsonValueKind.Null;

    private static WorkItemCommentUserDto? MapUser(JsonElement entry)
    {
        if (!entry.TryGetProperty("user", out var user) || user.ValueKind != JsonValueKind.Object)
            return null;

        int? id = null;
        if (user.TryGetProperty("pk", out var pk) &&
            pk.ValueKind == JsonValueKind.Number &&
            pk.TryGetInt32(out var parsedId) &&
            parsedId > 0)
            id = parsedId;

        return new WorkItemCommentUserDto
        {
            Id = id,
            Name = ReadOptionalString(user, "name"),
            Username = ReadOptionalString(user, "username"),
            IsActive = user.TryGetProperty("is_active", out var active) &&
                       active.ValueKind is JsonValueKind.True or JsonValueKind.False
                ? active.GetBoolean()
                : null
        };
    }

    private static WorkItemCommentUserDto? MapDeleteCommentUser(JsonElement entry)
    {
        if (!entry.TryGetProperty("delete_comment_user", out var user) ||
            user.ValueKind != JsonValueKind.Object)
            return null;

        return MapUserObject(user);
    }

    private static WorkItemCommentUserDto? MapUserObject(JsonElement user)
    {
        int? id = null;
        if (user.TryGetProperty("pk", out var pk) &&
            pk.ValueKind == JsonValueKind.Number &&
            pk.TryGetInt32(out var parsedId) &&
            parsedId > 0)
            id = parsedId;

        return new WorkItemCommentUserDto
        {
            Id = id,
            Name = ReadOptionalString(user, "name"),
            Username = ReadOptionalString(user, "username"),
            IsActive = ReadOptionalBoolean(user, "is_active")
        };
    }

    private static string ReadRequiredNonblankString(
        JsonElement element,
        string propertyName,
        string dataKind = "work-item comment")
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(value.GetString()))
            throw new TaigaRequestException($"Taiga returned invalid {dataKind} {propertyName} data.");

        return value.GetString()!;
    }

    private static int ReadRequiredInt(JsonElement element, string propertyName, string dataKind)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var result))
            throw new TaigaRequestException($"Taiga returned invalid {dataKind} {propertyName} data.");

        return result;
    }

    private static string? ReadOptionalString(JsonElement element, string propertyName)
        => element.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static bool? ReadOptionalBoolean(JsonElement element, string propertyName)
        => element.TryGetProperty(propertyName, out var value) &&
           value.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? value.GetBoolean()
            : null;

    private static JsonElement? ReadOptionalJson(JsonElement element, string propertyName)
        => element.TryGetProperty(propertyName, out var value) &&
           value.ValueKind != JsonValueKind.Null
            ? value.Clone()
            : null;

    private static bool HasHeader(IReadOnlyDictionary<string, string[]> headers, string name)
        => headers.Keys.Any(key => string.Equals(key, name, StringComparison.OrdinalIgnoreCase));

    private readonly record struct BodyPageInfo(
        bool HasCount,
        int? Total,
        bool HasNext,
        bool NextIsValid,
        int? NextPage,
        bool? HasMore)
    {
        public bool CountIsValid => Total.HasValue || !HasCount;
    }

    private readonly record struct ParsedCommentResponse(
        IReadOnlyList<WorkItemCommentEntryDto> Items,
        int? Total,
        int? NextPage,
        bool? HasMore);

    private readonly record struct ParsedHistoryResponse(
        IReadOnlyList<WorkItemHistoryEntryDto> Items,
        int? Total,
        int? NextPage,
        bool? HasMore);
}

internal static class WorkItemHistoryContract
{
    public static string GetRoute(WorkItemKind kind)
        => kind switch
        {
            WorkItemKind.issue => "issue",
            WorkItemKind.user_story => "userstory",
            WorkItemKind.task => "task",
            WorkItemKind.epic => "epic",
            _ => throw new ArgumentException("kind must be one of: issue, user_story, task, epic.")
        };
}

internal sealed record WorkItemCommentListPage(
    IReadOnlyList<WorkItemCommentEntryDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);

internal sealed record WorkItemHistoryListPage(
    IReadOnlyList<WorkItemHistoryEntryDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);
