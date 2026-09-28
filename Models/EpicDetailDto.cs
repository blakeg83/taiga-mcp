using System.Text.Json;
using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record EpicDetailDto
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

    [JsonPropertyName("color")]
    public string? Color { get; init; }

    [JsonPropertyName("tags")]
    public IReadOnlyList<JsonElement>? Tags { get; init; }

    [JsonPropertyName("modified")]
    public string? Modified { get; init; }

    [JsonPropertyName("is_closed")]
    public bool? IsClosed { get; init; }

    [JsonPropertyName("is_blocked")]
    public bool? IsBlocked { get; init; }

    [JsonPropertyName("blocked_note")]
    public string? BlockedNote { get; init; }

    [JsonPropertyName("client_requirement")]
    public bool? ClientRequirement { get; init; }

    [JsonPropertyName("team_requirement")]
    public bool? TeamRequirement { get; init; }

    [JsonPropertyName("user_stories_counts")]
    public JsonElement? UserStoriesCounts { get; init; }

    [JsonPropertyName("version")]
    public int Version { get; init; }
}
