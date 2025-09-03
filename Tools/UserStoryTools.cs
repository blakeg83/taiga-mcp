using ModelContextProtocol.Server;

[McpServerToolType]
public sealed class UserStoryTools
{
    private readonly UserStoryApi _userStories;

    public UserStoryTools(UserStoryApi userStories)
    {
        _userStories = userStories;
    }

    [McpServerTool(Name = "list_user_stories")]
    public Task<string> ListUserStories(int projectId, int page = 1)
        => _userStories.ListUserStoriesAsync(projectId, page);
}
