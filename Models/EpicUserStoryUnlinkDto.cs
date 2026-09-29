using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record EpicUserStoryUnlinkDto
{
    [JsonPropertyName("epic_id")]
    public int EpicId { get; init; }

    [JsonPropertyName("user_story_id")]
    public int UserStoryId { get; init; }

    [JsonPropertyName("removed")]
    public bool Removed { get; init; }
}
