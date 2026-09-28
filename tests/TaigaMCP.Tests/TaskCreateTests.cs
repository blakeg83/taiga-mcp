using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class TaskCreateTests
{
    [Fact]
    public async Task CreateTaskAsync_MinimalStandaloneTaskPreservesProjectDefaults()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/tasks",
                """
                {"id":203,"ref":17,"project":12,"subject":"Capture deployment checklist","user_story":null,"milestone":null,"version":2}
                """,
                HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var task = await NewApi(handler, auth).CreateTaskAsync(12, "Capture deployment checklist");

            Assert.Equal(203, task.Id);
            Assert.Equal(12, task.Project);
            Assert.Null(task.UserStory);
            Assert.Null(task.Milestone);
            Assert.Equal(2, task.Version);

            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks"));
            using var body = JsonDocument.Parse(request.Body);
            Assert.Equal(
                new[] { "project", "subject" },
                body.RootElement.EnumerateObject().Select(property => property.Name).ToArray());
        }
    }

    [Fact]
    public async Task CreateTaskAsync_MapsOptionalFieldsAndStandaloneMilestone()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/tasks", TaskCreateFixtures.CreatedTask, HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var task = await NewApi(handler, auth).CreateTaskAsync(
                12,
                "Implement saved-search endpoint",
                milestoneId: 55,
                description: "  **Acceptance:** preserve Markdown and Unicode — ✓  ",
                status: 11,
                assigned_to: 42,
                tags: ["search"]);

            Assert.Equal(203, task.Id);
            Assert.Equal(55, task.Milestone);
            Assert.Equal(2, task.Version);

            using var body = JsonDocument.Parse(Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks")).Body);
            Assert.Equal(
                new[] { "assigned_to", "description", "milestone", "project", "status", "subject", "tags" },
                body.RootElement.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
            Assert.Equal(55, body.RootElement.GetProperty("milestone").GetInt32());
            Assert.Equal("  **Acceptance:** preserve Markdown and Unicode — ✓  ", body.RootElement.GetProperty("description").GetString());
            Assert.Equal(new[] { "search" }, body.RootElement.GetProperty("tags").EnumerateArray().Select(tag => tag.GetString()));
        }
    }

    [Fact]
    public async Task CreateTaskAsync_SendsExplicitEmptyDescriptionAndTags()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/tasks", TaskCreateFixtures.CreatedTask, HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await NewApi(handler, auth).CreateTaskAsync(
                12,
                "Capture deployment checklist",
                description: "",
                tags: []);

            using var body = JsonDocument.Parse(Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks")).Body);
            Assert.Equal("", body.RootElement.GetProperty("description").GetString());
            Assert.Empty(body.RootElement.GetProperty("tags").EnumerateArray());
        }
    }

    [Fact]
    public async Task CreateTaskAsync_ValidatesParentAndOmitsMatchingMilestone()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/userstories/102", TaskCreateFixtures.ParentStoryWithSprint)
            .AddJsonRoute(HttpMethod.Post, "/api/v1/tasks", TaskCreateFixtures.CreatedTask, HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var task = await NewApi(handler, auth).CreateTaskAsync(
                12,
                "Implement saved-search endpoint",
                userStoryId: 102,
                milestoneId: 55);

            Assert.Equal(102, task.UserStory);
            Assert.Equal(55, task.Milestone);
            Assert.Equal(
                new[] { "/api/v1/userstories/102", "/api/v1/tasks" },
                handler.Requests.Where(item => item.Uri.AbsolutePath != "/api/v1/auth").Select(item => item.Uri.AbsolutePath));

            using var body = JsonDocument.Parse(Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks")).Body);
            Assert.Equal(102, body.RootElement.GetProperty("user_story").GetInt32());
            Assert.False(body.RootElement.TryGetProperty("milestone", out _));
        }
    }

    [Theory]
    [InlineData(0, "valid", null, null, null, null)]
    [InlineData(12, " ", null, null, null, null)]
    [InlineData(12, "valid", 0, null, null, null)]
    [InlineData(12, "valid", null, 0, null, null)]
    [InlineData(12, "valid", null, null, 0, null)]
    [InlineData(12, "valid", null, null, null, 0)]
    public async Task CreateTaskAsync_RejectsInvalidInputsBeforeHttp(
        int projectId,
        string subject,
        int? userStoryId,
        int? milestoneId,
        int? status,
        int? assignedTo)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);

            await Assert.ThrowsAsync<ArgumentException>(() => api.CreateTaskAsync(
                projectId,
                subject,
                userStoryId,
                milestoneId,
                status: status,
                assigned_to: assignedTo));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task CreateTaskAsync_RejectsParentProjectMismatchWithoutPost()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstories/102",
                TaskCreateFixtures.ParentStoryWithSprint.Replace("\"project\":12", "\"project\":99"));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).CreateTaskAsync(12, "Implement saved-search endpoint", userStoryId: 102));

            Assert.Contains("projectId", exception.Message);
            Assert.DoesNotContain(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks"));
        }
    }

    [Fact]
    public async Task CreateTaskAsync_RejectsParentSprintMismatchWithoutPost()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/userstories/102", TaskCreateFixtures.ParentStoryWithSprint);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).CreateTaskAsync(12, "Implement saved-search endpoint", userStoryId: 102, milestoneId: 56));

            Assert.Contains("milestoneId", exception.Message);
            Assert.DoesNotContain(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks"));
        }
    }

    [Fact]
    public async Task CreateTaskAsync_RejectsExplicitSprintForUnscheduledParentWithoutPost()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/userstories/103", TaskCreateFixtures.ParentStoryWithoutSprint);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).CreateTaskAsync(12, "Capture saved-search requirements", userStoryId: 103, milestoneId: 55));

            Assert.DoesNotContain(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks"));
        }
    }

    [Fact]
    public async Task CreateTaskAsync_ReportsParentLookupDenialWithoutPost()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/userstories/102", "{\"detail\":\"secret parent data\"}", HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).CreateTaskAsync(12, "Implement saved-search endpoint", userStoryId: 102));

            Assert.Contains("403", exception.Message);
            Assert.Contains("permission denied", exception.Message);
            Assert.DoesNotContain("secret parent data", exception.Message);
            Assert.DoesNotContain(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks"));
        }
    }

    [Fact]
    public async Task CreateTaskAsync_ReportsServerStatusAndAssigneeValidationSafely()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/tasks",
                "{\"status\":[\"secret status reason\"],\"assigned_to\":[\"secret assignee reason\"]}",
                HttpStatusCode.BadRequest);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).CreateTaskAsync(12, "Capture deployment checklist", status: 11, assigned_to: 42));

            Assert.Contains("status: rejected", exception.Message);
            Assert.Contains("assigned_to: rejected", exception.Message);
            Assert.DoesNotContain("secret status reason", exception.Message);
            Assert.DoesNotContain("secret assignee reason", exception.Message);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks"));
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest, "validation failed")]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    public async Task CreateTaskAsync_ReportsServerFailureWithoutRetry(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/tasks", "{\"detail\":\"secret task data\"}", statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).CreateTaskAsync(12, "Capture deployment checklist"));

            Assert.Contains(((int)statusCode).ToString(), exception.Message);
            Assert.Contains(category, exception.Message);
            Assert.DoesNotContain("secret task data", exception.Message);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks"));
        }
    }

    [Fact]
    public async Task CreateTaskAsync_ReportsAmbiguousTransportFailureWithoutRetry()
    {
        var handler = new FakeHttpMessageHandler()
            .AddExceptionRoute(HttpMethod.Post, "/api/v1/tasks", new HttpRequestException("secret connection details"));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).CreateTaskAsync(12, "Capture deployment checklist"));

            Assert.Contains("may already have applied", exception.Message);
            Assert.DoesNotContain("secret connection details", exception.Message);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks"));
        }
    }

    [Fact]
    public async Task CreateTaskAsync_ReportsResponseMappingFailureAsPotentiallyApplied()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/tasks", "{\"project\":12}", HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).CreateTaskAsync(12, "Capture deployment checklist"));

            Assert.Contains("may already have applied", exception.Message);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/tasks"));
        }
    }

    private static TaskApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
    {
        var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
        return new TaskApi(transport, new UserStoryApi(transport));
    }
}
