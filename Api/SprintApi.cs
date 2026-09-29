using System.Globalization;
using System.Text.Json;
using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>Sprint (Taiga milestone) operations.</summary>
public sealed class SprintApi
{
    private readonly TaigaTransport _transport;

    public SprintApi(TaigaTransport transport)
    {
        _transport = transport;
    }

    public async Task<IReadOnlyList<SprintDto>> ListSprintsAsync(
        int projectId,
        int page = 1,
        bool? closed = null,
        CancellationToken cancellationToken = default)
        => (await ListSprintsPageAsync(projectId, page, closed, cancellationToken)).Items;

    internal async Task<SprintListPage> ListSprintsPageAsync(
        int projectId,
        int page = 1,
        bool? closed = null,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(page, nameof(page));

        var query = string.Create(
            CultureInfo.InvariantCulture,
            $"milestones?project={Uri.EscapeDataString(projectId.ToString(CultureInfo.InvariantCulture))}&page={Uri.EscapeDataString(page.ToString(CultureInfo.InvariantCulture))}");
        if (closed.HasValue)
            query += $"&closed={(closed.Value ? "true" : "false")}";

        using var request = new HttpRequestMessage(HttpMethod.Get, query);
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;
        if (document.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid sprint list data.");

        var items = new List<SprintDto>(64);
        foreach (var sprint in document.RootElement.EnumerateArray())
        {
            var mapped = MapSprint(sprint);
            if (mapped.Project != projectId)
                throw new TaigaRequestException("Taiga returned sprint data for a different project.");

            items.Add(mapped);
        }

        var pageInfo = TaigaPagination.Parse(response.Headers, response.RequestUri);
        return new SprintListPage(items, page, pageInfo.Total, pageInfo.NextPage, pageInfo.HasMore);
    }

    private static SprintDto MapSprint(JsonElement sprint)
    {
        if (sprint.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid sprint data.");

        return new SprintDto
        {
            Id = ReadRequiredPositiveInt(sprint, "id"),
            Project = ReadRequiredPositiveInt(sprint, "project"),
            Name = ReadRequiredString(sprint, "name", allowBlank: false),
            Slug = ReadRequiredString(sprint, "slug", allowBlank: true),
            EstimatedStart = ReadRequiredIsoDate(sprint, "estimated_start"),
            EstimatedFinish = ReadRequiredIsoDate(sprint, "estimated_finish"),
            Closed = ReadRequiredBoolean(sprint, "closed")
        };
    }

    private static int ReadRequiredPositiveInt(JsonElement sprint, string propertyName)
    {
        if (!sprint.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid sprint {propertyName} data.");

        return number;
    }

    private static string ReadRequiredString(JsonElement sprint, string propertyName, bool allowBlank)
    {
        if (!sprint.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.String ||
            (!allowBlank && string.IsNullOrWhiteSpace(value.GetString())))
            throw new TaigaRequestException($"Taiga returned invalid sprint {propertyName} data.");

        return value.GetString()!;
    }

    private static string ReadRequiredIsoDate(JsonElement sprint, string propertyName)
    {
        var value = ReadRequiredString(sprint, propertyName, allowBlank: false);
        if (!DateOnly.TryParseExact(
                value,
                "yyyy-MM-dd",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out _))
            throw new TaigaRequestException($"Taiga returned invalid sprint {propertyName} data.");

        return value;
    }

    private static bool ReadRequiredBoolean(JsonElement sprint, string propertyName)
    {
        if (!sprint.TryGetProperty(propertyName, out var value) ||
            value.ValueKind is not JsonValueKind.True and not JsonValueKind.False)
            throw new TaigaRequestException($"Taiga returned invalid sprint {propertyName} data.");

        return value.GetBoolean();
    }
}

internal sealed record SprintListPage(
    IReadOnlyList<SprintDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);
