using System.Text.Json;
using System.Net;
using TaigaMCP.Api;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class TaskUpdateTests
{
    [Fact]
    public void TaskUpdatePayload_OmitsUnselectedFieldsAndPreservesExplicitEmptyValues()
    {
        var update = new TaskUpdateDto
        {
            Version = 2,
            Description = string.Empty,
            Tags = [],
            IsBlocked = false,
            BlockedNote = string.Empty,
            Comment = "Dependency resolved."
        };

        using var document = JsonDocument.Parse(JsonSerializer.Serialize(update.ToPatchPayload(false)));
        var body = document.RootElement;

        Assert.Equal(
            new[] { "blocked_note", "comment", "description", "is_blocked", "tags", "version" },
            body.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
        Assert.Equal(string.Empty, body.GetProperty("description").GetString());
        Assert.Empty(body.GetProperty("tags").EnumerateArray());
        Assert.False(body.GetProperty("is_blocked").GetBoolean());
        Assert.Equal(string.Empty, body.GetProperty("blocked_note").GetString());
        Assert.Equal(2, body.GetProperty("version").GetInt32());
        Assert.False(body.TryGetProperty("assigned_to", out _));
        Assert.False(body.TryGetProperty("subject", out _));
        Assert.False(body.TryGetProperty("status", out _));
    }

    [Fact]
    public void TaskUpdatePayload_UsesExplicitNullOnlyForAssignmentClear()
    {
        var update = new TaskUpdateDto
        {
            Version = 3,
            AssignedTo = null,
            IsBlocked = true
        };

        using var document = JsonDocument.Parse(JsonSerializer.Serialize(update.ToPatchPayload(true)));
        var body = document.RootElement;

        Assert.Equal(JsonValueKind.Null, body.GetProperty("assigned_to").ValueKind);
        Assert.True(body.GetProperty("is_blocked").GetBoolean());
        Assert.Equal(3, body.GetProperty("version").GetInt32());
        Assert.False(body.TryGetProperty("blocked_note", out _));
    }

    [Theory]
    [InlineData("omitted")]
    [InlineData("set")]
    [InlineData("clear")]
    public async Task UpdateTaskAsync_UsesPresenceAwareAssignmentPayload(string assignmentCase)
    {
        var handler = CreateUpdateHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            _ = assignmentCase switch
            {
                "omitted" => await api.UpdateTaskAsync(203, 2, description: "Changed"),
                "set" => await api.UpdateTaskAsync(203, 2, description: "Changed", assigned_to: 42),
                "clear" => await api.UpdateTaskAsync(203, 2, description: "Changed", clearFields: ["assigned_to"]),
                _ => throw new InvalidOperationException()
            };

            var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            using var body = JsonDocument.Parse(patch.Body);
            var root = body.RootElement;
            AssertPatchProperties(
                root,
                assignmentCase == "omitted"
                    ? ["description", "version"]
                    : ["assigned_to", "description", "version"]);
            Assert.Equal(2, root.GetProperty("version").GetInt32());
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
    public async Task UpdateTaskAsync_SendsExplicitFalseEmptyValuesAndDoesNotTouchParentOrSprint()
    {
        var handler = CreateUpdateHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var task = await NewApi(handler, auth).UpdateTaskAsync(
                203,
                version: 2,
                subject: "Unblocked task",
                description: string.Empty,
                status: 11,
                tags: [],
                isBlocked: false,
                blockedNote: string.Empty,
                comment: "Dependency resolved.");

            Assert.Equal(3, task.Version);
            Assert.Equal("Server task", task.Subject);
            var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            using var body = JsonDocument.Parse(patch.Body);
            AssertPatchProperties(
                body.RootElement,
                "blocked_note", "comment", "description", "is_blocked", "status", "subject", "tags", "version");
            Assert.False(body.RootElement.GetProperty("is_blocked").GetBoolean());
            Assert.Equal(string.Empty, body.RootElement.GetProperty("blocked_note").GetString());
            Assert.Empty(body.RootElement.GetProperty("tags").EnumerateArray());
            Assert.False(body.RootElement.TryGetProperty("user_story", out _));
            Assert.False(body.RootElement.TryGetProperty("milestone", out _));
        }
    }

    [Fact]
    public async Task UpdateTaskAsync_AllowsCommentOnlyUpdate()
    {
        var handler = CreateUpdateHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await NewApi(handler, auth).UpdateTaskAsync(203, version: 2, comment: "Progress noted.");

            var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            using var body = JsonDocument.Parse(patch.Body);
            AssertPatchProperties(body.RootElement, "comment", "version");
            Assert.Equal("Progress noted.", body.RootElement.GetProperty("comment").GetString());
        }
    }

    [Theory]
    [InlineData("id")]
    [InlineData("version")]
    [InlineData("status")]
    [InlineData("assigned")]
    [InlineData("subject")]
    [InlineData("empty")]
    [InlineData("blank-comment")]
    [InlineData("unsupported-clear")]
    [InlineData("conflicting-clear")]
    public async Task UpdateTaskAsync_RejectsInvalidInputsBeforeHttp(string scenario)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            await Assert.ThrowsAsync<ArgumentException>(() => scenario switch
            {
                "id" => api.UpdateTaskAsync(0, 2, description: "Changed"),
                "version" => api.UpdateTaskAsync(203, -1, description: "Changed"),
                "status" => api.UpdateTaskAsync(203, 2, status: 0),
                "assigned" => api.UpdateTaskAsync(203, 2, assigned_to: 0),
                "subject" => api.UpdateTaskAsync(203, 2, subject: " "),
                "empty" => api.UpdateTaskAsync(203, 2),
                "blank-comment" => api.UpdateTaskAsync(203, 2, comment: " "),
                "unsupported-clear" => api.UpdateTaskAsync(203, 2, clearFields: ["blocked_note"]),
                "conflicting-clear" => api.UpdateTaskAsync(203, 2, assigned_to: 42, clearFields: ["assigned_to"]),
                _ => throw new InvalidOperationException()
            });

            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest, "{\"version\":[\"invalid synthetic-token\"]}", "400", "version")]
    [InlineData(HttpStatusCode.Conflict, "{\"detail\":\"Version conflict synthetic-token\"}", "409", "version")]
    public async Task UpdateTaskAsync_PropagatesSafeHttpStatusWithoutRetry(
        HttpStatusCode statusCode,
        string errorBody,
        string expectedStatus,
        string expectedDetail)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/tasks/203", errorBody, statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UpdateTaskAsync(203, version: 2, status: 11));

            Assert.Contains(expectedStatus, exception.Message);
            Assert.Contains(expectedDetail, exception.Message, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic-token", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Get);
        }
    }

    [Fact]
    public async Task UpdateTaskAsync_ReportsMalformedSuccessWithoutRetry()
    {
        var handler = new FakeHttpMessageHandler()
            .AddTextRoute(HttpMethod.Patch, "/api/v1/tasks/203", "not json");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UpdateTaskAsync(203, version: 2, status: 11));

            Assert.Contains("may already have applied", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    private static TaskApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
    {
        var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
        return new TaskApi(transport, new UserStoryApi(transport));
    }

    private static FakeHttpMessageHandler CreateUpdateHandler()
        => new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Patch,
                "/api/v1/tasks/203",
                """
                {"id":203,"ref":17,"project":123,"subject":"Server task","description":"Server description","status":11,"status_extra_info":{"name":"Ready"},"assigned_to":42,"user_story":102,"milestone":55,"tags":[["search","#336699"]],"modified_date":"2026-09-28T12:30:00Z","version":3,"is_blocked":false,"blocked_note":""}
                """);

    private static void AssertPatchProperties(JsonElement body, params string[] expectedNames)
    {
        var actualNames = body.EnumerateObject().Select(property => property.Name);
        Assert.Equal(
            expectedNames.OrderBy(name => name, StringComparer.Ordinal),
            actualNames.OrderBy(name => name, StringComparer.Ordinal));
    }
}
