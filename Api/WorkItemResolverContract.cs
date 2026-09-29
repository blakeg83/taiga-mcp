using System.Text.Json;
using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>Closed route and response contract for project-local work-item references.</summary>
internal static class WorkItemResolverContract
{
    public static string GetRoute(WorkItemKind kind)
        => kind switch
        {
            WorkItemKind.issue => "issues",
            WorkItemKind.user_story => "userstories",
            WorkItemKind.task => "tasks",
            WorkItemKind.epic => "epics",
            _ => throw new ArgumentException("kind must be one of: issue, user_story, task, epic.")
        };

    public static ResolvedWorkItemDto MapResponse(
        JsonElement response,
        WorkItemKind kind,
        int requestedProject,
        int requestedRef)
    {
        if (response.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid work-item reference data.");

        var id = ReadRequiredPositiveInt(response, "id");
        var project = ReadRequiredPositiveInt(response, "project");
        var reference = ReadRequiredPositiveInt(response, "ref");
        if (project != requestedProject)
            throw new TaigaRequestException("Taiga returned a work item from a different project.");
        if (reference != requestedRef)
            throw new TaigaRequestException("Taiga returned a work item with a different reference.");

        return new ResolvedWorkItemDto
        {
            Kind = kind.ToString(),
            Id = id,
            Ref = reference,
            Project = project,
            Subject = ReadOptionalString(response, "subject"),
            Version = ReadOptionalNonnegativeInt(response, "version")
        };
    }

    private static int ReadRequiredPositiveInt(JsonElement response, string propertyName)
    {
        if (!response.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid work-item {propertyName} data.");

        return number;
    }

    private static int? ReadOptionalNonnegativeInt(JsonElement response, string propertyName)
    {
        if (!response.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number < 0)
            throw new TaigaRequestException($"Taiga returned invalid work-item {propertyName} data.");

        return number;
    }

    private static string? ReadOptionalString(JsonElement response, string propertyName)
    {
        if (!response.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.String)
            throw new TaigaRequestException($"Taiga returned invalid work-item {propertyName} data.");

        return value.GetString();
    }
}
