using System.Globalization;

namespace TaigaMCP.Api;

internal static class UserStoryListQueryBuilder
{
    public static string Build(int projectId, UserStoryListOptions options)
    {
        var parts = new List<string>
        {
            Pair("project", projectId.ToString(CultureInfo.InvariantCulture)),
            Pair("page", options.Page.ToString(CultureInfo.InvariantCulture))
        };

        if (options.StatusIds is { Count: > 0 })
        {
            parts.Add(Pair("status", string.Join(',', options.StatusIds)));
        }
        else
        {
            if (!options.IncludeArchived)
                parts.Add(Pair("status__is_archived", "false"));
            if (!options.IncludeClosed)
                parts.Add(Pair("status__is_closed", "false"));
        }

        if (options.AssignedTo is { } assignedTo)
            parts.Add(Pair("assigned_to", assignedTo.ToString(CultureInfo.InvariantCulture)));
        if (options.MilestoneId is { } milestoneId)
            parts.Add(Pair("milestone", milestoneId.ToString(CultureInfo.InvariantCulture)));
        else if (options.BacklogOnly)
            parts.Add(Pair("milestone__isnull", "true"));
        if (options.Tags is { Count: > 0 })
            parts.Add(Pair("tags", string.Join(',', options.Tags)));
        if (!string.IsNullOrWhiteSpace(options.Query))
            parts.Add(Pair("q", options.Query));

        return "userstories?" + string.Join('&', parts);
    }

    private static string Pair(string name, string value)
        => $"{name}={Uri.EscapeDataString(value)}";
}
