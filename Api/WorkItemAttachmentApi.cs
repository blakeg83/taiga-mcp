using System.Globalization;
using System.Text.Json;
using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>Read-only attachment operations shared by supported work-item kinds.</summary>
public sealed class WorkItemAttachmentApi
{
    private readonly TaigaTransport _transport;

    public WorkItemAttachmentApi(TaigaTransport transport)
    {
        _transport = transport;
    }

    internal async Task<WorkItemAttachmentListPage> ListPageAsync(
        string kind,
        int id,
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Required(kind, nameof(kind));
        InputValidation.Positive(id, nameof(id));
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(page, nameof(page));

        var route = WorkItemAttachmentRoutes.GetRoute(kind);
        var query = string.Join(
            '&',
            $"object_id={id.ToString(CultureInfo.InvariantCulture)}",
            $"project={projectId.ToString(CultureInfo.InvariantCulture)}",
            $"page={page.ToString(CultureInfo.InvariantCulture)}");
        using var request = new HttpRequestMessage(HttpMethod.Get, $"{route}?{query}");
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;
        if (document.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid work-item attachment list data.");

        var items = new List<WorkItemAttachmentDto>(document.RootElement.GetArrayLength());
        foreach (var attachment in document.RootElement.EnumerateArray())
            items.Add(MapAttachment(attachment));

        var pageInfo = TaigaPagination.Parse(response.Headers, response.RequestUri);
        return new WorkItemAttachmentListPage(
            items,
            page,
            pageInfo.Total,
            pageInfo.NextPage,
            pageInfo.HasMore);
    }

    private static WorkItemAttachmentDto MapAttachment(JsonElement attachment)
    {
        if (attachment.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid work-item attachment data.");

        return new WorkItemAttachmentDto
        {
            Id = ReadRequiredPositiveInt(attachment, "id"),
            Project = ReadRequiredPositiveInt(attachment, "project"),
            ObjectId = ReadRequiredPositiveInt(attachment, "object_id"),
            Owner = ReadOptionalPositiveInt(attachment, "owner"),
            Name = ReadOptionalString(attachment, "name"),
            Description = ReadOptionalString(attachment, "description"),
            Order = ReadOptionalInt(attachment, "order"),
            Size = ReadOptionalInt(attachment, "size"),
            AttachedFile = ReadOptionalString(attachment, "attached_file"),
            Url = ReadOptionalString(attachment, "url"),
            PreviewUrl = ReadOptionalString(attachment, "preview_url"),
            ThumbnailCardUrl = ReadOptionalString(attachment, "thumbnail_card_url"),
            Sha1 = ReadOptionalString(attachment, "sha1"),
            IsDeprecated = ReadOptionalBoolean(attachment, "is_deprecated"),
            FromComment = ReadOptionalBoolean(attachment, "from_comment"),
            CreatedDate = ReadOptionalString(attachment, "created_date"),
            ModifiedDate = ReadOptionalString(attachment, "modified_date")
        };
    }

    private static int ReadRequiredPositiveInt(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid work-item attachment {propertyName} data.");

        return number;
    }

    private static int? ReadOptionalPositiveInt(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid work-item attachment {propertyName} data.");

        return number;
    }

    private static int? ReadOptionalInt(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var number))
            throw new TaigaRequestException($"Taiga returned invalid work-item attachment {propertyName} data.");

        return number;
    }

    private static string? ReadOptionalString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.String)
            throw new TaigaRequestException($"Taiga returned invalid work-item attachment {propertyName} data.");

        return value.GetString();
    }

    private static bool? ReadOptionalBoolean(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind is not JsonValueKind.True and not JsonValueKind.False)
            throw new TaigaRequestException($"Taiga returned invalid work-item attachment {propertyName} data.");

        return value.GetBoolean();
    }
}

internal static class WorkItemAttachmentRoutes
{
    public static string GetRoute(string kind)
        => kind switch
        {
            "epic" => "epics/attachments",
            "user_story" => "userstories/attachments",
            "task" => "tasks/attachments",
            _ => throw new ArgumentException("kind must be one of: epic, user_story, task.", nameof(kind))
        };
}

internal sealed record WorkItemAttachmentListPage(
    IReadOnlyList<WorkItemAttachmentDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);
