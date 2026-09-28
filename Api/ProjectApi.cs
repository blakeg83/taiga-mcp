using TaigaMCP.Models;
using System.Text.Json;

namespace TaigaMCP.Api;

/// <summary>Project operations.</summary>
public sealed class ProjectApi
{
    private readonly HttpClient _http;
    private readonly AuthClient _auth;

    public ProjectApi(HttpClient http, AuthClient auth)
    {
        _http = http;
        _auth = auth;
    }

    public async Task<IReadOnlyList<ProjectDto>> ListProjectsAsync(string? member, int page)
    {
        var url = string.IsNullOrEmpty(member)
            ? $"projects?page={page}"
            : $"projects?member={Uri.EscapeDataString(member)}&page={page}";
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        var res = await _auth.SendAsync(_http, req);
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;
        JsonElement list = root.ValueKind == JsonValueKind.Object && root.TryGetProperty("results", out var results)
            ? results
            : root;

        var items = new List<ProjectDto>();
        foreach (var p in list.EnumerateArray())
        {
            items.Add(new ProjectDto
            {
                Id = p.TryGetProperty("id", out var id) && id.TryGetInt32(out var iv) ? iv : 0,
                Slug = p.TryGetProperty("slug", out var slug) ? slug.GetString() : null,
                Name = p.TryGetProperty("name", out var name) ? name.GetString() : null
            });
        }
        return items;
    }

    public async Task<int> ResolveProjectIdAsync(string slug)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, $"resolver?project={Uri.EscapeDataString(slug)}");
        var res = await _auth.SendAsync(_http, req);
        res.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        return doc.RootElement.GetProperty("project").GetInt32();
    }
}
