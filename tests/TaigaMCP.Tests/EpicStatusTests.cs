using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Models;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class EpicStatusTests
{
    [Fact]
    public void StatusContractPreservesLocalizedNamesAndClosureFlags()
    {
        var statuses = JsonSerializer.Deserialize<EpicStatusDto[]>(
            EpicStatusFixtures.LocalizedProjectStatuses)!;

        Assert.Collection(
            statuses,
            open =>
            {
                Assert.Equal(30, open.Id);
                Assert.Equal(123, open.Project);
                Assert.Equal("En revisión", open.Name);
                Assert.Equal("en-revision", open.Slug);
                Assert.Equal(0, open.Order);
                Assert.Equal("#336699", open.Color);
                Assert.False(open.IsClosed);
            },
            closed =>
            {
                Assert.Equal(31, closed.Id);
                Assert.Equal(123, closed.Project);
                Assert.Equal("Terminé", closed.Name);
                Assert.Equal("termine", closed.Slug);
                Assert.Null(closed.Order);
                Assert.Null(closed.Color);
                Assert.True(closed.IsClosed);
            });
    }

    [Fact]
    public void StatusResponseOmitsOnlyMissingOptionalValues()
    {
        var status = new EpicStatusDto
        {
            Id = 31,
            Name = "Terminé",
            Order = 0,
            IsClosed = true
        };

        using var json = JsonDocument.Parse(ToolResponseJson.Serialize(status));
        var root = json.RootElement;

        Assert.Equal(31, root.GetProperty("id").GetInt32());
        Assert.Equal("Terminé", root.GetProperty("name").GetString());
        Assert.Equal(0, root.GetProperty("order").GetInt32());
        Assert.True(root.GetProperty("is_closed").GetBoolean());
        Assert.False(root.TryGetProperty("project", out _));
        Assert.False(root.TryGetProperty("color", out _));
    }

    [Fact]
    public async Task ListEpicStatusesPage_MapsFieldsAndTrustedPagination()
    {
        var handler = StatusRoutes(
            EpicStatusFixtures.LocalizedProjectStatuses,
            new Dictionary<string, string>
            {
                ["x-paginated"] = "true",
                ["x-pagination-count"] = "4",
                ["x-pagination-next"] = "/api/v1/epic-statuses?project=123&page=3"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new EpicApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var page = await api.ListEpicStatusesPageAsync(123, page: 2);

            Assert.Equal(new[] { 30, 31 }, page.Items.Select(status => status.Id));
            Assert.Equal("En revisión", page.Items[0].Name);
            Assert.False(page.Items[0].IsClosed);
            Assert.Equal(0, page.Items[0].Order);
            Assert.True(page.Items[1].IsClosed);
            Assert.Null(page.Items[1].Order);
            Assert.Null(page.Items[1].Color);
            Assert.Equal(4, page.Total);
            Assert.Equal(3, page.NextPage);
            Assert.True(page.HasMore);

            var request = Assert.Single(handler.Requests, item =>
                item.Uri.AbsolutePath.EndsWith("/epic-statuses"));
            Assert.Equal("?project=123&page=2", request.Uri.Query);
        }
    }

    [Fact]
    public async Task ListEpicStatusesPage_RejectsInvalidArgumentsBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new EpicApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAsync<ArgumentException>(() => api.ListEpicStatusesPageAsync(0));
            await Assert.ThrowsAsync<ArgumentException>(() => api.ListEpicStatusesPageAsync(123, 0));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListEpicStatusesPage_RejectsMalformedRequiredStatusData()
    {
        var handler = StatusRoutes("[{\"id\":0,\"name\":\"Invalid\"}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new EpicApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(
                () => api.ListEpicStatusesPageAsync(123));

            Assert.Contains("epic status id", exception.Message);
        }
    }

    [Fact]
    public async Task ListEpicStatusesPage_PreservesUnknownMetadataOnEmptyPage()
    {
        var handler = StatusRoutes(
            "[]",
            new Dictionary<string, string>
            {
                ["x-paginated"] = "true",
                ["x-pagination-count"] = "not-a-number",
                ["x-pagination-next"] = "https://evil.example/epic-statuses?page=8"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new EpicApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var page = await api.ListEpicStatusesPageAsync(123, page: 4);

            Assert.Empty(page.Items);
            Assert.Equal(4, page.Page);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Fact]
    public async Task ListEpicStatusesPage_RejectsStatusFromAnotherProject()
    {
        var handler = StatusRoutes("[{\"id\":30,\"project\":999,\"name\":\"Wrong project\"}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new EpicApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(
                () => api.ListEpicStatusesPageAsync(123));

            Assert.Contains("different project", exception.Message);
        }
    }

    [Fact]
    public async Task ListEpicStatusesPage_HonorsPreCancellation()
    {
        var handler = StatusRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();
            var api = new EpicApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                api.ListEpicStatusesPageAsync(123, cancellationToken: cancellation.Token));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListEpicStatuses_ForbiddenResponseDoesNotExposeTheBody()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epic-statuses",
                "{\"detail\":\"status permission secret\"}",
                HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new EpicApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(
                () => api.ListEpicStatusesPageAsync(123));

            Assert.Equal(HttpStatusCode.Forbidden, exception.StatusCode);
            Assert.DoesNotContain("status permission secret", exception.Message);
        }
    }

    private static FakeHttpMessageHandler StatusRoutes(
        string statuses,
        IReadOnlyDictionary<string, string>? headers = null)
        => new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epic-statuses",
                statuses,
                headers: headers);
}
