namespace TaigaMCP.Api;

internal sealed record EpicListOptions
{
    public int Page { get; init; } = 1;
    public IReadOnlyList<int>? StatusIds { get; init; }
    public int? AssignedTo { get; init; }
    public IReadOnlyList<string>? Tags { get; init; }
    public string? Query { get; init; }
    public bool IncludeClosed { get; init; }
}

internal sealed record EpicListPage(
    IReadOnlyList<Models.EpicDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);
