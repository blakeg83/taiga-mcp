using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemAttachmentDeleteApiTests
{
    [Theory]
    [InlineData("epic", "/api/v1/epics/attachments/901")]
    [InlineData("user_story", "/api/v1/userstories/attachments/901")]
    [InlineData("task", "/api/v1/tasks/attachments/901")]
    public async Task DeleteAsync_UsesKindSpecificRouteAndReturnsReceipt(string kind, string path)
    {
        var handler = new FakeHttpMessageHandler().AddRoute(
            HttpMethod.Delete,
            path,
            _ => new HttpResponseMessage(HttpStatusCode.NoContent));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var receipt = await NewApi(handler, auth).DeleteAsync(kind, 901);

            Assert.Equal(kind, receipt.Kind);
            Assert.Equal(901, receipt.AttachmentId);
            Assert.True(receipt.Deleted);
            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Delete);
            Assert.Equal(path, request.Uri.AbsolutePath);
            Assert.DoesNotContain(handler.Requests, item =>
                item.Method == HttpMethod.Get ||
                item.Method == HttpMethod.Patch ||
                (item.Method == HttpMethod.Post && item.Uri.AbsolutePath != "/api/v1/auth"));
        }
    }

    [Theory]
    [InlineData("issue", 901)]
    [InlineData("task", 0)]
    public async Task DeleteAsync_RejectsInvalidInputBeforeHttp(string kind, int attachmentId)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).DeleteAsync(kind, attachmentId));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task DeleteTool_ReturnsSnakeCaseReceipt()
    {
        var handler = new FakeHttpMessageHandler().AddRoute(
            HttpMethod.Delete,
            "/api/v1/tasks/attachments/901",
            _ => new HttpResponseMessage(HttpStatusCode.NoContent));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var json = JsonSerializer.Deserialize<JsonElement>(await new WorkItemAttachmentTools(NewApi(handler, auth))
                .DeleteWorkItemAttachment("task", 901));

            Assert.Equal("task", json.GetProperty("kind").GetString());
            Assert.Equal(901, json.GetProperty("attachment_id").GetInt32());
            Assert.True(json.GetProperty("deleted").GetBoolean());
        }
    }

    private static WorkItemAttachmentApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));
}
