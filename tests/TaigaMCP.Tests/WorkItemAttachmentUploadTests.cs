using System.Net;
using TaigaMCP.Api;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemAttachmentUploadTests
{
    [Theory]
    [InlineData("epic", "/api/v1/epics/attachments")]
    [InlineData("user_story", "/api/v1/userstories/attachments")]
    [InlineData("task", "/api/v1/tasks/attachments")]
    public async Task UploadAsync_UsesKindRouteAndStreamsMultipartFields(string kind, string path)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, path, AttachmentUploadFixtures.Response);
        var file = Path.Combine(Path.GetTempPath(), $"taiga-upload-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(file, "synthetic upload bytes");
        var (http, auth) = TaigaTestClient.Create(handler);
        try
        {
            var attachment = await NewApi(handler, auth).UploadAsync(kind, 42, 123, file, "A description");

            Assert.Equal(901, attachment.Id);
            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath == path);
            Assert.Equal(path, request.Uri.AbsolutePath);
            Assert.StartsWith("multipart/form-data; boundary=", request.Headers["Content-Type"].Single(), StringComparison.OrdinalIgnoreCase);
            Assert.Contains("name=object_id", request.Body, StringComparison.Ordinal);
            Assert.Contains("\r\n42\r\n", request.Body, StringComparison.Ordinal);
            Assert.Contains("name=project", request.Body, StringComparison.Ordinal);
            Assert.Contains("\r\n123\r\n", request.Body, StringComparison.Ordinal);
            Assert.Contains("name=description", request.Body, StringComparison.Ordinal);
            Assert.Contains("A description", request.Body, StringComparison.Ordinal);
            Assert.Contains("name=attached_file; filename=", request.Body, StringComparison.Ordinal);
            Assert.Contains("synthetic upload bytes", request.Body, StringComparison.Ordinal);
            Assert.Contains("Content-Type: text/plain", request.Body, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            http.Dispose();
            File.Delete(file);
        }
    }

    [Fact]
    public async Task UploadAsync_OmitsDescriptionWhenNotSuppliedAndValidatesResponseAssociation()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/tasks/attachments",
                "{\"id\":901,\"project\":999,\"object_id\":42}");
        var file = Path.Combine(Path.GetTempPath(), $"taiga-upload-{Guid.NewGuid():N}.bin");
        await File.WriteAllBytesAsync(file, [0, 1, 255]);
        var (http, auth) = TaigaTestClient.Create(handler);
        try
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UploadAsync("task", 42, 123, file));

            Assert.Contains("unexpected project or work item", error.Message);
            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath == "/api/v1/tasks/attachments");
            Assert.DoesNotContain("name=description", request.Body, StringComparison.Ordinal);
            Assert.Contains("\0", request.Body, StringComparison.Ordinal);
        }
        finally
        {
            http.Dispose();
            File.Delete(file);
        }
    }

    [Fact]
    public async Task UploadAsync_RejectsInvalidInputsBeforeAuthenticationOrUpload()
    {
        var handler = new FakeHttpMessageHandler();
        var file = Path.Combine(Path.GetTempPath(), $"taiga-upload-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(file, "bytes");
        var (http, auth) = TaigaTestClient.Create(handler);
        try
        {
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).UploadAsync("issue", 42, 123, file));
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).UploadAsync("task", 0, 123, file));
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).UploadAsync("task", 42, 123, Path.Combine(Path.GetTempPath(), "missing-upload-file")));

            Assert.Empty(handler.Requests);
        }
        finally
        {
            http.Dispose();
            File.Delete(file);
        }
    }

    [Fact]
    public async Task UploadAsync_ReplaysA401FromFreshFileStream()
    {
        var uploadCount = 0;
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/auth/refresh", "{\"auth_token\":\"synthetic-refreshed-token\",\"refresh\":\"synthetic-refresh-2\"}")
            .AddRoute(
                HttpMethod.Post,
                "/api/v1/tasks/attachments",
                _ => ++uploadCount == 1
                    ? new HttpResponseMessage(HttpStatusCode.Unauthorized) { Content = new StringContent("{}") }
                    : new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(AttachmentUploadFixtures.Response) });
        var file = Path.Combine(Path.GetTempPath(), $"taiga-upload-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(file, "replayable bytes");
        var (http, auth) = TaigaTestClient.Create(handler);
        try
        {
            var attachment = await NewApi(handler, auth).UploadAsync("task", 42, 123, file);

            Assert.Equal(901, attachment.Id);
            Assert.Equal(2, uploadCount);
            var uploads = handler.Requests
                .Where(item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath == "/api/v1/tasks/attachments")
                .ToArray();
            Assert.Equal(2, uploads.Length);
            Assert.All(uploads, request => Assert.Contains("replayable bytes", request.Body, StringComparison.Ordinal));
        }
        finally
        {
            http.Dispose();
            File.Delete(file);
        }
    }

    private static WorkItemAttachmentApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

}

internal static class AttachmentUploadFixtures
{
    public const string Response = """
        {"id":901,"project":123,"object_id":42,"name":"upload.txt","description":"A description","size":22,"url":"https://files.example/901"}
        """;
}
