using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

/// <summary>Small identity receipt returned by a project-local work-item lookup.</summary>
public sealed record ResolvedWorkItemDto
{
    [JsonPropertyName("kind")]
    public required string Kind { get; init; }

    [JsonPropertyName("id")]
    public required int Id { get; init; }

    [JsonPropertyName("ref")]
    public required int Ref { get; init; }

    [JsonPropertyName("project")]
    public required int Project { get; init; }

    [JsonPropertyName("subject")]
    public string? Subject { get; init; }

    [JsonPropertyName("version")]
    public int? Version { get; init; }
}
