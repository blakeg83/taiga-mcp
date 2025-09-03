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

    public Task<IReadOnlyList<ProjectDto>> ListProjectsAsync(string? member = null, int page = 1)
        => _projects.ListProjectsAsync(member, page);

    public Task<int> ResolveProjectIdAsync(string slug)
        => _projects.ResolveProjectIdAsync(slug);

    public Task<IReadOnlyList<IssueDto>> ListIssuesAsync(int projectId, int page)
        => _issues.ListIssuesAsync(projectId, page);

    public Task<IssueDto> CreateIssueAsync(
        int projectId, string subject, string? description,
        int? status, int? type, int? priority, int? severity,
        int? assigned_to, string[]? tags)
        => _issues.CreateIssueAsync(projectId, subject, description, status, type, priority, severity, assigned_to, tags);

    public Task<IssueDto> UpdateIssueAsync(
        int issueId,
        string? subject,
        int version,
        string? description,
        int? status,
        int? type,
        int? priority,
        int? severity,
        int? assigned_to,
        string[]? tags,
        string? comment)
        => _issues.UpdateIssueAsync(issueId, version, subject, description, status, type, priority, severity, assigned_to, tags, comment);

    public Task<IReadOnlyList<IssueStatusDto>> ListIssueStatusesAsync(int projectId)
        => _issues.ListIssueStatusesAsync(projectId);

    public Task<IReadOnlyList<UserStoryDto>> ListUserStoriesAsync(int projectId, int page = 1)
        => _userStories.ListUserStoriesAsync(projectId, page);
}
