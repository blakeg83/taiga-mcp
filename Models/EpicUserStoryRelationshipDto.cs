using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record EpicUserStoryRelationshipDto
{
    [JsonPropertyName("epic_id")]
    public int EpicId { get; init; }

    [JsonPropertyName("user_story_id")]
    public int UserStoryId { get; init; }

    [JsonPropertyName("order")]
    public long Order { get; init; }
}
