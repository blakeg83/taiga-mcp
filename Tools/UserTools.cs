using System.ComponentModel;
using ModelContextProtocol.Server;
using TaigaMCP.Api;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class UserTools
{
    private readonly UserApi _users;

    public UserTools(UserApi users)
    {
        _users = users;
    }

    [McpServerTool(Name = "get_current_user")]
    [Description("Get the authenticated Taiga account identity. Returns its numeric id and available username, full name, and active state.")]
    public async Task<string> GetCurrentUser(CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var identity = await _users.GetCurrentUserAsync(cancellationToken);
        return ToolResponseJson.Serialize(identity);
    });
}
