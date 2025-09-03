using System.Text;
using System.Text.Json;

/// <summary>Issue operations.</summary>
public sealed class IssueApi
{
    private readonly HttpClient _http;
    private readonly AuthClient _auth;
    private readonly IssueMetadataCache _cache;

    public IssueApi(HttpClient http, AuthClient auth, IssueMetadataCache cache)
    {
        _http = http;
        _auth = auth;
        _cache = cache;
    }
    private static IssueDto MapIssue(
        JsonElement it,
        Dictionary<int, string> statuses,
        Dictionary<int, string> severities,
        Dictionary<int, string> types,
        Dictionary<int, string> priorities)
    {
        int sid = it.TryGetProperty("status", out var sEl)
            && sEl.ValueKind != JsonValueKind.Null
            && sEl.TryGetInt32(out var sVal)
            ? sVal
            : 0;
        int sev = it.TryGetProperty("severity", out var sevEl)
            && sevEl.ValueKind != JsonValueKind.Null
            && sevEl.TryGetInt32(out var sevVal)
            ? sevVal
            : 0;
        int typ = it.TryGetProperty("type", out var tEl)
            && tEl.ValueKind != JsonValueKind.Null
            && tEl.TryGetInt32(out var tVal)
            ? tVal
            : 0;
        int pri = it.TryGetProperty("priority", out var pEl)
            && pEl.ValueKind != JsonValueKind.Null
            && pEl.TryGetInt32(out var pVal)
            ? pVal
            : 0;

        return new IssueDto
        {
            Id = it.GetProperty("id").GetInt32(),
            Ref = it.TryGetProperty("ref", out var r) && r.TryGetInt32(out var rv) ? rv : 0,
            Project = it.TryGetProperty("project", out var projEl) && projEl.TryGetInt32(out var projVal) ? projVal : 0,
            Subject = it.TryGetProperty("subject", out var sub) ? sub.GetString() : null,
            Description = it.TryGetProperty("description", out var desc) ? desc.GetString() : null,
            Status = statuses.TryGetValue(sid, out var sName) ? sName : null,
            Severity = severities.TryGetValue(sev, out var sevName) ? sevName : null,
            Type = types.TryGetValue(typ, out var tName) ? tName : null,
            Priority = priorities.TryGetValue(pri, out var pName) ? pName : null,
            AssignedTo = it.TryGetProperty("assigned_to", out var a)
                && a.ValueKind != JsonValueKind.Null
                && a.TryGetInt32(out var av)
                ? av
                : (int?)null,
            Modified = it.TryGetProperty("modified_date", out var md) ? md.GetString() : null,
            Version = it.TryGetProperty("version", out var ver) && ver.TryGetInt32(out var vv) ? vv : 0
        };
    }

    public async Task<IReadOnlyList<IssueDto>> ListIssuesAsync(int projectId, int page)
    {
        await _auth.EnsureAuthAsync(_http);

        var statuses = await _cache.GetStatusesAsync(projectId);
        var severities = await _cache.GetSeveritiesAsync(projectId);
        var types = await _cache.GetTypesAsync(projectId);
        var priorities = await _cache.GetPrioritiesAsync(projectId);

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
        var items = new List<IssueDto>(64);
        foreach (var it in doc.RootElement.EnumerateArray())
        {
            items.Add(MapIssue(it, statuses, severities, types, priorities));
        }

        return items;
    }

    public async Task<IssueDto> GetIssueAsync(int issueId)
    {
        await _auth.EnsureAuthAsync(_http);

        var res = await _http.GetAsync($"issues/{issueId}");
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var el = doc.RootElement;
        int proj = el.TryGetProperty("project", out var pEl) && pEl.TryGetInt32(out var pVal) ? pVal : 0;
        var statuses = await _cache.GetStatusesAsync(proj);
        var severities = await _cache.GetSeveritiesAsync(proj);
        var types = await _cache.GetTypesAsync(proj);
        var priorities = await _cache.GetPrioritiesAsync(proj);
        return MapIssue(el, statuses, severities, types, priorities);
    }

    public async Task<IReadOnlyList<IssueCommentDto>> GetIssueCommentsAsync(int issueId)
    {
        await _auth.EnsureAuthAsync(_http);

        var res = await _http.GetAsync($"history/issue/{issueId}");
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var items = new List<IssueCommentDto>(32);
        foreach (var el in doc.RootElement.EnumerateArray())
        {
            bool isHidden = el.TryGetProperty("is_hidden", out var hiddenEl) && hiddenEl.ValueKind == JsonValueKind.True;
            if (isHidden) continue;

            if (!el.TryGetProperty("comment", out var commentEl) || commentEl.ValueKind != JsonValueKind.String)
                continue;

            var commentStr = commentEl.GetString();
            if (string.IsNullOrEmpty(commentStr))
                continue;

            var userName = el.TryGetProperty("user", out var userEl)
                && userEl.ValueKind == JsonValueKind.Object
                && userEl.TryGetProperty("name", out var nameEl)
                    ? nameEl.GetString()
                    : null;

            items.Add(new IssueCommentDto
            {
                Id = el.TryGetProperty("id", out var idEl) ? idEl.GetString() : null,
                Comment = commentStr,
                CreatedAt = el.TryGetProperty("created_at", out var createdEl) ? createdEl.GetString() : null,
                User = userName is not null ? new IssueCommentUserDto { Name = userName } : null
            });
        }

        return items;
    }

    public async Task<IReadOnlyList<IssueStatusDto>> ListIssueStatusesAsync(int projectId)
    {
        await _auth.EnsureAuthAsync(_http);

        var res = await _http.GetAsync($"issue-statuses?project={projectId}");
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var items = new List<IssueStatusDto>(32);
        foreach (var el in doc.RootElement.EnumerateArray())
        {
            items.Add(new IssueStatusDto
            {
                Id = el.TryGetProperty("id", out var idEl) && idEl.TryGetInt32(out var id) ? id : 0,
                Name = el.TryGetProperty("name", out var nameEl) ? nameEl.GetString() : null,
                Slug = el.TryGetProperty("slug", out var slugEl) ? slugEl.GetString() : null,
                IsClosed = el.TryGetProperty("is_closed", out var closedEl) && closedEl.ValueKind == JsonValueKind.True
            });
        }

        return items;
    }

    public async Task<IReadOnlyList<IssueSeverityDto>> ListIssueSeveritiesAsync(int projectId)
    {
        await _auth.EnsureAuthAsync(_http);

        var res = await _http.GetAsync($"severities?project={projectId}");
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var items = new List<IssueSeverityDto>(32);
        foreach (var el in doc.RootElement.EnumerateArray())
        {
            items.Add(new IssueSeverityDto
            {
                Id = el.TryGetProperty("id", out var idEl) && idEl.TryGetInt32(out var id) ? id : 0,
                Name = el.TryGetProperty("name", out var nameEl) ? nameEl.GetString() : null,
                Slug = el.TryGetProperty("slug", out var slugEl) ? slugEl.GetString() : null,
                Color = el.TryGetProperty("color", out var colorEl) ? colorEl.GetString() : null
            });
        }

        return items;
    }

    public async Task<IReadOnlyList<IssueTypeDto>> ListIssueTypesAsync(int projectId)
    {
        await _auth.EnsureAuthAsync(_http);

        var res = await _http.GetAsync($"issue-types?project={projectId}");
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var items = new List<IssueTypeDto>(32);
        foreach (var el in doc.RootElement.EnumerateArray())
        {
            items.Add(new IssueTypeDto
            {
                Id = el.TryGetProperty("id", out var idEl) && idEl.TryGetInt32(out var id) ? id : 0,
                Name = el.TryGetProperty("name", out var nameEl) ? nameEl.GetString() : null,
                Slug = el.TryGetProperty("slug", out var slugEl) ? slugEl.GetString() : null,
                Color = el.TryGetProperty("color", out var colorEl) ? colorEl.GetString() : null
            });
        }

        return items;
    }

    public async Task<IReadOnlyList<IssuePriorityDto>> ListIssuePrioritiesAsync(int projectId)
    {
        await _auth.EnsureAuthAsync(_http);

        var res = await _http.GetAsync($"priorities?project={projectId}");
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var items = new List<IssuePriorityDto>(32);
        foreach (var el in doc.RootElement.EnumerateArray())
        {
            items.Add(new IssuePriorityDto
            {
                Id = el.TryGetProperty("id", out var idEl) && idEl.TryGetInt32(out var id) ? id : 0,
                Name = el.TryGetProperty("name", out var nameEl) ? nameEl.GetString() : null,
                Slug = el.TryGetProperty("slug", out var slugEl) ? slugEl.GetString() : null,
                Color = el.TryGetProperty("color", out var colorEl) ? colorEl.GetString() : null
            });
        }

        return items;
    }

    public async Task<IssueDto> CreateIssueAsync(
        int projectId, string subject, string? description,
        int? status, int? type, int? priority, int? severity,
        int? assigned_to, string[]? tags)
    {
        await _auth.EnsureAuthAsync(_http);

        var payload = new IssueCreateDto
        {
            Project = projectId,
            Subject = subject,
            Description = description,
            Status = status,
            Type = type,
            Priority = priority,
            Severity = severity,
            AssignedTo = assigned_to,
            Tags = tags
        };
        var json = JsonSerializer.Serialize(
            payload,
            new JsonSerializerOptions { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull }
        );
        var res = await _http.PostAsync("issues", new StringContent(json, Encoding.UTF8, "application/json"));
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var el = doc.RootElement;
        int proj = el.TryGetProperty("project", out var pEl) && pEl.TryGetInt32(out var pVal) ? pVal : projectId;
        var statuses = await _cache.GetStatusesAsync(proj);
        var severities = await _cache.GetSeveritiesAsync(proj);
        var types = await _cache.GetTypesAsync(proj);
        var priorities = await _cache.GetPrioritiesAsync(proj);
        return MapIssue(el, statuses, severities, types, priorities);
    }

    public async Task<IssueDto> UpdateIssueAsync(
        int issueId,
        int version,
        string? subject = null,
        string? description = null,
        int? status = null,
        int? type = null,
        int? priority = null,
        int? severity = null,
        int? assigned_to = null,
        string[]? tags = null,
        string? comment = null)
    {
        await _auth.EnsureAuthAsync(_http);

        var payload = new IssueUpdateDto
        {
            Subject = subject,
            Description = description,
            Status = status,
            Type = type,
            Priority = priority,
            Severity = severity,
            AssignedTo = assigned_to,
            Tags = tags,
            Version = version,
            Comment = comment
        };

        var json = JsonSerializer.Serialize(
            payload,
            new JsonSerializerOptions
            {
                DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
            });

        using var req = new HttpRequestMessage(HttpMethod.Patch, $"issues/{issueId}")
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
        req.Headers.Accept.ParseAdd("application/json");

        var res = await _http.SendAsync(req);
        var body = await res.Content.ReadAsStringAsync();

        if (!res.IsSuccessStatusCode)
            throw new HttpRequestException($"PATCH issues/{issueId} failed: {(int)res.StatusCode} {res.ReasonPhrase}\n{body}");

        using var doc = JsonDocument.Parse(body);
        var el = doc.RootElement;

        // Map using your existing caches
        int proj = el.TryGetProperty("project", out var pEl) && pEl.TryGetInt32(out var pVal) ? pVal : 0;
        var statuses = await _cache.GetStatusesAsync(proj);
        var severities = await _cache.GetSeveritiesAsync(proj);
        var types = await _cache.GetTypesAsync(proj);
        var priorities = await _cache.GetPrioritiesAsync(proj);

        return MapIssue(el, statuses, severities, types, priorities);
    }

}
