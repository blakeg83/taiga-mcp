namespace TaigaMCP.Api;

internal sealed record TaskListOptions
{
    public int Page { get; init; } = 1;
    public IReadOnlyList<int>? StatusIds { get; init; }
    public int? UserStoryId { get; init; }
    public int? MilestoneId { get; init; }
    public int? AssignedTo { get; init; }
    public IReadOnlyList<string>? Tags { get; init; }
    public string? Query { get; init; }
    public bool IncludeClosed { get; init; }
}

internal sealed record TaskListPage(
    IReadOnlyList<Models.TaskDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);

internal sealed record TaskStatusListPage(
    IReadOnlyList<Models.TaskStatusDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);
