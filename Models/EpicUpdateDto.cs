using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record EpicUpdateDto
{
    [JsonPropertyName("subject")]
    public string? Subject { get; init; }

    [JsonPropertyName("description")]
    public string? Description { get; init; }

    [JsonPropertyName("status")]
    public int? Status { get; init; }

    [JsonPropertyName("assigned_to")]
    public int? AssignedTo { get; init; }

    [JsonPropertyName("color")]
    public string? Color { get; init; }

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
        if (clearAssignedTo) payload["assigned_to"] = null;
        else if (AssignedTo is not null) payload["assigned_to"] = AssignedTo;
        if (Color is not null) payload["color"] = Color;
        if (Tags is not null) payload["tags"] = Tags;
        if (Comment is not null) payload["comment"] = Comment;
        payload["version"] = Version;
        return payload;
    }
}
