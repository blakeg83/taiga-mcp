using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record UserStoryDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("ref")]
    public int Ref { get; init; }

    [JsonPropertyName("subject")]
    public string? Subject { get; init; }

    [JsonPropertyName("status")]
    public string? Status { get; init; }

    [JsonPropertyName("assigned_to")]
    public int? AssignedTo { get; init; }

    [JsonPropertyName("modified")]
    public string? Modified { get; init; }
}
