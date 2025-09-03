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

    public async Task<string> ListUserStoriesAsync(int projectId, int page = 1)
    {
        await _auth.EnsureAuthAsync(_http);

        var stRes = await _http.GetAsync($"userstory-statuses?project={projectId}");
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
        return await usRes.Content.ReadAsStringAsync();
    }
}
