using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemResolverContractTests
{
    public static IEnumerable<object[]> FourKinds()
    {
        yield return [WorkItemKind.issue, "issues", WorkItemResolverFixtures.Issue, 203, "Resolve the saved search issue", 3];
        yield return [WorkItemKind.user_story, "userstories", WorkItemResolverFixtures.UserStory, 304, "Allow saved searches", 4];
        yield return [WorkItemKind.task, "tasks", WorkItemResolverFixtures.Task, 405, "Implement saved-search endpoint", 5];
        yield return [WorkItemKind.epic, "epics", WorkItemResolverFixtures.Epic, 506, "Saved-search delivery", 6];
    }

    [Theory]
    [MemberData(nameof(FourKinds))]
    public void FourKindsUseClosedRoutesAndMapIdentity(
        WorkItemKind kind,
        string expectedRoute,
        string responseBody,
        int expectedId,
        string expectedSubject,
        int expectedVersion)
    {
        Assert.Equal(expectedRoute, WorkItemResolverContract.GetRoute(kind));

        using var document = JsonDocument.Parse(responseBody);
        var resolved = WorkItemResolverContract.MapResponse(document.RootElement, kind, 12, 42);

        Assert.Equal(kind.ToString(), resolved.Kind);
        Assert.Equal(expectedId, resolved.Id);
        Assert.Equal(42, resolved.Ref);
        Assert.Equal(12, resolved.Project);
        Assert.Equal(expectedSubject, resolved.Subject);
        Assert.Equal(expectedVersion, resolved.Version);
    }

    [Fact]
    public void IdentityReceiptKeepsDisplayedReferenceDistinctFromInternalId()
    {
        using var document = JsonDocument.Parse(WorkItemResolverFixtures.Task);

        var resolved = WorkItemResolverContract.MapResponse(document.RootElement, WorkItemKind.task, 12, 42);

        Assert.Equal(405, resolved.Id);
        Assert.Equal(42, resolved.Ref);
        Assert.NotEqual(resolved.Ref, resolved.Id);
    }

    [Theory]
    [InlineData(WorkItemResolverFixtures.MismatchedProject, "different project")]
    [InlineData(WorkItemResolverFixtures.MismatchedRef, "different reference")]
    public void MismatchedResponseIdentityIsRejected(string responseBody, string expectedMessage)
    {
        using var document = JsonDocument.Parse(responseBody);

        var exception = Assert.Throws<TaigaRequestException>(() =>
            WorkItemResolverContract.MapResponse(document.RootElement, WorkItemKind.issue, 12, 42));

        Assert.Contains(expectedMessage, exception.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(0, 42)]
    [InlineData(12, 0)]
    public void ContractRejectsNonpositiveRequestedIdentity(int projectId, int reference)
    {
        using var document = JsonDocument.Parse(WorkItemResolverFixtures.Issue);

        Assert.Throws<ArgumentException>(() =>
        {
            InputValidation.Positive(projectId, nameof(projectId));
            InputValidation.Positive(reference, nameof(reference));
            WorkItemResolverContract.MapResponse(document.RootElement, WorkItemKind.issue, projectId, reference);
        });
    }

    [Fact]
    public void UndefinedKindIsRejectedBeforeRouteConstruction()
        => Assert.Throws<ArgumentException>(() => WorkItemResolverContract.GetRoute((WorkItemKind)99));
}
