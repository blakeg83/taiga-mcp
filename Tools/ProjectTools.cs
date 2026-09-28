using TaigaMCP.Api;
using ModelContextProtocol.Server;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class ProjectTools
{
    private readonly ProjectApi _projects;

    public ProjectTools(ProjectApi projects)
    {
        _projects = projects;
    }

    [McpServerTool(Name = "list_projects")]
    public async Task<string> ListProjects(string? member = "6", int page = 1)
    {
        var projects = await _projects.ListProjectsAsync(member, page);
        return ToolResponseJson.Serialize(projects);
    }

    [McpServerTool(Name = "resolve_project")]
    public async Task<string> ResolveProject(string slug)
        => ToolResponseJson.Serialize(new { project = await _projects.ResolveProjectIdAsync(slug) });
}
