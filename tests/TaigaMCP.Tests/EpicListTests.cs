using System.Text.Json;
using System.Net;
using TaigaMCP.Api;
using TaigaMCP.Models;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class EpicListTests
{
    [Fact]
    public void EpicDto_PublicContractUsesStableNamesAndPreservesNullableFields()
    {
        using var document = JsonDocument.Parse(EpicListFixtures.OpenAndClosed);
        var first = document.RootElement[0];
        var tags = first.GetProperty("tags").EnumerateArray().Select(tag => tag.Clone()).ToArray();
        var epic = new EpicDto
        {
            Id = first.GetProperty("id").GetInt32(),
            Ref = first.GetProperty("ref").GetInt32(),
            Project = first.GetProperty("project").GetInt32(),
            Subject = first.GetProperty("subject").GetString(),
            StatusId = first.GetProperty("status").GetInt32(),
            Status = first.GetProperty("status_extra_info").GetProperty("name").GetString(),
            AssignedTo = first.GetProperty("assigned_to").GetInt32(),
            Color = first.GetProperty("color").GetString(),
            Tags = tags,
            Modified = first.GetProperty("modified_date").GetString(),
            Version = first.GetProperty("version").GetInt32()
        };

        var json = JsonSerializer.Deserialize<JsonElement>(ToolResponseJson.Serialize(epic));

        Assert.Equal(301, json.GetProperty("id").GetInt32());
        Assert.Equal(12, json.GetProperty("ref").GetInt32());
        Assert.Equal(123, json.GetProperty("project").GetInt32());
        Assert.Equal(7, json.GetProperty("status_id").GetInt32());
        Assert.Equal("Ready", json.GetProperty("status").GetString());
        Assert.Equal(42, json.GetProperty("assigned_to").GetInt32());
        Assert.Equal("#336699", json.GetProperty("color").GetString());
        Assert.Equal("2026-09-28T12:03:00Z", json.GetProperty("modified").GetString());
        Assert.Equal(4, json.GetProperty("version").GetInt32());
        Assert.Equal(2, json.GetProperty("tags").GetArrayLength());

        var nullable = new EpicDto { Id = 302, Ref = 13 };
        var nullableJson = JsonSerializer.Deserialize<JsonElement>(ToolResponseJson.Serialize(nullable));
        Assert.False(nullableJson.TryGetProperty("assigned_to", out _));
        Assert.False(nullableJson.TryGetProperty("color", out _));
        Assert.False(nullableJson.TryGetProperty("version", out _));
    }

    [Fact]
    public async Task ListEpicsPage_MapsFieldsAndAllowlistedEncodedFilters()
    {
        var handler = EpicRoutes(
            EpicListFixtures.OpenAndClosed,
            new Dictionary<string, string>
            {
                ["x-paginated"] = "true",
                ["x-pagination-count"] = "4",
                ["x-pagination-next"] = "/api/v1/epics?page=3"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListEpicsPageAsync(
                123,
                new EpicListOptions
                {
                    Page = 2,
                    StatusIds = [7, 8],
                    AssignedTo = 42,
                    Tags = ["a&b", "two words"],
                    Query = "fix & revisión"
                });

            Assert.Equal(2, page.Items.Count);
            var epic = page.Items[0];
            Assert.Equal(301, epic.Id);
            Assert.Equal(12, epic.Ref);
            Assert.Equal(123, epic.Project);
            Assert.Equal("Saved search epic — ✓", epic.Subject);
            Assert.Equal(7, epic.StatusId);
            Assert.Equal("Ready", epic.Status);
            Assert.Equal(42, epic.AssignedTo);
            Assert.Equal("#336699", epic.Color);
            Assert.Equal(2, epic.Tags!.Count);
            Assert.Equal("2026-09-28T12:03:00Z", epic.Modified);
            Assert.Equal(4, epic.Version);
            Assert.Equal(4, page.Total);
            Assert.Equal(3, page.NextPage);
            Assert.True(page.HasMore);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/epics"));
            Assert.Equal(
                "?project=123&page=2&status=7%2C8&assigned_to=42&tags=a%26b%2Ctwo%20words&q=fix%20%26%20revisi%C3%B3n",
                request.Uri.Query);
        }
    }

    [Fact]
    public async Task ListEpicsPage_ExplicitStatusesAndIncludeClosedOverrideDefaultFilter()
    {
        var handler = EpicRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            await api.ListEpicsPageAsync(123, new EpicListOptions { StatusIds = [8] });
            await api.ListEpicsPageAsync(123, new EpicListOptions { IncludeClosed = true });
            await api.ListEpicsPageAsync(123, new EpicListOptions());

            var requests = handler.Requests.Where(item => item.Uri.AbsolutePath.EndsWith("/epics")).ToArray();
            Assert.Equal("?project=123&page=1&status=8", requests[0].Uri.Query);
            Assert.Equal("?project=123&page=1", requests[1].Uri.Query);
            Assert.Equal("?project=123&page=1&status__is_closed=false", requests[2].Uri.Query);
        }
    }

    [Fact]
    public async Task ListEpicsPage_UsesServerClosedFlagForLocalizedStatuses()
    {
        var handler = new FakeHttpMessageHandler()
            .AddRoute(HttpMethod.Get, "/api/v1/epics", request =>
            {
                return request.Uri.Query switch
                {
                    "?project=123&page=1&status__is_closed=false" => AuthenticationTests.Json(
                        "[{\"id\":301,\"ref\":12,\"project\":123,\"subject\":\"Open\",\"status\":7,\"status_extra_info\":{\"name\":\"Done\"}}]"),
                    "?project=123&page=1&status=8" => AuthenticationTests.Json(
                        "[{\"id\":302,\"ref\":13,\"project\":123,\"subject\":\"Closed\",\"status\":8,\"status_extra_info\":{\"name\":\"Terminado\"}}]"),
                    _ => throw new InvalidOperationException($"Unexpected epic query: {request.Uri.Query}")
                };
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            var open = Assert.Single((await api.ListEpicsPageAsync(123, new EpicListOptions())).Items);
            var closed = Assert.Single((await api.ListEpicsPageAsync(123, new EpicListOptions { StatusIds = [8] })).Items);

            Assert.Equal("Done", open.Status);
            Assert.Equal("Terminado", closed.Status);
            Assert.Equal(8, closed.StatusId);
        }
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(123, 0)]
    public async Task ListEpicsPage_RejectsNonpositiveProjectAndPageBeforeHttp(int projectId, int page)
    {
        var handler = EpicRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).ListEpicsPageAsync(
                projectId,
                new EpicListOptions { Page = page }));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListEpicsPage_RejectsInvalidFilterIdsBeforeHttp()
    {
        var handler = EpicRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            await Assert.ThrowsAsync<ArgumentException>(() => api.ListEpicsPageAsync(
                123,
                new EpicListOptions { StatusIds = [0] }));
            await Assert.ThrowsAsync<ArgumentException>(() => api.ListEpicsPageAsync(
                123,
                new EpicListOptions { AssignedTo = 0 }));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListEpicsPage_PreservesNumericStatusWhenInlineLabelIsUnavailable()
    {
        var handler = EpicRoutes("[{\"id\":301,\"ref\":12,\"project\":123,\"status\":99,\"status_extra_info\":null}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var epic = Assert.Single(await NewApi(handler, auth).ListEpicsAsync(123));

            Assert.Equal(99, epic.StatusId);
            Assert.Null(epic.Status);
            Assert.Null(epic.Version);
        }
    }

    [Fact]
    public async Task ListEpicsPage_EmptyPageKeepsUnknownPaginationMetadataNull()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics",
                "[]",
                headers: new Dictionary<string, string>
                {
                    ["x-paginated"] = "true",
                    ["x-pagination-count"] = "not-a-number",
                    ["x-pagination-next"] = "https://evil.example/epics?page=8"
                });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListEpicsPageAsync(
                123,
                new EpicListOptions { Page = 4 });

            Assert.Empty(page.Items);
            Assert.Equal(4, page.Page);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Fact]
    public async Task ListEpicsTool_ReportsSafeHttpFailures()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics",
                "{\"detail\":\"secret epic credentials\"}",
                HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<ModelContextProtocol.McpException>(() =>
                new EpicTools(NewApi(handler, auth)).ListEpics(123));

            Assert.Contains("403", error.Message);
            Assert.Contains("permission denied", error.Message);
            Assert.DoesNotContain("secret epic credentials", error.Message);
            Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/epics"));
        }
    }

    [Fact]
    public async Task ListEpicsPage_RejectsMalformedListResponse()
    {
        var handler = EpicRoutes("{\"not\":\"an array\"}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).ListEpicsAsync(123));

            Assert.Contains("invalid epic list", error.Message);
        }
    }

    [Fact]
    public async Task ListEpicsTool_ReturnsEnvelopeWithExplicitNullPaginationValues()
    {
        var handler = EpicRoutes(EpicListFixtures.OpenAndClosed);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var json = JsonSerializer.Deserialize<JsonElement>(await new EpicTools(NewApi(handler, auth))
                .ListEpics(123, page: 4));

            Assert.Equal(JsonValueKind.Object, json.ValueKind);
            Assert.Equal(4, json.GetProperty("page").GetInt32());
            Assert.True(json.GetProperty("total").ValueKind == JsonValueKind.Null);
            Assert.True(json.GetProperty("next_page").ValueKind == JsonValueKind.Null);
            Assert.True(json.GetProperty("has_more").ValueKind == JsonValueKind.Null);
            Assert.Equal(301, json.GetProperty("items")[0].GetProperty("id").GetInt32());
            Assert.False(json.GetProperty("items")[1].TryGetProperty("assigned_to", out _));
        }
    }

    private static EpicApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private static FakeHttpMessageHandler EpicRoutes(
        string epics,
        IReadOnlyDictionary<string, string>? headers = null)
        => new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/epics", epics, headers: headers);
}
