using System.Text.Json.Serialization;

public sealed record IssueDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("ref")]
    public int Ref { get; init; }

    [JsonPropertyName("subject")]
    public string? Subject { get; init; }

    [JsonPropertyName("status")]
    public string? Status { get; init; }

    [JsonPropertyName("severity")]
    public string? Severity { get; init; }

    [JsonPropertyName("type")]
    public string? Type { get; init; }

    [JsonPropertyName("priority")]
    public string? Priority { get; init; }

    [JsonPropertyName("assigned_to")]
    public int? AssignedTo { get; init; }

    [JsonPropertyName("modified")]
    public string? Modified { get; init; }
}

