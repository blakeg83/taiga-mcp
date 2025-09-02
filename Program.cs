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

    public async Task<string> ListIssuesAsync(int projectId, int page)
    {
        await EnsureAuthAsync();
        var http = Client();
        var res = await http.GetAsync($"issues?project={projectId}&page={page}");
        res.EnsureSuccessStatusCode();
        return await res.Content.ReadAsStringAsync();
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
}
