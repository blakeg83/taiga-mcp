using System.Net;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using TaigaMCP.Api;
using TaigaMCP.Config;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class AuthenticationTests
{
    private static AuthClient CreateAuth() => new(Options.Create(new TaigaOptions
    {
        Username = "synthetic-user",
        Password = "synthetic-password"
    }), NullLogger<AuthClient>.Instance);

    [Fact]
    public async Task SendAsync_ConcurrentInitialCalls_OneLoginAndCancellableGate()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var logins = 0;
        using var handler = new AsyncHttpHandler(async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/auth"))
            {
                Assert.Null(request.Headers.Authorization);
                Interlocked.Increment(ref logins);
                entered.SetResult();
                await release.Task.WaitAsync(token);
                return Json("{\"auth_token\":\"first\",\"refresh\":\"refresh\"}");
            }
            Assert.Equal("first", request.Headers.Authorization!.Parameter);
            return Json("{}");
        });
        using var http = new TestHttpClientFactory(handler).CreateClient("taiga");
        using var auth = CreateAuth();
        async Task Send(CancellationToken token = default)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "projects");
            using var response = await auth.SendAsync(http, request, token);
        }
        var first = Send();
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var others = Enumerable.Range(0, 10).Select(_ => Send()).ToArray();
        using var cancellation = new CancellationTokenSource();
        var cancelled = Send(cancellation.Token);
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => cancelled);
        release.SetResult();
        await Task.WhenAll(others.Append(first)).WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(1, logins);
        Assert.Null(http.DefaultRequestHeaders.Authorization);
    }

    [Fact]
    public async Task SendAsync_Simultaneous401s_RefreshOnceAndReuseReplacement()
    {
        var bothRejected = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var rejected = 0;
        var refreshes = 0;
        var logins = 0;
        using var handler = new AsyncHttpHandler(async (request, token) =>
        {
            var path = request.RequestUri!.AbsolutePath;
            if (path.EndsWith("/auth"))
            {
                Interlocked.Increment(ref logins);
                return Json("{\"auth_token\":\"old\",\"refresh\":\"r\"}");
            }
            if (path.EndsWith("/auth/refresh"))
            {
                Assert.Null(request.Headers.Authorization);
                Interlocked.Increment(ref refreshes);
                return Json("{\"auth_token\":\"new\",\"refresh\":\"r2\"}");
            }
            if (request.Headers.Authorization!.Parameter == "old")
            {
                if (Interlocked.Increment(ref rejected) == 2) bothRejected.SetResult();
                await bothRejected.Task.WaitAsync(token);
                return new HttpResponseMessage(HttpStatusCode.Unauthorized);
            }
            Assert.Equal("new", request.Headers.Authorization.Parameter);
            return Json("{}");
        });
        using var http = new TestHttpClientFactory(handler).CreateClient("taiga");
        using var auth = CreateAuth();
        async Task Send()
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "projects");
            using var response = await auth.SendAsync(http, request);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }
        await Task.WhenAll(Send(), Send()).WaitAsync(TimeSpan.FromSeconds(5));
        await Send();
        Assert.Equal(1, logins);
        Assert.Equal(1, refreshes);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task SendAsync_RefreshRejected_FallsBackAndReplaysPatchAtMostOnce(bool repeated401)
    {
        var logins = 0;
        var patches = 0;
        using var handler = new AsyncHttpHandler(async (request, token) =>
        {
            var path = request.RequestUri!.AbsolutePath;
            if (path.EndsWith("/auth"))
            {
                Assert.Null(request.Headers.Authorization);
                return Json($"{{\"auth_token\":\"t{++logins}\",\"refresh\":\"r\"}}");
            }
            if (path.EndsWith("/auth/refresh"))
            {
                Assert.Null(request.Headers.Authorization);
                return new HttpResponseMessage(HttpStatusCode.Forbidden);
            }
            patches++;
            Assert.Equal(HttpMethod.Patch, request.Method);
            Assert.Equal("{\"version\":7,\"description\":\"\"}", await request.Content!.ReadAsStringAsync(token));
            Assert.Equal("application/json", request.Content.Headers.ContentType!.MediaType);
            Assert.Equal("retained", request.Headers.GetValues("X-Test").Single());
            Assert.True(request.Options.TryGetValue(new HttpRequestOptionsKey<string>("test"), out var option));
            Assert.Equal("value", option);
            Assert.Equal(HttpVersion.Version20, request.Version);
            Assert.Equal(HttpVersionPolicy.RequestVersionOrLower, request.VersionPolicy);
            return patches == 1 || repeated401 ? new HttpResponseMessage(HttpStatusCode.Unauthorized) : Json("{}");
        });
        using var http = new TestHttpClientFactory(handler).CreateClient("taiga");
        using var auth = CreateAuth();
        using var request = new HttpRequestMessage(HttpMethod.Patch, "issues/42")
        {
            Content = new StringContent("{\"version\":7,\"description\":\"\"}", Encoding.UTF8, "application/json"),
            Version = HttpVersion.Version20,
            VersionPolicy = HttpVersionPolicy.RequestVersionOrLower
        };
        request.Headers.Add("X-Test", "retained");
        request.Options.Set(new HttpRequestOptionsKey<string>("test"), "value");
        using var response = await auth.SendAsync(http, request);
        Assert.Equal(repeated401 ? HttpStatusCode.Unauthorized : HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(2, logins);
        Assert.Equal(2, patches);
    }

    [Fact]
    public async Task SendAsync_AmbiguousPatchFailure_NeverReplays()
    {
        var writes = 0;
        using var handler = new AsyncHttpHandler((request, _) =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/auth")) return Task.FromResult(Json("{\"auth_token\":\"t\"}"));
            writes++;
            throw new HttpRequestException("connection lost");
        });
        using var auth = CreateAuth();
        var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
        using var request = new HttpRequestMessage(HttpMethod.Patch, "issues/42");
        var error = await Assert.ThrowsAsync<TaigaRequestException>(() => transport.ReadAsync(request));
        Assert.Contains("may already have applied", error.Message);
        Assert.Equal(1, writes);
    }

    internal static HttpResponseMessage Json(string json) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json")
    };
}

internal sealed class AsyncHttpHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => send(request, cancellationToken);
}
