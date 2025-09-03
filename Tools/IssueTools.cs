using System.Text.Json;
using ModelContextProtocol.Server;

[McpServerToolType]
public sealed class IssueTools
{
    private readonly IssueApi _issues;

    public IssueTools(IssueApi issues)
    {
        _issues = issues;
    }

    [McpServerTool(Name = "list_issues")]
    public Task<string> ListIssues(int projectId, int page = 1)
        => _issues.ListIssuesAsync(projectId, page);

    [McpServerTool(Name = "create_issue")]
    public Task<string> CreateIssue(
        int projectId,
        string subject,
        string? description = null,
        int? status = null, int? type = null, int? priority = null, int? severity = null,
        int? assigned_to = null, string[]? tags = null)
        => _issues.CreateIssueAsync(projectId, subject, description, status, type, priority, severity, assigned_to, tags);

    [McpServerTool(Name = "update_issue")]
    public Task<string> UpdateIssue(int issueId, JsonElement patch)
        => _issues.UpdateIssueAsync(issueId, patch);
}
