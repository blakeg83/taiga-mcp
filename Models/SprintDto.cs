using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record SprintDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("project")]
    public int Project { get; init; }

    [JsonPropertyName("name")]
    public string Name { get; init; } = string.Empty;

    [JsonPropertyName("slug")]
    public string Slug { get; init; } = string.Empty;

    [JsonPropertyName("estimated_start")]
    public string EstimatedStart { get; init; } = string.Empty;

    [JsonPropertyName("estimated_finish")]
    public string EstimatedFinish { get; init; } = string.Empty;

    [JsonPropertyName("closed")]
    public bool Closed { get; init; }
}
