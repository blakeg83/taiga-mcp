using System.Text.Json.Serialization;

public sealed record IssueSeverityDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("name")]
    public string? Name { get; init; }

    [JsonPropertyName("slug")]
    public string? Slug { get; init; }

    [JsonPropertyName("color")]
    public string? Color { get; init; }
}

