using System.Globalization;

namespace TaigaMCP.Api;

internal static class IssueListQueryBuilder
{
    public static string Build(int projectId, IssueListOptions options)
    {
        var parts = new List<string>
        {
            Pair("project", projectId.ToString(CultureInfo.InvariantCulture)),
            Pair("page", options.Page.ToString(CultureInfo.InvariantCulture))
        };

        if (options.StatusIds is { Count: > 0 })
            parts.Add(Pair("status", string.Join(',', options.StatusIds)));
        else if (!options.IncludeClosed)
            parts.Add(Pair("status__is_closed", "false"));

        if (options.AssignedTo is { } assignedTo)
            parts.Add(Pair("assigned_to", assignedTo.ToString(CultureInfo.InvariantCulture)));
        if (options.TypeId is { } typeId)
            parts.Add(Pair("type", typeId.ToString(CultureInfo.InvariantCulture)));
        if (options.PriorityId is { } priorityId)
            parts.Add(Pair("priority", priorityId.ToString(CultureInfo.InvariantCulture)));
        if (options.SeverityId is { } severityId)
            parts.Add(Pair("severity", severityId.ToString(CultureInfo.InvariantCulture)));
        if (options.Tags is { Count: > 0 })
            parts.Add(Pair("tags", string.Join(',', options.Tags)));
        if (!string.IsNullOrWhiteSpace(options.Query))
            parts.Add(Pair("q", options.Query));

        return "issues?" + string.Join('&', parts);
    }

    private static string Pair(string name, string value)
        => $"{name}={Uri.EscapeDataString(value)}";
}
