using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record IssueUpdateDto
{
    [JsonPropertyName("subject")]
    public string? Subject { get; init; }

    [JsonPropertyName("description")]
    public string? Description { get; init; }

    [JsonPropertyName("status")]
    public int? Status { get; init; }

    [JsonPropertyName("type")]
    public int? Type { get; init; }

    [JsonPropertyName("priority")]
    public int? Priority { get; init; }

    [JsonPropertyName("severity")]
    public int? Severity { get; init; }

    [JsonPropertyName("assigned_to")]
    public int? AssignedTo { get; init; }

    [JsonPropertyName("tags")]
    public string[]? Tags { get; init; }

    [JsonPropertyName("comment")]
    public string? Comment { get; init; }

    [JsonPropertyName("version")]
    public required int Version { get; init; }

    internal Dictionary<string, object?> ToPatchPayload(bool clearAssignedTo)
    {
        var payload = new Dictionary<string, object?>(StringComparer.Ordinal);
        if (Subject is not null) payload["subject"] = Subject;
        if (Description is not null) payload["description"] = Description;
        if (Status is not null) payload["status"] = Status;
        if (Type is not null) payload["type"] = Type;
        if (Priority is not null) payload["priority"] = Priority;
        if (Severity is not null) payload["severity"] = Severity;
        if (clearAssignedTo) payload["assigned_to"] = null;
        else if (AssignedTo is not null) payload["assigned_to"] = AssignedTo;
        if (Tags is not null) payload["tags"] = Tags;
        if (Comment is not null) payload["comment"] = Comment;
        payload["version"] = Version;
        return payload;
    }
}
