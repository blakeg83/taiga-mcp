using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>Resolves project-local displayed references to internal work-item identities.</summary>
public sealed class WorkItemResolverApi
{
    private readonly TaigaTransport _transport;

    public WorkItemResolverApi(TaigaTransport transport)
    {
        _transport = transport;
    }

    public async Task<ResolvedWorkItemDto> ResolveAsync(
        int projectId,
        WorkItemKind kind,
        int reference,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(reference, nameof(reference));
        var route = WorkItemResolverContract.GetRoute(kind);

        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"{route}/by_ref?project={projectId}&ref={reference}");
        using var document = await _transport.ReadAsync(request, cancellationToken);
        return WorkItemResolverContract.MapResponse(document.RootElement, kind, projectId, reference);
    }
}
