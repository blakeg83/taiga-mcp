using TaigaMCP.Models;
using System.Text.Json;

namespace TaigaMCP.Api;

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
        using var stReq = new HttpRequestMessage(HttpMethod.Get, $"userstory-statuses?project={projectId}");
        var stRes = await _auth.SendAsync(_http, stReq);
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

        using var usReq = new HttpRequestMessage(HttpMethod.Get, $"userstories?{string.Join("&", q)}");
        var usRes = await _auth.SendAsync(_http, usReq);
        usRes.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await usRes.Content.ReadAsStringAsync());
        var items = new List<UserStoryDto>();
        foreach (var us in doc.RootElement.EnumerateArray())
        {
            if (!us.TryGetProperty("id", out var idEl) || idEl.ValueKind == JsonValueKind.Null || !idEl.TryGetInt32(out var idVal))
                continue;
            int stId = us.TryGetProperty("status", out var stEl) && stEl.ValueKind != JsonValueKind.Null && stEl.TryGetInt32(out var stVal) ? stVal : 0;
            items.Add(new UserStoryDto
            {
                Id = idVal,
                Ref = us.TryGetProperty("ref", out var r) && r.ValueKind != JsonValueKind.Null && r.TryGetInt32(out var rv) ? rv : 0,
                Subject = us.TryGetProperty("subject", out var sub) ? sub.GetString() : null,
                Status = statusMap.TryGetValue(stId, out var stName) ? stName : null,
                AssignedTo = us.TryGetProperty("assigned_to", out var a) && a.ValueKind != JsonValueKind.Null && a.TryGetInt32(out var av) ? av : (int?)null,
                Modified = us.TryGetProperty("modified_date", out var md) ? md.GetString() : null
            });
        }

        return items;
    }
}
