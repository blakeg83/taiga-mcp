using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

/// <summary>Supported Taiga resources for the shared comment command.</summary>
public enum WorkItemKind
{
    issue,
    user_story,
    task,
    epic
}

/// <summary>Receipt returned after Taiga confirms a comment-only update.</summary>
public sealed record WorkItemCommentReceipt
{
    [JsonPropertyName("kind")]
    public required string Kind { get; init; }

    [JsonPropertyName("id")]
    public required int Id { get; init; }

    [JsonPropertyName("version")]
    public required int Version { get; init; }

    [JsonPropertyName("comment_submitted")]
    public required bool CommentSubmitted { get; init; }
}
