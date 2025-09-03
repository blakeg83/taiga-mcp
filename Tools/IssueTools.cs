using System.Text.Json;
using System.Text.Json.Serialization;
using ModelContextProtocol.Server;

[McpServerToolType]
public sealed class IssueTools
{
    private readonly IssueApi _issues;
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public IssueTools(IssueApi issues)
    {
        _issues = issues;
    }

    [McpServerTool(Name = "list_issues")]
    public async Task<string> ListIssues(int projectId, int page = 1)
    {
        var issues = await _issues.ListIssuesAsync(projectId, page);
        return JsonSerializer.Serialize(issues, JsonOpts);
    }

    [McpServerTool(Name = "get_issue")]
    public async Task<string> GetIssue(int issueId)
    {
        var issue = await _issues.GetIssueAsync(issueId);
        return JsonSerializer.Serialize(issue, JsonOpts);
    }

    [McpServerTool(Name = "create_issue")]
    public async Task<string> CreateIssue(
        int projectId,
        string subject,
        string? description = null,
        int? status = null, int? type = null, int? priority = null, int? severity = null,
        int? assigned_to = null, string[]? tags = null)
    {
        var issue = await _issues.CreateIssueAsync(projectId, subject, description, status, type, priority, severity, assigned_to, tags);
        return JsonSerializer.Serialize(issue, JsonOpts);
    }

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
        string? comment = null)
    {
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
            comment);
        return JsonSerializer.Serialize(issue, JsonOpts);
    }

    [McpServerTool(Name = "list_issue_statuses")]
    public async Task<string> ListIssueStatuses(int projectId)
    {
        var statuses = await _issues.ListIssueStatusesAsync(projectId);
        return JsonSerializer.Serialize(statuses, JsonOpts);
    }

    [McpServerTool(Name = "list_issue_severities")]
    public async Task<string> ListIssueSeverities(int projectId)
    {
        var severities = await _issues.ListIssueSeveritiesAsync(projectId);
        return JsonSerializer.Serialize(severities, JsonOpts);
    }

    [McpServerTool(Name = "list_issue_types")]
    public async Task<string> ListIssueTypes(int projectId)
    {
        var types = await _issues.ListIssueTypesAsync(projectId);
        return JsonSerializer.Serialize(types, JsonOpts);
    }

    [McpServerTool(Name = "list_issue_priorities")]
    public async Task<string> ListIssuePriorities(int projectId)
    {
        var priorities = await _issues.ListIssuePrioritiesAsync(projectId);
        return JsonSerializer.Serialize(priorities, JsonOpts);
    }
}
