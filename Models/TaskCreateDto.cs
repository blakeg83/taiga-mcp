using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record TaskCreateDto
{
    [JsonPropertyName("project")]
    public int Project { get; init; }

    [JsonPropertyName("subject")]
    public string Subject { get; init; } = string.Empty;

    [JsonPropertyName("description")]
    public string? Description { get; init; }

    [JsonPropertyName("status")]
    public int? Status { get; init; }

    [JsonPropertyName("assigned_to")]
    public int? AssignedTo { get; init; }

    [JsonPropertyName("tags")]
    public string[]? Tags { get; init; }

    [JsonPropertyName("user_story")]
    public int? UserStory { get; init; }

    [JsonPropertyName("milestone")]
    public int? Milestone { get; init; }
}
