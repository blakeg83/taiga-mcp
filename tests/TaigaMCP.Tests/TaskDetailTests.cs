using System.Text.Json;
using TaigaMCP.Api;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class TaskDetailTests
{
    [Fact]
    public async Task GetTaskAsync_MapsStandaloneDetailWithoutExtraReads()
    {
        var handler = TaskRoutes(TaskDetailFixtures.Standalone, 203);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var task = await NewApi(handler, auth).GetTaskAsync(203);

            Assert.Equal(203, task.Id);
            Assert.Equal(17, task.Ref);
            Assert.Equal(12, task.Project);
            Assert.Equal("Document the search flow — ✓", task.Subject);
            Assert.Equal("**Acceptance:** preserve Markdown and Unicode — ✓", task.Description);
            Assert.Equal(11, task.StatusId);
            Assert.Equal("Ready", task.Status);
            Assert.Null(task.AssignedTo);
            Assert.Null(task.UserStory);
            Assert.Null(task.Milestone);
            Assert.Equal(2, task.Tags!.Count);
            Assert.Equal("search", task.Tags[0][0].GetString());
            Assert.Equal("#336699", task.Tags[0][1].GetString());
            Assert.Null(task.DueDate);
            Assert.Equal("not_set", task.DueDateStatus);
            Assert.False(task.IsBlocked);
            Assert.Equal(2, task.Version);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/tasks/203"));
            Assert.Equal(HttpMethod.Get, request.Method);
            Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/auth"));
        }
    }

    [Fact]
    public async Task GetTaskAsync_MapsStoryParentSprintAndDetailWorkflowFields()
    {
        var handler = TaskRoutes(TaskDetailFixtures.StoryLinked, 204);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var task = await NewApi(handler, auth).GetTaskAsync(204);

            Assert.Equal(204, task.Id);
            Assert.Equal(44, task.StatusId);
            Assert.Equal("Terminado", task.Status);
            Assert.Equal(42, task.AssignedTo);
            Assert.Equal(102, task.UserStory);
            Assert.Equal(55, task.Milestone);
            Assert.Equal("2026-10-15", task.DueDate);
            Assert.Equal("Release readiness review", task.DueDateReason);
            Assert.True(task.IsBlocked);
            Assert.Equal("Waiting for the saved-search API.", task.BlockedNote);
            Assert.False(task.IsClosed);
            Assert.Equal(3, task.Version);
            Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/tasks/204"));
        }
    }

    [Theory]
    [InlineData(TaskDetailFixtures.MissingVersion)]
    [InlineData(TaskDetailFixtures.InvalidIdentity)]
    public async Task GetTaskAsync_RejectsMissingOrInvalidRequiredDetailFields(string payload)
    {
        var handler = TaskRoutes(payload, 203);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).GetTaskAsync(203));

            Assert.Contains("task", exception.Message);
            Assert.DoesNotContain("future_field", exception.Message);
        }
    }

    [Fact]
    public async Task GetTaskAsync_RejectsNonpositiveIdBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).GetTaskAsync(0));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task GetTaskAsync_PreservesStatusIdWhenLabelIsUnavailable()
    {
        var handler = TaskRoutes(
            """{"id":203,"ref":17,"project":12,"status":99,"version":1,"status_extra_info":null}""",
            203);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var task = await NewApi(handler, auth).GetTaskAsync(203);

            Assert.Equal(99, task.StatusId);
            Assert.Null(task.Status);
            Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/tasks/203"));
        }
    }

    [Fact]
    public async Task GetTaskAsync_RejectsMalformedDetailObject()
    {
        var handler = TaskRoutes("[]", 203);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).GetTaskAsync(203));

            Assert.Contains("invalid task detail", exception.Message);
        }
    }

    private static TaskApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private static FakeHttpMessageHandler TaskRoutes(string task, int taskId)
        => new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, $"/api/v1/tasks/{taskId}", task);
}
