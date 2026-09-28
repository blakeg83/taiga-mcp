using System.Text.Json;
using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record TaskDetailDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("ref")]
    public int Ref { get; init; }

    [JsonPropertyName("project")]
    public int Project { get; init; }

    [JsonPropertyName("subject")]
    public string? Subject { get; init; }

    [JsonPropertyName("description")]
    public string? Description { get; init; }

    [JsonPropertyName("status_id")]
    public int? StatusId { get; init; }

    [JsonPropertyName("status")]
    public string? Status { get; init; }

    [JsonPropertyName("assigned_to")]
    public int? AssignedTo { get; init; }

    [JsonPropertyName("user_story")]
    public int? UserStory { get; init; }

    [JsonPropertyName("milestone")]
    public int? Milestone { get; init; }

    [JsonPropertyName("tags")]
    public IReadOnlyList<JsonElement>? Tags { get; init; }

    [JsonPropertyName("modified")]
    public string? Modified { get; init; }

    [JsonPropertyName("due_date")]
    public string? DueDate { get; init; }

    [JsonPropertyName("due_date_reason")]
    public string? DueDateReason { get; init; }

    [JsonPropertyName("due_date_status")]
    public string? DueDateStatus { get; init; }

    [JsonPropertyName("is_blocked")]
    public bool? IsBlocked { get; init; }

    [JsonPropertyName("blocked_note")]
    public string? BlockedNote { get; init; }

    [JsonPropertyName("is_closed")]
    public bool? IsClosed { get; init; }

    [JsonPropertyName("version")]
    public int Version { get; init; }
}
