using TaigaMCP.Models;

namespace TaigaMCP.Api;

internal sealed record UserStoryListOptions
{
    public int Page { get; init; } = 1;
    public IReadOnlyList<int>? StatusIds { get; init; }
    public int? AssignedTo { get; init; }
    public int? MilestoneId { get; init; }
    public bool BacklogOnly { get; init; }
    public IReadOnlyList<string>? Tags { get; init; }
    public string? Query { get; init; }
    public bool IncludeClosed { get; init; }
    public bool IncludeArchived { get; init; }
}

internal sealed record UserStoryListPage(
    IReadOnlyList<UserStoryDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);
