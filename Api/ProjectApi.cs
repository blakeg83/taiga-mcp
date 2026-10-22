using System.Globalization;
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
        InputValidation.Positive(page, nameof(page));
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

    public async Task<IReadOnlyList<ProjectMemberDto>> ListProjectMembersAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
        => (await ListProjectMembersPageAsync(projectId, page, cancellationToken)).Items;

    internal async Task<ProjectMemberListPage> ListProjectMembersPageAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(page, nameof(page));

        var projectValue = Uri.EscapeDataString(projectId.ToString(CultureInfo.InvariantCulture));
        var pageValue = Uri.EscapeDataString(page.ToString(CultureInfo.InvariantCulture));
        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"memberships?project={projectValue}&page={pageValue}");
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;
        if (document.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid project member list data.");

        var items = new List<ProjectMemberDto>(64);
        foreach (var member in document.RootElement.EnumerateArray())
            items.Add(MapProjectMember(member));

        var pageInfo = TaigaPagination.Parse(response.Headers, response.RequestUri);
        return new ProjectMemberListPage(items, page, pageInfo.Total, pageInfo.NextPage, pageInfo.HasMore);
    }

    public async Task<IReadOnlyList<PointOptionDto>> ListPointsAsync(
        int projectId,
        CancellationToken cancellationToken = default)
        => (await ListPointsPageAsync(projectId, 1, cancellationToken)).Items;

    public async Task<IReadOnlyList<PointOptionDto>> ListPointsAsync(
        int projectId,
        int page,
        CancellationToken cancellationToken = default)
        => (await ListPointsPageAsync(projectId, page, cancellationToken)).Items;

    internal async Task<ProjectPointListPage> ListPointsPageAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(page, nameof(page));

        var projectValue = Uri.EscapeDataString(projectId.ToString(CultureInfo.InvariantCulture));
        var pageValue = Uri.EscapeDataString(page.ToString(CultureInfo.InvariantCulture));
        using var request = new HttpRequestMessage(HttpMethod.Get, $"points?project={projectValue}&page={pageValue}");
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;
        if (document.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid project point list data.");

        var items = new List<PointOptionDto>(32);
        foreach (var point in document.RootElement.EnumerateArray())
        {
            var mapped = MapPoint(point);
            if (mapped.Project.HasValue && mapped.Project.Value != projectId)
                throw new TaigaRequestException("Taiga returned project point data for a different project.");

            items.Add(mapped);
        }

        var pageInfo = TaigaPagination.Parse(response.Headers, response.RequestUri);
        return new ProjectPointListPage(items, page, pageInfo.Total, pageInfo.NextPage, pageInfo.HasMore);
    }

    public async Task<IReadOnlyList<ProjectRoleDto>> ListProjectRolesAsync(
        int projectId,
        CancellationToken cancellationToken = default)
        => (await ListProjectRolesPageAsync(projectId, 1, cancellationToken)).Items;

    public async Task<IReadOnlyList<ProjectRoleDto>> ListProjectRolesAsync(
        int projectId,
        int page,
        CancellationToken cancellationToken = default)
        => (await ListProjectRolesPageAsync(projectId, page, cancellationToken)).Items;

    internal async Task<ProjectRoleListPage> ListProjectRolesPageAsync(
        int projectId,
        int page = 1,
        CancellationToken cancellationToken = default)
    {
        InputValidation.Positive(projectId, nameof(projectId));
        InputValidation.Positive(page, nameof(page));

        var projectValue = Uri.EscapeDataString(projectId.ToString(CultureInfo.InvariantCulture));
        var pageValue = Uri.EscapeDataString(page.ToString(CultureInfo.InvariantCulture));
        using var request = new HttpRequestMessage(HttpMethod.Get, $"roles?project={projectValue}&page={pageValue}");
        using var response = await _transport.ReadWithHeadersAsync(request, cancellationToken);
        using var document = response.Document;
        if (document.RootElement.ValueKind != JsonValueKind.Array)
            throw new TaigaRequestException("Taiga returned invalid project role list data.");

        var items = new List<ProjectRoleDto>(32);
        foreach (var role in document.RootElement.EnumerateArray())
        {
            var mapped = MapProjectRole(role);
            if (TryReadOptionalPositiveInt(role, "project", "project role") is { } roleProject && roleProject != projectId)
                throw new TaigaRequestException("Taiga returned project role data for a different project.");

            items.Add(mapped);
        }

        var pageInfo = TaigaPagination.Parse(response.Headers, response.RequestUri);
        return new ProjectRoleListPage(items, page, pageInfo.Total, pageInfo.NextPage, pageInfo.HasMore);
    }

    public async Task<int> ResolveProjectIdAsync(string slug, CancellationToken cancellationToken = default)
    {
        InputValidation.Required(slug, nameof(slug));
        using var req = new HttpRequestMessage(HttpMethod.Get, $"resolver?project={Uri.EscapeDataString(slug)}");
        using var doc = await _transport.ReadAsync(req, cancellationToken);
        return doc.RootElement.GetProperty("project").GetInt32();
    }

    private static PointOptionDto MapPoint(JsonElement point)
    {
        if (point.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid project point data.");

        return new PointOptionDto
        {
            Id = ReadRequiredPositiveInt(point, "id", "project point"),
            Name = ReadRequiredString(point, "name", "project point"),
            Value = ReadOptionalDouble(point, "value", "project point"),
            Order = ReadRequiredInt(point, "order", "project point"),
            Project = TryReadOptionalPositiveInt(point, "project", "project point")
        };
    }

    private static ProjectRoleDto MapProjectRole(JsonElement role)
    {
        if (role.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid project role data.");

        return new ProjectRoleDto
        {
            Id = ReadRequiredPositiveInt(role, "id", "project role"),
            Name = ReadRequiredString(role, "name", "project role"),
            Computable = ReadRequiredBoolean(role, "computable", "project role")
        };
    }

    private static int ReadRequiredPositiveInt(JsonElement element, string propertyName, string resource)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid {resource} {propertyName} data.");

        return number;
    }

    private static int ReadRequiredInt(JsonElement element, string propertyName, string resource)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number))
            throw new TaigaRequestException($"Taiga returned invalid {resource} {propertyName} data.");

        return number;
    }

    private static string ReadRequiredString(JsonElement element, string propertyName, string resource)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(value.GetString()))
            throw new TaigaRequestException($"Taiga returned invalid {resource} {propertyName} data.");

        return value.GetString()!;
    }

    private static bool ReadRequiredBoolean(JsonElement element, string propertyName, string resource)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind is not JsonValueKind.True and not JsonValueKind.False)
            throw new TaigaRequestException($"Taiga returned invalid {resource} {propertyName} data.");

        return value.GetBoolean();
    }

    private static double? ReadOptionalDouble(JsonElement element, string propertyName, string resource)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetDouble(out var number) ||
            !double.IsFinite(number))
            throw new TaigaRequestException($"Taiga returned invalid {resource} {propertyName} data.");

        return number;
    }

    private static int? TryReadOptionalPositiveInt(JsonElement element, string propertyName, string resource)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid {resource} {propertyName} data.");

        return number;
    }

    private static ProjectMemberDto MapProjectMember(JsonElement member)
    {
        if (member.ValueKind != JsonValueKind.Object)
            throw new TaigaRequestException("Taiga returned invalid project member data.");

        return new ProjectMemberDto
        {
            MembershipId = ReadRequiredPositiveInt(member, "id"),
            Project = ReadRequiredPositiveInt(member, "project"),
            UserId = ReadOptionalPositiveInt(member, "user"),
            RoleId = ReadOptionalPositiveInt(member, "role"),
            RoleName = ReadOptionalString(member, "role_name"),
            FullName = ReadOptionalString(member, "full_name"),
            IsUserActive = ReadOptionalBoolean(member, "is_user_active"),
            IsAdmin = ReadOptionalBoolean(member, "is_admin"),
            IsOwner = ReadOptionalBoolean(member, "is_owner")
        };
    }

    private static int ReadRequiredPositiveInt(JsonElement member, string propertyName)
    {
        if (!member.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid project member {propertyName} data.");

        return number;
    }

    private static int? ReadOptionalPositiveInt(JsonElement member, string propertyName)
    {
        if (!member.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var number) ||
            number <= 0)
            throw new TaigaRequestException($"Taiga returned invalid project member {propertyName} data.");

        return number;
    }

    private static string? ReadOptionalString(JsonElement member, string propertyName)
    {
        if (!member.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind != JsonValueKind.String)
            throw new TaigaRequestException($"Taiga returned invalid project member {propertyName} data.");

        return value.GetString();
    }

    private static bool? ReadOptionalBoolean(JsonElement member, string propertyName)
    {
        if (!member.TryGetProperty(propertyName, out var value) ||
            value.ValueKind == JsonValueKind.Null)
            return null;

        if (value.ValueKind is not JsonValueKind.True and not JsonValueKind.False)
            throw new TaigaRequestException($"Taiga returned invalid project member {propertyName} data.");

        return value.GetBoolean();
    }
}

internal sealed record ProjectMemberListPage(
    IReadOnlyList<ProjectMemberDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);

internal sealed record ProjectPointListPage(
    IReadOnlyList<PointOptionDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);

internal sealed record ProjectRoleListPage(
    IReadOnlyList<ProjectRoleDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);
