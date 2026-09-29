using System.ComponentModel;
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
    [Description("List one page of projects; member is an optional member ID filter (default null means no member filter). Returns an array without pagination metadata.")]
    public async Task<string> ListProjects(
        [Description("Member ID filter; null or empty means no filter.")] string? member = null,
        [Description("Page number, starting at 1; requests one page only.")] int page = 1,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var projects = await _projects.ListProjectsAsync(member, page, cancellationToken);
        return ToolResponseJson.Serialize(projects);
    });

    [McpServerTool(Name = "list_project_members")]
    [Description("List one page of project membership records. membership_id identifies the membership record; user_id identifies the Taiga account to use for a later assigned_to value. Pending records without user_id and inactive users remain visible, but membership alone does not guarantee permission for a future write. Email and invitation text are not returned.")]
    public async Task<string> ListProjectMembers(
        [Description("Positive internal project ID.")] int projectId,
        [Description("Page number, starting at 1; requests one page only.")] int page = 1,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _projects.ListProjectMembersPageAsync(projectId, page, cancellationToken);
        return ToolResponseJson.SerializePage(
            result.Items,
            result.Page,
            result.Total,
            result.NextPage,
            result.HasMore);
    });

    [McpServerTool(Name = "resolve_project")]
    [Description("Resolve an exact project slug to its internal project ID.")]
    public async Task<string> ResolveProject(
        [Description("Nonblank exact project slug.")] string slug,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        return ToolResponseJson.Serialize(new { project = await _projects.ResolveProjectIdAsync(slug, cancellationToken) });
    });
}
