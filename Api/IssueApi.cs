using TaigaMCP.Models;
using TaigaMCP.Caching;
using System.Text;
using System.Text.Json;

namespace TaigaMCP.Api;

/// <summary>Issue operations.</summary>
public sealed class IssueApi
{
    private readonly TaigaTransport _transport;
    private readonly IssueMetadataCache _cache;

    public IssueApi(TaigaTransport transport, IssueMetadataCache cache)
    {
        _transport = transport;
        _cache = cache;
    }
    private static IssueDto MapIssue(
        JsonElement it,
        IReadOnlyDictionary<int, string> statuses,
        IReadOnlyDictionary<int, string> severities,
        IReadOnlyDictionary<int, string> types,
        IReadOnlyDictionary<int, string> priorities)
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

    public async Task<IReadOnlyList<IssueDto>> ListIssuesAsync(int projectId, int page, CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(page, nameof(page));
        var statuses = await _cache.GetStatusesAsync(projectId, cancellationToken);
        var severities = await _cache.GetSeveritiesAsync(projectId, cancellationToken);
        var types = await _cache.GetTypesAsync(projectId, cancellationToken);
        var priorities = await _cache.GetPrioritiesAsync(projectId, cancellationToken);
        using var req = new HttpRequestMessage(HttpMethod.Get, $"issues?project={projectId}&page={page}&status__is_closed=false");
        using var doc = await _transport.ReadAsync(req, cancellationToken);
        var items = new List<IssueDto>(64);
        foreach (var it in doc.RootElement.EnumerateArray())
        {
            items.Add(MapIssue(it, statuses, severities, types, priorities));
        }

        return items;
    }

    public async Task<IssueDto> GetIssueAsync(int issueId, CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(issueId, nameof(issueId));
        using var req = new HttpRequestMessage(HttpMethod.Get, $"issues/{issueId}");
        using var doc = await _transport.ReadAsync(req, cancellationToken);
        var el = doc.RootElement;
        int proj = el.TryGetProperty("project", out var pEl) && pEl.TryGetInt32(out var pVal) ? pVal : 0;
        var statuses = await _cache.GetStatusesAsync(proj, cancellationToken);
        var severities = await _cache.GetSeveritiesAsync(proj, cancellationToken);
        var types = await _cache.GetTypesAsync(proj, cancellationToken);
        var priorities = await _cache.GetPrioritiesAsync(proj, cancellationToken);
        return MapIssue(el, statuses, severities, types, priorities);
    }

    public async Task<IReadOnlyList<IssueCommentDto>> GetIssueCommentsAsync(int issueId, CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(issueId, nameof(issueId));
        using var req = new HttpRequestMessage(HttpMethod.Get, $"history/issue/{issueId}");
        using var doc = await _transport.ReadAsync(req, cancellationToken);
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

    public async Task<IReadOnlyList<IssueStatusDto>> ListIssueStatusesAsync(int projectId, CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        using var req = new HttpRequestMessage(HttpMethod.Get, $"issue-statuses?project={projectId}");
        using var doc = await _transport.ReadAsync(req, cancellationToken);
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

    public async Task<IReadOnlyList<IssueSeverityDto>> ListIssueSeveritiesAsync(int projectId, CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        using var req = new HttpRequestMessage(HttpMethod.Get, $"severities?project={projectId}");
        using var doc = await _transport.ReadAsync(req, cancellationToken);
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

    public async Task<IReadOnlyList<IssueTypeDto>> ListIssueTypesAsync(int projectId, CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        using var req = new HttpRequestMessage(HttpMethod.Get, $"issue-types?project={projectId}");
        using var doc = await _transport.ReadAsync(req, cancellationToken);
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

    public async Task<IReadOnlyList<IssuePriorityDto>> ListIssuePrioritiesAsync(int projectId, CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        using var req = new HttpRequestMessage(HttpMethod.Get, $"priorities?project={projectId}");
        using var doc = await _transport.ReadAsync(req, cancellationToken);
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
        int? assigned_to, string[]? tags, CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Required(subject, nameof(subject));
        InputValidation.OptionalIds((status, nameof(status)), (type, nameof(type)), (priority, nameof(priority)), (severity, nameof(severity)), (assigned_to, nameof(assigned_to)));
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
        using var req = new HttpRequestMessage(HttpMethod.Post, "issues")
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
        using var doc = await _transport.ReadAsync(req, cancellationToken);
        try
        {
            var el = doc.RootElement;
            int proj = el.TryGetProperty("project", out var pEl) && pEl.TryGetInt32(out var pVal) ? pVal : projectId;
            var statuses = await _cache.GetStatusesAsync(proj, cancellationToken);
            var severities = await _cache.GetSeveritiesAsync(proj, cancellationToken);
            var types = await _cache.GetTypesAsync(proj, cancellationToken);
            var priorities = await _cache.GetPrioritiesAsync(proj, cancellationToken);
            return MapIssue(el, statuses, severities, types, priorities);
        }
        catch (OperationCanceledException)
        {
            throw new OperationCanceledException("Taiga write may already have applied; enrichment was cancelled. Read the entity before retrying.", cancellationToken);
        }
        catch (Exception)
        {
            throw new TaigaRequestException("Taiga write may already have applied; response enrichment failed. Read the entity before retrying.");
        }
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
        string? comment = null, CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(issueId, nameof(issueId));
        InputValidation.OptionalIds((status, nameof(status)), (type, nameof(type)), (priority, nameof(priority)), (severity, nameof(severity)), (assigned_to, nameof(assigned_to)));
        if (version < 0) throw new ArgumentException("version must be nonnegative.");
        if (subject is not null) InputValidation.Required(subject, nameof(subject));
        if (subject is null && description is null && status is null && type is null && priority is null &&
            severity is null && assigned_to is null && tags is null && string.IsNullOrWhiteSpace(comment))
            throw new ArgumentException("An update requires a change or a nonblank comment.");
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

        using var doc = await _transport.ReadAsync(req, cancellationToken);
        try
        {
            var el = doc.RootElement;

            int proj = el.TryGetProperty("project", out var pEl) && pEl.TryGetInt32(out var pVal) ? pVal : 0;
            var statuses = await _cache.GetStatusesAsync(proj, cancellationToken);
            var severities = await _cache.GetSeveritiesAsync(proj, cancellationToken);
            var types = await _cache.GetTypesAsync(proj, cancellationToken);
            var priorities = await _cache.GetPrioritiesAsync(proj, cancellationToken);

            return MapIssue(el, statuses, severities, types, priorities);
        }
        catch (OperationCanceledException)
        {
            throw new OperationCanceledException("Taiga write may already have applied; enrichment was cancelled. Read the entity before retrying.", cancellationToken);
        }
        catch (Exception)
        {
            throw new TaigaRequestException("Taiga write may already have applied; response enrichment failed. Read the entity before retrying.");
        }
    }

}
