using System.Net;
using System.Text;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class UserIdentityTests
{
    [Fact]
    public async Task GetCurrentUserAsync_MapsAllowlistedFieldsAndUsesUsersMe()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/users/me", UserIdentityFixtures.AdminWithPrivateFields);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var identity = await api.GetCurrentUserAsync();

            Assert.Equal(new UserIdentityDto
            {
                Id = 42,
                Username = "synthetic-user",
                FullName = "Synthetic User",
                IsActive = true
            }, identity);
            var request = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Get && request.Uri.AbsolutePath == "/api/v1/users/me");
            Assert.Equal("Bearer synthetic-token", request.Headers["Authorization"].Single());
            Assert.DoesNotContain("email", JsonSerializer.Serialize(identity));
            Assert.DoesNotContain("auth_token", JsonSerializer.Serialize(identity));
            Assert.DoesNotContain("roles", JsonSerializer.Serialize(identity));
            Assert.DoesNotContain("uuid", JsonSerializer.Serialize(identity));
        }
    }

    [Fact]
    public async Task GetCurrentUserAsync_PreservesMissingOptionalFieldsAsNull()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/users/me", UserIdentityFixtures.Minimal);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var identity = await new UserApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)).GetCurrentUserAsync();

            Assert.Equal(42, identity.Id);
            Assert.Null(identity.Username);
            Assert.Null(identity.FullName);
            Assert.Null(identity.IsActive);
        }
    }

    [Theory]
    [MemberData(nameof(InvalidIdentityResponses))]
    public async Task GetCurrentUserAsync_RejectsInvalidIdentity(string responseBody)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/users/me", responseBody);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                new UserApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)).GetCurrentUserAsync());

            Assert.DoesNotContain("synthetic", exception.Message, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public async Task GetCurrentUserAsync_PropagatesSafeHttpError()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/users/me", "{\"detail\":\"private synthetic failure\"}", HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                new UserApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)).GetCurrentUserAsync());

            Assert.Equal(HttpStatusCode.Forbidden, exception.StatusCode);
            Assert.Contains("permission denied", exception.Message);
            Assert.DoesNotContain("private synthetic failure", exception.Message);
        }
    }

    [Fact]
    public async Task GetCurrentUserAsync_ReplaysOnlyReceived401WithRefreshedToken()
    {
        var userRequests = 0;
        var handler = new FakeHttpMessageHandler()
            .AddRoute(HttpMethod.Get, "/api/v1/users/me", _ =>
                Interlocked.Increment(ref userRequests) == 1
                    ? new HttpResponseMessage(HttpStatusCode.Unauthorized)
                    : new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent(UserIdentityFixtures.Populated, Encoding.UTF8, "application/json")
                    })
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/auth/refresh",
                "{\"auth_token\":\"refreshed-token\",\"refresh\":\"next-refresh\"}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var identity = await new UserApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)).GetCurrentUserAsync();

            Assert.Equal(42, identity.Id);
            var requests = handler.Requests
                .Where(request => request.Method == HttpMethod.Get && request.Uri.AbsolutePath == "/api/v1/users/me")
                .ToArray();
            Assert.Equal(2, requests.Length);
            Assert.Equal("Bearer synthetic-token", requests[0].Headers["Authorization"].Single());
            Assert.Equal("Bearer refreshed-token", requests[1].Headers["Authorization"].Single());
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Post && request.Uri.AbsolutePath == "/api/v1/auth/refresh");
        }
    }

    [Fact]
    public async Task GetCurrentUserAsync_CancellationStopsBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                new UserApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)).GetCurrentUserAsync(cancellation.Token));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task GetCurrentUserAsync_DisposesResponseWhileReturningOwnedIdentity()
    {
        var content = new TrackingContent(UserIdentityFixtures.Populated);
        var handler = new FakeHttpMessageHandler()
            .AddRoute(HttpMethod.Get, "/api/v1/users/me", _ => new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var identity = await new UserApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)).GetCurrentUserAsync();

            Assert.True(content.Disposed);
            Assert.Equal(42, identity.Id);
            Assert.Equal("synthetic-user", identity.Username);
        }
    }

    public static IEnumerable<object[]> InvalidIdentityResponses()
    {
        yield return [UserIdentityFixtures.MissingId];
        yield return [UserIdentityFixtures.NonPositiveId];
        yield return [UserIdentityFixtures.WrongIdType];
        yield return [UserIdentityFixtures.Malformed];
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
