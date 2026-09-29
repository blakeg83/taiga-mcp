using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record UserStoryStatusDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("project")]
    public int? Project { get; init; }

    [JsonPropertyName("name")]
    public string? Name { get; init; }

    [JsonPropertyName("slug")]
    public string? Slug { get; init; }

    [JsonPropertyName("order")]
    public int? Order { get; init; }

    [JsonPropertyName("color")]
    public string? Color { get; init; }

    [JsonPropertyName("is_closed")]
    public bool? IsClosed { get; init; }

    [JsonPropertyName("is_archived")]
    public bool? IsArchived { get; init; }

    [JsonPropertyName("wip_limit")]
    public int? WipLimit { get; init; }
}
