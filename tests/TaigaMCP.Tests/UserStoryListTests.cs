using System.Net;
using System.Text.Json;
using ModelContextProtocol;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class UserStoryListTests
{
    [Fact]
    public async Task BaselineListUserStories_ReturnsLegacyArrayAndUsesVerifiedStatusFlags()
    {
        const string statuses = """
            [{"id":1,"name":"Done","is_closed":false,"is_archived":false},
             {"id":2,"name":"Terminado","is_closed":true,"is_archived":false},
             {"id":3,"name":"Guardado","is_closed":false,"is_archived":true},
             {"id":4,"name":"Archived","is_closed":false,"is_archived":false}]
            """;
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/userstory-statuses", statuses)
            .AddRoute(HttpMethod.Get, "/api/v1/userstories", request =>
            {
                Assert.Equal(
                    "?project=123&page=1&status__is_archived=false&status__is_closed=false",
                    request.Uri.Query);
                var selected = JsonSerializer.Deserialize<JsonElement>(statuses).EnumerateArray()
                    .Where(status => !status.GetProperty("is_closed").GetBoolean() &&
                                     !status.GetProperty("is_archived").GetBoolean())
                    .Select(status => new
                    {
                        id = status.GetProperty("id").GetInt32() + 10,
                        @ref = status.GetProperty("id").GetInt32(),
                        subject = status.GetProperty("name").GetString(),
                        status = status.GetProperty("id").GetInt32()
                    });
                return AuthenticationTests.Json(JsonSerializer.Serialize(selected));
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var tools = new UserStoryTools(new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)));

            using var result = JsonDocument.Parse(await tools.ListUserStories(123));

            Assert.Equal(JsonValueKind.Array, result.RootElement.ValueKind);
            Assert.Equal(new[] { "Done", "Archived" }, result.RootElement.EnumerateArray()
                .Select(story => story.GetProperty("status").GetString())
                .ToArray());
        }
    }

    [Fact]
    public async Task BaselineListUserStories_RejectsNonpositiveProjectAndPageBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAsync<ArgumentException>(() => api.ListUserStoriesAsync(0));
            await Assert.ThrowsAsync<ArgumentException>(() => api.ListUserStoriesAsync(123, 0));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListUserStoriesPage_MapsFiltersFieldsAndTrustedPagination()
    {
        var handler = StoryRoutes(
            "[{\"id\":90,\"ref\":12,\"project\":123,\"subject\":\"Ship & fix\",\"status\":10,\"assigned_to\":42,\"modified_date\":\"2026-09-28T12:02:00Z\",\"milestone\":55,\"version\":7}]",
            new Dictionary<string, string>
            {
                ["x-paginated"] = "true",
                ["x-pagination-count"] = "4",
                ["x-pagination-next"] = "/api/v1/userstories?page=3"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var page = await api.ListUserStoriesPageAsync(123, new UserStoryListOptions
            {
                Page = 2,
                StatusIds = [10, 11],
                AssignedTo = 42,
                MilestoneId = 55,
                Tags = ["a&b", "two words"],
                Query = "fix & revisión"
            });

            var story = Assert.Single(page.Items);
            Assert.Equal(123, story.Project);
            Assert.Equal(10, story.StatusId);
            Assert.Equal(55, story.Milestone);
            Assert.Equal(7, story.Version);
            Assert.Equal("Ready", story.Status);
            Assert.Equal(4, page.Total);
            Assert.Equal(3, page.NextPage);
            Assert.True(page.HasMore);
            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/userstories"));
            Assert.Equal(
                "?project=123&page=2&status=10%2C11&assigned_to=42&milestone=55&tags=a%26b%2Ctwo%20words&q=fix%20%26%20revisi%C3%B3n",
                request.Uri.Query);
        }
    }

    [Fact]
    public async Task ListUserStoriesPage_BacklogUsesNullMilestoneFilterAndConflictFailsBeforeHttp()
    {
        var backlogHandler = StoryRoutes("[]");
        var (backlogHttp, backlogAuth) = TaigaTestClient.Create(backlogHandler);
        using (backlogHttp)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(backlogHandler), backlogAuth));

            await api.ListUserStoriesPageAsync(123, new UserStoryListOptions { BacklogOnly = true });

            var request = Assert.Single(backlogHandler.Requests, item => item.Uri.AbsolutePath.EndsWith("/userstories"));
            Assert.Equal(
                "?project=123&page=1&status__is_archived=false&status__is_closed=false&milestone__isnull=true",
                request.Uri.Query);
        }

        var conflictHandler = new FakeHttpMessageHandler();
        var (conflictHttp, conflictAuth) = TaigaTestClient.Create(conflictHandler);
        using (conflictHttp)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(conflictHandler), conflictAuth));

            var exception = await Assert.ThrowsAsync<ArgumentException>(() => api.ListUserStoriesPageAsync(
                123,
                new UserStoryListOptions { MilestoneId = 55, BacklogOnly = true }));

            Assert.Contains("backlogOnly", exception.Message);
            Assert.Empty(conflictHandler.Requests);
        }
    }

    [Fact]
    public async Task ListUserStoriesPage_IncludeFlagsAndExplicitStatusesHavePrecedence()
    {
        var handler = StoryRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await api.ListUserStoriesPageAsync(123, new UserStoryListOptions());
            await api.ListUserStoriesPageAsync(123, new UserStoryListOptions { IncludeClosed = true });
            await api.ListUserStoriesPageAsync(123, new UserStoryListOptions { IncludeArchived = true });
            await api.ListUserStoriesPageAsync(123, new UserStoryListOptions
            {
                IncludeClosed = true,
                IncludeArchived = true
            });
            await api.ListUserStoriesPageAsync(123, new UserStoryListOptions
            {
                StatusIds = [77],
                IncludeClosed = true,
                IncludeArchived = true
            });

            var requests = handler.Requests.Where(item => item.Uri.AbsolutePath.EndsWith("/userstories")).ToArray();
            Assert.Equal(
                "?project=123&page=1&status__is_archived=false&status__is_closed=false",
                requests[0].Uri.Query);
            Assert.Equal("?project=123&page=1&status__is_archived=false", requests[1].Uri.Query);
            Assert.Equal("?project=123&page=1&status__is_closed=false", requests[2].Uri.Query);
            Assert.Equal("?project=123&page=1", requests[3].Uri.Query);
            Assert.Equal("?project=123&page=1&status=77", requests[4].Uri.Query);
        }
    }

    [Fact]
    public async Task ListUserStoriesPage_MissingVersionStaysNullAndPublicJsonOmitsIt()
    {
        var handler = StoryRoutes("[{\"id\":90,\"project\":123,\"status\":10}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var tools = new UserStoryTools(new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)));

            var json = JsonSerializer.Deserialize<JsonElement>(await tools.ListUserStories(123));

            Assert.False(json[0].TryGetProperty("version", out _));
            Assert.Equal(10, json[0].GetProperty("status_id").GetInt32());
        }
    }

    [Fact]
    public async Task ListUserStoriesPage_NonnumericOptionalVersionIsOmittedRatherThanFailing()
    {
        var handler = StoryRoutes("[{\"id\":90,\"project\":123,\"status\":10,\"version\":\"unknown\"}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var tools = new UserStoryTools(new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)));

            var json = JsonSerializer.Deserialize<JsonElement>(await tools.ListUserStories(123));

            Assert.False(json[0].TryGetProperty("version", out _));
        }
    }

    [Fact]
    public async Task ListUserStoriesPage_PreservesServerOrderAndUnknownEmptyPageMetadata()
    {
        var orderedHandler = StoryRoutes("[{\"id\":92,\"ref\":2,\"project\":123},{\"id\":91,\"ref\":1,\"project\":123}]");
        var (orderedHttp, orderedAuth) = TaigaTestClient.Create(orderedHandler);
        using (orderedHttp)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(orderedHandler), orderedAuth));

            var page = await api.ListUserStoriesPageAsync(123, new UserStoryListOptions { Page = 2 });

            Assert.Equal(new[] { 92, 91 }, page.Items.Select(item => item.Id));
        }

        var emptyHandler = StoryRoutes(
            "[]",
            new Dictionary<string, string>
            {
                ["x-paginated"] = "true",
                ["x-pagination-count"] = "not-a-number",
                ["x-pagination-next"] = "https://evil.example/userstories?page=8"
            });
        var (emptyHttp, emptyAuth) = TaigaTestClient.Create(emptyHandler);
        using (emptyHttp)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(emptyHandler), emptyAuth));

            var page = await api.ListUserStoriesPageAsync(123, new UserStoryListOptions { Page = 4 });

            Assert.Empty(page.Items);
            Assert.Equal(4, page.Page);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Fact]
    public async Task ListUserStories_InaccessibleProjectIsSafeToolFailure()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstory-statuses",
                "{\"detail\":\"secret project data\"}",
                HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var tools = new UserStoryTools(new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)));

            var exception = await Assert.ThrowsAsync<McpException>(() => tools.ListUserStories(123));

            Assert.Contains("403", exception.Message);
            Assert.Contains("permission denied", exception.Message);
            Assert.DoesNotContain("secret project data", exception.Message);
            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath.EndsWith("/userstories"));
        }
    }

    private static FakeHttpMessageHandler StoryRoutes(
        string stories,
        IReadOnlyDictionary<string, string>? headers = null)
        => new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/userstory-statuses", "[{\"id\":10,\"name\":\"Ready\"},{\"id\":77,\"name\":\"Terminado\"}]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/userstories", stories, headers: headers);
}
