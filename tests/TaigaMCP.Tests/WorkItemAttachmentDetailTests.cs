using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemAttachmentDetailTests
{
    [Theory]
    [InlineData("epic", "/api/v1/epics/attachments/901")]
    [InlineData("user_story", "/api/v1/userstories/attachments/901")]
    [InlineData("task", "/api/v1/tasks/attachments/901")]
    public async Task GetAsync_UsesKindSpecificDetailRoute(string kind, string path)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, path, AttachmentDetailFixtures.Detail);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var attachment = await NewApi(handler, auth).GetAsync(kind, 901);

            Assert.Equal(901, attachment.Id);
            Assert.Equal(123, attachment.Project);
            Assert.Equal(42, attachment.ObjectId);
            Assert.Equal(7, attachment.Owner);
            Assert.Equal("résumé & 檔案.txt", attachment.Name);
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

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath != "/api/v1/auth");
            Assert.Equal(HttpMethod.Get, request.Method);
            Assert.Equal(path, request.Uri.AbsolutePath);
            Assert.Empty(request.Uri.Query);
        }
    }

    [Fact]
    public async Task GetTool_ReturnsMetadataAndOmitsNullFields()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks/attachments/902",
                AttachmentDetailFixtures.NullableDetail);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var result = JsonSerializer.Deserialize<JsonElement>(await new WorkItemAttachmentTools(NewApi(handler, auth))
                .GetWorkItemAttachment("task", 902));

            Assert.Equal(902, result.GetProperty("id").GetInt32());
            Assert.Equal(string.Empty, result.GetProperty("description").GetString());
            Assert.False(result.TryGetProperty("owner", out _));
            Assert.False(result.TryGetProperty("preview_url", out _));
            Assert.False(result.TryGetProperty("thumbnail_card_url", out _));
            Assert.False(result.TryGetProperty("content_type", out _));
            Assert.False(result.TryGetProperty("unknown_field", out _));
        }
    }

    [Theory]
    [InlineData("issue")]
    [InlineData("")]
    public async Task GetAsync_RejectsUnsupportedKindBeforeHttp(string kind)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", AttachmentDetailFixtures.Detail);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).GetAsync(kind, 901));
            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath != "/api/v1/auth");
        }
    }

    [Fact]
    public async Task GetAsync_RejectsNonpositiveAttachmentIdBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", AttachmentDetailFixtures.Detail);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).GetAsync("task", 0));
            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath != "/api/v1/auth");
        }
    }

    [Fact]
    public async Task GetAsync_RejectsUnexpectedResponseIdentity()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/attachments/901",
                "{\"id\":902,\"project\":123,\"object_id\":42}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).GetAsync("epic", 901));

            Assert.Contains("unexpected id", error.Message);
        }
    }

    [Theory]
    [InlineData("{\"project\":123,\"object_id\":42}")]
    [InlineData("{\"id\":901,\"project\":0,\"object_id\":42}")]
    [InlineData("{\"id\":901,\"project\":123,\"object_id\":0}")]
    public async Task GetAsync_RejectsMissingOrInvalidRequiredIdentity(string response)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", response);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).GetAsync("task", 901));
        }
    }

    [Theory]
    [InlineData("[]")]
    [InlineData("{not-json")]
    [InlineData("{\"id\":901,\"project\":123,\"object_id\":42,\"name\":17}")]
    public async Task GetAsync_RejectsMalformedResponse(string response)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", response);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).GetAsync("task", 901));
        }
    }

    [Fact]
    public async Task GetAsync_PropagatesCancellationBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/epics/attachments/901", AttachmentDetailFixtures.Detail);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                NewApi(handler, auth).GetAsync("epic", 901, cancellation.Token));

            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath != "/api/v1/auth");
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    [InlineData(HttpStatusCode.NotFound, "resource not found")]
    public async Task GetTool_ReportsSafeHttpFailures(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks/attachments/901",
                "{\"detail\":\"attachment secret\"}",
                statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<ModelContextProtocol.McpException>(() =>
                new WorkItemAttachmentTools(NewApi(handler, auth))
                    .GetWorkItemAttachment("task", 901));

            Assert.Contains(((int)statusCode).ToString(), error.Message);
            Assert.Contains(category, error.Message);
            Assert.DoesNotContain("attachment secret", error.Message);
        }
    }

    [Fact]
    public async Task GetTool_ReportsSafeTransportFailure()
    {
        var handler = new FakeHttpMessageHandler()
            .AddExceptionRoute(
                HttpMethod.Get,
                "/api/v1/tasks/attachments/901",
                new HttpRequestException("transport secret"));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<ModelContextProtocol.McpException>(() =>
                new WorkItemAttachmentTools(NewApi(handler, auth))
                    .GetWorkItemAttachment("task", 901));

            Assert.Contains("transport failure", error.Message);
            Assert.DoesNotContain("transport secret", error.Message);
        }
    }

    private static WorkItemAttachmentApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));
}

internal static class AttachmentDetailFixtures
{
    public const string Detail = """
        {
          "id":901,
          "project":123,
          "object_id":42,
          "owner":7,
          "name":"résumé & 檔案.txt",
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
        }
        """;

    public const string NullableDetail = """
        {
          "id":902,
          "project":123,
          "object_id":42,
          "name":"empty-description.txt",
          "description":"",
          "unknown_field":"ignored",
          "order":0,
          "size":0,
          "attached_file":"attachments/empty-description.txt",
          "url":"https://files.example/902",
          "preview_url":null,
          "thumbnail_card_url":null,
          "sha1":"",
          "is_deprecated":false,
          "from_comment":false
        }
        """;
}
