using System.Text.Json;
using System.Net;
using System.Text;
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

    [Theory]
    [MemberData(nameof(FourKinds))]
    public async Task ResolveAsync_UsesTheClosedByRefRouteAndExactNumericQuery(
        WorkItemKind kind,
        string expectedRoute,
        string responseBody,
        int expectedId,
        string expectedSubject,
        int expectedVersion)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                $"/api/v1/{expectedRoute}/by_ref",
                responseBody);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var resolved = await CreateApi(handler, auth).ResolveAsync(12, kind, 42);

            Assert.Equal(expectedId, resolved.Id);
            Assert.Equal(expectedSubject, resolved.Subject);
            Assert.Equal(expectedVersion, resolved.Version);
            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Get);
            Assert.Equal($"?project=12&ref=42", request.Uri.Query);
            Assert.Equal("Bearer synthetic-token", request.Headers["Authorization"].Single());
        }
    }

    [Fact]
    public async Task ResolveAsync_PreservesMissingOptionalIdentityFields()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks/by_ref",
                "{\"id\":405,\"ref\":42,\"project\":12}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var resolved = await CreateApi(handler, auth).ResolveAsync(12, WorkItemKind.task, 42);

            Assert.Null(resolved.Subject);
            Assert.Null(resolved.Version);
        }
    }

    [Theory]
    [InlineData(0, 12, 42)]
    [InlineData(12, 0, 42)]
    [InlineData(12, 99, 42)]
    public async Task ResolveAsync_RejectsInvalidRequestBeforeHttp(int projectId, int reference, int kindValue)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var kind = (WorkItemKind)kindValue;
            await Assert.ThrowsAsync<ArgumentException>(() => CreateApi(handler, auth).ResolveAsync(projectId, kind, reference));
            Assert.Empty(handler.Requests);
        }
    }

    [Theory]
    [InlineData(WorkItemResolverFixtures.MismatchedProject, "different project")]
    [InlineData(WorkItemResolverFixtures.MismatchedRef, "different reference")]
    public async Task ResolveAsync_RejectsMismatchedResponseIdentity(string responseBody, string expectedMessage)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issues/by_ref", responseBody);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                CreateApi(handler, auth).ResolveAsync(12, WorkItemKind.issue, 42));

            Assert.Contains(expectedMessage, exception.Message, StringComparison.Ordinal);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Get);
        }
    }

    [Theory]
    [InlineData("[]")]
    [InlineData("{\"id\":203,\"project\":12,\"ref\":42,\"version\":-1}")]
    [InlineData("{\"id\":203,\"project\":12,\"ref\":42,\"version\":\"3\"}")]
    public async Task ResolveAsync_RejectsMalformedRequiredOrOptionalData(string responseBody)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issues/by_ref", responseBody);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<TaigaRequestException>(() =>
                CreateApi(handler, auth).ResolveAsync(12, WorkItemKind.issue, 42));
        }
    }

    [Fact]
    public async Task ResolveAsync_PropagatesSafeLookupFailure()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/issues/by_ref",
                "{\"detail\":\"private lookup failure\"}",
                HttpStatusCode.NotFound);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                CreateApi(handler, auth).ResolveAsync(12, WorkItemKind.issue, 42));

            Assert.Equal(HttpStatusCode.NotFound, exception.StatusCode);
            Assert.Contains("resource not found", exception.Message);
            Assert.DoesNotContain("private lookup failure", exception.Message);
        }
    }

    [Fact]
    public async Task ResolveAsync_PreservesSameReferenceAcrossProjectsWithoutCrossProjectSearch()
    {
        var handler = new FakeHttpMessageHandler()
            .AddRoute(
                HttpMethod.Get,
                "/api/v1/tasks/by_ref",
                request => request.Uri.Query.Contains("project=12&ref=42", StringComparison.Ordinal)
                    ? new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent(
                            "{\"id\":405,\"ref\":42,\"project\":12,\"subject\":\"Project twelve\",\"version\":1}",
                            Encoding.UTF8,
                            "application/json")
                    }
                    : new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent(
                            "{\"id\":905,\"ref\":42,\"project\":99,\"subject\":\"Project ninety-nine\",\"version\":2}",
                            Encoding.UTF8,
                            "application/json")
                    });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = CreateApi(handler, auth);
            var first = await api.ResolveAsync(12, WorkItemKind.task, 42);
            var second = await api.ResolveAsync(99, WorkItemKind.task, 42);

            Assert.Equal((405, 12, "Project twelve"), (first.Id, first.Project, first.Subject));
            Assert.Equal((905, 99, "Project ninety-nine"), (second.Id, second.Project, second.Subject));
            Assert.Equal(
                new[] { "?project=12&ref=42", "?project=99&ref=42" },
                handler.Requests
                    .Where(request => request.Method == HttpMethod.Get)
                    .Select(request => request.Uri.Query));
        }
    }

    [Fact]
    public async Task ResolveAsync_PropagatesSafePermissionFailure()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/by_ref",
                "{\"detail\":\"private resolver permission secret\"}",
                HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                CreateApi(handler, auth).ResolveAsync(12, WorkItemKind.epic, 42));

            Assert.Equal(HttpStatusCode.Forbidden, exception.StatusCode);
            Assert.Contains("permission denied", exception.Message);
            Assert.DoesNotContain("private resolver permission secret", exception.Message);
        }
    }

    [Fact]
    public async Task ResolveAsync_ReplaysOnlyReceived401()
    {
        var lookupRequests = 0;
        var handler = new FakeHttpMessageHandler()
            .AddRoute(
                HttpMethod.Get,
                "/api/v1/issues/by_ref",
                _ => Interlocked.Increment(ref lookupRequests) == 1
                    ? new HttpResponseMessage(HttpStatusCode.Unauthorized)
                    : new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent(
                            WorkItemResolverFixtures.Issue,
                            Encoding.UTF8,
                            "application/json")
                    })
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/auth/refresh",
                "{\"auth_token\":\"refreshed-token\",\"refresh\":\"next-refresh\"}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var resolved = await CreateApi(handler, auth).ResolveAsync(12, WorkItemKind.issue, 42);

            Assert.Equal(203, resolved.Id);
            var requests = handler.Requests
                .Where(request => request.Method == HttpMethod.Get && request.Uri.AbsolutePath.EndsWith("/issues/by_ref"))
                .ToArray();
            Assert.Equal(2, requests.Length);
            Assert.Equal("Bearer synthetic-token", requests[0].Headers["Authorization"].Single());
            Assert.Equal("Bearer refreshed-token", requests[1].Headers["Authorization"].Single());
        }
    }

    [Fact]
    public async Task ResolveAsync_CancellationStopsBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/by_ref", WorkItemResolverFixtures.Task);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                CreateApi(handler, auth).ResolveAsync(12, WorkItemKind.task, 42, cancellation.Token));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ResolveAsync_DisposesResponseBeforeReturningOwnedReceipt()
    {
        var content = new TrackingContent(WorkItemResolverFixtures.Epic);
        var handler = new FakeHttpMessageHandler()
            .AddRoute(
                HttpMethod.Get,
                "/api/v1/epics/by_ref",
                _ => new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var resolved = await CreateApi(handler, auth).ResolveAsync(12, WorkItemKind.epic, 42);

            Assert.True(content.Disposed);
            Assert.Equal(506, resolved.Id);
            Assert.Equal("Saved-search delivery", resolved.Subject);
        }
    }

    private static WorkItemResolverApi CreateApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private sealed class TrackingContent(string body) : StringContent(body, Encoding.UTF8, "application/json")
    {
        public bool Disposed { get; private set; }

        protected override void Dispose(bool disposing)
        {
            Disposed = true;
            base.Dispose(disposing);
        }
    }
}
