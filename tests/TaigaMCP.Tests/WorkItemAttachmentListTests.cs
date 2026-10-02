using System.Text.Json;
using System.Net;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemAttachmentListTests
{
    [Theory]
    [InlineData("epic", "/api/v1/epics/attachments")]
    [InlineData("user_story", "/api/v1/userstories/attachments")]
    [InlineData("task", "/api/v1/tasks/attachments")]
    public async Task ListPage_UsesSharedRouteAndAllowlistedFilters(string kind, string path)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, path, AttachmentListFixtures.OneAttachment);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            var page = await api.ListPageAsync(kind, id: 42, projectId: 123, page: 2);

            var attachment = Assert.Single(page.Items);
            Assert.Equal(901, attachment.Id);
            Assert.Equal(123, attachment.Project);
            Assert.Equal(42, attachment.ObjectId);
            Assert.Equal(7, attachment.Owner);
            Assert.Equal("spec & notes.txt", attachment.Name);
            Assert.Equal("A useful description", attachment.Description);
            Assert.Equal(3, attachment.Order);
            Assert.Equal(2048, attachment.Size);
            Assert.Equal("attachments/spec.txt", attachment.AttachedFile);
            Assert.Equal("https://files.example/901#token", attachment.Url);
            Assert.Equal("https://files.example/901/preview", attachment.PreviewUrl);
            Assert.Null(attachment.ThumbnailCardUrl);
            Assert.Equal("abc123", attachment.Sha1);
            Assert.False(attachment.IsDeprecated);
            Assert.False(attachment.FromComment);
            Assert.Equal("2026-10-02T12:00:00Z", attachment.CreatedDate);
            Assert.Equal("2026-10-02T12:01:00Z", attachment.ModifiedDate);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath == path);
            Assert.Equal("?object_id=42&project=123&page=2", request.Uri.Query);
        }
    }

    [Fact]
    public async Task ListTool_ReturnsStandardEnvelopeAndOmitsNullAttachmentFields()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks/attachments",
                AttachmentListFixtures.NullableAttachment,
                headers: new Dictionary<string, string>
                {
                    ["x-pagination-count"] = "1",
                    ["x-pagination-next"] = "https://fake.taiga.test/api/v1/tasks/attachments?object_id=42&project=123&page=3"
                });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var result = JsonSerializer.Deserialize<JsonElement>(await new WorkItemAttachmentTools(NewApi(handler, auth))
                .ListWorkItemAttachments("task", 42, 123));

            Assert.Equal(1, result.GetProperty("page").GetInt32());
            Assert.Equal(1, result.GetProperty("total").GetInt32());
            Assert.Equal(3, result.GetProperty("next_page").GetInt32());
            Assert.True(result.GetProperty("has_more").GetBoolean());
            var item = Assert.Single(result.GetProperty("items").EnumerateArray());
            Assert.Equal(902, item.GetProperty("id").GetInt32());
            Assert.Equal(string.Empty, item.GetProperty("description").GetString());
            Assert.False(item.TryGetProperty("owner", out _));
            Assert.False(item.TryGetProperty("thumbnail_card_url", out _));
            Assert.False(item.TryGetProperty("content_type", out _));
        }
    }

    [Theory]
    [InlineData("issue", "kind")]
    [InlineData("", "kind")]
    [InlineData("task", "id")]
    public async Task ListPage_RejectsUnsupportedKindOrNonpositiveIdBeforeHttp(string kind, string _)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);
            if (kind == "task")
                await Assert.ThrowsAsync<ArgumentException>(() => api.ListPageAsync(kind, 0, 123));
            else
                await Assert.ThrowsAsync<ArgumentException>(() => api.ListPageAsync(kind, 42, 123));

            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath != "/api/v1/auth");
        }
    }

    [Fact]
    public async Task ListPage_RejectsMalformedRequiredIdentity()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/attachments",
                "[{\"id\":0,\"project\":123,\"object_id\":42}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).ListPageAsync("epic", 42, 123));

            Assert.Contains("attachment id", error.Message);
        }
    }

    [Fact]
    public async Task ListPage_EmptyPagePreservesMissingAndMalformedPaginationAsNull()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/userstories/attachments",
                "[]",
                headers: new Dictionary<string, string>
                {
                    ["x-paginated"] = "true",
                    ["x-pagination-count"] = "not-a-number",
                    ["x-pagination-next"] = "https://evil.example/attachments?page=8"
                });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListPageAsync("user_story", 42, 123, page: 4);

            Assert.Empty(page.Items);
            Assert.Equal(4, page.Page);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Fact]
    public async Task ListPage_MissingPaginationHeadersRemainNull()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/epics/attachments", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListPageAsync("epic", 42, 123);

            Assert.Empty(page.Items);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Fact]
    public async Task ListPage_RejectsNonpositivePageBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).ListPageAsync("task", 42, 123, page: 0));

            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath != "/api/v1/auth");
        }
    }

    [Fact]
    public async Task ListPage_PropagatesCancellationThroughFakeHttpBoundary()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/epics/attachments", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                NewApi(handler, auth).ListPageAsync("epic", 42, 123, cancellationToken: cancellation.Token));

            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath != "/api/v1/auth");
        }
    }

    [Fact]
    public async Task ListPage_RejectsNonArrayResponse()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments", "{\"items\":[]}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).ListPageAsync("task", 42, 123));

            Assert.Contains("invalid work-item attachment list", error.Message);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    [InlineData(HttpStatusCode.NotFound, "resource not found")]
    public async Task ListTool_ReportsSafeHttpFailures(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks/attachments",
                "{\"detail\":\"attachment secret\"}",
                statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<ModelContextProtocol.McpException>(() =>
                new WorkItemAttachmentTools(NewApi(handler, auth))
                    .ListWorkItemAttachments("task", 42, 123));

            Assert.Contains(((int)statusCode).ToString(), error.Message);
            Assert.Contains(category, error.Message);
            Assert.DoesNotContain("attachment secret", error.Message);
        }
    }

    private static WorkItemAttachmentApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));
}

internal static class AttachmentListFixtures
{
    public const string OneAttachment = """
        [{
          "id":901,
          "project":123,
          "object_id":42,
          "owner":7,
          "name":"spec & notes.txt",
          "description":"A useful description",
          "order":3,
          "size":2048,
          "attached_file":"attachments/spec.txt",
          "url":"https://files.example/901#token",
          "preview_url":"https://files.example/901/preview",
          "thumbnail_card_url":null,
          "sha1":"abc123",
          "is_deprecated":false,
          "from_comment":false,
          "created_date":"2026-10-02T12:00:00Z",
          "modified_date":"2026-10-02T12:01:00Z"
        }]
        """;

    public const string NullableAttachment = """
        [{
          "id":902,
          "project":123,
          "object_id":42,
          "name":"empty-description.txt",
          "description":"",
          "order":0,
          "size":0,
          "attached_file":"attachments/empty-description.txt",
          "url":"https://files.example/902",
          "preview_url":null,
          "thumbnail_card_url":null,
          "sha1":"",
          "is_deprecated":false,
          "from_comment":false
        }]
        """;
}
