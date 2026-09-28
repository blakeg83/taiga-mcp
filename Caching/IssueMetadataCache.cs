using TaigaMCP.Api;
using System.Text.Json;

namespace TaigaMCP.Caching;

/// <summary>
/// Caches issue metadata such as statuses, severities, types and priorities per project.
/// </summary>
public sealed class IssueMetadataCache
{
    private readonly HttpClient _http;
    private readonly AuthClient _auth;
    private readonly Dictionary<int, Dictionary<int, string>> _statusCache = new();
    private readonly Dictionary<int, Dictionary<int, string>> _severityCache = new();
    private readonly Dictionary<int, Dictionary<int, string>> _typeCache = new();
    private readonly Dictionary<int, Dictionary<int, string>> _priorityCache = new();

    public IssueMetadataCache(HttpClient http, AuthClient auth)
    {
        _http = http;
        _auth = auth;
    }

    private async Task<Dictionary<int, string>> GetMapAsync(string path, int projectId, Dictionary<int, Dictionary<int, string>> cache)
    {
        if (cache.TryGetValue(projectId, out var m)) return m;

        using var req = new HttpRequestMessage(HttpMethod.Get, $"{path}?project={projectId}");
        var res = await _auth.SendAsync(_http, req);
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
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

    public Task<Dictionary<int, string>> GetStatusesAsync(int projectId)
        => GetMapAsync("issue-statuses", projectId, _statusCache);

    public Task<Dictionary<int, string>> GetSeveritiesAsync(int projectId)
        => GetMapAsync("severities", projectId, _severityCache);

    public Task<Dictionary<int, string>> GetTypesAsync(int projectId)
        => GetMapAsync("issue-types", projectId, _typeCache);

    public Task<Dictionary<int, string>> GetPrioritiesAsync(int projectId)
        => GetMapAsync("priorities", projectId, _priorityCache);
}
