using System.Net;
using System.Text.Json;
using ModelContextProtocol;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class EpicDetailTests
{
    [Fact]
    public async Task GetEpicAsync_MapsRichDetailWithoutRelationshipReads()
    {
        var handler = EpicRoutes(EpicDetailFixtures.Rich, 301);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var epic = await NewApi(handler, auth).GetEpicAsync(301);

            Assert.Equal(301, epic.Id);
            Assert.Equal(12, epic.Ref);
            Assert.Equal(123, epic.Project);
            Assert.Equal("Saved search epic — ✓", epic.Subject);
            Assert.Equal("**Acceptance:** preserve Markdown and Unicode — ✓", epic.Description);
            Assert.Equal(7, epic.StatusId);
            Assert.Equal("Ready", epic.Status);
            Assert.Null(epic.AssignedTo);
            Assert.Equal("#336699", epic.Color);
            Assert.Equal(2, epic.Tags!.Count);
            Assert.Equal("2026-09-28T12:03:00Z", epic.Modified);
            Assert.False(epic.IsClosed);
            Assert.True(epic.IsBlocked);
            Assert.Equal("Waiting for the saved-search API.", epic.BlockedNote);
            Assert.True(epic.ClientRequirement);
            Assert.False(epic.TeamRequirement);
            Assert.Equal(3, epic.UserStoriesCounts!.Value.GetProperty("total").GetInt32());
            Assert.Equal(4, epic.Version);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/epics/301"));
            Assert.Equal(HttpMethod.Get, request.Method);
            Assert.DoesNotContain(handler.Requests, item => item.Uri.AbsolutePath.Contains("related_userstories"));
            Assert.DoesNotContain(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/epic-statuses"));
        }
    }

    [Theory]
    [InlineData(EpicDetailFixtures.MissingVersion)]
    [InlineData(EpicDetailFixtures.InvalidIdentity)]
    [InlineData(EpicDetailFixtures.InvalidReference)]
    [InlineData(EpicDetailFixtures.InvalidProject)]
    [InlineData(EpicDetailFixtures.InvalidVersion)]
    public async Task GetEpicAsync_RejectsMalformedRequiredDetailFields(string payload)
    {
        var handler = EpicRoutes(payload, 301);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).GetEpicAsync(301));

            Assert.Contains("epic", exception.Message);
        }
    }

    [Fact]
    public async Task GetEpicAsync_RejectsNonpositiveIdBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).GetEpicAsync(0));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task GetEpicAsync_PreservesStatusIdWhenLabelIsUnavailable()
    {
        var handler = EpicRoutes(
            """{"id":301,"ref":12,"project":123,"status":99,"status_extra_info":null,"version":1}""",
            301);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var epic = await NewApi(handler, auth).GetEpicAsync(301);

            Assert.Equal(99, epic.StatusId);
            Assert.Null(epic.Status);
            Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/epics/301"));
        }
    }

    [Fact]
    public async Task GetEpicTool_OmitsMissingOptionalSummaryAndUnknownFields()
    {
        var handler = EpicRoutes(
            """{"id":301,"ref":12,"project":123,"subject":"Backlog","description":"","status":null,"assigned_to":null,"color":null,"tags":[],"version":0,"future_field":{"ignored":true}}""",
            301);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var json = JsonSerializer.Deserialize<JsonElement>(await new EpicTools(NewApi(handler, auth)).GetEpic(301));

            Assert.Equal(0, json.GetProperty("version").GetInt32());
            Assert.Equal(JsonValueKind.Array, json.GetProperty("tags").ValueKind);
            Assert.Empty(json.GetProperty("tags").EnumerateArray());
            Assert.False(json.TryGetProperty("assigned_to", out _));
            Assert.False(json.TryGetProperty("color", out _));
            Assert.False(json.TryGetProperty("user_stories_counts", out _));
            Assert.False(json.TryGetProperty("future_field", out _));
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    [InlineData(HttpStatusCode.NotFound, "resource not found")]
    public async Task GetEpicTool_ReportsSafeHttpFailures(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301",
                "{\"detail\":\"secret epic credentials\"}",
                statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<McpException>(() => new EpicTools(NewApi(handler, auth)).GetEpic(301));

            Assert.Contains(((int)statusCode).ToString(), exception.Message);
            Assert.Contains(category, exception.Message);
            Assert.DoesNotContain("secret epic credentials", exception.Message);
        }
    }

    private static EpicApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private static FakeHttpMessageHandler EpicRoutes(string epic, int epicId)
        => new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, $"/api/v1/epics/{epicId}", epic);
}
