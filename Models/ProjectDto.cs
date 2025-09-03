using System.Text.Json.Serialization;

public sealed record ProjectDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("slug")]
    public string? Slug { get; init; }

    [JsonPropertyName("name")]
    public string? Name { get; init; }
}

