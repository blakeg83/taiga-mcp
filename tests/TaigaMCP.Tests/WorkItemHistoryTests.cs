using System.Net;
using System.Text;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemHistoryTests
{
    [Fact]
    public async Task ListWorkItemHistoryPage_MapsVisibleEntriesAndRedactsDeletedCommentContent()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/history/issue/42", WorkItemHistoryFixtures.FullHistoryPage);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListWorkItemHistoryPageAsync(WorkItemKind.issue, 42);

            Assert.Equal(3, page.Items.Count);
            var change = page.Items[0];
            Assert.Equal("change-entry", change.Id);
            Assert.Equal(1, change.Type);
            Assert.Equal("2026-09-28T12:00:00Z", change.CreatedAt);
            Assert.Equal("kept", change.Diff!.Value.GetProperty("unknown_change").GetProperty("after").GetString());
            Assert.Equal("Done", change.ValuesDiff!.Value.GetProperty("status")[1].GetString());
            Assert.Null(change.Comment);

            var comment = page.Items[1];
            Assert.Equal("Visible **comment**", comment.Comment);
            Assert.Equal("2026-09-28T12:02:00Z", comment.EditCommentDate);

            var deleted = page.Items[2];
            Assert.True(deleted.CommentDeleted);
            Assert.Null(deleted.Comment);
            Assert.Equal("2026-09-28T12:03:00Z", deleted.DeleteCommentDate);
            Assert.Equal(9, deleted.DeleteCommentUser!.Id);
            Assert.Equal("Moderator", deleted.DeleteCommentUser.Name);
            Assert.Equal(2, deleted.Diff!.Value.GetProperty("status")[1].GetInt32());
            Assert.Equal("preserve", deleted.Diff.Value.GetProperty("nested").GetProperty("safe").GetString());
            Assert.True(deleted.ValuesDiff!.Value.GetProperty("nested").GetProperty("safe").GetBoolean());

            var serialized = JsonSerializer.Serialize(page.Items);
            Assert.DoesNotContain("deleted secret", serialized, StringComparison.Ordinal);
            Assert.DoesNotContain("comment_versions", serialized, StringComparison.Ordinal);
            Assert.DoesNotContain("comment_html", serialized, StringComparison.Ordinal);
            Assert.DoesNotContain("\"snapshot\":", serialized, StringComparison.Ordinal);
            Assert.DoesNotContain("\"values\":", serialized, StringComparison.Ordinal);
        }
    }

    [Theory]
    [InlineData(WorkItemKind.issue, 42, "issue")]
    [InlineData(WorkItemKind.user_story, 102, "userstory")]
    [InlineData(WorkItemKind.task, 203, "task")]
    [InlineData(WorkItemKind.epic, 301, "epic")]
    public async Task ListWorkItemHistoryPage_UsesFullHistoryRouteForEveryKind(
        WorkItemKind kind,
        int id,
        string route)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, $"/api/v1/history/{route}/{id}", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListWorkItemHistoryPageAsync(kind, id, page: 2);

            Assert.Empty(page.Items);
            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Get);
            Assert.Equal($"/api/v1/history/{route}/{id}", request.Uri.AbsolutePath);
            Assert.Equal("?page=2", request.Uri.Query);
        }
    }

    [Fact]
    public async Task ListWorkItemHistoryPage_UsesVerifiedBodyPaginationWhenHeadersAreAbsent()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/history/task/203",
                """
                {"count":3,"next":"https://fake.taiga.test/api/v1/history/task/203?page=2","results":[{"id":"entry","type":2,"created_at":"2026-09-28T12:00:00Z"}]}
                """);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListWorkItemHistoryPageAsync(WorkItemKind.task, 203);

            Assert.Equal(3, page.Total);
            Assert.Equal(2, page.NextPage);
            Assert.True(page.HasMore);
            Assert.Equal(2, Assert.Single(page.Items).Type);
        }
    }

    [Fact]
    public async Task ListWorkItemHistoryPage_RejectsMalformedRequiredData()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/history/issue/42",
                "[{\"id\":\"entry\",\"type\":\"change\",\"created_at\":\"2026-09-28T12:00:00Z\"}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).ListWorkItemHistoryPageAsync(WorkItemKind.issue, 42));

            Assert.Contains("type", exception.Message);
        }
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(42, 0)]
    public async Task ListWorkItemHistoryPage_RejectsInvalidInputsBeforeHttp(int id, int page)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).ListWorkItemHistoryPageAsync(WorkItemKind.issue, id, page));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListWorkItemHistoryPage_PropagatesPreCancellationWithoutHttp()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/history/issue/42", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                NewApi(handler, auth).ListWorkItemHistoryPageAsync(
                    WorkItemKind.issue,
                    42,
                    cancellationToken: cancellation.Token));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListWorkItemHistoryPage_DisposesResponseAfterMapping()
    {
        var content = new TrackingContent("[{\"id\":\"entry\",\"type\":1,\"created_at\":\"2026-09-28T12:00:00Z\"}]");
        var handler = new FakeHttpMessageHandler()
            .AddRoute(
                HttpMethod.Get,
                "/api/v1/history/issue/42",
                _ => new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListWorkItemHistoryPageAsync(WorkItemKind.issue, 42);

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
