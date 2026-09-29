using System.Net;
using System.Text;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemCommentReadTests
{
    public static IEnumerable<object[]> FourKinds()
    {
        yield return [WorkItemKind.issue, "issue", 42];
        yield return [WorkItemKind.user_story, "userstory", 102];
        yield return [WorkItemKind.task, "task", 203];
        yield return [WorkItemKind.epic, "epic", 301];
    }

    [Fact]
    public async Task ListWorkItemCommentsAsync_FiltersAndMapsVisibleComments()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/history/userstory/102", WorkItemHistoryFixtures.CommentsPage);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListWorkItemCommentsPageAsync(
                WorkItemKind.user_story,
                102,
                page: 1);

            Assert.Equal(1, page.Page);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
            Assert.Equal(2, page.Items.Count);

            var edited = page.Items[0];
            Assert.Equal("550e8400-e29b-41d4-a716-446655440000", edited.Id);
            Assert.Equal("**Progress**\n@alice — revisión ✓", edited.Comment);
            Assert.Equal("2026-09-28T12:01:00Z", edited.CreatedAt);
            Assert.Equal("2026-09-28T12:05:00Z", edited.EditCommentDate);
            Assert.Equal(42, edited.User!.Id);
            Assert.Equal("Example User", edited.User.Name);
            Assert.Equal("example", edited.User.Username);
            Assert.True(edited.User.IsActive);

            var missingActor = page.Items[1];
            Assert.Equal("missing-actor", missingActor.Id);
            Assert.Null(missingActor.User!.Id);
            Assert.Null(missingActor.User.Name);
            Assert.Null(missingActor.User.Username);
            Assert.False(missingActor.User.IsActive);

            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Get);
            Assert.Equal("?type=comment&page=1", request.Uri.Query);
            Assert.Equal("Bearer synthetic-token", request.Headers["Authorization"].Single());
        }
    }

    [Theory]
    [MemberData(nameof(FourKinds))]
    public async Task ListWorkItemCommentsAsync_UsesClosedHistoryRoutesAndExplicitPage(
        WorkItemKind kind,
        string route,
        int id)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, $"/api/v1/history/{route}/{id}", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var items = await NewApi(handler, auth).ListWorkItemCommentsAsync(kind, id, page: 2);

            Assert.Empty(items);
            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Get);
            Assert.Equal($"/api/v1/history/{route}/{id}", request.Uri.AbsolutePath);
            Assert.Equal("?type=comment&page=2", request.Uri.Query);
        }
    }

    [Fact]
    public async Task ListWorkItemCommentsPage_PreservesUpstreamMetadataForFilteredEmptyPage()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/history/issue/42",
                "[{\"id\":\"hidden\",\"is_hidden\":true,\"comment\":\"not visible\"}]",
                headers: new Dictionary<string, string>
                {
                    ["x-pagination-count"] = "3",
                    ["x-pagination-next"] = "https://fake.taiga.test/api/v1/history/issue/42?type=comment&page=2",
                    ["x-paginated"] = "true"
                });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListWorkItemCommentsPageAsync(WorkItemKind.issue, 42);

            Assert.Empty(page.Items);
            Assert.Equal(3, page.Total);
            Assert.Equal(2, page.NextPage);
            Assert.True(page.HasMore);
        }
    }

    [Fact]
    public async Task ListWorkItemCommentsPage_UsesVerifiedBodyPaginationWhenHeadersAreAbsent()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/history/userstory/102", WorkItemHistoryFixtures.PaginatedBody);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListWorkItemCommentsPageAsync(WorkItemKind.user_story, 102);

            Assert.Equal(3, page.Total);
            Assert.Equal(2, page.NextPage);
            Assert.True(page.HasMore);
            Assert.Equal("edited-entry", Assert.Single(page.Items).Id);
        }
    }

    [Fact]
    public async Task ListWorkItemCommentsPage_UsesNullNextAsLastPageEvidence()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/history/task/203",
                "{\"count\":1,\"next\":null,\"results\":[{\"id\":\"last\",\"comment\":\"Done\",\"created_at\":\"2026-09-28T12:00:00Z\"}]}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListWorkItemCommentsPageAsync(WorkItemKind.task, 203);

            Assert.Equal(1, page.Total);
            Assert.Null(page.NextPage);
            Assert.False(page.HasMore);
        }
    }

    [Fact]
    public async Task ListWorkItemCommentsPage_TreatsMalformedBodyMetadataAsUnknown()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/history/epic/301",
                "{\"count\":\"three\",\"next\":\"not-a-page\",\"results\":[{\"id\":\"visible\",\"comment\":\"Kept\",\"created_at\":\"2026-09-28T12:00:00Z\"}]}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListWorkItemCommentsPageAsync(WorkItemKind.epic, 301);

            Assert.Single(page.Items);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Fact]
    public async Task ListWorkItemCommentsPage_TreatsConflictingHeaderAndBodyMetadataAsUnknown()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/history/task/203",
                "{\"count\":4,\"next\":\"https://fake.taiga.test/api/v1/history/task/203?type=comment&page=3\",\"results\":[]}",
                headers: new Dictionary<string, string>
                {
                    ["x-pagination-count"] = "3",
                    ["x-pagination-next"] = "2",
                    ["x-paginated"] = "true"
                });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListWorkItemCommentsPageAsync(WorkItemKind.task, 203);

            Assert.Empty(page.Items);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.True(page.HasMore);
        }
    }

    [Fact]
    public async Task ListWorkItemCommentsPage_RejectsMalformedVisibleRequiredData()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/history/issue/42",
                "[{\"id\":\"visible\",\"comment\":\"Missing timestamp\"}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).ListWorkItemCommentsPageAsync(WorkItemKind.issue, 42));

            Assert.Contains("created_at", exception.Message);
        }
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(42, 0)]
    public async Task ListWorkItemCommentsPage_RejectsInvalidInputsBeforeHttp(int id, int page)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).ListWorkItemCommentsPageAsync(WorkItemKind.issue, id, page));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListWorkItemCommentsPage_RejectsUndefinedKindBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).ListWorkItemCommentsPageAsync((WorkItemKind)99, 42));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListWorkItemCommentsPage_PropagatesPermissionFailureSafely()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/history/epic/301",
                "{\"detail\":\"history secret\"}",
                HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).ListWorkItemCommentsPageAsync(WorkItemKind.epic, 301));

            Assert.Contains("403", exception.Message);
            Assert.Contains("permission denied", exception.Message);
            Assert.DoesNotContain("history secret", exception.Message);
        }
    }

    [Fact]
    public async Task ListWorkItemCommentsPage_PropagatesPreCancellationWithoutHttp()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/history/issue/42", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                NewApi(handler, auth).ListWorkItemCommentsPageAsync(
                    WorkItemKind.issue,
                    42,
                    cancellationToken: cancellation.Token));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListWorkItemCommentsPage_DisposesResponseAfterMapping()
    {
        var content = new TrackingContent("[{\"id\":\"entry\",\"comment\":\"Read\",\"created_at\":\"2026-09-28T12:00:00Z\"}]");
        var handler = new FakeHttpMessageHandler()
            .AddRoute(
                HttpMethod.Get,
                "/api/v1/history/issue/42",
                _ => new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListWorkItemCommentsPageAsync(WorkItemKind.issue, 42);

            Assert.True(content.Disposed);
            Assert.Equal("entry", Assert.Single(page.Items).Id);
        }
    }

    private static WorkItemHistoryApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
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
