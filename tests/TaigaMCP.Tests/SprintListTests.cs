using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class SprintListTests
{
    [Fact]
    public async Task ListSprintsPage_MapsLightweightFieldsAndIgnoresNestedAggregates()
    {
        var handler = SprintRoutes(
            SprintListFixtures.OpenAndClosed,
            new Dictionary<string, string>
            {
                ["x-pagination-count"] = "7",
                ["x-pagination-next"] = "/api/v1/milestones?project=12&page=3",
                ["Taiga-Info-Total-Opened-Milestones"] = "4",
                ["Taiga-Info-Total-Closed-Milestones"] = "3"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListSprintsPageAsync(12, page: 2);

            Assert.Equal(2, page.Items.Count);
            Assert.Equal(2, page.Page);
            Assert.Equal(7, page.Total);
            Assert.Equal(3, page.NextPage);
            Assert.True(page.HasMore);

            var open = page.Items[0];
            Assert.Equal(301, open.Id);
            Assert.Equal(12, open.Project);
            Assert.Equal("Sprint 2026-09", open.Name);
            Assert.Equal("sprint-2026-09", open.Slug);
            Assert.Equal("2026-09-01", open.EstimatedStart);
            Assert.Equal("2026-09-14", open.EstimatedFinish);
            Assert.False(open.Closed);

            var closed = page.Items[1];
            Assert.Equal(302, closed.Id);
            Assert.True(closed.Closed);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/milestones"));
            Assert.Equal("?project=12&page=2", request.Uri.Query);
        }
    }

    [Fact]
    public async Task ListSprintsPage_ClosedFilterDistinguishesOmissionFalseAndTrue()
    {
        var handler = SprintRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            await api.ListSprintsPageAsync(12, page: 1, closed: null);
            await api.ListSprintsPageAsync(12, page: 2, closed: false);
            await api.ListSprintsPageAsync(12, page: 3, closed: true);

            var requests = handler.Requests.Where(item => item.Uri.AbsolutePath.EndsWith("/milestones")).ToArray();
            Assert.Equal("?project=12&page=1", requests[0].Uri.Query);
            Assert.Equal("?project=12&page=2&closed=false", requests[1].Uri.Query);
            Assert.Equal("?project=12&page=3&closed=true", requests[2].Uri.Query);
        }
    }

    [Fact]
    public async Task ListSprintsPage_PreservesOptionalIgnoredNullsAndDateOnlyValues()
    {
        var handler = SprintRoutes(SprintListFixtures.OpenWithNullOptionalExtras);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var sprint = Assert.Single(await NewApi(handler, auth).ListSprintsAsync(12));

            Assert.Equal("2026-10-01", sprint.EstimatedStart);
            Assert.Equal("2026-10-14", sprint.EstimatedFinish);
            var json = JsonSerializer.Serialize(sprint);
            Assert.DoesNotContain("user_stories", json);
            Assert.DoesNotContain("total_points", json);
            Assert.DoesNotContain("closed_points", json);
            Assert.DoesNotContain("owner", json);
        }
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(12, 0)]
    public async Task ListSprintsPage_RejectsNonpositiveProjectAndPageBeforeHttp(int projectId, int page)
    {
        var handler = SprintRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).ListSprintsPageAsync(projectId, page));
            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListSprintsPage_RejectsMismatchedProjectAndMalformedDates()
    {
        var mismatched = SprintRoutes("""[{"id":301,"project":99,"name":"Sprint","slug":"sprint","estimated_start":"2026-09-01","estimated_finish":"2026-09-14","closed":false}]""");
        var (mismatchedHttp, mismatchedAuth) = TaigaTestClient.Create(mismatched);
        using (mismatchedHttp)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(mismatched, mismatchedAuth).ListSprintsPageAsync(12));
            Assert.Contains("different project", error.Message);
        }

        var malformed = SprintRoutes("""[{"id":301,"project":12,"name":"Sprint","slug":"sprint","estimated_start":"2026-9-1","estimated_finish":"2026-09-14","closed":false}]""");
        var (malformedHttp, malformedAuth) = TaigaTestClient.Create(malformed);
        using (malformedHttp)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(malformed, malformedAuth).ListSprintsPageAsync(12));
            Assert.Contains("estimated_start", error.Message);
        }
    }

    [Theory]
    [InlineData("{\"project\":12,\"name\":\"Sprint\",\"slug\":\"sprint\",\"estimated_start\":\"2026-09-01\",\"estimated_finish\":\"2026-09-14\",\"closed\":false}", "id")]
    [InlineData("{\"id\":0,\"project\":12,\"name\":\"Sprint\",\"slug\":\"sprint\",\"estimated_start\":\"2026-09-01\",\"estimated_finish\":\"2026-09-14\",\"closed\":false}", "id")]
    [InlineData("{\"id\":301,\"project\":\"12\",\"name\":\"Sprint\",\"slug\":\"sprint\",\"estimated_start\":\"2026-09-01\",\"estimated_finish\":\"2026-09-14\",\"closed\":false}", "project")]
    public async Task ListSprintsPage_RejectsMalformedIdentity(string sprintJson, string propertyName)
    {
        var handler = SprintRoutes($"[{sprintJson}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).ListSprintsPageAsync(12));
            Assert.Contains(propertyName, error.Message);
        }
    }

    [Fact]
    public async Task ListSprintsPage_RejectsMalformedListResponse()
    {
        var handler = SprintRoutes("{\"not\":\"an array\"}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).ListSprintsPageAsync(12));
            Assert.Contains("invalid sprint list", error.Message);
        }
    }

    [Fact]
    public async Task ListSprintsPage_PreservesUnknownPaginationMetadata()
    {
        var handler = SprintRoutes(
            "[]",
            new Dictionary<string, string>
            {
                ["x-paginated"] = "true",
                ["x-pagination-count"] = "not-a-number",
                ["x-pagination-next"] = "https://evil.example/milestones?page=8"
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListSprintsPageAsync(12, page: 4);
            Assert.Empty(page.Items);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Fact]
    public async Task ListSprintsPage_HonorsPreCancellation()
    {
        var handler = SprintRoutes("[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            using var cancellation = new CancellationTokenSource();
            cancellation.Cancel();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => NewApi(handler, auth).ListSprintsPageAsync(12, cancellationToken: cancellation.Token));
            Assert.Empty(handler.Requests);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    [InlineData(HttpStatusCode.NotFound, "resource not found")]
    public async Task ListSprintsPage_ReportsSafeHttpFailures(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/milestones",
                "{\"detail\":\"secret sprint credentials\"}",
                statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).ListSprintsPageAsync(12));
            Assert.Contains(((int)statusCode).ToString(), error.Message);
            Assert.Contains(category, error.Message);
            Assert.DoesNotContain("secret sprint credentials", error.Message);
        }
    }

    private static SprintApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private static FakeHttpMessageHandler SprintRoutes(
        string json,
        IReadOnlyDictionary<string, string>? headers = null)
        => new FakeHttpMessageHandler().AddJsonRoute(
            HttpMethod.Get,
            "/api/v1/milestones",
            json,
            headers: headers);
}
