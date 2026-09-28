using TaigaMCP.Models;
using System.Text.Json;

namespace TaigaMCP.Api;

/// <summary>Project operations.</summary>
public sealed class ProjectApi
{
    private readonly TaigaTransport _transport;

    public ProjectApi(TaigaTransport transport)
    {
        _transport = transport;
    }

    public async Task<IReadOnlyList<ProjectDto>> ListProjectsAsync(string? member, int page, CancellationToken cancellationToken = default)
    {
        var url = string.IsNullOrEmpty(member)
            ? $"projects?page={page}"
            : $"projects?member={Uri.EscapeDataString(member)}&page={page}";
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        using var doc = await _transport.ReadAsync(req, cancellationToken);
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

    public async Task<int> ResolveProjectIdAsync(string slug, CancellationToken cancellationToken = default)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, $"resolver?project={Uri.EscapeDataString(slug)}");
        using var doc = await _transport.ReadAsync(req, cancellationToken);
        return doc.RootElement.GetProperty("project").GetInt32();
    }
}
