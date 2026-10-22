using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record PointOptionDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("name")]
    public string Name { get; init; } = string.Empty;

    [JsonPropertyName("value")]
    [JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public double? Value { get; init; }

    [JsonPropertyName("order")]
    public int Order { get; init; }

    [JsonPropertyName("project")]
    public int? Project { get; init; }
}
