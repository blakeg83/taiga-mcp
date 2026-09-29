using System.Net;
using System.Text;
using TaigaMCP.Api;
using TaigaMCP.Caching;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class TransportTests
{
    [Theory]
    [InlineData(400)]
    [InlineData(401)]
    [InlineData(403)]
    [InlineData(404)]
    [InlineData(409)]
    [InlineData(429)]
    [InlineData(500)]
    public async Task ReadAsync_Error_PreservesStatusAndSafeDetailsAndDisposes(int status)
    {
        var contents = new List<TrackingContent>();
        var handler = new FakeHttpMessageHandler().AddRoute(HttpMethod.Get, "/api/v1/test", _ =>
        {
            var content = new TrackingContent("""{"version":["secret synthetic-token"],"password":"do-not-expose"}""");
            contents.Add(content);
            return new HttpResponseMessage((HttpStatusCode)status) { Content = content };
        }).AddJsonRoute(HttpMethod.Post, "/api/v1/auth/refresh", "{}", HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(HttpMethod.Get, "test"))
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() => new TaigaTransport(new TestHttpClientFactory(handler), auth).ReadAsync(request));
            Assert.Equal((HttpStatusCode)status, error.StatusCode);
            Assert.Contains("version: rejected", error.Message);
            Assert.DoesNotContain("secret", error.Message);
            Assert.DoesNotContain("synthetic-token", error.Message);
            Assert.DoesNotContain("do-not-expose", error.Message);
            Assert.All(contents, content => Assert.True(content.Disposed));
        }
    }

    [Theory]
    [InlineData("GET")]
    [InlineData("POST")]
    [InlineData("PATCH")]
    public async Task ReadAsync_Success_DisposesResponseAndLeavesOwnedDocumentUsable(string method)
    {
        var content = new TrackingContent("{\"id\":42}");
        var handler = new FakeHttpMessageHandler().AddRoute(new HttpMethod(method), "/api/v1/test",
            _ => new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(new HttpMethod(method), "test"))
        using (var doc = await new TaigaTransport(new TestHttpClientFactory(handler), auth).ReadAsync(request))
        {
            Assert.True(content.Disposed);
            Assert.Equal(42, doc.RootElement.GetProperty("id").GetInt32());
        }
    }

    [Theory]
    [InlineData("GET", "invalid JSON")]
    [InlineData("POST", "may already have applied")]
    [InlineData("PATCH", "may already have applied")]
    public async Task ReadAsync_MalformedResponse_ReportsWriteUncertainty(string method, string message)
    {
        var content = new TrackingContent("not json");
        var handler = new FakeHttpMessageHandler().AddRoute(new HttpMethod(method), "/api/v1/test",
            _ => new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(new HttpMethod(method), "test"))
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() => new TaigaTransport(new TestHttpClientFactory(handler), auth).ReadAsync(request));
            Assert.Contains(message, error.Message);
            Assert.True(content.Disposed);
        }
    }

    [Fact]
    public async Task ReadAsync_Cancelled_DoesNotBecomeUpstreamError()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(HttpMethod.Get, "test"))
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => new TaigaTransport(new TestHttpClientFactory(handler), auth).ReadAsync(request, cancellation.Token));
            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task UpdateIssueAsync_EnrichmentFails_ReportsAppliedWriteWithoutRetry()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/issues/42", "{\"id\":42,\"project\":123}")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-statuses", "{}", HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
            var api = new IssueApi(transport, new IssueMetadataCache(transport));
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() => api.UpdateIssueAsync(42, 3, subject: "Change"));
            Assert.Contains("may already have applied", error.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Fact]
    public async Task ReadAsync_OversizedError_ReadsAtMost4096Bytes()
    {
        var stream = new ObservedStream(new byte[20000]);
        var handler = new FakeHttpMessageHandler().AddRoute(HttpMethod.Get, "/api/v1/test", _ =>
            new HttpResponseMessage(HttpStatusCode.BadRequest) { Content = new StreamContent(stream) });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(HttpMethod.Get, "test"))
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() => new TaigaTransport(new TestHttpClientFactory(handler), auth).ReadAsync(request));
            Assert.Equal(HttpStatusCode.BadRequest, error.StatusCode);
            Assert.Equal(4096, stream.BytesRead);
            Assert.True(stream.Disposed);
            Assert.True(error.Message.Length < 200);
        }
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task ReadAsync_WriteResponseReadFailsOrCancels_ReportsUncertainty(bool cancel)
    {
        using var cancellation = new CancellationTokenSource();
        var stream = new ObservedStream([], () =>
        {
            if (cancel)
            {
                cancellation.Cancel();
                cancellation.Token.ThrowIfCancellationRequested();
            }
            throw new IOException("unsafe upstream text");
        });
        var handler = new FakeHttpMessageHandler().AddRoute(HttpMethod.Patch, "/api/v1/test", _ =>
            new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(stream) });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(HttpMethod.Patch, "test"))
        {
            var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
            var error = cancel
                ? await Assert.ThrowsAnyAsync<OperationCanceledException>(() => transport.ReadAsync(request, cancellation.Token))
                : (Exception)await Assert.ThrowsAsync<TaigaRequestException>(() => transport.ReadAsync(request));
            Assert.Contains("may already have applied", error.Message);
            Assert.DoesNotContain("unsafe", error.Message);
            Assert.True(stream.Disposed);
        }
    }

    [Fact]
    public async Task SendNoContentAsync_204DoesNotParseBodyAndDisposesResponse()
    {
        var content = new TrackingContent("not JSON");
        var handler = new FakeHttpMessageHandler().AddRoute(HttpMethod.Delete, "/api/v1/test", _ =>
            new HttpResponseMessage(HttpStatusCode.NoContent) { Content = content });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(HttpMethod.Delete, "test"))
        {
            await new TaigaTransport(new TestHttpClientFactory(handler), auth).SendNoContentAsync(request);

            Assert.True(content.Disposed);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Delete);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    [InlineData(HttpStatusCode.NotFound, "resource not found")]
    public async Task SendNoContentAsync_ErrorPreservesSafeStatusAndDisposes(
        HttpStatusCode statusCode,
        string category)
    {
        var content = new TrackingContent("{\"detail\":\"secret synthetic error\"}");
        var handler = new FakeHttpMessageHandler().AddRoute(HttpMethod.Delete, "/api/v1/test", _ =>
            new HttpResponseMessage(statusCode) { Content = content });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(HttpMethod.Delete, "test"))
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                new TaigaTransport(new TestHttpClientFactory(handler), auth).SendNoContentAsync(request));

            Assert.Equal(statusCode, error.StatusCode);
            Assert.Contains(category, error.Message);
            Assert.DoesNotContain("secret synthetic error", error.Message);
            Assert.True(content.Disposed);
        }
    }

    [Fact]
    public async Task SendNoContentAsync_UnexpectedSuccessfulStatusReportsPotentiallyApplied()
    {
        var content = new TrackingContent("{\"removed\":true}");
        var handler = new FakeHttpMessageHandler().AddRoute(HttpMethod.Delete, "/api/v1/test", _ =>
            new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(HttpMethod.Delete, "test"))
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                new TaigaTransport(new TestHttpClientFactory(handler), auth).SendNoContentAsync(request));

            Assert.Equal(HttpStatusCode.OK, error.StatusCode);
            Assert.Contains("unexpected HTTP 200", error.Message);
            Assert.Contains("may already have applied", error.Message);
            Assert.True(content.Disposed);
        }
    }

    [Fact]
    public async Task SendNoContentAsync_Received401ReplaysOnceThenAccepts204()
    {
        var unauthorized = new TrackingContent("{\"detail\":\"expired\"}");
        var success = new TrackingContent(string.Empty);
        var attempts = 0;
        var handler = new FakeHttpMessageHandler()
            .AddRoute(HttpMethod.Delete, "/api/v1/test", _ =>
            {
                attempts++;
                return attempts == 1
                    ? new HttpResponseMessage(HttpStatusCode.Unauthorized) { Content = unauthorized }
                    : new HttpResponseMessage(HttpStatusCode.NoContent) { Content = success };
            })
            .AddJsonRoute(HttpMethod.Post, "/api/v1/auth/refresh", "{\"auth_token\":\"replayed-token\",\"refresh\":\"next-refresh\"}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(HttpMethod.Delete, "test"))
        {
            await new TaigaTransport(new TestHttpClientFactory(handler), auth).SendNoContentAsync(request);

            Assert.Equal(2, attempts);
            Assert.True(unauthorized.Disposed);
            Assert.True(success.Disposed);
            Assert.Equal(2, handler.Requests.Count(item => item.Method == HttpMethod.Delete));
        }
    }

    [Fact]
    public async Task SendNoContentAsync_Repeated401StopsAfterOneReplayAndDisposesResponses()
    {
        var firstUnauthorized = new TrackingContent("{\"detail\":\"expired\"}");
        var secondUnauthorized = new TrackingContent("{\"detail\":\"still expired\"}");
        var attempts = 0;
        var handler = new FakeHttpMessageHandler()
            .AddRoute(HttpMethod.Delete, "/api/v1/test", _ =>
            {
                attempts++;
                var content = attempts == 1 ? firstUnauthorized : secondUnauthorized;
                return new HttpResponseMessage(HttpStatusCode.Unauthorized) { Content = content };
            })
            .AddJsonRoute(HttpMethod.Post, "/api/v1/auth/refresh", "{\"auth_token\":\"replayed-token\",\"refresh\":\"next-refresh\"}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(HttpMethod.Delete, "test"))
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                new TaigaTransport(new TestHttpClientFactory(handler), auth).SendNoContentAsync(request));

            Assert.Equal(HttpStatusCode.Unauthorized, error.StatusCode);
            Assert.Equal(2, attempts);
            Assert.True(firstUnauthorized.Disposed);
            Assert.True(secondUnauthorized.Disposed);
        }
    }

    [Fact]
    public async Task SendNoContentAsync_CancellationPropagatesWithoutUpstreamError()
    {
        var handler = new FakeHttpMessageHandler().AddRoute(HttpMethod.Delete, "/api/v1/test", _ =>
            throw new OperationCanceledException());
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(HttpMethod.Delete, "test"))
        {
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                new TaigaTransport(new TestHttpClientFactory(handler), auth).SendNoContentAsync(request));
        }
    }

    [Fact]
    public async Task SendNoContentAsync_TransportFailureReportsPotentiallyAppliedWithoutRetry()
    {
        var handler = new FakeHttpMessageHandler()
            .AddExceptionRoute(HttpMethod.Delete, "/api/v1/test", new IOException("secret transport details"));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var request = new HttpRequestMessage(HttpMethod.Delete, "test"))
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                new TaigaTransport(new TestHttpClientFactory(handler), auth).SendNoContentAsync(request));

            Assert.Contains("may already have applied", error.Message);
            Assert.DoesNotContain("secret transport details", error.Message);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Delete);
        }
    }

    private sealed class ObservedStream(byte[] bytes, Action? beforeRead = null) : MemoryStream(bytes)
    {
        public int BytesRead { get; private set; }
        public bool Disposed { get; private set; }
        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            beforeRead?.Invoke();
            var count = await base.ReadAsync(buffer, cancellationToken);
            BytesRead += count;
            return count;
        }
        protected override void Dispose(bool disposing)
        {
            Disposed = true;
            base.Dispose(disposing);
        }
    }
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
