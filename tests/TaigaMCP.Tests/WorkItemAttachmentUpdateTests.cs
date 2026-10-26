using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemAttachmentUpdateTests
{
    [Theory]
    [InlineData("epic", "/api/v1/epics/attachments/901")]
    [InlineData("user_story", "/api/v1/userstories/attachments/901")]
    [InlineData("task", "/api/v1/tasks/attachments/901")]
    [InlineData("issue", "/api/v1/issues/attachments/901")]
    public async Task UpdateAsync_UsesKindSpecificPatchAndPreservesExplicitValues(string kind, string path)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, path, AttachmentUpdateFixtures.Updated);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var fields = JsonDocument.Parse("""
            {"description":"","order":0,"is_deprecated":false}
            """))
        {
            var attachment = await NewApi(handler, auth).UpdateAsync(kind, 901, fields.RootElement);

            Assert.Equal(901, attachment.Id);
            Assert.Equal(123, attachment.Project);
            Assert.Equal(42, attachment.ObjectId);
            Assert.Equal(string.Empty, attachment.Description);
            Assert.Equal(0, attachment.Order);
            Assert.False(attachment.IsDeprecated);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath != "/api/v1/auth");
            Assert.Equal(HttpMethod.Patch, request.Method);
            Assert.Equal(path, request.Uri.AbsolutePath);
            Assert.Empty(request.Uri.Query);
            Assert.Equal("application/json; charset=utf-8", request.Headers["Content-Type"].Single());

            var payload = JsonSerializer.Deserialize<JsonElement>(request.Body);
            Assert.Equal(string.Empty, payload.GetProperty("description").GetString());
            Assert.Equal(0, payload.GetProperty("order").GetInt32());
            Assert.False(payload.GetProperty("is_deprecated").GetBoolean());
            Assert.False(payload.TryGetProperty("version", out _));
            Assert.False(payload.TryGetProperty("attached_file", out _));
            Assert.False(payload.TryGetProperty("object_id", out _));
            Assert.False(payload.TryGetProperty("project", out _));
        }
    }

    [Fact]
    public async Task UpdateAsync_OmitsFieldsNotSelectedByCaller()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/tasks/attachments/901", AttachmentUpdateFixtures.Updated);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var fields = JsonDocument.Parse("""{"description":"Only this field"}"""))
        {
            await NewApi(handler, auth).UpdateAsync("task", 901, fields.RootElement);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath != "/api/v1/auth");
            var payload = JsonSerializer.Deserialize<JsonElement>(request.Body);
            Assert.Equal("Only this field", payload.GetProperty("description").GetString());
            Assert.Single(payload.EnumerateObject());
        }
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"unknown\":true}")]
    [InlineData("{\"description\":null}")]
    [InlineData("{\"order\":1.5}")]
    [InlineData("{\"is_deprecated\":null}")]
    public async Task UpdateAsync_RejectsUnsupportedOrEmptyFieldsBeforeHttp(string fieldsJson)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/tasks/attachments/901", AttachmentUpdateFixtures.Updated);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var fields = JsonDocument.Parse(fieldsJson))
        {
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).UpdateAsync("task", 901, fields.RootElement));

            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath != "/api/v1/auth");
        }
    }

    [Fact]
    public async Task UpdateTool_ReturnsAuthoritativeMetadata()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/tasks/attachments/901", AttachmentUpdateFixtures.Updated);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var fields = JsonDocument.Parse("""{"order":0}"""))
        {
            var result = JsonSerializer.Deserialize<JsonElement>(await new WorkItemAttachmentTools(NewApi(handler, auth))
                .UpdateWorkItemAttachment("task", 901, fields.RootElement));

            Assert.Equal(901, result.GetProperty("id").GetInt32());
            Assert.Equal(123, result.GetProperty("project").GetInt32());
            Assert.Equal(0, result.GetProperty("order").GetInt32());
            Assert.False(result.TryGetProperty("version", out _));
        }
    }

    [Fact]
    public async Task UpdateAsync_ReportsPostWriteMappingUncertainty()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/tasks/attachments/901", "{\"id\":901,\"project\":123,\"object_id\":42,\"order\":\"invalid\"}");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var fields = JsonDocument.Parse("""{"order":0}"""))
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UpdateAsync("task", 901, fields.RootElement));

            Assert.Contains("may already have applied", error.Message);
            Assert.Single(handler.Requests, item => item.Uri.AbsolutePath == "/api/v1/tasks/attachments/901");
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest, "validation failed")]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    [InlineData(HttpStatusCode.NotFound, "resource not found")]
    [InlineData(HttpStatusCode.Conflict, "conflict")]
    public async Task UpdateTool_ReportsSafeHttpFailures(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Patch,
                "/api/v1/tasks/attachments/901",
                "{\"detail\":\"attachment update secret\"}",
                statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var fields = JsonDocument.Parse("""{"order":0}"""))
        {
            var error = await Assert.ThrowsAsync<ModelContextProtocol.McpException>(() =>
                new WorkItemAttachmentTools(NewApi(handler, auth))
                    .UpdateWorkItemAttachment("task", 901, fields.RootElement));

            Assert.Contains(((int)statusCode).ToString(), error.Message);
            Assert.Contains(category, error.Message);
            Assert.DoesNotContain("attachment update secret", error.Message);
        }
    }

    [Fact]
    public async Task UpdateAsync_PropagatesCancellationBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Patch, "/api/v1/tasks/attachments/901", AttachmentUpdateFixtures.Updated);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var fields = JsonDocument.Parse("""{"order":0}"""))
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                NewApi(handler, auth).UpdateAsync("task", 901, fields.RootElement, cancellation.Token));

            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath != "/api/v1/auth");
        }
    }

    [Fact]
    public async Task UpdateAsync_ReplaysOnlyAReceivedUnauthorizedResponse()
    {
        var patchAttempts = 0;
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/auth/refresh",
                "{\"auth_token\":\"replacement-token\",\"refresh\":\"replacement-refresh\"}")
            .AddRoute(
                HttpMethod.Patch,
                "/api/v1/tasks/attachments/901",
                _ => Interlocked.Increment(ref patchAttempts) == 1
                    ? new HttpResponseMessage(HttpStatusCode.Unauthorized)
                    : new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent(AttachmentUpdateFixtures.Updated, System.Text.Encoding.UTF8, "application/json")
                    });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var fields = JsonDocument.Parse("""{"order":0}"""))
        {
            var attachment = await NewApi(handler, auth).UpdateAsync("task", 901, fields.RootElement);

            Assert.Equal(901, attachment.Id);
            Assert.Equal(2, patchAttempts);
            Assert.Equal(2, handler.Requests.Count(request => request.Uri.AbsolutePath == "/api/v1/tasks/attachments/901"));
        }
    }

    [Fact]
    public async Task UpdateAsync_DoesNotRetryAmbiguousTransportFailures()
    {
        var handler = new FakeHttpMessageHandler()
            .AddExceptionRoute(
                HttpMethod.Patch,
                "/api/v1/tasks/attachments/901",
                new HttpRequestException("synthetic connection drop"));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var fields = JsonDocument.Parse("""{"order":0}"""))
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UpdateAsync("task", 901, fields.RootElement));

            Assert.Contains("may already have applied", error.Message);
            Assert.Single(handler.Requests, request => request.Uri.AbsolutePath == "/api/v1/tasks/attachments/901");
        }
    }

    private static WorkItemAttachmentApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));
}

internal static class AttachmentUpdateFixtures
{
    public const string Updated = """
        {
          "id":901,
          "project":123,
          "object_id":42,
          "owner":7,
          "name":"spec.txt",
          "description":"",
          "order":0,
          "size":2048,
          "attached_file":"attachments/spec.txt",
          "url":"https://files.example/901#token",
          "is_deprecated":false,
          "from_comment":false,
          "sha1":"abc123",
          "created_date":"2026-10-02T12:00:00Z",
          "modified_date":"2026-10-02T12:05:00Z"
        }
        """;
}
