using System.ComponentModel;
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
    [Description("List one page of open, non-archived user stories by internal project ID. Returns an array without pagination metadata.")]
    public async Task<string> ListUserStories([Description("Positive internal project ID, not a slug.")] int projectId, [Description("Page number, starting at 1; requests one page only.")] int page = 1, CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () => {
        var stories = await _userStories.ListUserStoriesAsync(projectId, page, cancellationToken);
        return ToolResponseJson.Serialize(stories);
    });
}
