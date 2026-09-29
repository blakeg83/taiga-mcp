using System.Net;
using System.Text.Json;
using ModelContextProtocol;
using TaigaMCP.Api;
using TaigaMCP.Models;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class TaskStatusTests
{
    [Fact]
    public void StatusContractPreservesLocalizedNamesAndIndependentClosureFlags()
    {
        var statuses = JsonSerializer.Deserialize<TaskStatusDto[]>(
            TaskStatusFixtures.LocalizedProjectStatuses)!;

        Assert.Collection(
            statuses,
            open =>
            {
                Assert.Equal(20, open.Id);
                Assert.Equal(123, open.Project);
                Assert.Equal("Done", open.Name);
                Assert.Equal("done", open.Slug);
                Assert.Equal(0, open.Order);
                Assert.Equal("#00aa00", open.Color);
                Assert.False(open.IsClosed);
            },
            closed =>
            {
                Assert.Equal(21, closed.Id);
                Assert.Equal("Terminé", closed.Name);
                Assert.Equal("termine", closed.Slug);
                Assert.Equal(1, closed.Order);
                Assert.Null(closed.Color);
                Assert.True(closed.IsClosed);
            });
    }

    [Fact]
    public void StatusResponseDoesNotExposeStoryOnlyMetadata()
    {
        var status = new TaskStatusDto
        {
            Id = 21,
            Name = "Terminé",
            IsClosed = true
        };

        using var json = JsonDocument.Parse(ToolResponseJson.Serialize(status));
        var root = json.RootElement;

        Assert.Equal(21, root.GetProperty("id").GetInt32());
        Assert.Equal("Terminé", root.GetProperty("name").GetString());
        Assert.True(root.GetProperty("is_closed").GetBoolean());
        Assert.False(root.TryGetProperty("is_archived", out _));
        Assert.False(root.TryGetProperty("wip_limit", out _));
        Assert.False(root.TryGetProperty("project", out _));
    }

    [Fact]
    public async Task ListTaskStatusesPage_MapsFieldsAndTrustedPagination()
    {
        var handler = StatusRoutes(
            TaskStatusFixtures.LocalizedProjectStatuses,
            new Dictionary<string, string>
            {
                ["x-paginated"] = "true",
                ["x-pagination-count"] = "4",
                ["x-pagination-next"] = "/api/v1/task-statuses?project=123&page=3"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new TaskApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var page = await api.ListTaskStatusesPageAsync(123, page: 2);

            Assert.Equal(new[] { 20, 21 }, page.Items.Select(status => status.Id));
            Assert.Equal("Done", page.Items[0].Name);
            Assert.False(page.Items[0].IsClosed);
            Assert.Equal(0, page.Items[0].Order);
            Assert.True(page.Items[1].IsClosed);
            Assert.Equal("Terminé", page.Items[1].Name);
            Assert.Null(page.Items[1].Color);
            Assert.Equal(4, page.Total);
            Assert.Equal(3, page.NextPage);
            Assert.True(page.HasMore);

            var request = Assert.Single(handler.Requests, item =>
                item.Uri.AbsolutePath.EndsWith("/task-statuses"));
            Assert.Equal("?project=123&page=2", request.Uri.Query);
        }
    }

    [Fact]
    public async Task ListTaskStatusesPage_RejectsInvalidArgumentsBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new TaskApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAsync<ArgumentException>(() => api.ListTaskStatusesPageAsync(0));
            await Assert.ThrowsAsync<ArgumentException>(() => api.ListTaskStatusesPageAsync(123, 0));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListTaskStatusesPage_RejectsMalformedRequiredStatusData()
    {
        var handler = StatusRoutes("[{\"id\":0,\"name\":\"Invalid\"}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new TaskApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(
                () => api.ListTaskStatusesPageAsync(123));

            Assert.Contains("task status id", exception.Message);
        }
    }

    [Fact]
    public async Task ListTaskStatusesPage_PreservesUnknownMetadataOnEmptyPage()
    {
        var handler = StatusRoutes(
            "[]",
            new Dictionary<string, string>
            {
                ["x-paginated"] = "true",
                ["x-pagination-count"] = "not-a-number",
                ["x-pagination-next"] = "https://evil.example/task-statuses?page=8"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new TaskApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var page = await api.ListTaskStatusesPageAsync(123, page: 4);

            Assert.Empty(page.Items);
            Assert.Equal(4, page.Page);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Fact]
    public async Task ListTaskStatusesPage_RejectsStatusFromAnotherProject()
    {
        var handler = StatusRoutes("[{\"id\":20,\"project\":999,\"name\":\"Wrong project\"}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new TaskApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(
                () => api.ListTaskStatusesPageAsync(123));

            Assert.Contains("different project", exception.Message);
        }
    }

    [Fact]
    public async Task ListTaskStatusesPage_HonorsPreCancellation()
    {
        var handler = StatusRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();
            var api = new TaskApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                api.ListTaskStatusesPageAsync(123, cancellationToken: cancellation.Token));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListTaskStatuses_ForbiddenResponseIsSafeToolFailure()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/task-statuses",
                "{\"detail\":\"status permission secret\"}",
                HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var tools = new TaskTools(new TaskApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)));

            var exception = await Assert.ThrowsAsync<McpException>(() => tools.ListTaskStatuses(123));

            Assert.Contains("403", exception.Message);
            Assert.Contains("permission denied", exception.Message, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("status permission secret", exception.Message);
        }
    }

    private static FakeHttpMessageHandler StatusRoutes(
        string statuses,
        IReadOnlyDictionary<string, string>? headers = null)
        => new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/task-statuses",
                statuses,
                headers: headers);
}
