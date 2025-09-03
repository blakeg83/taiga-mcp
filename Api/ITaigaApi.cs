using System.Text.Json;

/// <summary>Taiga API abstraction.</summary>
public interface ITaigaApi
{
    Task<IReadOnlyList<ProjectDto>> ListProjectsAsync(string? member = null, int page = 1);
    Task<int> ResolveProjectIdAsync(string slug);
    Task<IReadOnlyList<IssueDto>> ListIssuesAsync(int projectId, int page);
    Task<bool> CreateIssueAsync(
        int projectId, string subject, string? description,
        int? status, int? type, int? priority, int? severity,
        int? assigned_to, string[]? tags);
    Task<IssueDto> UpdateIssueAsync(int issueId, JsonElement patch);
    Task<IReadOnlyList<IssueStatusDto>> ListIssueStatusesAsync(int projectId);
    Task<IReadOnlyList<UserStoryDto>> ListUserStoriesAsync(int projectId, int page = 1);
}
