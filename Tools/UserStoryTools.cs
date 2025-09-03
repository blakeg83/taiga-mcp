using System.Text.Json;
using System.Text.Json.Serialization;
using ModelContextProtocol.Server;

[McpServerToolType]
public sealed class UserStoryTools
{
    private readonly UserStoryApi _userStories;
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public UserStoryTools(UserStoryApi userStories)
    {
        _userStories = userStories;
    }

    [McpServerTool(Name = "list_user_stories")]
    public async Task<string> ListUserStories(int projectId, int page = 1)
    {
        var stories = await _userStories.ListUserStoriesAsync(projectId, page);
        return JsonSerializer.Serialize(stories, JsonOpts);
    }
}
