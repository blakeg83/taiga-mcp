using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class UserStoryCreateTests
{
    [Fact]
    public async Task CreateUserStoryAsync_MinimalRequestPreservesServerDefaultsAndMapsDetail()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/userstories",
                """
                {
                  "id":102,
                  "ref":18,
                  "project":12,
                  "subject":"Allow saved searches",
                  "status":7,
                  "status_extra_info":{"name":"Ready"},
                  "assigned_to":null,
                  "tags":[],
                  "milestone":null,
                  "version":4
                }
                """,
                HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var story = await api.CreateUserStoryAsync(12, "Allow saved searches");

            Assert.Equal(102, story.Id);
            Assert.Equal(18, story.Ref);
            Assert.Equal(12, story.Project);
            Assert.Equal("Ready", story.Status);
            Assert.Null(story.AssignedTo);
            Assert.Empty(story.Tags!);
            Assert.Null(story.Milestone);
            Assert.Equal(4, story.Version);

            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/userstories"));
            using var body = JsonDocument.Parse(request.Body);
            Assert.Equal(
                new[] { "project", "subject" },
                body.RootElement.EnumerateObject().Select(property => property.Name).ToArray());
            Assert.Equal(12, body.RootElement.GetProperty("project").GetInt32());
            Assert.Equal("Allow saved searches", body.RootElement.GetProperty("subject").GetString());
        }
    }

    [Fact]
    public async Task CreateUserStoryAsync_PopulatedRequestMapsPublicNamesAndPreservesText()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/userstories", UserStoryCreateFixtures.CreatedStory, HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));
            const string description = "  Acceptance: saved searches can be reopened.  ";

            var story = await api.CreateUserStoryAsync(
                12,
                "Allow saved searches",
                description,
                status: 7,
                assigned_to: 42,
                tags: ["search", "saved"],
                milestoneId: 55);

            Assert.Equal(102, story.Id);
            Assert.Equal("Acceptance: saved searches can be reopened.", story.Description);
            Assert.Equal(7, story.StatusId);
            Assert.Equal(42, story.AssignedTo);
            Assert.Equal(55, story.Milestone);

            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/userstories"));
            using var body = JsonDocument.Parse(request.Body);
            Assert.Equal(
                new[] { "assigned_to", "description", "milestone", "project", "status", "subject", "tags" },
                body.RootElement.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
            Assert.Equal(description, body.RootElement.GetProperty("description").GetString());
            Assert.Equal(7, body.RootElement.GetProperty("status").GetInt32());
            Assert.Equal(42, body.RootElement.GetProperty("assigned_to").GetInt32());
            Assert.Equal(55, body.RootElement.GetProperty("milestone").GetInt32());
            Assert.Equal(new[] { "search", "saved" }, body.RootElement.GetProperty("tags").EnumerateArray().Select(tag => tag.GetString()));
        }
    }

    [Fact]
    public async Task CreateUserStoryAsync_SendsExplicitEmptyDescriptionAndTags()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/userstories", UserStoryCreateFixtures.CreatedStory, HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await api.CreateUserStoryAsync(12, "Allow saved searches", description: "", tags: []);

            using var body = JsonDocument.Parse(Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/userstories")).Body);
            Assert.Equal("", body.RootElement.GetProperty("description").GetString());
            Assert.Empty(body.RootElement.GetProperty("tags").EnumerateArray());
        }
    }

    [Theory]
    [InlineData(0, "valid", null, null, null)]
    [InlineData(12, " ", null, null, null)]
    [InlineData(12, "valid", 0, null, null)]
    [InlineData(12, "valid", null, -1, null)]
    [InlineData(12, "valid", null, null, 0)]
    public async Task CreateUserStoryAsync_RejectsInvalidInputsBeforeHttp(
        int projectId,
        string subject,
        int? status,
        int? assignedTo,
        int? milestoneId)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAsync<ArgumentException>(() => api.CreateUserStoryAsync(
                projectId,
                subject,
                status: status,
                assigned_to: assignedTo,
                milestoneId: milestoneId));

            Assert.Empty(handler.Requests);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest, "validation failed")]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    public async Task CreateUserStoryAsync_ReportsHttpFailureWithoutRetry(
        HttpStatusCode statusCode,
        string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/userstories",
                "{\"detail\":\"secret story data\"}",
                statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                api.CreateUserStoryAsync(12, "Allow saved searches"));

            Assert.Contains(((int)statusCode).ToString(), exception.Message);
            Assert.Contains(category, exception.Message);
            Assert.DoesNotContain("secret story data", exception.Message);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/userstories"));
        }
    }

    [Fact]
    public async Task CreateUserStoryAsync_ReportsAmbiguousTransportFailureWithoutRetry()
    {
        var handler = new FakeHttpMessageHandler()
            .AddExceptionRoute(
                HttpMethod.Post,
                "/api/v1/userstories",
                new HttpRequestException("secret connection details"));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                api.CreateUserStoryAsync(12, "Allow saved searches"));

            Assert.Contains("may already have applied", exception.Message);
            Assert.DoesNotContain("secret connection details", exception.Message);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/userstories"));
        }
    }

}
