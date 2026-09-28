using System.Text.Json;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class TaigaApiContractTests
{
    [Fact]
    public async Task GetIssueCommentsAsync_FiltersHiddenAndNonCommentHistory()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/history/issue/42",
                """
                [
                  {"id":"hidden","is_hidden":true,"comment":"do not return"},
                  {"id":"field-change","comment":null},
                  {"id":"empty","comment":""},
                  {"id":"visible","comment":"Looks good","created_at":"2026-09-28T12:00:00Z","user":{"name":"Example"}}
                ]
                """);
        var (http, auth) = TaigaTestClient.Create(handler);
        var api = new IssueApi(http, auth, new IssueMetadataCache(http, auth));

        var comments = await api.GetIssueCommentsAsync(42);

        var comment = Assert.Single(comments);
        Assert.Equal("visible", comment.Id);
        Assert.Equal("Looks good", comment.Comment);
        var historyRequest = Assert.Single(handler.Requests, request => request.Uri.AbsolutePath.EndsWith("/history/issue/42"));
        Assert.Equal("Bearer synthetic-token", historyRequest.Headers["Authorization"].Single());
    }

    [Fact]
    public async Task UpdateIssueAsync_ForwardsCallerVersionAndMapsReturnedIssue()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Patch,
                "/api/v1/issues/42",
                """
                {"id":42,"ref":7,"project":123,"subject":"Updated","status":1,"severity":2,"type":3,"priority":4,"version":6}
                """)
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-statuses", """[{"id":1,"name":"Open"}]""")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/severities", """[{"id":2,"name":"Normal"}]""")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-types", """[{"id":3,"name":"Bug"}]""")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/priorities", """[{"id":4,"name":"Normal"}]""");
        var (http, auth) = TaigaTestClient.Create(handler);
        var api = new IssueApi(http, auth, new IssueMetadataCache(http, auth));

        var issue = await api.UpdateIssueAsync(42, version: 5, subject: "Updated");

        Assert.Equal(6, issue.Version);
        Assert.Equal("Open", issue.Status);
        var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
        using var body = JsonDocument.Parse(patch.Body);
        Assert.Equal(5, body.RootElement.GetProperty("version").GetInt32());
        Assert.Equal("Updated", body.RootElement.GetProperty("subject").GetString());
        Assert.Equal("Bearer synthetic-token", patch.Headers["Authorization"].Single());
    }

    [Fact]
    public async Task ListUserStoriesAsync_MapsStatusAndNullableFields()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstory-statuses",
                """[{"id":10,"name":"Ready"}]""")
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstories",
                """
                [{"id":90,"ref":12,"subject":"Ship fix","status":10,"assigned_to":null,"modified_date":"2026-09-28T12:02:00Z"}]
                """);
        var (http, auth) = TaigaTestClient.Create(handler);
        var api = new UserStoryApi(http, auth);

        var stories = await api.ListUserStoriesAsync(123, page: 2);

        var story = Assert.Single(stories);
        Assert.Equal(90, story.Id);
        Assert.Equal(12, story.Ref);
        Assert.Equal("Ready", story.Status);
        Assert.Null(story.AssignedTo);
        var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/userstories"));
        Assert.Equal("2", ParseQuery(request.Uri).GetValueOrDefault("page"));
        Assert.Equal("false", ParseQuery(request.Uri).GetValueOrDefault("status__is_archived"));
        Assert.Equal("false", ParseQuery(request.Uri).GetValueOrDefault("status__is_closed"));
    }

    [Fact]
    public async Task AuthenticatedRequest_AttachesBearerButAuthRequestDoesNot()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/resolver", "{\"project\":123}");
        var (http, auth) = TaigaTestClient.Create(handler);
        var api = new ProjectApi(http, auth);

        Assert.Equal(123, await api.ResolveProjectIdAsync("demo project"));

        var authRequest = Assert.Single(handler.Requests, request => request.Uri.AbsolutePath.EndsWith("/auth"));
        Assert.False(authRequest.Headers.ContainsKey("Authorization"));
        var resolverRequest = Assert.Single(handler.Requests, request => request.Uri.AbsolutePath.EndsWith("/resolver"));
        Assert.Equal("Bearer synthetic-token", resolverRequest.Headers["Authorization"].Single());
        Assert.Equal("demo%20project", resolverRequest.Uri.Query.Split("project=", StringSplitOptions.None).Last());
    }

    private static Dictionary<string, string> ParseQuery(Uri uri)
        => uri.Query.TrimStart('?')
            .Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Split('=', 2))
            .ToDictionary(
                parts => Uri.UnescapeDataString(parts[0]),
                parts => parts.Length == 1 ? string.Empty : Uri.UnescapeDataString(parts[1]),
                StringComparer.OrdinalIgnoreCase);
}
