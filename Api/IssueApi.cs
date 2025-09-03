using System.Text;
using System.Text.Json;

/// <summary>Issue operations.</summary>
public sealed class IssueApi
{
    private readonly HttpClient _http;
    private readonly AuthClient _auth;
    private readonly Dictionary<int, Dictionary<int, string>> _statusCache = new();
    private readonly Dictionary<int, Dictionary<int, string>> _severityCache = new();
    private readonly Dictionary<int, Dictionary<int, string>> _typeCache = new();
    private readonly Dictionary<int, Dictionary<int, string>> _priorityCache = new();

    public IssueApi(HttpClient http, AuthClient auth)
    {
        _http = http;
        _auth = auth;
    }

    private async Task<Dictionary<int, string>> GetMapAsync(string path, int projectId, Dictionary<int, Dictionary<int, string>> cache)
    {
        if (cache.TryGetValue(projectId, out var m)) return m;
        var res = await _http.GetAsync($"{path}?project={projectId}");
        res.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var map = new Dictionary<int, string>(32);
        foreach (var el in doc.RootElement.EnumerateArray())
        {
            if (!el.TryGetProperty("id", out var idProp) || !el.TryGetProperty("name", out var nameProp)) continue;
            if (idProp.TryGetInt32(out var id) && nameProp.GetString() is { } name) map[id] = name;
        }
        cache[projectId] = map;
        return map;
    }

    private Task<Dictionary<int, string>> GetIssueStatusesAsync(int projectId)
        => GetMapAsync("issue-statuses", projectId, _statusCache);

    private Task<Dictionary<int, string>> GetIssueSeveritiesAsync(int projectId)
        => GetMapAsync("severities", projectId, _severityCache);

    private Task<Dictionary<int, string>> GetIssueTypesAsync(int projectId)
        => GetMapAsync("issue-types", projectId, _typeCache);

    private Task<Dictionary<int, string>> GetIssuePrioritiesAsync(int projectId)
        => GetMapAsync("priorities", projectId, _priorityCache);

    public async Task<string> ListIssuesAsync(int projectId, int page)
    {
        await _auth.EnsureAuthAsync(_http);

        var statuses = await GetIssueStatusesAsync(projectId);
        var severities = await GetIssueSeveritiesAsync(projectId);
        var types = await GetIssueTypesAsync(projectId);
        var priorities = await GetIssuePrioritiesAsync(projectId);

        var rejected = await _http.GetAsync($"issue-statuses?project={projectId}&is_closed=true");
        rejected.EnsureSuccessStatusCode();
        using var rejDoc = JsonDocument.Parse(await rejected.Content.ReadAsStringAsync());
        var rejectedIds = rejDoc.RootElement.EnumerateArray()
            .Select(el => el.TryGetProperty("id", out var id) && id.TryGetInt32(out var iv) ? iv : (int?)null)
            .Where(id => id.HasValue)
            .Select(id => id!.Value)
            .ToList();

        var q = new List<string>
        {
            $"project={projectId}",
            $"page={page}",
            "status__is_closed=false",
            "status__is_archived=false"
        };
        foreach (var id in rejectedIds) q.Add($"exclude_status={id}");

        var res = await _http.GetAsync($"issues?{string.Join("&", q)}");
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var items = new List<object>(64);
        foreach (var it in doc.RootElement.EnumerateArray())
        {
            int sid = it.TryGetProperty("status", out var sEl) && sEl.TryGetInt32(out var sVal) ? sVal : 0;
            int sev = it.TryGetProperty("severity", out var sevEl) && sevEl.TryGetInt32(out var sevVal) ? sevVal : 0;
            int typ = it.TryGetProperty("type", out var tEl) && tEl.TryGetInt32(out var tVal) ? tVal : 0;
            int pri = it.TryGetProperty("priority", out var pEl) && pEl.TryGetInt32(out var pVal) ? pVal : 0;

            items.Add(new
            {
                id = it.GetProperty("id").GetInt32(),
                @ref = it.TryGetProperty("ref", out var r) && r.TryGetInt32(out var rv) ? rv : 0,
                subject = it.TryGetProperty("subject", out var sub) ? sub.GetString() : null,
                status = statuses.TryGetValue(sid, out var sName) ? sName : null,
                severity = severities.TryGetValue(sev, out var sevName) ? sevName : null,
                type = types.TryGetValue(typ, out var tName) ? tName : null,
                priority = priorities.TryGetValue(pri, out var pName) ? pName : null,
                assigned_to = it.TryGetProperty("assigned_to", out var a) && a.TryGetInt32(out var av) ? av : (int?)null,
                modified = it.TryGetProperty("modified_date", out var md) ? md.GetString() : null
            });
        }

        return JsonSerializer.Serialize(
            items,
            new JsonSerializerOptions { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull }
        );
    }

    public async Task<string> CreateIssueAsync(
        int projectId, string subject, string? description,
        int? status, int? type, int? priority, int? severity,
        int? assigned_to, string[]? tags)
    {
        await _auth.EnsureAuthAsync(_http);

        var payload = new Dictionary<string, object?>
        {
            ["project"] = projectId,
            ["subject"] = subject,
            ["description"] = description,
            ["status"] = status,
            ["type"] = type,
            ["priority"] = priority,
            ["severity"] = severity,
            ["assigned_to"] = assigned_to,
            ["tags"] = tags
        };
        var json = JsonSerializer.Serialize(
            payload
                .Where(p => p.Value is not null)
                .ToDictionary(p => p.Key, p => p.Value)
        );
        var res = await _http.PostAsync("issues", new StringContent(json, Encoding.UTF8, "application/json"));
        res.EnsureSuccessStatusCode();
        return await res.Content.ReadAsStringAsync();
    }

    public async Task<string> UpdateIssueAsync(int issueId, JsonElement patch)
    {
        await _auth.EnsureAuthAsync(_http);
        if (!patch.TryGetProperty("version", out _))
            throw new InvalidOperationException("Taiga requires 'version' in patch for optimistic concurrency.");

        var req = new HttpRequestMessage(new HttpMethod("PATCH"), $"issues/{issueId}")
        {
            Content = new StringContent(patch.GetRawText(), Encoding.UTF8, "application/json")
        };
        var res = await _http.SendAsync(req);
        res.EnsureSuccessStatusCode();
        return await res.Content.ReadAsStringAsync();
    }
}
