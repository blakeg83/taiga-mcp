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
