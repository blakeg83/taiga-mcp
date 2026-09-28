using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Caching;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class ListFilterTests
{
    [Theory]
    [InlineData(null, "?page=1")]
    [InlineData("6", "?member=6&page=1")]
    [InlineData("6&other=1", "?member=6%26other%3D1&page=1")]
    public async Task ListProjects_DefaultOrExplicitMember_EncodesExactly(string? member, string query)
    {
        var handler = new FakeHttpMessageHandler().AddJsonRoute(HttpMethod.Get, "/api/v1/projects", "[{\"id\":123,\"slug\":\"demo\",\"name\":\"Demo\"}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var tools = new ProjectTools(new ProjectApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)));
            var result = member is null ? await tools.ListProjects() : await tools.ListProjects(member);
            Assert.Equal(123, JsonSerializer.Deserialize<JsonElement>(result)[0].GetProperty("id").GetInt32());
            Assert.Equal(query, handler.Requests.Last().Uri.Query);
        }
    }

    [Fact]
    public async Task ListUserStories_CustomLabels_UsesVerifiedFlagsWithoutNameExclusions()
    {
        const string statuses = """
            [{"id":1,"name":"Done","is_closed":false,"is_archived":false},
             {"id":2,"name":"Terminado","is_closed":true,"is_archived":false},
             {"id":3,"name":"Guardado","is_closed":false,"is_archived":true},
             {"id":4,"name":"Archived","is_closed":false,"is_archived":false}]
            """;
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/userstory-statuses", statuses)
            .AddRoute(HttpMethod.Get, "/api/v1/userstories", request =>
            {
                Assert.Equal("?project=123&page=2&status__is_archived=false&status__is_closed=false", request.Uri.Query);
                // Simulate the pinned Taiga flag filters, including custom/localized labels.
                var selected = JsonSerializer.Deserialize<JsonElement>(statuses).EnumerateArray()
                    .Where(status => !status.GetProperty("is_closed").GetBoolean() && !status.GetProperty("is_archived").GetBoolean())
                    .Select(status => new { id = status.GetProperty("id").GetInt32() + 10, status = status.GetProperty("id").GetInt32() });
                return AuthenticationTests.Json(JsonSerializer.Serialize(selected));
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));
            var stories = await api.ListUserStoriesAsync(123, 2);
            Assert.Equal(new[] { "Done", "Archived" }, stories.Select(story => story.Status));
            Assert.DoesNotContain(stories, story => story.Status == "Terminado" || story.Status == "Guardado");
        }
    }

    [Fact]
    public async Task ListIssues_OpenOnly_DropsUnsupportedArchiveAndRedundantStatusQueries()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-statuses", "[{\"id\":1,\"name\":\"Abierto\",\"is_closed\":false}]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/severities", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-types", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/priorities", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issues", "[{\"id\":42,\"project\":123,\"status\":1}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
            var issues = await new IssueApi(transport, new IssueMetadataCache(transport)).ListIssuesAsync(123, 2);
            Assert.Equal("Abierto", Assert.Single(issues).Status);
            Assert.Equal("?project=123&page=2&status__is_closed=false", handler.Requests.Last().Uri.Query);
            Assert.Single(handler.Requests, r => r.Uri.AbsolutePath.EndsWith("/issue-statuses"));
            Assert.DoesNotContain(handler.Requests, r => r.Uri.Query.Contains("exclude_status") || r.Uri.Query.Contains("is_archived"));
        }
    }
}
