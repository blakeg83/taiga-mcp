using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Caching;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class IssueListTests
{
    [Fact]
    public async Task LegacyListIssues_ReturnsBareArrayAndOpenOnlyQuery()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-statuses", "[{\"id\":1,\"name\":\"Open\"}]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/severities", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-types", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/priorities", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issues", "[{\"id\":42,\"project\":123,\"subject\":\"Triage\",\"status\":1}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var tools = new IssueTools(new IssueApi(
                new TaigaTransport(new TestHttpClientFactory(handler), auth),
                new IssueMetadataCache(new TaigaTransport(new TestHttpClientFactory(handler), auth))));

            var result = await tools.ListIssues(123, page: 2);

            using var document = JsonDocument.Parse(result);
            Assert.Equal(JsonValueKind.Array, document.RootElement.ValueKind);
            Assert.Equal(42, document.RootElement[0].GetProperty("id").GetInt32());
            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/issues"));
            Assert.Equal("?project=123&page=2&status__is_closed=false", request.Uri.Query);
        }
    }

    [Fact]
    public async Task FilteredListIssues_UsesAllowlistedEncodedWireFilters()
    {
        var handler = IssueRoutes(
            "[{\"id\":42,\"project\":123,\"subject\":\"Filtered\",\"status\":8,\"severity\":9,\"type\":10,\"priority\":11}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new IssueApi(
                new TaigaTransport(new TestHttpClientFactory(handler), auth),
                new IssueMetadataCache(new TaigaTransport(new TestHttpClientFactory(handler), auth)));

            var page = await api.ListIssuesPageAsync(123, new IssueListOptions
            {
                Page = 2,
                StatusIds = [8, 9],
                AssignedTo = 42,
                TypeId = 10,
                PriorityId = 11,
                SeverityId = 12,
                Tags = ["a&b", "two words"],
                Query = "fix & revisión"
            });

            Assert.Single(page.Items);
            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/issues"));
            Assert.Equal(
                "?project=123&page=2&status=8%2C9&assigned_to=42&type=10&priority=11&severity=12&tags=a%26b%2Ctwo%20words&q=fix%20%26%20revisi%C3%B3n",
                request.Uri.Query);
        }
    }

    [Fact]
    public async Task ExplicitStatusesOverrideOpenOnlyAndIncludeClosedRemovesDefault()
    {
        var explicitStatusHandler = IssueRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(explicitStatusHandler);
        using (http)
        {
            var api = NewApi(explicitStatusHandler, auth);
            await api.ListIssuesPageAsync(123, new IssueListOptions { StatusIds = [8] });
            Assert.Equal("?project=123&page=1&status=8", Assert.Single(explicitStatusHandler.Requests, item => item.Uri.AbsolutePath.EndsWith("/issues")).Uri.Query);
        }

        var includeClosedHandler = IssueRoutes("[]");
        var (closedHttp, closedAuth) = TaigaTestClient.Create(includeClosedHandler);
        using (closedHttp)
        {
            var api = NewApi(includeClosedHandler, closedAuth);
            await api.ListIssuesPageAsync(123, new IssueListOptions { IncludeClosed = true });
            Assert.Equal("?project=123&page=1", Assert.Single(includeClosedHandler.Requests, item => item.Uri.AbsolutePath.EndsWith("/issues")).Uri.Query);
        }
    }

    [Fact]
    public async Task PageMetadataPreservesUnknownHeadersAndParsesTrustedContinuation()
    {
        var handler = IssueRoutes(
            "[]",
            new Dictionary<string, string>
            {
                ["x-pagination-count"] = "not-a-number",
                ["x-pagination-next"] = "https://evil.example/issues?page=4"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListIssuesPageAsync(123, new IssueListOptions { Page = 3 });

            Assert.Equal(3, page.Page);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Fact]
    public async Task ClassificationIdsSurviveUnknownLabels()
    {
        var handler = IssueRoutes(
            "[{\"id\":42,\"project\":123,\"status\":8,\"severity\":9,\"type\":10,\"priority\":11}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var issue = Assert.Single(await NewApi(handler, auth).ListIssuesAsync(123, 1));

            Assert.Null(issue.Status);
            Assert.Equal(8, issue.StatusId);
            Assert.Null(issue.Severity);
            Assert.Equal(9, issue.SeverityId);
            Assert.Null(issue.Type);
            Assert.Equal(10, issue.TypeId);
            Assert.Null(issue.Priority);
            Assert.Equal(11, issue.PriorityId);
        }
    }

    [Fact]
    public async Task InvalidFilterIdsFailBeforeHttp()
    {
        var handler = IssueRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);

            await Assert.ThrowsAsync<ArgumentException>(() => api.ListIssuesPageAsync(123, new IssueListOptions
            {
                StatusIds = [0]
            }));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ToolKeepsLegacyArrayAndOptInEnvelopeItemsIdentical()
    {
        var handler = IssueRoutes(
            "[{\"id\":42,\"project\":123,\"subject\":\"Closed\",\"status\":8}]",
            new Dictionary<string, string>
            {
                ["x-paginated"] = "true",
                ["x-pagination-count"] = "4",
                ["x-pagination-next"] = "/api/v1/issues?page=2"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var tools = new IssueTools(NewApi(handler, auth));
            var array = JsonSerializer.Deserialize<JsonElement>(await tools.ListIssues(123, page: 1, statusIds: [8]));
            var envelope = JsonSerializer.Deserialize<JsonElement>(await tools.ListIssues(
                123,
                page: 1,
                statusIds: [8],
                includePageInfo: true));

            Assert.Equal(JsonValueKind.Array, array.ValueKind);
            Assert.Equal(array.GetRawText(), envelope.GetProperty("items").GetRawText());
            Assert.Equal(1, envelope.GetProperty("page").GetInt32());
            Assert.Equal(4, envelope.GetProperty("total").GetInt32());
            Assert.Equal(2, envelope.GetProperty("next_page").GetInt32());
            Assert.True(envelope.GetProperty("has_more").GetBoolean());
            Assert.DoesNotContain(handler.Requests, item => item.Uri.Query.Contains("status__is_closed", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task EnvelopeWritesUnknownPaginationAsExplicitNull()
    {
        var handler = IssueRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var result = JsonSerializer.Deserialize<JsonElement>(await new IssueTools(NewApi(handler, auth))
                .ListIssues(123, includePageInfo: true));

            Assert.True(result.TryGetProperty("total", out var total));
            Assert.Equal(JsonValueKind.Null, total.ValueKind);
            Assert.True(result.TryGetProperty("next_page", out var next));
            Assert.Equal(JsonValueKind.Null, next.ValueKind);
            Assert.True(result.TryGetProperty("has_more", out var more));
            Assert.Equal(JsonValueKind.Null, more.ValueKind);
        }
    }

    private static IssueApi NewApi(FakeHttpMessageHandler handler, TaigaMCP.Api.AuthClient auth)
    {
        var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
        return new IssueApi(transport, new IssueMetadataCache(transport));
    }

    private static FakeHttpMessageHandler IssueRoutes(
        string issues,
        IReadOnlyDictionary<string, string>? issueHeaders = null)
        => new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-statuses", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/severities", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-types", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/priorities", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issues", issues, headers: issueHeaders);
}
