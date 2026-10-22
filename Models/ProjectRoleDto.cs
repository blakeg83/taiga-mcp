using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record ProjectRoleDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("name")]
    public string Name { get; init; } = string.Empty;

    [JsonPropertyName("computable")]
    public bool Computable { get; init; }
}
