using TaigaMCP.Api;
using ModelContextProtocol.Server;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class IssueTools
{
    private readonly IssueApi _issues;

    public IssueTools(IssueApi issues)
    {
        _issues = issues;
    }

    [McpServerTool(Name = "list_issues")]
    public async Task<string> ListIssues(int projectId, int page = 1, CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () => {
        var issues = await _issues.ListIssuesAsync(projectId, page, cancellationToken);
        return ToolResponseJson.Serialize(issues);
    });

    [McpServerTool(Name = "get_issue")]
    public async Task<string> GetIssue(int issueId, CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () => {
        var issue = await _issues.GetIssueAsync(issueId, cancellationToken);
        var comments = await _issues.GetIssueCommentsAsync(issueId, cancellationToken);
        var result = new { issue, comments };
        return ToolResponseJson.Serialize(result);
    });

    [McpServerTool(Name = "create_issue")]
    public async Task<string> CreateIssue(
        int projectId,
        string subject,
        string? description = null,
        int? status = null, int? type = null, int? priority = null, int? severity = null,
        int? assigned_to = null, string[]? tags = null, CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () => {
        var issue = await _issues.CreateIssueAsync(projectId, subject, description, status, type, priority, severity, assigned_to, tags, cancellationToken);
        return ToolResponseJson.Serialize(issue);
    });

    [McpServerTool(Name = "update_issue")]
    public async Task<string> UpdateIssue(
        int issueId,
        string? subject,
        int version,
        string? description = null,
        int? status = null,
        int? type = null,
        int? priority = null,
        int? severity = null,
        int? assigned_to = null,
        string[]? tags = null,
        string? comment = null, CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () => {
        var issue = await _issues.UpdateIssueAsync(
            issueId,
            version,
            subject,
            description,
            status,
            type,
            priority,
            severity,
            assigned_to,
            tags,
            comment, cancellationToken);
        return ToolResponseJson.Serialize(issue);
    });

    [McpServerTool(Name = "list_issue_statuses")]
    public async Task<string> ListIssueStatuses(int projectId, CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () => {
        var statuses = await _issues.ListIssueStatusesAsync(projectId, cancellationToken);
        return ToolResponseJson.Serialize(statuses);
    });

    [McpServerTool(Name = "list_issue_severities")]
    public async Task<string> ListIssueSeverities(int projectId, CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () => {
        var severities = await _issues.ListIssueSeveritiesAsync(projectId, cancellationToken);
        return ToolResponseJson.Serialize(severities);
    });

    [McpServerTool(Name = "list_issue_types")]
    public async Task<string> ListIssueTypes(int projectId, CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () => {
        var types = await _issues.ListIssueTypesAsync(projectId, cancellationToken);
        return ToolResponseJson.Serialize(types);
    });

    [McpServerTool(Name = "list_issue_priorities")]
    public async Task<string> ListIssuePriorities(int projectId, CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () => {
        var priorities = await _issues.ListIssuePrioritiesAsync(projectId, cancellationToken);
        return ToolResponseJson.Serialize(priorities);
    });
}
