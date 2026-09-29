using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record ProjectMemberDto
{
    [JsonPropertyName("membership_id")]
    public required int MembershipId { get; init; }

    [JsonPropertyName("project")]
    public required int Project { get; init; }

    [JsonPropertyName("user_id")]
    public int? UserId { get; init; }

    [JsonPropertyName("role_id")]
    public int? RoleId { get; init; }

    [JsonPropertyName("role_name")]
    public string? RoleName { get; init; }

    [JsonPropertyName("full_name")]
    public string? FullName { get; init; }

    [JsonPropertyName("is_user_active")]
    public bool? IsUserActive { get; init; }

    [JsonPropertyName("is_admin")]
    public bool? IsAdmin { get; init; }

    [JsonPropertyName("is_owner")]
    public bool? IsOwner { get; init; }
}
