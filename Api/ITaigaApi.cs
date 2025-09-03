using System.Text.Json;

/// <summary>Taiga API abstraction.</summary>
public interface ITaigaApi
{
    Task<string> ListProjectsAsync(string? member = null, int page = 1);
    Task<int> ResolveProjectIdAsync(string slug);
    Task<string> ListIssuesAsync(int projectId, int page);
    Task<string> CreateIssueAsync(
        int projectId, string subject, string? description,
        int? status, int? type, int? priority, int? severity,
        int? assigned_to, string[]? tags);
    Task<string> UpdateIssueAsync(int issueId, JsonElement patch);
    Task<string> ListUserStoriesAsync(int projectId, int page = 1);
}
