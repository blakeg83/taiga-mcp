using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.Extensions.Options;
using TaigaMCP.Api;
using TaigaMCP.Config;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemAttachmentDownloadTests
{
    [Theory]
    [InlineData("epic", "/api/v1/epics/attachments/901")]
    [InlineData("user_story", "/api/v1/userstories/attachments/901")]
    [InlineData("task", "/api/v1/tasks/attachments/901")]
    public async Task DownloadAsync_UsesMetadataAndWritesExactBytesForEveryKind(string kind, string detailPath)
    {
        var bytes = new byte[] { 0, 1, 127, 128, 254, 255, 13, 10 };
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, detailPath, DownloadFixtures.Detail)
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent(bytes)
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var result = await NewApi(handler, auth).DownloadAsync(kind, 901, destination);

                Assert.Equal(Path.GetFullPath(destination), result.Destination);
                Assert.Equal(bytes.Length, result.Bytes);
                Assert.Equal(bytes, await File.ReadAllBytesAsync(destination));
                Assert.Equal(901, result.Attachment.Id);
                Assert.Equal(123, result.Attachment.Project);

                var requests = handler.Requests.Where(item => item.Uri.AbsolutePath != "/api/v1/auth").ToArray();
                Assert.Equal(2, requests.Length);
                Assert.All(requests, request => Assert.Equal("Bearer synthetic-token", request.Headers["Authorization"].Single()));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadTool_ReturnsSmallReceiptAndPreservesAttachmentMetadata()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.Detail)
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([5, 4, 3])
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var json = await new WorkItemAttachmentTools(NewApi(handler, auth))
                    .DownloadWorkItemAttachment("task", 901, destination);
                var result = JsonSerializer.Deserialize<JsonElement>(json);

                Assert.Equal(Path.GetFullPath(destination), result.GetProperty("destination").GetString());
                Assert.Equal(3, result.GetProperty("bytes").GetInt64());
                Assert.Equal(901, result.GetProperty("attachment").GetProperty("id").GetInt32());
                Assert.DoesNotContain("synthetic-token", json, StringComparison.Ordinal);
                Assert.DoesNotContain("\u0005", json, StringComparison.Ordinal);
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_RejectsKnownOversizeBeforeCreatingDestination()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.Detail)
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([1, 2, 3, 4, 5])
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var api = new WorkItemAttachmentApi(
                    new TaigaTransport(new TestHttpClientFactory(handler), auth),
                    Options.Create(new TaigaOptions { MaxAttachmentBytes = 4 }));
                var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                    api.DownloadAsync("task", 901, destination));

                Assert.Contains("exceeds", error.Message);
                Assert.False(File.Exists(destination));
                Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath.Contains(".download", StringComparison.Ordinal));
            }
            finally { File.Delete(destination); }
        }
    }

    private static WorkItemAttachmentApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(
            new TaigaTransport(new TestHttpClientFactory(handler), auth),
            Options.Create(new TaigaOptions { BaseUrl = TaigaTestClient.BaseUrl }));
}

internal static class DownloadFixtures
{
    public const string Detail = """
        {
          "id":901,
          "project":123,
          "object_id":42,
          "name":"upstream-name.bin",
          "size":8,
          "attached_file":"media/901.bin",
          "url":"https://fake.taiga.test/media/901.bin",
          "sha1":"abc123"
        }
        """;
}
