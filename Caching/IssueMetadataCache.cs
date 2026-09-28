using TaigaMCP.Api;
using System.Text.Json;

namespace TaigaMCP.Caching;

/// <summary>
/// Caches issue metadata such as statuses, severities, types and priorities per project.
/// </summary>
public sealed class IssueMetadataCache
{
    private readonly TaigaTransport _transport;
    private readonly Dictionary<int, Dictionary<int, string>> _statusCache = new();
    private readonly Dictionary<int, Dictionary<int, string>> _severityCache = new();
    private readonly Dictionary<int, Dictionary<int, string>> _typeCache = new();
    private readonly Dictionary<int, Dictionary<int, string>> _priorityCache = new();

    public IssueMetadataCache(TaigaTransport transport)
    {
        _transport = transport;
    }

    private async Task<Dictionary<int, string>> GetMapAsync(string path, int projectId, Dictionary<int, Dictionary<int, string>> cache, CancellationToken cancellationToken)
    {
        if (cache.TryGetValue(projectId, out var m)) return m;

        using var req = new HttpRequestMessage(HttpMethod.Get, $"{path}?project={projectId}");
        using var doc = await _transport.ReadAsync(req, cancellationToken);
        var map = new Dictionary<int, string>(32);
        foreach (var el in doc.RootElement.EnumerateArray())
        {
            if (!el.TryGetProperty("id", out var idProp) || !el.TryGetProperty("name", out var nameProp)) continue;
            if (idProp.TryGetInt32(out var id) && nameProp.GetString() is { } name)
                map[id] = name;
        }
        cache[projectId] = map;
        return map;
    }

    public Task<Dictionary<int, string>> GetStatusesAsync(int projectId, CancellationToken cancellationToken = default)
        => GetMapAsync("issue-statuses", projectId, _statusCache, cancellationToken);

    public Task<Dictionary<int, string>> GetSeveritiesAsync(int projectId, CancellationToken cancellationToken = default)
        => GetMapAsync("severities", projectId, _severityCache, cancellationToken);

    public Task<Dictionary<int, string>> GetTypesAsync(int projectId, CancellationToken cancellationToken = default)
        => GetMapAsync("issue-types", projectId, _typeCache, cancellationToken);

    public Task<Dictionary<int, string>> GetPrioritiesAsync(int projectId, CancellationToken cancellationToken = default)
        => GetMapAsync("priorities", projectId, _priorityCache, cancellationToken);
}
