using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

/// <summary>A visible comment stored as a work-item history entry.</summary>
public sealed record WorkItemCommentEntryDto
{
    [JsonPropertyName("id")]
    public required string Id { get; init; }

    [JsonPropertyName("comment")]
    public required string Comment { get; init; }

    [JsonPropertyName("created_at")]
    public required string CreatedAt { get; init; }

    [JsonPropertyName("user")]
    public WorkItemCommentUserDto? User { get; init; }

    [JsonPropertyName("edit_comment_date")]
    public string? EditCommentDate { get; init; }
}

/// <summary>Safe actor identity returned with a visible work-item comment.</summary>
public sealed record WorkItemCommentUserDto
{
    [JsonPropertyName("id")]
    public int? Id { get; init; }

    [JsonPropertyName("name")]
    public string? Name { get; init; }

    [JsonPropertyName("username")]
    public string? Username { get; init; }

    [JsonPropertyName("is_active")]
    public bool? IsActive { get; init; }
}
