using System.Text;
using System.Globalization;
using System.Text.Json;
using Microsoft.Extensions.Options;
using TaigaMCP.Config;
using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>Read-only attachment operations shared by supported work-item kinds.</summary>
public sealed class WorkItemAttachmentApi
{
    private readonly TaigaTransport _transport;
    private readonly IOptions<TaigaOptions> _options;

    public WorkItemAttachmentApi(TaigaTransport transport)
        : this(transport, Options.Create(new TaigaOptions()))
    {
    }

    public WorkItemAttachmentApi(TaigaTransport transport, IOptions<TaigaOptions> options)
    {
        _transport = transport;
        _options = options;
    }

    internal async Task<WorkItemAttachmentDto> UploadAsync(
        string kind,
        int id,
        int projectId,
        string file,
        string? description = null,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Required(kind, nameof(kind));
        InputValidation.Positive(id, nameof(id));
        InputValidation.Positive(projectId, nameof(projectId));

        var route = WorkItemAttachmentRoutes.GetRoute(kind);
        var source = AttachmentFileContract.Validate(file, _options);
        using var content = new AttachmentMultipartContent(
            source,
            id,
            projectId,
            description,
            _options.Value.MaxAttachmentBytes);
        using var request = new HttpRequestMessage(HttpMethod.Post, route) { Content = content };
        using var document = await _transport.ReadAsync(request, cancellationToken);
        try
        {
            var attachment = MapAttachment(document.RootElement);
            if (attachment.Project != projectId || attachment.ObjectId != id)
                throw new TaigaRequestException("Taiga returned an attachment for an unexpected project or work item.");
            return attachment;
        }
        catch (TaigaRequestException exception)
        {
            throw new TaigaRequestException(
                $"{exception.Message.TrimEnd('.')} The upload may already have applied; read the attachment list before retrying.",
                exception.StatusCode);
        }
    }

    internal async Task<WorkItemAttachmentDto> GetAsync(
        string kind,
        int attachmentId,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Required(kind, nameof(kind));
        InputValidation.Positive(attachmentId, nameof(attachmentId));

        var route = WorkItemAttachmentRoutes.GetRoute(kind);
        using var request = new HttpRequestMessage(HttpMethod.Get, $"{route}/{attachmentId}");
        using var document = await _transport.ReadAsync(request, cancellationToken);
        return MapAttachment(document.RootElement, attachmentId);
    }

    internal async Task<WorkItemAttachmentDto> UpdateAsync(
        string kind,
        int attachmentId,
        JsonElement fields,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Required(kind, nameof(kind));
        InputValidation.Positive(attachmentId, nameof(attachmentId));

        var route = WorkItemAttachmentRoutes.GetRoute(kind);
        var payload = WorkItemAttachmentUpdateContract.Parse(fields);
        var json = JsonSerializer.Serialize(payload);
        using var request = new HttpRequestMessage(HttpMethod.Patch, $"{route}/{attachmentId}")
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
        request.Headers.Accept.ParseAdd("application/json");

        using var document = await _transport.ReadAsync(request, cancellationToken);
        try
        {
            return MapAttachment(document.RootElement, attachmentId);
        }
        catch (OperationCanceledException)
        {
            throw new OperationCanceledException(
                "Taiga attachment update may already have applied; response parsing was cancelled. Read the attachment before retrying.",
                cancellationToken);
        }
        catch (TaigaRequestException exception)
        {
            throw new TaigaRequestException(
                $"{exception.Message.TrimEnd('.')} The update may already have applied; read the attachment before retrying.",
                exception.StatusCode);
        }
    }

    internal async Task<WorkItemAttachmentDeleteDto> DeleteAsync(
        string kind,
        int attachmentId,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Required(kind, nameof(kind));
        InputValidation.Positive(attachmentId, nameof(attachmentId));

        var route = WorkItemAttachmentRoutes.GetRoute(kind);
        using var request = new HttpRequestMessage(HttpMethod.Delete, $"{route}/{attachmentId}");
        await _transport.SendNoContentAsync(request, cancellationToken, "attachment");

        return new WorkItemAttachmentDeleteDto
        {
            Kind = kind,
            AttachmentId = attachmentId,
            Deleted = true
        };
    }

    internal async Task<WorkItemAttachmentDownloadDto> DownloadAsync(
        string kind,
        int attachmentId,
        string destination,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Required(kind, nameof(kind));
        InputValidation.Positive(attachmentId, nameof(attachmentId));
        InputValidation.Required(destination, nameof(destination));

        TaigaRequestException? mediaFailure = null;
        Uri? rejectedSource = null;
        while (true)
        {
            WorkItemAttachmentDto attachment;
            try
            {
                attachment = await GetAsync(kind, attachmentId, cancellationToken);
            }
            catch (TaigaRequestException exception)
            {
                throw new TaigaRequestException($"Taiga attachment metadata request failed. {exception.Message}", exception.StatusCode);
            }

            if (attachment.Size is > 0 && attachment.Size.Value > _options.Value.MaxAttachmentBytes)
                throw new TaigaRequestException($"attachment exceeds the configured maximum size of {_options.Value.MaxAttachmentBytes} bytes.");

            var plan = AttachmentDownloadContract.CreatePlan(attachment, destination, _options);
            // A media 403 is not an API authentication failure. Refresh metadata
            // once, and retry only if Taiga supplies a different download URL.
            // Compare the complete URL, including its signed query and fragment.
            if (mediaFailure is not null && plan.SourceUri.AbsoluteUri == rejectedSource!.AbsoluteUri)
                throw mediaFailure;

            try
            {
                var result = await _transport.DownloadAsync(plan, cancellationToken);
                return new WorkItemAttachmentDownloadDto
                {
                    Destination = result.DestinationPath,
                    Bytes = result.BytesWritten,
                    Attachment = attachment
                };
            }
            catch (TaigaRequestException exception) when (
                exception.StatusCode == System.Net.HttpStatusCode.Forbidden && mediaFailure is null)
            {
                mediaFailure = exception;
                rejectedSource = plan.SourceUri;
            }
        }
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

    private static WorkItemAttachmentDto MapAttachment(JsonElement attachment, int? expectedId = null)
    {
        if (attachment.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid work-item attachment data.");

        var id = ReadRequiredPositiveInt(attachment, "id");
        if (expectedId.HasValue && id != expectedId.Value)
            throw new TaigaRequestException("Taiga returned a work-item attachment with an unexpected id.");

        return new WorkItemAttachmentDto
        {
            Id = id,
            Project = ReadRequiredPositiveInt(attachment, "project"),
            ObjectId = ReadRequiredPositiveInt(attachment, "object_id"),
            Owner = ReadOptionalPositiveInt(attachment, "owner"),
            Name = ReadOptionalString(attachment, "name"),
            Description = ReadOptionalString(attachment, "description"),
            Order = ReadOptionalInt(attachment, "order"),
            Size = ReadOptionalNonnegativeInt(attachment, "size"),
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

    private static int? ReadOptionalNonnegativeInt(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number < 0)
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
            "issue" => "issues/attachments",
            _ => throw new ArgumentException("kind must be one of: epic, user_story, task, issue.", nameof(kind))
        };
}

internal sealed record WorkItemAttachmentListPage(
    IReadOnlyList<WorkItemAttachmentDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);
