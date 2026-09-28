using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record IssueUpdateDto
{
    [JsonPropertyName("subject")]
    public string? Subject { get; init; }

    [JsonPropertyName("description")]
    public string? Description { get; init; }

    [JsonPropertyName("status")]
    public int? Status { get; init; }

    [JsonPropertyName("type")]
    public int? Type { get; init; }

    [JsonPropertyName("priority")]
    public int? Priority { get; init; }

    [JsonPropertyName("severity")]
    public int? Severity { get; init; }

    [JsonPropertyName("assigned_to")]
    public int? AssignedTo { get; init; }

    [JsonPropertyName("tags")]
    public string[]? Tags { get; init; }

    [JsonPropertyName("comment")]
    public string? Comment { get; init; }

    [JsonPropertyName("version")]
    public required int Version { get; init; }
}
