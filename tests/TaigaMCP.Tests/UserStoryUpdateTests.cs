using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class UserStoryUpdateTests
{
    [Theory]
    [InlineData("omitted")]
    [InlineData("set")]
    [InlineData("clear")]
    public async Task UpdateUserStoryAsync_UsesPresenceAwareAssignmentPayload(string assignmentCase)
    {
        var handler = CreateUpdateHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var story = assignmentCase switch
            {
                "omitted" => await api.UpdateUserStoryAsync(102, version: 7, description: "Changed"),
                "set" => await api.UpdateUserStoryAsync(102, version: 7, description: "Changed", assigned_to: 42),
                "clear" => await api.UpdateUserStoryAsync(102, version: 7, description: "Changed", clearFields: ["assigned_to"]),
                _ => throw new InvalidOperationException()
            };

            Assert.Equal(8, story.Version);
            Assert.Equal("Server subject", story.Subject);
            var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            using var body = JsonDocument.Parse(patch.Body);
            var root = body.RootElement;
            AssertPatchProperties(
                root,
                assignmentCase == "omitted"
                    ? ["description", "version"]
                    : ["assigned_to", "description", "version"]);
            Assert.Equal(7, root.GetProperty("version").GetInt32());
            Assert.Equal("Changed", root.GetProperty("description").GetString());

            if (assignmentCase == "omitted")
                Assert.False(root.TryGetProperty("assigned_to", out _));
            else if (assignmentCase == "set")
                Assert.Equal(42, root.GetProperty("assigned_to").GetInt32());
            else
                Assert.Equal(JsonValueKind.Null, root.GetProperty("assigned_to").ValueKind);
        }
    }

    [Fact]
    public async Task UpdateUserStoryAsync_MapsMilestoneAndSupportsExplicitSprintRemoval()
    {
        var setHandler = CreateUpdateHandler();
        var (setHttp, setAuth) = TaigaTestClient.Create(setHandler);
        using (setHttp)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(setHandler), setAuth));
            await api.UpdateUserStoryAsync(102, version: 7, milestoneId: 55);

            var setPatch = Assert.Single(setHandler.Requests, request => request.Method == HttpMethod.Patch);
            using var setBody = JsonDocument.Parse(setPatch.Body);
            AssertPatchProperties(setBody.RootElement, ["milestone", "version"]);
            Assert.Equal(55, setBody.RootElement.GetProperty("milestone").GetInt32());
        }

        var clearHandler = CreateUpdateHandler();
        var (clearHttp, clearAuth) = TaigaTestClient.Create(clearHandler);
        using (clearHttp)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(clearHandler), clearAuth));
            await api.UpdateUserStoryAsync(102, version: 7, clearFields: ["milestone"]);

            var clearPatch = Assert.Single(clearHandler.Requests, request => request.Method == HttpMethod.Patch);
            using var clearBody = JsonDocument.Parse(clearPatch.Body);
            AssertPatchProperties(clearBody.RootElement, ["milestone", "version"]);
            Assert.Equal(JsonValueKind.Null, clearBody.RootElement.GetProperty("milestone").ValueKind);
        }
    }

    [Fact]
    public async Task UpdateUserStoryAsync_SendsExplicitEmptyDescriptionAndTags()
    {
        var handler = CreateUpdateHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));
            await api.UpdateUserStoryAsync(102, version: 7, description: "", tags: []);

            var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            using var body = JsonDocument.Parse(patch.Body);
            AssertPatchProperties(body.RootElement, ["description", "tags", "version"]);
            Assert.Equal(string.Empty, body.RootElement.GetProperty("description").GetString());
            Assert.Empty(body.RootElement.GetProperty("tags").EnumerateArray());
        }
    }

    [Fact]
    public async Task UpdateUserStoryAsync_AllowsCommentOnlyUpdateWithoutOtherFields()
    {
        var handler = CreateUpdateHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));
            await api.UpdateUserStoryAsync(102, version: 7, comment: "Returned to backlog.");

            var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            using var body = JsonDocument.Parse(patch.Body);
            AssertPatchProperties(body.RootElement, ["comment", "version"]);
            Assert.Equal("Returned to backlog.", body.RootElement.GetProperty("comment").GetString());
        }
    }

    [Theory]
    [InlineData("id")]
    [InlineData("version")]
    [InlineData("status")]
    [InlineData("assigned")]
    [InlineData("milestone")]
    [InlineData("subject")]
    [InlineData("no-change")]
    [InlineData("unsupported-clear")]
    [InlineData("conflicting-clear")]
    public async Task UpdateUserStoryAsync_RejectsInvalidInputsBeforeHttp(string scenario)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAsync<ArgumentException>(() => scenario switch
            {
                "id" => api.UpdateUserStoryAsync(0, version: 7, description: "Changed"),
                "version" => api.UpdateUserStoryAsync(102, version: -1, description: "Changed"),
                "status" => api.UpdateUserStoryAsync(102, version: 7, status: 0),
                "assigned" => api.UpdateUserStoryAsync(102, version: 7, assigned_to: 0),
                "milestone" => api.UpdateUserStoryAsync(102, version: 7, milestoneId: 0),
                "subject" => api.UpdateUserStoryAsync(102, version: 7, subject: "  "),
                "no-change" => api.UpdateUserStoryAsync(102, version: 7),
                "unsupported-clear" => api.UpdateUserStoryAsync(102, version: 7, clearFields: ["description"]),
                "conflicting-clear" => api.UpdateUserStoryAsync(102, version: 7, assigned_to: 42, clearFields: ["assigned_to"]),
                _ => throw new InvalidOperationException()
            });

            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest, "{\"version\":[\"invalid synthetic-token\"]}", "400", "version")]
    [InlineData(HttpStatusCode.Conflict, "{\"detail\":\"Version conflict synthetic-token\"}", "409", "version")]
    public async Task UpdateUserStoryAsync_PropagatesSafeHttpStatusWithoutRetry(
        HttpStatusCode statusCode,
        string errorBody,
        string expectedStatus,
        string expectedDetail)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/userstories/102", errorBody, statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                api.UpdateUserStoryAsync(102, version: 7, status: 1));

            Assert.Contains(expectedStatus, exception.Message);
            Assert.Contains(expectedDetail, exception.Message, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic-token", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Fact]
    public async Task UpdateUserStoryAsync_ReportsMalformedSuccessWithoutRetry()
    {
        var handler = new FakeHttpMessageHandler()
            .AddTextRoute(HttpMethod.Patch, "/api/v1/userstories/102", "not json");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                api.UpdateUserStoryAsync(102, version: 7, status: 1));

            Assert.Contains("may already have applied", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    private static FakeHttpMessageHandler CreateUpdateHandler()
        => new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Patch,
                "/api/v1/userstories/102",
                """
                {"id":102,"ref":18,"project":12,"subject":"Server subject","description":"Server description","status":7,"status_extra_info":{"name":"Ready"},"assigned_to":42,"tags":[["search","#336699"]],"milestone":55,"modified_date":"2026-09-28T12:30:00Z","version":8}
                """);

    private static void AssertPatchProperties(JsonElement body, params string[] expectedNames)
    {
        var actualNames = body.EnumerateObject().Select(property => property.Name);
        Assert.Equal(
            expectedNames.OrderBy(name => name, StringComparer.Ordinal),
            actualNames.OrderBy(name => name, StringComparer.Ordinal));
    }
}
