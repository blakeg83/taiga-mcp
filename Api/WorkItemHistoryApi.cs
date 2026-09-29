using System.Globalization;
using System.Text.Json;
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

    private static ParsedCommentResponse ParseResponse(
        JsonElement root,
        IReadOnlyDictionary<string, string[]> headers,
        Uri requestUri)
    {
        JsonElement entries;
        BodyPageInfo bodyInfo = default;
        if (root.ValueKind == JsonValueKind.Array)
        {
            entries = root;
        }
        else if (root.ValueKind == JsonValueKind.Object &&
                 root.TryGetProperty("results", out var results) &&
                 results.ValueKind == JsonValueKind.Array)
        {
            entries = results;
            bodyInfo = ParseBodyPageInfo(root, requestUri);
        }
        else
        {
            throw new TaigaRequestException("Taiga returned invalid work-item comment history data.");
        }

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
            HasHeader(headers, "x-pagination-next") || HasHeader(headers, "x-paginated"),
            headerValue,
            bodyInfo.HasNext,
            bodyInfo.NextIsValid,
            bodyInfo.HasMore);

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

    private static string ReadRequiredNonblankString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(value.GetString()))
            throw new TaigaRequestException($"Taiga returned invalid work-item comment {propertyName} data.");

        return value.GetString()!;
    }

    private static string? ReadOptionalString(JsonElement element, string propertyName)
        => element.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
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
