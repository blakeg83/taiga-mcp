using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Caching;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemCommentTests
{
    [Fact]
    public void WorkItemKind_IsClosedToTheFourWireValues()
    {
        Assert.Equal(
            new[] { "issue", "user_story", "task", "epic" },
            Enum.GetNames<WorkItemKind>());
    }

    [Fact]
    public void WorkItemCommentReceipt_UsesTheStableSubmissionShape()
    {
        var receipt = new WorkItemCommentReceipt
        {
            Kind = WorkItemKind.user_story.ToString(),
            Id = 102,
            Version = 8,
            CommentSubmitted = true
        };

        using var document = JsonDocument.Parse(JsonSerializer.Serialize(receipt));
        var properties = document.RootElement.EnumerateObject()
            .Select(property => property.Name)
            .OrderBy(name => name, StringComparer.Ordinal);

        Assert.Equal(new[] { "comment_submitted", "id", "kind", "version" }, properties);
        Assert.Equal("user_story", document.RootElement.GetProperty("kind").GetString());
        Assert.Equal(102, document.RootElement.GetProperty("id").GetInt32());
        Assert.Equal(8, document.RootElement.GetProperty("version").GetInt32());
        Assert.True(document.RootElement.GetProperty("comment_submitted").GetBoolean());
    }

    [Theory]
    [InlineData("issue", 42, "/api/v1/issues/42")]
    [InlineData("user_story", 102, "/api/v1/userstories/102")]
    [InlineData("task", 203, "/api/v1/tasks/203")]
    [InlineData("epic", 301, "/api/v1/epics/301")]
    public async Task DomainApis_SendOnlyCommentAndVersionToTheSelectedRoute(
        string kind,
        int id,
        string expectedPath)
    {
        const string text = "**Done**\n@alice — revisión ✓";
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, expectedPath, "{\"version\":9}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
            var returnedVersion = kind switch
            {
                "issue" => await new IssueApi(transport, new IssueMetadataCache(transport))
                    .AddCommentAsync(id, 8, text),
                "user_story" => await new UserStoryApi(transport).AddCommentAsync(id, 8, text),
                "task" => await new TaskApi(transport).AddCommentAsync(id, 8, text),
                "epic" => await new EpicApi(transport).AddCommentAsync(id, 8, text),
                _ => throw new InvalidOperationException()
            };

            Assert.Equal(9, returnedVersion);
            var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            Assert.Equal(expectedPath, patch.Uri.AbsolutePath);
            using var body = JsonDocument.Parse(patch.Body);
            Assert.Equal(
                new[] { "comment", "version" },
                body.RootElement.EnumerateObject()
                    .Select(property => property.Name)
                    .OrderBy(name => name, StringComparer.Ordinal));
            Assert.Equal(text, body.RootElement.GetProperty("comment").GetString());
            Assert.Equal(8, body.RootElement.GetProperty("version").GetInt32());
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Get);
        }
    }

    [Theory]
    [InlineData("issue")]
    [InlineData("user_story")]
    [InlineData("task")]
    [InlineData("epic")]
    public async Task DomainApis_RejectInvalidCommentInputsBeforeHttp(string kind)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
            Func<Task<int>> call = kind switch
            {
                "issue" => () => new IssueApi(transport, new IssueMetadataCache(transport)).AddCommentAsync(0, 1, "text"),
                "user_story" => () => new UserStoryApi(transport).AddCommentAsync(0, 1, "text"),
                "task" => () => new TaskApi(transport).AddCommentAsync(0, 1, "text"),
                "epic" => () => new EpicApi(transport).AddCommentAsync(0, 1, "text"),
                _ => throw new InvalidOperationException()
            };

            await Assert.ThrowsAsync<ArgumentException>(call);
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Theory]
    [InlineData("issue", "/api/v1/issues/42")]
    [InlineData("user_story", "/api/v1/userstories/102")]
    [InlineData("task", "/api/v1/tasks/203")]
    [InlineData("epic", "/api/v1/epics/301")]
    public async Task DomainApis_PropagateSafeVersionFailuresWithoutRetry(string kind, string path)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, path, "{\"version\":[\"invalid synthetic-token\"]}", HttpStatusCode.BadRequest);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
            Func<Task<int>> call = kind switch
            {
                "issue" => () => new IssueApi(transport, new IssueMetadataCache(transport)).AddCommentAsync(42, 8, "text"),
                "user_story" => () => new UserStoryApi(transport).AddCommentAsync(102, 8, "text"),
                "task" => () => new TaskApi(transport).AddCommentAsync(203, 8, "text"),
                "epic" => () => new EpicApi(transport).AddCommentAsync(301, 8, "text"),
                _ => throw new InvalidOperationException()
            };

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(call);

            Assert.Contains("400", exception.Message);
            Assert.Contains("version", exception.Message, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic-token", exception.Message);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }
}
