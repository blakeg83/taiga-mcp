using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

internal static class EpicStoryLinkFixtures
{
    public const string Success = """
        {"epic":301,"user_story":102,"order":9001}
        """;

    public const string Duplicate = """
        {"non_field_errors":["The fields epic, user_story must make a unique set."]}
        """;

    public const string MissingLink = """
        {"detail":"Not found."}
        """;

    public const string PermissionDenied = """
        {"detail":"Permission denied."}
        """;

    public static JsonElement Parse(string json)
        => JsonDocument.Parse(json).RootElement.Clone();
}

public sealed class EpicStoryLinkFixtureTests
{
    [Fact]
    public void SuccessResponseUsesNestedLookupIdentifiersAndRelationshipOrder()
    {
        var response = EpicStoryLinkFixtures.Parse(EpicStoryLinkFixtures.Success);

        Assert.Equal(301, response.GetProperty("epic").GetInt32());
        Assert.Equal(102, response.GetProperty("user_story").GetInt32());
        Assert.Equal(9001, response.GetProperty("order").GetInt64());
    }

    [Fact]
    public void DuplicateResponseIsAValidationFailureRatherThanAnUnqualifiedNotFound()
    {
        var response = EpicStoryLinkFixtures.Parse(EpicStoryLinkFixtures.Duplicate);

        Assert.Equal(JsonValueKind.Array, response.GetProperty("non_field_errors").ValueKind);
        Assert.Contains("unique", response.GetProperty("non_field_errors")[0].GetString()!, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData(EpicStoryLinkFixtures.MissingLink, HttpStatusCode.NotFound)]
    [InlineData(EpicStoryLinkFixtures.PermissionDenied, HttpStatusCode.Forbidden)]
    public void MissingAndPermissionFixturesRetainTheirDistinctHttpSemantics(string body, HttpStatusCode statusCode)
    {
        using var document = JsonDocument.Parse(body);

        Assert.Equal(JsonValueKind.Object, document.RootElement.ValueKind);
        Assert.True((int)statusCode is 403 or 404);
        Assert.True(document.RootElement.TryGetProperty("detail", out _));
    }
}

public sealed class EpicStoryLinkApiTests
{
    [Fact]
    public async Task LinkUserStoryToEpicAsync_ConfirmsResourcesAndPostsRelationshipWithOrder()
    {
        var handler = MissingLinkThenResourceRoutes()
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/epics/301/related_userstories",
                EpicStoryLinkFixtures.Success,
                HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var link = await NewApi(handler, auth).LinkUserStoryToEpicAsync(301, 102, order: 9001);

            Assert.Equal(301, link.EpicId);
            Assert.Equal(102, link.UserStoryId);
            Assert.Equal(9001, link.Order);
            Assert.True(link.Created);

            var post = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Post &&
                request.Uri.AbsolutePath.EndsWith("/related_userstories", StringComparison.Ordinal));
            using var body = JsonDocument.Parse(post.Body);
            Assert.Equal(
                new[] { "epic", "order", "user_story" },
                body.RootElement.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
            Assert.Equal(301, body.RootElement.GetProperty("epic").GetInt32());
            Assert.Equal(102, body.RootElement.GetProperty("user_story").GetInt32());
            Assert.Equal(9001, body.RootElement.GetProperty("order").GetInt64());
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Fact]
    public async Task LinkUserStoryToEpicAsync_ExistingRelationshipKeepsServerOrderAndSkipsWrites()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories/102",
                "{\"epic\":301,\"user_story\":102,\"order\":1234}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var link = await NewApi(handler, auth).LinkUserStoryToEpicAsync(301, 102, order: 9001);

            Assert.Equal(1234, link.Order);
            Assert.False(link.Created);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Get &&
                request.Uri.AbsolutePath.EndsWith("related_userstories/102", StringComparison.Ordinal));
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Post &&
                request.Uri.AbsolutePath.EndsWith("/related_userstories", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task LinkUserStoryToEpicAsync_OmitsOrderWhenNotRequested()
    {
        var handler = MissingLinkThenResourceRoutes()
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/epics/301/related_userstories",
                EpicStoryLinkFixtures.Success,
                HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await NewApi(handler, auth).LinkUserStoryToEpicAsync(301, 102);

            using var body = JsonDocument.Parse(Assert.Single(
                handler.Requests,
                request => request.Method == HttpMethod.Post &&
                    request.Uri.AbsolutePath.EndsWith("/related_userstories", StringComparison.Ordinal)).Body);
            Assert.False(body.RootElement.TryGetProperty("order", out _));
        }
    }

    [Fact]
    public async Task LinkUserStoryToEpicAsync_RecognizedConcurrentDuplicateReadsBackConfirmedLink()
    {
        var nestedReads = 0;
        var handler = new FakeHttpMessageHandler()
            .AddRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories/102",
                _ =>
                {
                    nestedReads++;
                    return nestedReads == 1
                        ? Response(HttpStatusCode.NotFound, EpicStoryLinkFixtures.MissingLink)
                        : Response(HttpStatusCode.OK, EpicStoryLinkFixtures.Success);
                })
            .AddJsonRoute(HttpMethod.Get, "/api/v1/epics/301", EpicDetailFixtures.Rich)
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstories/102",
                "{\"id\":102,\"ref\":18,\"project\":123,\"status\":7,\"status_extra_info\":{\"name\":\"Ready\"},\"version\":4}")
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/epics/301/related_userstories",
                EpicStoryLinkFixtures.Duplicate,
                HttpStatusCode.BadRequest);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var link = await NewApi(handler, auth).LinkUserStoryToEpicAsync(301, 102, order: 9001);

            Assert.Equal(9001, link.Order);
            Assert.False(link.Created);
            Assert.Equal(2, handler.Requests.Count(request => request.Method == HttpMethod.Get &&
                request.Uri.AbsolutePath.EndsWith("related_userstories/102", StringComparison.Ordinal)));
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Post &&
                request.Uri.AbsolutePath.EndsWith("/related_userstories", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task LinkUserStoryToEpicAsync_DoesNotTreatUnrelatedBadRequestAsDuplicate()
    {
        var handler = MissingLinkThenResourceRoutes()
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/epics/301/related_userstories",
                "{\"user_story\":[\"The story is not accessible\"]}",
                HttpStatusCode.BadRequest);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).LinkUserStoryToEpicAsync(301, 102));

            Assert.Contains("400", exception.Message);
            Assert.Contains("user_story: rejected", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Post &&
                request.Uri.AbsolutePath.EndsWith("/related_userstories", StringComparison.Ordinal));
            Assert.Equal(1, handler.Requests.Count(request => request.Uri.AbsolutePath.EndsWith("related_userstories/102", StringComparison.Ordinal)));
        }
    }

    [Fact]
    public async Task LinkUserStoryToEpicAsync_AllowsTaigaToDecideCrossProjectEligibility()
    {
        var handler = MissingLinkThenResourceRoutes(
            "{\"id\":102,\"ref\":18,\"project\":999,\"status\":7,\"status_extra_info\":{\"name\":\"Ready\"},\"version\":4}")
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/epics/301/related_userstories",
                EpicStoryLinkFixtures.Success,
                HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var link = await NewApi(handler, auth).LinkUserStoryToEpicAsync(301, 102);

            Assert.True(link.Created);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Post &&
                request.Uri.AbsolutePath.EndsWith("/related_userstories", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task LinkUserStoryToEpicAsync_DoesNotPostWhenNested404BelongsToMissingStory()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories/102",
                EpicStoryLinkFixtures.MissingLink,
                HttpStatusCode.NotFound)
            .AddJsonRoute(HttpMethod.Get, "/api/v1/epics/301", EpicDetailFixtures.Rich)
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstories/102",
                "{\"detail\":\"missing story\"}",
                HttpStatusCode.NotFound);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).LinkUserStoryToEpicAsync(301, 102));

            Assert.Contains("404", exception.Message);
            Assert.Contains("resource not found", exception.Message);
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Post &&
                request.Uri.AbsolutePath.EndsWith("/related_userstories", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task LinkUserStoryToEpicAsync_DoesNotRetryAmbiguousPostTransportFailure()
    {
        var handler = MissingLinkThenResourceRoutes()
            .AddExceptionRoute(
                HttpMethod.Post,
                "/api/v1/epics/301/related_userstories",
                new IOException("secret transport details"));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).LinkUserStoryToEpicAsync(301, 102));

            Assert.Contains("may already have applied", exception.Message);
            Assert.DoesNotContain("secret transport details", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Post &&
                request.Uri.AbsolutePath.EndsWith("/related_userstories", StringComparison.Ordinal));
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Get &&
                request.Uri.AbsolutePath.EndsWith("related_userstories/102", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task LinkUserStoryToEpicAsync_DoesNotPostWhenNested404BelongsToInaccessibleEpic()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories/102",
                EpicStoryLinkFixtures.MissingLink,
                HttpStatusCode.NotFound)
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301",
                EpicStoryLinkFixtures.PermissionDenied,
                HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).LinkUserStoryToEpicAsync(301, 102));

            Assert.Contains("403", exception.Message);
            Assert.Contains("permission denied", exception.Message);
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Post &&
                request.Uri.AbsolutePath.EndsWith("/related_userstories", StringComparison.Ordinal));
            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath.EndsWith("/userstories/102"));
        }
    }

    [Theory]
    [InlineData(0, 102)]
    [InlineData(301, 0)]
    public async Task LinkUserStoryToEpicAsync_RejectsNonpositiveIdsBeforeHttp(int epicId, int userStoryId)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).LinkUserStoryToEpicAsync(epicId, userStoryId));

            Assert.Empty(handler.Requests);
        }
    }

    private static FakeHttpMessageHandler MissingLinkThenResourceRoutes(string? storyJson = null)
        => new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories/102",
                EpicStoryLinkFixtures.MissingLink,
                HttpStatusCode.NotFound)
            .AddJsonRoute(HttpMethod.Get, "/api/v1/epics/301", EpicDetailFixtures.Rich)
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstories/102",
                storyJson ?? "{\"id\":102,\"ref\":18,\"project\":123,\"status\":7,\"status_extra_info\":{\"name\":\"Ready\"},\"version\":4}");

    private static HttpResponseMessage Response(HttpStatusCode statusCode, string body)
        => new(statusCode)
        {
            Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json")
        };

    private static EpicApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));
}

public sealed class EpicStoryLinkToolTests
{
    [Fact]
    public async Task LinkUserStoryToEpicTool_ReturnsPublicRelationshipShape()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories/102",
                "{\"epic\":301,\"user_story\":102,\"order\":1234}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var json = JsonSerializer.Deserialize<JsonElement>(await new EpicTools(NewApi(handler, auth)).LinkUserStoryToEpic(301, 102, 9001));

            Assert.Equal(301, json.GetProperty("epic_id").GetInt32());
            Assert.Equal(102, json.GetProperty("user_story_id").GetInt32());
            Assert.Equal(1234, json.GetProperty("order").GetInt64());
            Assert.False(json.GetProperty("created").GetBoolean());
        }
    }

    private static EpicApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));
}
