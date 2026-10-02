using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemAttachmentDeleteApiTests
{
    [Theory]
    [InlineData("epic", "/api/v1/epics/attachments/901")]
    [InlineData("user_story", "/api/v1/userstories/attachments/901")]
    [InlineData("task", "/api/v1/tasks/attachments/901")]
    public async Task DeleteAsync_UsesKindSpecificRouteAndReturnsReceipt(string kind, string path)
    {
        var handler = new FakeHttpMessageHandler().AddRoute(
            HttpMethod.Delete,
            path,
            _ => new HttpResponseMessage(HttpStatusCode.NoContent));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var receipt = await NewApi(handler, auth).DeleteAsync(kind, 901);

            Assert.Equal(kind, receipt.Kind);
            Assert.Equal(901, receipt.AttachmentId);
            Assert.True(receipt.Deleted);
            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Delete);
            Assert.Equal(path, request.Uri.AbsolutePath);
            Assert.DoesNotContain(handler.Requests, item =>
                item.Method == HttpMethod.Get ||
                item.Method == HttpMethod.Patch ||
                (item.Method == HttpMethod.Post && item.Uri.AbsolutePath != "/api/v1/auth"));
        }
    }

    [Theory]
    [InlineData("issue", 901)]
    [InlineData("task", 0)]
    public async Task DeleteAsync_RejectsInvalidInputBeforeHttp(string kind, int attachmentId)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).DeleteAsync(kind, attachmentId));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task DeleteTool_ReturnsSnakeCaseReceipt()
    {
        var handler = new FakeHttpMessageHandler().AddRoute(
            HttpMethod.Delete,
            "/api/v1/tasks/attachments/901",
            _ => new HttpResponseMessage(HttpStatusCode.NoContent));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var json = JsonSerializer.Deserialize<JsonElement>(await new WorkItemAttachmentTools(NewApi(handler, auth))
                .DeleteWorkItemAttachment("task", 901));

            Assert.Equal("task", json.GetProperty("kind").GetString());
            Assert.Equal(901, json.GetProperty("attachment_id").GetInt32());
            Assert.True(json.GetProperty("deleted").GetBoolean());
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    [InlineData(HttpStatusCode.NotFound, "resource not found")]
    [InlineData(HttpStatusCode.InternalServerError, "upstream failure")]
    public async Task DeleteAsync_ReportsSafeHttpFailuresWithoutRetry(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler().AddTextRoute(
            HttpMethod.Delete,
            "/api/v1/tasks/attachments/901",
            "{\"detail\":\"attachment deletion secret\"}",
            statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).DeleteAsync("task", 901));

            Assert.Equal(statusCode, error.StatusCode);
            Assert.Contains(((int)statusCode).ToString(), error.Message);
            Assert.Contains(category, error.Message);
            Assert.DoesNotContain("attachment deletion secret", error.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Delete);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.OK)]
    [InlineData(HttpStatusCode.Created)]
    [InlineData(HttpStatusCode.Accepted)]
    public async Task DeleteAsync_RejectsUnexpectedSuccessfulStatusAsPotentiallyApplied(HttpStatusCode statusCode)
    {
        var handler = new FakeHttpMessageHandler().AddTextRoute(
            HttpMethod.Delete,
            "/api/v1/tasks/attachments/901",
            "{\"deleted\":true}",
            statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).DeleteAsync("task", 901));

            Assert.Equal(statusCode, error.StatusCode);
            Assert.Contains($"unexpected HTTP {(int)statusCode}", error.Message);
            Assert.Contains("attachment", error.Message);
            Assert.Contains("may already have applied", error.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Delete);
        }
    }

    [Fact]
    public async Task DeleteAsync_ReplaysOnlyAReceivedUnauthorizedResponse()
    {
        var deleteAttempts = 0;
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/auth/refresh",
                "{\"auth_token\":\"replacement-token\",\"refresh\":\"replacement-refresh\"}")
            .AddRoute(
                HttpMethod.Delete,
                "/api/v1/tasks/attachments/901",
                _ => Interlocked.Increment(ref deleteAttempts) == 1
                    ? new HttpResponseMessage(HttpStatusCode.Unauthorized)
                    : new HttpResponseMessage(HttpStatusCode.NoContent));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var receipt = await NewApi(handler, auth).DeleteAsync("task", 901);

            Assert.True(receipt.Deleted);
            Assert.Equal(2, deleteAttempts);
            Assert.Equal(2, handler.Requests.Count(request => request.Method == HttpMethod.Delete));
        }
    }

    [Fact]
    public async Task DeleteAsync_DoesNotRetryAmbiguousTransportFailure()
    {
        var handler = new FakeHttpMessageHandler().AddExceptionRoute(
            HttpMethod.Delete,
            "/api/v1/tasks/attachments/901",
            new HttpRequestException("synthetic deletion transport secret"));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).DeleteAsync("task", 901));

            Assert.Contains("attachment write", error.Message);
            Assert.Contains("may already have applied", error.Message);
            Assert.DoesNotContain("synthetic deletion transport secret", error.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Delete);
        }
    }

    [Fact]
    public async Task DeleteAsync_PropagatesCancellationBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler().AddRoute(
            HttpMethod.Delete,
            "/api/v1/tasks/attachments/901",
            _ => new HttpResponseMessage(HttpStatusCode.NoContent));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                NewApi(handler, auth).DeleteAsync("task", 901, cancellation.Token));

            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath != "/api/v1/auth");
        }
    }

    [Fact]
    public async Task DeleteAsync_Confirms204AndDisposesResponseWithoutParsingBody()
    {
        var content = new TrackingContent("not JSON");
        var handler = new FakeHttpMessageHandler().AddRoute(
            HttpMethod.Delete,
            "/api/v1/tasks/attachments/901",
            _ => new HttpResponseMessage(HttpStatusCode.NoContent) { Content = content });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var receipt = await NewApi(handler, auth).DeleteAsync("task", 901);

            Assert.True(receipt.Deleted);
            Assert.True(content.Disposed);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Delete);
        }
    }

    private static WorkItemAttachmentApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private sealed class TrackingContent(string body) : StringContent(body)
    {
        public bool Disposed { get; private set; }

        protected override void Dispose(bool disposing)
        {
            Disposed = true;
            base.Dispose(disposing);
        }
    }
}
