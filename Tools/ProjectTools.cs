using System.Text.Json;
using ModelContextProtocol.Server;

[McpServerToolType]
public sealed class ProjectTools
{
    private readonly ProjectApi _projects;

    public ProjectTools(ProjectApi projects)
    {
        _projects = projects;
    }

    [McpServerTool(Name = "list_projects")]
    public Task<string> ListProjects(string? member = "me", int page = 1)
        => _projects.ListProjectsAsync(member, page);

    [McpServerTool(Name = "resolve_project")]
    public async Task<string> ResolveProject(string slug)
        => JsonSerializer.Serialize(new { project = await _projects.ResolveProjectIdAsync(slug) });
}
