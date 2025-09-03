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
    public async Task<string> UpdateIssue(int issueId, JsonElement patch)
    {
        var issue = await _issues.UpdateIssueAsync(issueId, patch);
        return JsonSerializer.Serialize(issue, JsonOpts);
    }
}
