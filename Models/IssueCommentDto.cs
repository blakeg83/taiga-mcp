using System.Text.Json.Serialization;

public sealed record IssueCommentDto
{
    [JsonPropertyName("id")]
    public string? Id { get; init; }

    [JsonPropertyName("comment")]
    public string? Comment { get; init; }

    [JsonPropertyName("created_at")]
    public string? CreatedAt { get; init; }

    [JsonPropertyName("user")]
    public IssueCommentUserDto? User { get; init; }
}

public sealed record IssueCommentUserDto
{
    [JsonPropertyName("name")]
    public string? Name { get; init; }
}
