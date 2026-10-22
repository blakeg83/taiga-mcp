using System.Net;
using System.Text;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class UserStoryEstimateTests
{
    [Fact]
    public async Task SetUserStoryEstimatesAsync_SendsOneRoleMappingAndReturnsAuthoritativeState()
    {
        var handler = CreateEstimateHandler(
            """
            {"id":102,"ref":18,"project":123,"subject":"Estimated story","status":7,"status_extra_info":{"name":"Ready"},"points":{"7":22,"8":21},"total_points":5.5,"version":8}
            """);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var story = await NewApi(handler, auth).SetUserStoryEstimatesAsync(
                102,
                version: 7,
                [new UserStoryEstimateEntry { RoleId = 7, PointId = 22 }]);

            Assert.Equal(8, story.Version);
            Assert.Equal(22, story.Points![7]);
            Assert.Equal(21, story.Points[8]);
            Assert.Equal(5.5, story.TotalPoints);

            var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            using var body = JsonDocument.Parse(patch.Body);
            AssertPatchProperties(body.RootElement, "points", "version");
            Assert.Equal(7, body.RootElement.GetProperty("version").GetInt32());
            var points = body.RootElement.GetProperty("points");
            Assert.Equal(22, points.GetProperty("7").GetInt32());
            Assert.Single(points.EnumerateObject());
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Get);
        }
    }

    [Fact]
    public async Task SetUserStoryEstimatesAsync_SendsMultipleRolesIncludingUnestimatedPointOption()
    {
        var handler = CreateEstimateHandler(
            """
            {"id":102,"ref":18,"project":123,"subject":"Estimated story","status":7,"status_extra_info":{"name":"Ready"},"points":{"7":21,"8":22},"total_points":null,"version":8}
            """);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var story = await NewApi(handler, auth).SetUserStoryEstimatesAsync(
                102,
                version: 7,
                [
                    new UserStoryEstimateEntry { RoleId = 7, PointId = 21 },
                    new UserStoryEstimateEntry { RoleId = 8, PointId = 22 }
                ]);

            Assert.Null(story.TotalPoints);
            using var body = JsonDocument.Parse(Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch).Body);
            var points = body.RootElement.GetProperty("points");
            Assert.Equal(21, points.GetProperty("7").GetInt32());
            Assert.Equal(22, points.GetProperty("8").GetInt32());
            Assert.Equal(2, points.EnumerateObject().Count());
        }
    }

    [Theory]
    [InlineData("story", 0, 7, 22)]
    [InlineData("version", 102, -1, 22)]
    [InlineData("role", 102, 7, 22)]
    [InlineData("point", 102, 7, 0)]
    public async Task SetUserStoryEstimatesAsync_RejectsInvalidIdsBeforeHttp(
        string scenario,
        int userStoryId,
        int version,
        int pointId)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var entry = new UserStoryEstimateEntry
            {
                RoleId = scenario == "role" ? 0 : 7,
                PointId = pointId
            };

            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).SetUserStoryEstimatesAsync(
                userStoryId,
                version,
                [entry]));

            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Fact]
    public async Task SetUserStoryEstimatesAsync_RejectsEmptyNullAndDuplicateRoleEntriesBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            await Assert.ThrowsAsync<ArgumentException>(() => api.SetUserStoryEstimatesAsync(102, 7, []));
            await Assert.ThrowsAsync<ArgumentException>(() => api.SetUserStoryEstimatesAsync(102, 7, [null!]));
            await Assert.ThrowsAsync<ArgumentException>(() => api.SetUserStoryEstimatesAsync(
                102,
                7,
                [
                    new UserStoryEstimateEntry { RoleId = 7, PointId = 21 },
                    new UserStoryEstimateEntry { RoleId = 7, PointId = 22 }
                ]));

            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Conflict, "409", "version")]
    [InlineData(HttpStatusCode.Forbidden, "403", "permission denied")]
    public async Task SetUserStoryEstimatesAsync_PropagatesSafeHttpFailuresWithoutRetry(
        HttpStatusCode statusCode,
        string expectedStatus,
        string expectedCategory)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Patch,
                "/api/v1/userstories/102",
                statusCode == HttpStatusCode.Conflict
                    ? "{\"detail\":\"Version conflict synthetic-token\"}"
                    : "{\"detail\":\"synthetic estimate secret\"}",
                statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).SetUserStoryEstimatesAsync(
                102,
                7,
                [new UserStoryEstimateEntry { RoleId = 7, PointId = 21 }]));

            Assert.Contains(expectedStatus, exception.Message);
            Assert.Contains(expectedCategory, exception.Message, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic-token", exception.Message);
            Assert.DoesNotContain("synthetic estimate secret", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Get);
        }
    }

    [Fact]
    public async Task SetUserStoryEstimatesAsync_ReportsMalformedSuccessAsPotentiallyApplied()
    {
        var handler = CreateEstimateHandler("{\"id\":102,\"version\":8,\"points\":{\"bad\":21}}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).SetUserStoryEstimatesAsync(
                102,
                7,
                [new UserStoryEstimateEntry { RoleId = 7, PointId = 21 }]));

            Assert.Contains("may already have applied", exception.Message);
            Assert.Contains("role id", exception.Message, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("bad", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Theory]
    [InlineData("missing", "{\"id\":102,\"version\":8}")]
    [InlineData("null", "{\"id\":102,\"version\":8,\"points\":null}")]
    [InlineData("mismatched-id", "{\"id\":103,\"version\":8,\"points\":{\"7\":21}}")]
    public async Task SetUserStoryEstimatesAsync_RejectsUnreliableAuthoritativeSuccess(
        string scenario,
        string response)
    {
        var handler = CreateEstimateHandler(response);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).SetUserStoryEstimatesAsync(
                102,
                7,
                [new UserStoryEstimateEntry { RoleId = 7, PointId = 21 }]));

            Assert.Contains("may already have applied", exception.Message);
            Assert.Contains(
                scenario == "mismatched-id" ? "identity" : "points",
                exception.Message,
                StringComparison.OrdinalIgnoreCase);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    private static UserStoryApi NewApi(FakeHttpMessageHandler handler, TaigaMCP.Api.AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private static FakeHttpMessageHandler CreateEstimateHandler(string response)
        => new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/userstories/102", response);

    private static void AssertPatchProperties(JsonElement body, params string[] expectedNames)
    {
        var actualNames = body.EnumerateObject().Select(property => property.Name);
        Assert.Equal(
            expectedNames.OrderBy(name => name, StringComparer.Ordinal),
            actualNames.OrderBy(name => name, StringComparer.Ordinal));
    }
}
