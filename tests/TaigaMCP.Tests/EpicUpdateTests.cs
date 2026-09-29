using System.Text.Json;
using System.Net;
using TaigaMCP.Api;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class EpicUpdateContractTests
{
    [Theory]
    [InlineData("status-only", false)]
    [InlineData("unassignment", true)]
    [InlineData("empty-description-and-tags", false)]
    [InlineData("color-change", false)]
    [InlineData("comment-only", false)]
    public void EpicUpdateDto_UsesPresenceAwarePatchPayload(string fixtureName, bool clearAssignedTo)
    {
        var update = fixtureName switch
        {
            "status-only" => new EpicUpdateDto { Status = 7, Version = 4 },
            "unassignment" => new EpicUpdateDto { Version = 4 },
            "empty-description-and-tags" => new EpicUpdateDto { Description = "", Tags = [], Version = 4 },
            "color-change" => new EpicUpdateDto { Color = "#336699", Version = 4 },
            "comment-only" => new EpicUpdateDto { Comment = "Delivery complete.", Version = 4 },
            _ => throw new InvalidOperationException($"Unknown fixture '{fixtureName}'.")
        };

        var actual = JsonSerializer.SerializeToElement(update.ToPatchPayload(clearAssignedTo));
        var expected = JsonSerializer.Deserialize<JsonElement>(EpicUpdateFixtures.ExpectedRequest(fixtureName));

        Assert.True(JsonElement.DeepEquals(expected, actual));
    }
}

public sealed class EpicUpdateApiTests
{
    [Theory]
    [InlineData("status-only")]
    [InlineData("unassignment")]
    [InlineData("empty-description-and-tags")]
    [InlineData("color-change")]
    [InlineData("comment-only")]
    public async Task UpdateEpicAsync_SendsOnlyRequestedFieldsAndMapsAuthoritativeDetail(string fixtureName)
    {
        var handler = CreateUpdateHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var epic = fixtureName switch
            {
                "status-only" => await NewApi(handler, auth).UpdateEpicAsync(301, 4, status: 7),
                "unassignment" => await NewApi(handler, auth).UpdateEpicAsync(301, 4, clearFields: ["assigned_to"]),
                "empty-description-and-tags" => await NewApi(handler, auth).UpdateEpicAsync(301, 4, description: "", tags: []),
                "color-change" => await NewApi(handler, auth).UpdateEpicAsync(301, 4, color: "#336699"),
                "comment-only" => await NewApi(handler, auth).UpdateEpicAsync(301, 4, comment: "Delivery complete."),
                _ => throw new InvalidOperationException($"Unknown fixture '{fixtureName}'.")
            };

            Assert.Equal(301, epic.Id);
            Assert.Equal(5, epic.Version);
            Assert.Equal("Server epic", epic.Subject);

            var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            using var body = JsonDocument.Parse(patch.Body);
            var expected = JsonSerializer.Deserialize<JsonElement>(EpicUpdateFixtures.ExpectedRequest(fixtureName));
            Assert.True(JsonElement.DeepEquals(expected, body.RootElement));
            Assert.Equal("application/json", patch.Headers["Content-Type"].Single().Split(';')[0]);
        }
    }

    [Theory]
    [InlineData("id")]
    [InlineData("version")]
    [InlineData("status")]
    [InlineData("assigned")]
    [InlineData("subject")]
    [InlineData("no-change")]
    [InlineData("unsupported-clear")]
    [InlineData("conflicting-clear")]
    public async Task UpdateEpicAsync_RejectsInvalidInputsBeforeHttp(string scenario)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);

            await Assert.ThrowsAsync<ArgumentException>(() => scenario switch
            {
                "id" => api.UpdateEpicAsync(0, 4, description: "Changed"),
                "version" => api.UpdateEpicAsync(301, -1, description: "Changed"),
                "status" => api.UpdateEpicAsync(301, 4, status: 0),
                "assigned" => api.UpdateEpicAsync(301, 4, assigned_to: 0),
                "subject" => api.UpdateEpicAsync(301, 4, subject: "  "),
                "no-change" => api.UpdateEpicAsync(301, 4),
                "unsupported-clear" => api.UpdateEpicAsync(301, 4, clearFields: ["description"]),
                "conflicting-clear" => api.UpdateEpicAsync(301, 4, assigned_to: 42, clearFields: ["assigned_to"]),
                _ => throw new InvalidOperationException()
            });

            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest, "{\"version\":[\"invalid synthetic-token\"]}", "400", "version")]
    [InlineData(HttpStatusCode.Conflict, "{\"detail\":\"Version conflict synthetic-token\"}", "409", "version")]
    [InlineData(HttpStatusCode.BadRequest, "{\"status\":[\"wrong project synthetic-token\"]}", "400", "status")]
    [InlineData(HttpStatusCode.Forbidden, "{\"detail\":\"permission synthetic-token\"}", "403", "permission denied")]
    [InlineData(HttpStatusCode.NotFound, "{\"detail\":\"missing synthetic-token\"}", "404", "resource not found")]
    public async Task UpdateEpicAsync_PropagatesSafeHttpStatusWithoutRetry(
        HttpStatusCode statusCode,
        string errorBody,
        string expectedStatus,
        string expectedDetail)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/epics/301", errorBody, statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UpdateEpicAsync(301, 4, status: 7));

            Assert.Contains(expectedStatus, exception.Message);
            Assert.Contains(expectedDetail, exception.Message, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic-token", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Get);
        }
    }

    [Fact]
    public async Task UpdateEpicAsync_AllowsServerAcceptedStaleVersionWithoutReplay()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Patch,
                "/api/v1/epics/301",
                EpicUpdateFixtures.AcceptedStaleVersionResponse);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var epic = await NewApi(handler, auth).UpdateEpicAsync(301, 3, status: 7);

            Assert.Equal(5, epic.Version);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Get);
        }
    }

    [Fact]
    public async Task UpdateEpicAsync_ClosesAndReopensUsingDiscoveredStatusesAndReturnedVersions()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/epic-statuses", EpicStatusFixtures.LocalizedProjectStatuses)
            .AddJsonRoute(HttpMethod.Get, "/api/v1/epics/301", EpicDetailFixtures.Rich)
            .AddRoute(
                HttpMethod.Patch,
                "/api/v1/epics/301",
                request =>
                {
                    using var body = JsonDocument.Parse(request.Body);
                    var status = body.RootElement.GetProperty("status").GetInt32();
                    var response = status == 31
                        ? EpicUpdateFixtures.ClosedEpicResponse
                        : EpicUpdateFixtures.ReopenedEpicResponse;
                    return new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent(response, System.Text.Encoding.UTF8, "application/json")
                    };
                });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            var statuses = await api.ListEpicStatusesAsync(123);
            var closedStatus = Assert.Single(statuses, status => status.IsClosed == true);
            var openStatus = Assert.Single(statuses, status => status.IsClosed == false);
            var current = await api.GetEpicAsync(301);

            var closed = await api.UpdateEpicAsync(301, current.Version, status: closedStatus.Id);
            var reopened = await api.UpdateEpicAsync(301, closed.Version, status: openStatus.Id);

            Assert.True(closed.IsClosed);
            Assert.Equal(5, closed.Version);
            Assert.False(reopened.IsClosed);
            Assert.Equal(6, reopened.Version);

            var patches = handler.Requests.Where(request => request.Method == HttpMethod.Patch).ToArray();
            Assert.Equal(2, patches.Length);
            using var closeBody = JsonDocument.Parse(patches[0].Body);
            using var reopenBody = JsonDocument.Parse(patches[1].Body);
            Assert.Equal(4, closeBody.RootElement.GetProperty("version").GetInt32());
            Assert.Equal(31, closeBody.RootElement.GetProperty("status").GetInt32());
            Assert.Equal(5, reopenBody.RootElement.GetProperty("version").GetInt32());
            Assert.Equal(30, reopenBody.RootElement.GetProperty("status").GetInt32());
            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath.Contains("related_userstories", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task UpdateEpicAsync_ReportsMalformedSuccessWithoutRetry()
    {
        var handler = new FakeHttpMessageHandler()
            .AddTextRoute(HttpMethod.Patch, "/api/v1/epics/301", "not json");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UpdateEpicAsync(301, 4, status: 7));

            Assert.Contains("may already have applied", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Fact]
    public async Task UpdateEpicAsync_ReportsMalformedMappedSuccessAsPotentiallyApplied()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/epics/301", "{\"version\":5}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UpdateEpicAsync(301, 4, status: 7));

            Assert.Contains("may already have applied", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Get);
        }
    }

    [Fact]
    public async Task UpdateEpicAsync_ReportsAmbiguousTransportFailureWithoutRetry()
    {
        var handler = new FakeHttpMessageHandler()
            .AddExceptionRoute(
                HttpMethod.Patch,
                "/api/v1/epics/301",
                new IOException("secret synthetic-token"));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UpdateEpicAsync(301, 4, status: 7));

            Assert.Contains("transport failure", exception.Message, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("may already have applied", exception.Message);
            Assert.DoesNotContain("synthetic-token", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Fact]
    public async Task UpdateEpicAsync_HonorsPreCancellationBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                NewApi(handler, auth).UpdateEpicAsync(301, 4, status: 7, cancellationToken: cancellation.Token));

            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    private static EpicApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private static FakeHttpMessageHandler CreateUpdateHandler()
        => new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/epics/301", EpicUpdateFixtures.UpdatedEpic);
}

internal static class EpicUpdateFixtures
{
    public static string ExpectedRequest(string name)
        => name switch
        {
            "status-only" => StatusOnlyRequest,
            "unassignment" => UnassignmentRequest,
            "empty-description-and-tags" => EmptyDescriptionAndTagsRequest,
            "color-change" => ColorChangeRequest,
            "comment-only" => CommentOnlyRequest,
            _ => throw new ArgumentException($"Unknown fixture '{name}'.", nameof(name))
        };

    private const string StatusOnlyRequest = """
        {"status":7,"version":4}
        """;

    private const string UnassignmentRequest = """
        {"assigned_to":null,"version":4}
        """;

    private const string EmptyDescriptionAndTagsRequest = """
        {"description":"","tags":[],"version":4}
        """;

    private const string ColorChangeRequest = """
        {"color":"#336699","version":4}
        """;

    private const string CommentOnlyRequest = """
        {"comment":"Delivery complete.","version":4}
        """;

    public const string UpdatedEpic = """
        {"id":301,"ref":12,"project":123,"subject":"Server epic","description":"Server description","status":7,"status_extra_info":{"name":"Ready"},"assigned_to":42,"color":"#336699","tags":[["search","#336699"]],"modified_date":"2026-09-29T12:30:00Z","version":5}
        """;

    public const string AcceptedStaleVersionResponse = """
        {"id":301,"ref":12,"project":123,"subject":"Server epic","status":7,"status_extra_info":{"name":"Ready"},"version":5}
        """;

    public const string ClosedEpicResponse = """
        {"id":301,"ref":12,"project":123,"subject":"Server epic","status":31,"status_extra_info":{"name":"Terminé"},"is_closed":true,"version":5}
        """;

    public const string ReopenedEpicResponse = """
        {"id":301,"ref":12,"project":123,"subject":"Server epic","status":30,"status_extra_info":{"name":"En revisión"},"is_closed":false,"version":6}
        """;
}
