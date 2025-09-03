using System.Text.Json;
using Microsoft.Extensions.Options;

/// <summary>Main Taiga API delegating to domain APIs.</summary>
public sealed class TaigaApi : ITaigaApi
{
    private readonly ProjectApi _projects;
    private readonly IssueApi _issues;
    private readonly UserStoryApi _userStories;
    private readonly TaigaOptions _cfg;

    public TaigaApi(ProjectApi projects, IssueApi issues, UserStoryApi userStories, IOptions<TaigaOptions> opts)
    {
        _projects = projects;
        _issues = issues;
        _userStories = userStories;
        _cfg = opts.Value;
    }

    public Task<string> ListProjectsAsync(string? member = null, int page = 1)
        => _projects.ListProjectsAsync(member, page);

    public Task<int> ResolveProjectIdAsync(string slug)
        => _projects.ResolveProjectIdAsync(slug);

    public Task<string> ListIssuesAsync(int projectId, int page)
        => _issues.ListIssuesAsync(projectId, page);

    public Task<string> CreateIssueAsync(
        int projectId, string subject, string? description,
        int? status, int? type, int? priority, int? severity,
        int? assigned_to, string[]? tags)
        => _issues.CreateIssueAsync(projectId, subject, description, status, type, priority, severity, assigned_to, tags);

    public Task<string> UpdateIssueAsync(int issueId, JsonElement patch)
        => _issues.UpdateIssueAsync(issueId, patch);

    public Task<string> ListUserStoriesAsync(int projectId, int page = 1)
        => _userStories.ListUserStoriesAsync(projectId, page);
}
