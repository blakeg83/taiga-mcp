using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class UserStoryDetailTests
{
    [Fact]
    public async Task GetUserStoryAsync_MapsDetailFieldsAndRelationshipsWithoutExtraReads()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstories/102",
                """
                {
                  "id":102,
                  "ref":18,
                  "project":12,
                  "subject":"Allow saved searches",
                  "description":"**Acceptance:** preserve Markdown and Unicode — ✓",
                  "status":7,
                  "status_extra_info":{"name":"Ready","color":"#00aa00"},
                  "assigned_to":null,
                  "tags":[["search","#336699"],["backend",null]],
                  "milestone":null,
                  "modified_date":"2026-09-28T12:00:00Z",
                  "version":4,
                  "origin_issue":{"id":201,"ref":9,"subject":"Saved search"},
                  "origin_task":null,
                  "epics":[{"id":301,"ref":2,"subject":"Search","project":{"id":12},"new_field":"kept upstream"}],
                  "future_field":"ignored"
                }
                """);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var story = await api.GetUserStoryAsync(102);

            Assert.Equal(102, story.Id);
            Assert.Equal(18, story.Ref);
            Assert.Equal(12, story.Project);
            Assert.Equal("Allow saved searches", story.Subject);
            Assert.Equal("**Acceptance:** preserve Markdown and Unicode — ✓", story.Description);
            Assert.Equal(7, story.StatusId);
            Assert.Equal("Ready", story.Status);
            Assert.Null(story.AssignedTo);
            Assert.Equal(2, story.Tags!.Count);
            Assert.Equal("search", story.Tags[0][0].GetString());
            Assert.Equal("#336699", story.Tags[0][1].GetString());
            Assert.Null(story.Milestone);
            Assert.Equal("2026-09-28T12:00:00Z", story.Modified);
            Assert.Equal(4, story.Version);
            Assert.Equal(201, story.OriginIssue!.Value.GetProperty("id").GetInt32());
            Assert.Equal(1, story.Epics!.Value.GetArrayLength());
            Assert.Equal("kept upstream", story.Epics.Value[0].GetProperty("new_field").GetString());
            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath.EndsWith("/userstory-statuses"));
            Assert.Single(handler.Requests, request => request.Uri.AbsolutePath.EndsWith("/userstories/102"));
        }
    }

    [Fact]
    public async Task GetUserStoryAsync_UsesProjectStatusLookupWhenExtraInfoIsAbsent()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstories/102",
                """{"id":102,"project":12,"status":7,"version":3}""")
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstory-statuses",
                """[{"id":7,"name":"Ready"}]""");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var story = await api.GetUserStoryAsync(102);

            Assert.Equal(7, story.StatusId);
            Assert.Equal("Ready", story.Status);
            var statusRequest = Assert.Single(handler.Requests, request => request.Uri.AbsolutePath.EndsWith("/userstory-statuses"));
            Assert.Equal("?project=12", statusRequest.Uri.Query);
        }
    }

    [Fact]
    public async Task GetUserStoryTool_OmitsNullsButPreservesEmptyTags()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstories/102",
                """{"id":102,"ref":18,"project":12,"subject":"Backlog","description":"","status":null,"assigned_to":null,"tags":[],"milestone":null,"version":0,"origin_issue":null,"origin_task":null,"epics":null}""");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var storyDto = await api.GetUserStoryAsync(102);
            using var json = JsonDocument.Parse(ToolResponseJson.Serialize(storyDto));
            var story = json.RootElement;
            Assert.Equal(0, story.GetProperty("version").GetInt32());
            Assert.Equal(JsonValueKind.Array, story.GetProperty("tags").ValueKind);
            Assert.False(story.TryGetProperty("assigned_to", out _));
            Assert.False(story.TryGetProperty("milestone", out _));
            Assert.False(story.TryGetProperty("origin_issue", out _));
            Assert.False(story.TryGetProperty("epics", out _));
        }
    }

    [Theory]
    [InlineData("{\"id\":102}")]
    [InlineData("{\"id\":102,\"version\":\"unknown\"}")]
    [InlineData("{\"id\":102,\"version\":-1}")]
    [InlineData("{\"id\":0,\"version\":1}")]
    public async Task GetUserStoryAsync_RejectsMalformedIdentityOrVersion(string payload)
    {
        var handler = new FakeHttpMessageHandler().AddJsonRoute(HttpMethod.Get, "/api/v1/userstories/102", payload);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => api.GetUserStoryAsync(102));

            Assert.Contains("user story", exception.Message);
        }
    }

    [Fact]
    public async Task GetUserStoryAsync_RejectsNonpositiveIdBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAsync<ArgumentException>(() => api.GetUserStoryAsync(0));

            Assert.Empty(handler.Requests);
        }
    }
}
