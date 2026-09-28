using System.Text.Json;
using System.Text.Json.Serialization;
using ModelContextProtocol.Server;

[McpServerToolType]
public sealed class ProjectTools
{
    private readonly ProjectApi _projects;
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public ProjectTools(ProjectApi projects)
    {
        _projects = projects;
    }

    [McpServerTool(Name = "list_projects")]
    public async Task<string> ListProjects(string? member = "6", int page = 1)
    {
        var projects = await _projects.ListProjectsAsync(member, page);
        return JsonSerializer.Serialize(projects, JsonOpts);
    }

    [McpServerTool(Name = "resolve_project")]
    public async Task<string> ResolveProject(string slug)
        => JsonSerializer.Serialize(new { project = await _projects.ResolveProjectIdAsync(slug) });
}
