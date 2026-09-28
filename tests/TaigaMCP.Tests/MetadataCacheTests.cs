using System.Net;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using TaigaMCP.Api;
using TaigaMCP.Caching;
using TaigaMCP.Config;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class MetadataCacheTests
{
    private static IssueMetadataCache Create(HttpMessageHandler handler, TimeProvider? clock = null)
    {
        var options = Options.Create(new TaigaOptions { Username = "synthetic", Password = "synthetic", MetadataTtlSeconds = 300 });
        return new IssueMetadataCache(new TaigaTransport(new TestHttpClientFactory(handler),
            new AuthClient(options, NullLogger<AuthClient>.Instance)), options, clock);
    }

    [Fact]
    public async Task GetStatusesAsync_HitExpiryAndCallerMutation_UsesImmutableSnapshots()
    {
        var calls = 0;
        using var handler = new AsyncHttpHandler((request, _) => Task.FromResult(
            request.RequestUri!.AbsolutePath.EndsWith("/auth") ? AuthenticationTests.Json("{\"auth_token\":\"t\"}") :
            AuthenticationTests.Json($"[{{\"id\":1,\"name\":\"Label {++calls}\"}}]")));
        var clock = new ManualClock();
        var cache = Create(handler, clock);
        var first = await cache.GetStatusesAsync(1);
        Assert.Same(first, await cache.GetStatusesAsync(1));
        var mutableView = Assert.IsAssignableFrom<IDictionary<int, string>>(first);
        Assert.Throws<NotSupportedException>(() => mutableView[1] = "mutated");
        clock.Advance(TimeSpan.FromMinutes(5));
        var next = await cache.GetStatusesAsync(1);
        Assert.Equal("Label 2", next[1]);
        Assert.Equal("Label 1", first[1]);
        Assert.Equal(2, calls);
    }

    [Fact]
    public async Task GetStatusesAsync_ConcurrentLoads_CoalescesAndIsolatesProjectsAndKinds()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        using var handler = new AsyncHttpHandler(async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/auth")) return AuthenticationTests.Json("{\"auth_token\":\"t\"}");
            Interlocked.Increment(ref calls);
            if (request.RequestUri.PathAndQuery.EndsWith("issue-statuses?project=1"))
            {
                entered.TrySetResult();
                await release.Task.WaitAsync(token);
            }
            return AuthenticationTests.Json("[{\"id\":1,\"name\":\"Open\"}]");
        });
        var cache = Create(handler);
        var first = cache.GetStatusesAsync(1);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var same = cache.GetStatusesAsync(1);
        await cache.GetStatusesAsync(2).WaitAsync(TimeSpan.FromSeconds(5));
        await cache.GetTypesAsync(1).WaitAsync(TimeSpan.FromSeconds(5));
        using var cancellation = new CancellationTokenSource();
        var waiter = cache.GetStatusesAsync(1, cancellation.Token);
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => waiter);
        release.SetResult();
        Assert.Same(await first, await same);
        Assert.Equal(3, calls);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task GetStatusesAsync_FailedOrCancelledLoad_AllowsRetry(bool cancel)
    {
        var calls = 0;
        using var cancellation = new CancellationTokenSource();
        using var handler = new AsyncHttpHandler((request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/auth")) return Task.FromResult(AuthenticationTests.Json("{\"auth_token\":\"t\"}"));
            if (++calls == 1)
            {
                if (cancel) { cancellation.Cancel(); token.ThrowIfCancellationRequested(); }
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
            }
            return Task.FromResult(AuthenticationTests.Json("[{\"id\":1,\"name\":\"Open\"}]"));
        });
        var cache = Create(handler);
        if (cancel) await Assert.ThrowsAnyAsync<OperationCanceledException>(() => cache.GetStatusesAsync(1, cancellation.Token));
        else await Assert.ThrowsAsync<TaigaRequestException>(() => cache.GetStatusesAsync(1));
        Assert.Equal("Open", (await cache.GetStatusesAsync(1))[1]);
        Assert.Equal(2, calls);
    }

    [Fact]
    public async Task GetStatusesAsync_ManyIdleProjects_EvictsOldEntries()
    {
        var calls = 0;
        using var handler = new AsyncHttpHandler((request, _) => Task.FromResult(
            request.RequestUri!.AbsolutePath.EndsWith("/auth") ? AuthenticationTests.Json("{\"auth_token\":\"t\"}") :
            AuthenticationTests.Json($"[{{\"id\":1,\"name\":\"{++calls}\"}}]")));
        var clock = new ManualClock();
        var cache = Create(handler, clock);
        for (var id = 1; id <= 257; id++)
        {
            await cache.GetStatusesAsync(id);
            clock.Advance(TimeSpan.FromMilliseconds(1));
        }
        await cache.GetStatusesAsync(1);
        Assert.Equal(258, calls);
    }

    private sealed class ManualClock : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.UnixEpoch;
        public override DateTimeOffset GetUtcNow() => _now;
        public void Advance(TimeSpan duration) => _now += duration;
    }
}
