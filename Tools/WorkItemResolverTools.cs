using System.ComponentModel;
using ModelContextProtocol.Server;
using TaigaMCP.Api;
using TaigaMCP.Models;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class WorkItemResolverTools
{
    private readonly WorkItemResolverApi _resolver;

    public WorkItemResolverTools(WorkItemResolverApi resolver)
    {
        _resolver = resolver;
    }

    [McpServerTool(Name = "resolve_work_item")]
    [Description("Resolve one displayed project-local #ref for a known issue, user story, task, or epic kind. Returns only the matching kind, internal ID, ref, project, and available subject/version; use the returned ID with the existing get_* tool before a versioned edit. The ref is numeric without a leading #, and this does not search other projects or guess the kind.")]
    public async Task<string> ResolveWorkItem(
        [Description("Positive internal project ID, not a slug.")] int projectId,
        [Description("Work-item kind: issue, user_story, task, or epic.")] WorkItemKind kind,
        [Description("Positive displayed project-local reference number, without a leading #; this is not the internal ID.")] int @ref,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var result = await _resolver.ResolveAsync(projectId, kind, @ref, cancellationToken);
        return ToolResponseJson.Serialize(result);
    });
}
