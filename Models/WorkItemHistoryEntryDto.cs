using System.Text.Json;
using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

/// <summary>A visibility-filtered work-item history entry.</summary>
public sealed record WorkItemHistoryEntryDto
{
    [JsonPropertyName("id")]
    public required string Id { get; init; }

    [JsonPropertyName("type")]
    public int Type { get; init; }

    [JsonPropertyName("created_at")]
    public required string CreatedAt { get; init; }

    [JsonPropertyName("user")]
    public WorkItemCommentUserDto? User { get; init; }

    [JsonPropertyName("diff")]
    public JsonElement? Diff { get; init; }

    [JsonPropertyName("values_diff")]
    public JsonElement? ValuesDiff { get; init; }

    [JsonPropertyName("comment")]
    public string? Comment { get; init; }

    [JsonPropertyName("edit_comment_date")]
    public string? EditCommentDate { get; init; }

    [JsonPropertyName("delete_comment_date")]
    public string? DeleteCommentDate { get; init; }

    [JsonPropertyName("delete_comment_user")]
    public WorkItemCommentUserDto? DeleteCommentUser { get; init; }

    [JsonPropertyName("comment_deleted")]
    public bool? CommentDeleted { get; init; }

    [JsonPropertyName("is_snapshot")]
    public bool? IsSnapshot { get; init; }
}
