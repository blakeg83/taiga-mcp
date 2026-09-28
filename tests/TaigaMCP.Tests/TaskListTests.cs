using System.Net;
using System.Text.Json;
using ModelContextProtocol;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class TaskListTests
{
    [Fact]
    public async Task ListTasksPage_MapsStandaloneTaskAndInlineStatusLabel()
    {
        var handler = TaskRoutes(TaskListFixtures.Standalone);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListTasksPageAsync(
                12,
                new TaskListOptions { Page = 2 });

            var task = Assert.Single(page.Items);
            Assert.Equal(203, task.Id);
            Assert.Equal(17, task.Ref);
            Assert.Equal(12, task.Project);
            Assert.Equal("Document the search flow — ✓", task.Subject);
            Assert.Equal(11, task.StatusId);
            Assert.Equal("Ready", task.Status);
            Assert.Null(task.AssignedTo);
            Assert.Null(task.UserStory);
            Assert.Null(task.Milestone);
            Assert.Equal("2026-09-28T12:00:00Z", task.Modified);
            Assert.Equal(2, task.Version);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/tasks"));
            Assert.Equal("?project=12&page=2&status__is_closed=false", request.Uri.Query);
        }
    }

    [Fact]
    public async Task ListTasksPage_UsesAllowlistedEncodedFiltersAndMapsParents()
    {
        var handler = TaskRoutes(TaskListFixtures.StoryLinkedClosed);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListTasksPageAsync(
                12,
                new TaskListOptions
                {
                    Page = 3,
                    StatusIds = [44, 45],
                    UserStoryId = 102,
                    MilestoneId = 55,
                    AssignedTo = 42,
                    Tags = ["a&b", "two words"],
                    Query = "fix & revisión"
                });

            var task = Assert.Single(page.Items);
            Assert.Equal(44, task.StatusId);
            Assert.Equal("Terminado", task.Status);
            Assert.Equal(42, task.AssignedTo);
            Assert.Equal(102, task.UserStory);
            Assert.Equal(55, task.Milestone);
            Assert.Equal(3, task.Version);
            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/tasks"));
            Assert.Equal(
                "?project=12&page=3&status=44%2C45&user_story=102&milestone=55&assigned_to=42&tags=a%26b%2Ctwo%20words&q=fix%20%26%20revisi%C3%B3n",
                request.Uri.Query);
        }
    }

    [Fact]
    public async Task ListTasksPage_ExplicitStatusesAndIncludeClosedOverrideDefaultFilter()
    {
        var handler = TaskRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            await api.ListTasksPageAsync(12, new TaskListOptions { StatusIds = [44] });
            await api.ListTasksPageAsync(12, new TaskListOptions { IncludeClosed = true });

            var requests = handler.Requests.Where(item => item.Uri.AbsolutePath.EndsWith("/tasks")).ToArray();
            Assert.Equal("?project=12&page=1&status=44", requests[0].Uri.Query);
            Assert.Equal("?project=12&page=1", requests[1].Uri.Query);
        }
    }

    [Fact]
    public async Task ListTasksPage_PreservesNumericStatusWhenLabelIsUnavailable()
    {
        var handler = TaskRoutes(TaskListFixtures.UnavailableStatusLabel);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var task = Assert.Single(await NewApi(handler, auth).ListTasksAsync(12));

            Assert.Equal(99, task.StatusId);
            Assert.Null(task.Status);
            Assert.Null(task.Version);
        }
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(12, 0)]
    public async Task ListTasksPage_RejectsNonpositiveProjectAndPageBeforeHttp(int projectId, int page)
    {
        var handler = TaskRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).ListTasksPageAsync(
                projectId,
                new TaskListOptions { Page = page }));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListTasksPage_RejectsInvalidFilterIdsBeforeHttp()
    {
        var handler = TaskRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            await Assert.ThrowsAsync<ArgumentException>(() => api.ListTasksPageAsync(
                12,
                new TaskListOptions { StatusIds = [0] }));
            await Assert.ThrowsAsync<ArgumentException>(() => api.ListTasksPageAsync(
                12,
                new TaskListOptions { UserStoryId = 0 }));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListTasksPage_RejectsMalformedListResponse()
    {
        var handler = TaskRoutes("{\"not\":\"an array\"}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).ListTasksAsync(12));

            Assert.Contains("invalid task list", error.Message);
        }
    }

    [Fact]
    public async Task ListTasksPage_EmptyPageKeepsUnknownPaginationMetadataNull()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks",
                "[]",
                headers: new Dictionary<string, string>
                {
                    ["x-paginated"] = "true",
                    ["x-pagination-count"] = "not-a-number",
                    ["x-pagination-next"] = "https://evil.example/tasks?page=8"
                });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListTasksPageAsync(
                12,
                new TaskListOptions { Page = 4 });

            Assert.Empty(page.Items);
            Assert.Equal(4, page.Page);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Fact]
    public async Task ListTasksTool_ReturnsEnvelopeAndExplicitNullPaginationValues()
    {
        var handler = TaskRoutes(TaskListFixtures.Standalone);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var result = JsonSerializer.Deserialize<JsonElement>(await new TaskTools(NewApi(handler, auth))
                .ListTasks(12, page: 4));

            Assert.Equal(JsonValueKind.Object, result.ValueKind);
            Assert.Equal(4, result.GetProperty("page").GetInt32());
            Assert.True(result.TryGetProperty("total", out var total));
            Assert.Equal(JsonValueKind.Null, total.ValueKind);
            Assert.True(result.TryGetProperty("next_page", out var next));
            Assert.Equal(JsonValueKind.Null, next.ValueKind);
            Assert.True(result.TryGetProperty("has_more", out var hasMore));
            Assert.Equal(JsonValueKind.Null, hasMore.ValueKind);
            Assert.False(result.GetProperty("items")[0].TryGetProperty("assigned_to", out _));
            Assert.False(result.GetProperty("items")[0].TryGetProperty("user_story", out _));
            Assert.False(result.GetProperty("items")[0].TryGetProperty("milestone", out _));
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    [InlineData(HttpStatusCode.NotFound, "resource not found")]
    public async Task ListTasksTool_ReportsSafeHttpFailures(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks",
                "{\"detail\":\"secret task credentials\"}",
                statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<McpException>(() => new TaskTools(NewApi(handler, auth)).ListTasks(12));

            Assert.Contains(((int)statusCode).ToString(), error.Message);
            Assert.Contains(category, error.Message);
            Assert.DoesNotContain("secret task credentials", error.Message);
            Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/tasks"));
        }
    }

    [Fact]
    public async Task ListTasksPage_AllowsStoryAndSprintSelectorsIndependently()
    {
        var handler = TaskRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            await api.ListTasksPageAsync(12, new TaskListOptions { UserStoryId = 102 });
            await api.ListTasksPageAsync(12, new TaskListOptions { MilestoneId = 55 });

            var requests = handler.Requests.Where(item => item.Uri.AbsolutePath.EndsWith("/tasks")).ToArray();
            Assert.Equal("?project=12&page=1&status__is_closed=false&user_story=102", requests[0].Uri.Query);
            Assert.Equal("?project=12&page=1&status__is_closed=false&milestone=55", requests[1].Uri.Query);
        }
    }

    private static TaskApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
    {
        var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
        return new TaskApi(transport, new UserStoryApi(transport));
    }

    private static FakeHttpMessageHandler TaskRoutes(string tasks)
        => new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks", tasks);
}
