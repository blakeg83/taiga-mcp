using System.Text.Json;
using ModelContextProtocol.Server;

// ===== MCP tools (DI via constructor; no [FromServices]) =====
[McpServerToolType]
public sealed class TaigaTools
{
    private readonly TaigaApi _api;

    public TaigaTools(TaigaApi api)
    {
        _api = api;
    }

    [McpServerTool(Name = "list_projects")]
    public Task<string> ListProjects(string? member = "me", int page = 1)
    => _api.ListProjectsAsync(member, page);

    [McpServerTool(Name = "resolve_project")]
    public async Task<string> ResolveProject(string slug)
    => JsonSerializer.Serialize(new { project = await _api.ResolveProjectIdAsync(slug) });

    [McpServerTool(Name = "list_issues")]
    public Task<string> ListIssues(int projectId, int page = 1)
        => _api.ListIssuesAsync(projectId, page);

    [McpServerTool(Name = "create_issue")]
    public Task<string> CreateIssue(
        int projectId,
        string subject,
        string? description = null,
        int? status = null, int? type = null, int? priority = null, int? severity = null,
        int? assigned_to = null, string[]? tags = null)
        => _api.CreateIssueAsync(projectId, subject, description, status, type, priority, severity, assigned_to, tags);

    [McpServerTool(Name = "update_issue")]
    public Task<string> UpdateIssue(int issueId, JsonElement patch)
        => _api.UpdateIssueAsync(issueId, patch);

    // In TaigaTools
    [McpServerTool(Name = "list_user_stories")]
    public Task<string> ListUserStories(int projectId, int page = 1)
        => _api.ListUserStoriesAsync(projectId, page);

}
