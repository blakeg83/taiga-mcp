using TaigaMCP.Api;
using ModelContextProtocol.Server;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class UserStoryTools
{
    private readonly UserStoryApi _userStories;

    public UserStoryTools(UserStoryApi userStories)
    {
        _userStories = userStories;
    }

    [McpServerTool(Name = "list_user_stories")]
    public async Task<string> ListUserStories(int projectId, int page = 1)
    {
        var stories = await _userStories.ListUserStoriesAsync(projectId, page);
        return ToolResponseJson.Serialize(stories);
    }
}
