using System.Text.Json;

/// <summary>User story operations.</summary>
public sealed class UserStoryApi
{
    private readonly HttpClient _http;
    private readonly AuthClient _auth;

    public UserStoryApi(HttpClient http, AuthClient auth)
    {
        _http = http;
        _auth = auth;
    }

    public async Task<IReadOnlyList<UserStoryDto>> ListUserStoriesAsync(int projectId, int page = 1)
    {
        await _auth.EnsureAuthAsync(_http);

        var stRes = await _http.GetAsync($"userstory-statuses?project={projectId}");
        stRes.EnsureSuccessStatusCode();
        using var stDoc = JsonDocument.Parse(await stRes.Content.ReadAsStringAsync());
        var excludeIds = new List<int>();
        var statusMap = new Dictionary<int, string>();
        foreach (var st in stDoc.RootElement.EnumerateArray())
        {
            var name = st.TryGetProperty("name", out var n) ? n.GetString() : null;
            if (name is null) continue;
            if (st.TryGetProperty("id", out var idProp) && idProp.TryGetInt32(out var id))
            {
                statusMap[id] = name;
                if (string.Equals(name, "Done", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(name, "Archived", StringComparison.OrdinalIgnoreCase))
                {
                    excludeIds.Add(id);
                }
            }
        }

        var q = new List<string>
        {
            $"project={projectId}",
            $"page={page}",
            "status__is_archived=false",
            "status__is_closed=false"
        };
        foreach (var id in excludeIds)
            q.Add($"exclude_status={id}");

        var usRes = await _http.GetAsync($"userstories?{string.Join("&", q)}");
        usRes.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await usRes.Content.ReadAsStringAsync());
        var items = new List<UserStoryDto>();
        foreach (var us in doc.RootElement.EnumerateArray())
        {
            int stId = us.TryGetProperty("status", out var stEl) && stEl.TryGetInt32(out var stVal) ? stVal : 0;
            items.Add(new UserStoryDto
            {
                Id = us.GetProperty("id").GetInt32(),
                Ref = us.TryGetProperty("ref", out var r) && r.TryGetInt32(out var rv) ? rv : 0,
                Subject = us.TryGetProperty("subject", out var sub) ? sub.GetString() : null,
                Status = statusMap.TryGetValue(stId, out var stName) ? stName : null,
                AssignedTo = us.TryGetProperty("assigned_to", out var a) && a.TryGetInt32(out var av) ? av : (int?)null,
                Modified = us.TryGetProperty("modified_date", out var md) ? md.GetString() : null
            });
        }

        return items;
    }
}
