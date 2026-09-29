using System.Net;
using System.Text.Json;
using ModelContextProtocol;
using TaigaMCP.Api;
using TaigaMCP.Models;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class UserStoryStatusTests
{
    [Fact]
    public void StatusContractPreservesLocalizedNamesIndependentFlagsAndZeroValues()
    {
        var statuses = JsonSerializer.Deserialize<UserStoryStatusDto[]>(
            UserStoryStatusFixtures.LocalizedProjectStatuses)!;

        Assert.Collection(
            statuses,
            closed =>
            {
                Assert.Equal(10, closed.Id);
                Assert.Equal(123, closed.Project);
                Assert.Equal("Terminado", closed.Name);
                Assert.Equal("terminado", closed.Slug);
                Assert.Equal(0, closed.Order);
                Assert.Equal("#cc0000", closed.Color);
                Assert.True(closed.IsClosed);
                Assert.False(closed.IsArchived);
                Assert.Equal(0, closed.WipLimit);
            },
            archived =>
            {
                Assert.Equal(11, archived.Id);
                Assert.False(archived.IsClosed);
                Assert.True(archived.IsArchived);
                Assert.Null(archived.Color);
                Assert.Null(archived.WipLimit);
            });
    }

    [Fact]
    public void StatusResponseOmitsOnlyMissingOptionalValues()
    {
        var status = new UserStoryStatusDto
        {
            Id = 11,
            Name = "Guardado",
            Order = 0,
            IsClosed = false,
            IsArchived = true,
            WipLimit = 0
        };

        using var json = JsonDocument.Parse(ToolResponseJson.Serialize(status));
        var root = json.RootElement;

        Assert.Equal(11, root.GetProperty("id").GetInt32());
        Assert.Equal(0, root.GetProperty("order").GetInt32());
        Assert.False(root.GetProperty("is_closed").GetBoolean());
        Assert.True(root.GetProperty("is_archived").GetBoolean());
        Assert.Equal(0, root.GetProperty("wip_limit").GetInt32());
        Assert.False(root.TryGetProperty("project", out _));
        Assert.False(root.TryGetProperty("color", out _));
    }

    [Fact]
    public async Task ListUserStoryStatusesPage_MapsFieldsAndTrustedPagination()
    {
        var handler = StatusRoutes(
            UserStoryStatusFixtures.LocalizedProjectStatuses,
            new Dictionary<string, string>
            {
                ["x-paginated"] = "true",
                ["x-pagination-count"] = "4",
                ["x-pagination-next"] = "/api/v1/userstory-statuses?project=123&page=3"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var page = await api.ListUserStoryStatusesPageAsync(123, page: 2);

            Assert.Equal(new[] { 10, 11 }, page.Items.Select(status => status.Id));
            Assert.Equal("Terminado", page.Items[0].Name);
            Assert.True(page.Items[0].IsClosed);
            Assert.False(page.Items[0].IsArchived);
            Assert.Equal(0, page.Items[0].Order);
            Assert.Equal(0, page.Items[0].WipLimit);
            Assert.False(page.Items[1].IsClosed);
            Assert.True(page.Items[1].IsArchived);
            Assert.Null(page.Items[1].WipLimit);
            Assert.Equal(4, page.Total);
            Assert.Equal(3, page.NextPage);
            Assert.True(page.HasMore);

            var request = Assert.Single(handler.Requests, item =>
                item.Uri.AbsolutePath.EndsWith("/userstory-statuses"));
            Assert.Equal("?project=123&page=2", request.Uri.Query);
        }
    }

    [Fact]
    public async Task ListUserStoryStatusesPage_RejectsInvalidArgumentsBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAsync<ArgumentException>(() => api.ListUserStoryStatusesPageAsync(0));
            await Assert.ThrowsAsync<ArgumentException>(() => api.ListUserStoryStatusesPageAsync(123, 0));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListUserStoryStatusesPage_RejectsMalformedRequiredStatusData()
    {
        var handler = StatusRoutes("[{\"id\":0,\"name\":\"Invalid\"}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(
                () => api.ListUserStoryStatusesPageAsync(123));

            Assert.Contains("status id", exception.Message);
        }
    }

    [Fact]
    public async Task ListUserStoryStatusesPage_PreservesUnknownMetadataOnEmptyPage()
    {
        var handler = StatusRoutes(
            "[]",
            new Dictionary<string, string>
            {
                ["x-paginated"] = "true",
                ["x-pagination-count"] = "not-a-number",
                ["x-pagination-next"] = "https://evil.example/userstory-statuses?page=8"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var page = await api.ListUserStoryStatusesPageAsync(123, page: 4);

            Assert.Empty(page.Items);
            Assert.Equal(4, page.Page);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Fact]
    public async Task ListUserStoryStatusesPage_RejectsStatusFromAnotherProject()
    {
        var handler = StatusRoutes("[{\"id\":10,\"project\":999,\"name\":\"Wrong project\"}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(
                () => api.ListUserStoryStatusesPageAsync(123));

            Assert.Contains("different project", exception.Message);
        }
    }

    [Fact]
    public async Task ListUserStoryStatusesPage_HonorsPreCancellation()
    {
        var handler = StatusRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                api.ListUserStoryStatusesPageAsync(123, cancellationToken: cancellation.Token));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListUserStoryStatuses_ForbiddenResponseIsSafeToolFailure()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstory-statuses",
                "{\"detail\":\"status permission secret\"}",
                HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var tools = new UserStoryTools(new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)));

            var exception = await Assert.ThrowsAsync<McpException>(() => tools.ListUserStoryStatuses(123));

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
                "/api/v1/userstory-statuses",
                statuses,
                headers: headers);
}
