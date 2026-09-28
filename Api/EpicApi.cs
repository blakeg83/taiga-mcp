using System.Text.Json;
using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>Epic operations.</summary>
public sealed class EpicApi
{
    private readonly TaigaTransport _transport;

    public EpicApi(TaigaTransport transport)
    {
        _transport = transport;
    }

    public async Task<IReadOnlyList<EpicDto>> ListEpicsAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
        => (await ListEpicsPageAsync(
            projectId,
            new EpicListOptions { Page = page },
            cancellationToken)).Items;

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

    private static string? ReadOptionalString(JsonElement epic, string propertyName)
    {
        if (!epic.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.String)
            throw new TaigaRequestException($"Taiga returned invalid epic {propertyName} data.");

        return value.GetString();
    }
}
