using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

/// <summary>One native role-to-point-option assignment for a user story.</summary>
public sealed record UserStoryEstimateEntry
{
    [JsonPropertyName("roleId")]
    public int RoleId { get; init; }

    [JsonPropertyName("pointId")]
    public int PointId { get; init; }
}
