using System.ComponentModel;
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
    [Description("List one page of project issues. By default only open issues are returned as the legacy array; explicit statusIds or includeClosed=true can retrieve closed issues. Set includePageInfo=true for the page envelope.")]
    public async Task<string> ListIssues(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Page number, starting at 1; requests one page only.")] int page = 1,
        [Description("Optional positive internal issue status IDs. When nonempty, these override the default open-only filter.")] int[]? statusIds = null,
        [Description("Optional positive internal assignee user ID.")] int? assignedTo = null,
        [Description("Optional positive internal issue type ID.")] int? typeId = null,
        [Description("Optional positive internal issue priority ID.")] int? priorityId = null,
        [Description("Optional positive internal issue severity ID.")] int? severityId = null,
        [Description("Optional issue tags; values are sent as Taiga's encoded multi-value filter.")] string[]? tags = null,
        [Description("Optional text query searched by Taiga.")] string? query = null,
        [Description("Include closed issues when true. Explicit nonempty statusIds take precedence.")] bool includeClosed = false,
        [Description("Return an object with items and pagination metadata instead of the legacy array.")] bool includePageInfo = false,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _issues.ListIssuesPageAsync(projectId, new IssueListOptions
        {
            Page = page,
            StatusIds = statusIds,
            AssignedTo = assignedTo,
            TypeId = typeId,
            PriorityId = priorityId,
            SeverityId = severityId,
            Tags = tags,
            Query = query,
            IncludeClosed = includeClosed
        }, cancellationToken);
        return includePageInfo
            ? ToolResponseJson.SerializePage(result.Items, result.Page, result.Total, result.NextPage, result.HasMore)
            : ToolResponseJson.Serialize(result.Items);
    });

    [McpServerTool(Name = "get_issue")]
    [Description("Read an issue by internal ID (not its project ref), including visible nonempty comments.")]
    public async Task<string> GetIssue(
        [Description("Positive internal issue ID, not the project ref.")] int issueId,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var issue = await _issues.GetIssueAsync(issueId, cancellationToken);
        var comments = await _issues.GetIssueCommentsAsync(issueId, cancellationToken);
        var result = new { issue, comments };
        return ToolResponseJson.Serialize(result);
    });

    [McpServerTool(Name = "create_issue")]
    [Description("Create an issue. Omitted or null optional fields leave project defaults; empty description and tags are sent explicitly.")]
    public async Task<string> CreateIssue(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Nonblank subject; null on update leaves unchanged.")] string subject,
        [Description("Description; null leaves default/unchanged, empty string clears.")] string? description = null,
        [Description("Positive internal status ID; null leaves default/unchanged.")] int? status = null,
        [Description("Positive internal issue type ID; null leaves default/unchanged.")] int? type = null,
        [Description("Positive internal priority ID; null leaves default/unchanged.")] int? priority = null,
        [Description("Positive internal severity ID; null leaves default/unchanged.")] int? severity = null,
        [Description("Positive internal user ID; null leaves default/unchanged and does not unassign.")] int? assigned_to = null,
        [Description("Tags; null leaves default/unchanged, empty array clears.")] string[]? tags = null,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var issue = await _issues.CreateIssueAsync(projectId, subject, description, status, type, priority, severity, assigned_to, tags, cancellationToken);
        return ToolResponseJson.Serialize(issue);
    });

    [McpServerTool(Name = "update_issue")]
    [Description("Update an issue by internal ID using the caller-supplied version. Null leaves fields unchanged; empty description or tags clears them. Requires a change or nonblank comment. No automatic version retry.")]
    public async Task<string> UpdateIssue(
        [Description("Positive internal issue ID, not the project ref.")] int issueId,
        [Description("Nonblank subject; null on update leaves unchanged.")] string? subject,
        [Description("Required current entity version, zero or greater; forwarded unchanged.")] int version,
        [Description("Description; null leaves default/unchanged, empty string clears.")] string? description = null,
        [Description("Positive internal status ID; null leaves default/unchanged.")] int? status = null,
        [Description("Positive internal issue type ID; null leaves default/unchanged.")] int? type = null,
        [Description("Positive internal priority ID; null leaves default/unchanged.")] int? priority = null,
        [Description("Positive internal severity ID; null leaves default/unchanged.")] int? severity = null,
        [Description("Positive internal user ID; null leaves default/unchanged and does not unassign.")] int? assigned_to = null,
        [Description("Tags; null leaves default/unchanged, empty array clears.")] string[]? tags = null,
        [Description("Optional comment; a comment-only update requires nonblank text.")] string? comment = null,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
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
            comment, cancellationToken);
        return ToolResponseJson.Serialize(issue);
    });

    [McpServerTool(Name = "list_issue_statuses")]
    [Description("List project issue statuses with internal IDs and closed flags.")]
    public async Task<string> ListIssueStatuses(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var statuses = await _issues.ListIssueStatusesAsync(projectId, cancellationToken);
        return ToolResponseJson.Serialize(statuses);
    });

    [McpServerTool(Name = "list_issue_severities")]
    [Description("List project issue severities with internal IDs.")]
    public async Task<string> ListIssueSeverities(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var severities = await _issues.ListIssueSeveritiesAsync(projectId, cancellationToken);
        return ToolResponseJson.Serialize(severities);
    });

    [McpServerTool(Name = "list_issue_types")]
    [Description("List project issue types with internal IDs.")]
    public async Task<string> ListIssueTypes(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var types = await _issues.ListIssueTypesAsync(projectId, cancellationToken);
        return ToolResponseJson.Serialize(types);
    });

    [McpServerTool(Name = "list_issue_priorities")]
    [Description("List project issue priorities with internal IDs.")]
    public async Task<string> ListIssuePriorities(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var priorities = await _issues.ListIssuePrioritiesAsync(projectId, cancellationToken);
        return ToolResponseJson.Serialize(priorities);
    });
}
