// Program.cs
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Server;

var builder = Host.CreateApplicationBuilder(args);
builder.Logging.AddConsole(o => o.LogToStandardErrorThreshold = LogLevel.Information);

// Environment config
var taigaBase = Environment.GetEnvironmentVariable("TAIGA_BASE_URL") ?? "https://api.taiga.io/api/v1/";
var taigaUser = Environment.GetEnvironmentVariable("TAIGA_USERNAME") ?? "";
var taigaPass = Environment.GetEnvironmentVariable("TAIGA_PASSWORD") ?? "";

// HttpClient
builder.Services.AddHttpClient("taiga", client =>
{
    client.BaseAddress = new Uri(taigaBase.EndsWith("/") ? taigaBase : taigaBase + "/");
    client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
});

// Taiga API helper
builder.Services.AddSingleton(new TaigaConfig(taigaUser, taigaPass));
builder.Services.AddSingleton<TaigaApi>();

// MCP server with tools discovered from this assembly
builder.Services
    .AddMcpServer()
    .WithStdioServerTransport()
    .WithToolsFromAssembly();

await builder.Build().RunAsync();

/// <summary>Runtime Taiga configuration.</summary>
public record TaigaConfig(string Username, string Password);

/// <summary>Thin Taiga API wrapper. Handles auth and common calls.</summary>
public sealed class TaigaApi
{
    private readonly IHttpClientFactory _factory;
    private readonly TaigaConfig _cfg;
    private string? _token;
    private readonly Dictionary<int, Dictionary<int, string>> _issueStatusCache = new();
    private readonly Dictionary<int, Dictionary<int, string>> _issueSeverityCache = new();
    private readonly Dictionary<int, Dictionary<int, string>> _issueTypeCache = new();

    private async Task<Dictionary<int, string>> GetMapAsync(string path, int projectId, Dictionary<int, Dictionary<int, string>> cache)
    {
        if (cache.TryGetValue(projectId, out var m)) return m;
        var http = Client();
        var res = await http.GetAsync($"{path}?project={projectId}");
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
        => GetMapAsync("issue-statuses", projectId, _issueStatusCache);

    private Task<Dictionary<int, string>> GetIssueSeveritiesAsync(int projectId)
        => GetMapAsync("severities", projectId, _issueSeverityCache);

    private Task<Dictionary<int, string>> GetIssueTypesAsync(int projectId)
        => GetMapAsync("issue-types", projectId, _issueTypeCache);


    public TaigaApi(IHttpClientFactory factory, TaigaConfig cfg)
    {
        _factory = factory;
        _cfg = cfg;
    }

    private HttpClient Client()
    {
        var http = _factory.CreateClient("taiga");
        if (!string.IsNullOrEmpty(_token))
            http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _token);
        return http;
    }

    private async Task EnsureAuthAsync()
    {
        if (!string.IsNullOrEmpty(_token)) return;
        var http = _factory.CreateClient("taiga");
        var body = JsonSerializer.Serialize(new { type = "normal", username = _cfg.Username, password = _cfg.Password });
        var res = await http.PostAsync("auth", new StringContent(body, Encoding.UTF8, "application/json"));
        res.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        _token = doc.RootElement.GetProperty("auth_token").GetString()
                 ?? throw new InvalidOperationException("Taiga auth_token missing");
    }

    public async Task<string> ListProjectsAsync(string? member = null, int page = 1)
    {
        await EnsureAuthAsync();
        var http = Client();
        var url = string.IsNullOrEmpty(member)
            ? $"projects?page={page}"
            : $"projects?member={Uri.EscapeDataString(member)}&page={page}";
        var res = await http.GetAsync(url);
        res.EnsureSuccessStatusCode();

        // Trim to id, slug, name
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        // API may return either an array or a paged object with "results"
        JsonElement root = doc.RootElement;
        JsonElement list = root.ValueKind == JsonValueKind.Object && root.TryGetProperty("results", out var results)
            ? results
            : root;

        var items = new List<Dictionary<string, object?>>();
        foreach (var p in list.EnumerateArray())
        {
            items.Add(new()
            {
                ["id"] = p.TryGetProperty("id", out var id) ? id.GetInt32() : 0,
                ["slug"] = p.TryGetProperty("slug", out var slug) ? slug.GetString() : null,
                ["name"] = p.TryGetProperty("name", out var name) ? name.GetString() : null
            });
        }
        return JsonSerializer.Serialize(items);
    }

    public async Task<int> ResolveProjectIdAsync(string slug)
    {
        await EnsureAuthAsync();
        var http = Client();
        var res = await http.GetAsync($"resolver?project={Uri.EscapeDataString(slug)}");
        res.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        return doc.RootElement.GetProperty("project").GetInt32();
    }

    public async Task<string> ListIssuesAsync(int projectId, int page)
    {
        await EnsureAuthAsync();
        var http = Client();

        // 1) maps
        var statuses = await GetIssueStatusesAsync(projectId);
        var severities = await GetIssueSeveritiesAsync(projectId);
        var types = await GetIssueTypesAsync(projectId);

        // 2) exclude Closed/Rejected by ID
        var excludeIds = statuses
            .Where(kv => kv.Value.Contains("Closed", StringComparison.OrdinalIgnoreCase) ||
                         kv.Value.Contains("Rejected", StringComparison.OrdinalIgnoreCase))
            .Select(kv => kv.Key);

        // 3) request with excludes
        var q = new List<string> { $"project={projectId}", $"page={page}" };
        foreach (var id in excludeIds) q.Add($"exclude_status={id}");
        var res = await http.GetAsync($"issues?{string.Join("&", q)}");
        res.EnsureSuccessStatusCode();

        // 4) compact projection with names
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var items = new List<object>(64);
        foreach (var it in doc.RootElement.EnumerateArray())
        {
            int sid = it.TryGetProperty("status", out var sEl) && sEl.TryGetInt32(out var sVal) ? sVal : 0;
            int sev = it.TryGetProperty("severity", out var sevEl) && sevEl.TryGetInt32(out var sevVal) ? sevVal : 0;
            int typ = it.TryGetProperty("type", out var tEl) && tEl.TryGetInt32(out var tVal) ? tVal : 0;

            items.Add(new
            {
                id = it.GetProperty("id").GetInt32(),
                @ref = it.TryGetProperty("ref", out var r) && r.TryGetInt32(out var rv) ? rv : 0,
                subject = it.TryGetProperty("subject", out var sub) ? sub.GetString() : null,
                description = it.TryGetProperty("description", out var desc) ? desc.GetString() : null,
                status = statuses.TryGetValue(sid, out var sName) ? sName : null,
                severity = severities.TryGetValue(sev, out var sevName) ? sevName : null,
                type = types.TryGetValue(typ, out var tName) ? tName : null,
                modified = it.TryGetProperty("modified_date", out var md) ? md.GetString() : null
            });
        }

        var json = JsonSerializer.Serialize(
            items,
            new JsonSerializerOptions { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull }
        );
        return json;
    }


    public async Task<string> CreateIssueAsync(
        int projectId, string subject, string? description,
        int? status, int? type, int? priority, int? severity,
        int? assigned_to, string[]? tags)
    {
        await EnsureAuthAsync();
        var http = Client();

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
        var res = await http.PostAsync("issues", new StringContent(json, Encoding.UTF8, "application/json"));
        res.EnsureSuccessStatusCode();
        return await res.Content.ReadAsStringAsync();
    }

    public async Task<string> UpdateIssueAsync(int issueId, JsonElement patch)
    {
        await EnsureAuthAsync();
        if (!patch.TryGetProperty("version", out _))
            throw new InvalidOperationException("Taiga requires 'version' in patch for optimistic concurrency.");

        var http = Client();
        var req = new HttpRequestMessage(new HttpMethod("PATCH"), $"issues/{issueId}")
        {
            Content = new StringContent(patch.GetRawText(), Encoding.UTF8, "application/json")
        };
        var res = await http.SendAsync(req);
        res.EnsureSuccessStatusCode();
        return await res.Content.ReadAsStringAsync();
    }

    // In TaigaApi
    public async Task<string> ListUserStoriesAsync(int projectId, int page = 1)
    {
        await EnsureAuthAsync();
        var http = Client();

        // 1) resolve status IDs for "Done" and "Archived" in this project
        var stRes = await http.GetAsync($"userstory-statuses?project={projectId}");
        stRes.EnsureSuccessStatusCode();
        using var stDoc = JsonDocument.Parse(await stRes.Content.ReadAsStringAsync());
        var excludeIds = new List<int>();
        foreach (var st in stDoc.RootElement.EnumerateArray())
        {
            var name = st.TryGetProperty("name", out var n) ? n.GetString() : null;
            if (name is null) continue;
            if (string.Equals(name, "Done", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(name, "Archived", StringComparison.OrdinalIgnoreCase))
            {
                if (st.TryGetProperty("id", out var idProp) && idProp.TryGetInt32(out var id))
                    excludeIds.Add(id);
            }
        }

        // 2) build query
        var q = new List<string>
        {
            $"project={projectId}",
            $"page={page}",
            "status__is_archived=false",
            "status__is_closed=false"
        };
        foreach (var id in excludeIds)
            q.Add($"exclude_status={id}");


        var usRes = await http.GetAsync($"userstories?{string.Join("&", q)}");
        usRes.EnsureSuccessStatusCode();
        return await usRes.Content.ReadAsStringAsync();
    }

}

// ===== MCP tools (DI via constructor; no [FromServices]) =====
[McpServerToolType]
public sealed class TaigaTools
{
    private readonly TaigaApi _api;

    public TaigaTools(TaigaApi api)
    {
        _api = api;
    }

    [McpServerTool(Name = "list_projects")]
    public Task<string> ListProjects(string? member = "me", int page = 1)
    => _api.ListProjectsAsync(member, page);

    [McpServerTool(Name = "resolve_project")]
    public async Task<string> ResolveProject(string slug)
    => JsonSerializer.Serialize(new { project = await _api.ResolveProjectIdAsync(slug) });

    [McpServerTool(Name = "list_issues")]
    public Task<string> ListIssues(int projectId, int page = 1)
        => _api.ListIssuesAsync(projectId, page);

    [McpServerTool(Name = "create_issue")]
    public Task<string> CreateIssue(
        int projectId,
        string subject,
        string? description = null,
        int? status = null, int? type = null, int? priority = null, int? severity = null,
        int? assigned_to = null, string[]? tags = null)
        => _api.CreateIssueAsync(projectId, subject, description, status, type, priority, severity, assigned_to, tags);

    [McpServerTool(Name = "update_issue")]
    public Task<string> UpdateIssue(int issueId, JsonElement patch)
        => _api.UpdateIssueAsync(issueId, patch);

    // In TaigaTools
    [McpServerTool(Name = "list_user_stories")]
    public Task<string> ListUserStories(int projectId, int page = 1)
        => _api.ListUserStoriesAsync(projectId, page);

}
