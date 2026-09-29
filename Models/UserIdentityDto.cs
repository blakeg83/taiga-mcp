using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record UserIdentityDto
{
    [JsonPropertyName("id")]
    public required int Id { get; init; }

    [JsonPropertyName("username")]
    public string? Username { get; init; }

    [JsonPropertyName("full_name")]
    public string? FullName { get; init; }

    [JsonPropertyName("is_active")]
    public bool? IsActive { get; init; }
}
