using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record UserStoryCreateDto
{
    [JsonPropertyName("project")]
    public int Project { get; init; }

    [JsonPropertyName("subject")]
    public required string Subject { get; init; }

    [JsonPropertyName("description")]
    public string? Description { get; init; }

    [JsonPropertyName("status")]
    public int? Status { get; init; }

    [JsonPropertyName("assigned_to")]
    public int? AssignedTo { get; init; }

    [JsonPropertyName("tags")]
    public string[]? Tags { get; init; }

    [JsonPropertyName("milestone")]
    public int? Milestone { get; init; }
}
