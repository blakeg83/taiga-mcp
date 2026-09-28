namespace TaigaMCP.Api;

internal sealed record IssueListOptions
{
    public int Page { get; init; } = 1;
    public IReadOnlyList<int>? StatusIds { get; init; }
    public int? AssignedTo { get; init; }
    public int? TypeId { get; init; }
    public int? PriorityId { get; init; }
    public int? SeverityId { get; init; }
    public IReadOnlyList<string>? Tags { get; init; }
    public string? Query { get; init; }
    public bool IncludeClosed { get; init; }
}

internal sealed record IssueListPage(
    IReadOnlyList<Models.IssueDto> Items,
    int Page,
    int? Total,
    int? NextPage,
    bool? HasMore);
