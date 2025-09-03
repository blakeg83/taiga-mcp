using System.Text.Json.Serialization;

public sealed record IssueStatusDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("name")]
    public string? Name { get; init; }

    [JsonPropertyName("slug")]
    public string? Slug { get; init; }

    [JsonPropertyName("is_closed")]
    public bool IsClosed { get; init; }
}

