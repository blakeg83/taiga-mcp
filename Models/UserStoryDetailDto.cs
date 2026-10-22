using System.Text.Json;
using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record UserStoryDetailDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("ref")]
    public int? Ref { get; init; }

    [JsonPropertyName("project")]
    public int? Project { get; init; }

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

    [JsonPropertyName("tags")]
    public IReadOnlyList<JsonElement>? Tags { get; init; }

    [JsonPropertyName("milestone")]
    public int? Milestone { get; init; }

    [JsonPropertyName("modified")]
    public string? Modified { get; init; }

    [JsonPropertyName("version")]
    public int Version { get; init; }

    [JsonPropertyName("points")]
    public IReadOnlyDictionary<int, int>? Points { get; init; }

    [JsonPropertyName("total_points")]
    public double? TotalPoints { get; init; }

    [JsonPropertyName("origin_issue")]
    public JsonElement? OriginIssue { get; init; }

    [JsonPropertyName("origin_task")]
    public JsonElement? OriginTask { get; init; }

    [JsonPropertyName("epics")]
    public JsonElement? Epics { get; init; }
}
