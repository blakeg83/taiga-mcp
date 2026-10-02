using System.Diagnostics;
using System.Net;
using Microsoft.Extensions.Options;
using ModelContextProtocol;
using TaigaMCP.Api;
using TaigaMCP.Config;
using TaigaMCP.Tools;
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
        var payload = new byte[] { 0, 1, 127, 128, 254, 255, 13, 10 };
        await File.WriteAllBytesAsync(file, payload);
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
            Assert.True(ContainsBytes(request.BodyBytes, payload));
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
            foreach (var upload in uploads)
            {
                var boundary = upload.Headers["Content-Type"].Single().Split("boundary=", 2, StringSplitOptions.None)[1].Trim('"');
                Assert.StartsWith($"--{boundary}", upload.Body, StringComparison.Ordinal);
            }
        }
        finally
        {
            http.Dispose();
            File.Delete(file);
        }
    }

    [Fact]
    public async Task UploadAsync_AcceptsEmptyAndExactBoundaryFiles()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/tasks/attachments", AttachmentUploadFixtures.Response);
        var empty = Path.Combine(Path.GetTempPath(), $"taiga-upload-empty-{Guid.NewGuid():N}.txt");
        var boundary = Path.Combine(Path.GetTempPath(), $"taiga-upload-boundary-{Guid.NewGuid():N}.bin");
        await File.WriteAllBytesAsync(empty, []);
        await File.WriteAllBytesAsync(boundary, [1, 2, 3, 4]);
        var (http, auth) = TaigaTestClient.Create(handler);
        try
        {
            var api = new WorkItemAttachmentApi(
                new TaigaTransport(new TestHttpClientFactory(handler), auth),
                Options.Create(new TaigaOptions { MaxAttachmentBytes = 4 }));

            await api.UploadAsync("task", 42, 123, empty);
            await api.UploadAsync("task", 42, 123, boundary);

            var uploads = handler.Requests
                .Where(item => item.Uri.AbsolutePath == "/api/v1/tasks/attachments")
                .ToArray();
            Assert.Equal(2, uploads.Length);
            Assert.True(ContainsBytes(uploads[1].BodyBytes, [1, 2, 3, 4]));
        }
        finally
        {
            http.Dispose();
            File.Delete(empty);
            File.Delete(boundary);
        }
    }

    [Fact]
    public async Task UploadAsync_ReportsAmbiguousWriteAndDoesNotRetry()
    {
        var handler = new FakeHttpMessageHandler()
            .AddExceptionRoute(HttpMethod.Post, "/api/v1/tasks/attachments", new HttpRequestException("synthetic connection drop"));
        var file = Path.Combine(Path.GetTempPath(), $"taiga-upload-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(file, "ambiguous");
        var (http, auth) = TaigaTestClient.Create(handler);
        try
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UploadAsync("task", 42, 123, file));

            Assert.Contains("may already have applied", error.Message, StringComparison.OrdinalIgnoreCase);
            Assert.Single(handler.Requests, item => item.Uri.AbsolutePath == "/api/v1/tasks/attachments");
        }
        finally
        {
            http.Dispose();
            File.Delete(file);
        }
    }

    [Fact]
    public async Task UploadAsync_ReportsPossibleApplyWhenSuccessBodyIsUnreadable()
    {
        var handler = new FakeHttpMessageHandler()
            .AddTextRoute(HttpMethod.Post, "/api/v1/tasks/attachments", "{not-json");
        var file = Path.Combine(Path.GetTempPath(), $"taiga-upload-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(file, "malformed response");
        var (http, auth) = TaigaTestClient.Create(handler);
        try
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UploadAsync("task", 42, 123, file));

            Assert.Contains("may already have applied", error.Message, StringComparison.OrdinalIgnoreCase);
            Assert.Single(handler.Requests, item => item.Uri.AbsolutePath == "/api/v1/tasks/attachments");
        }
        finally
        {
            http.Dispose();
            File.Delete(file);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    [InlineData(HttpStatusCode.BadRequest, "validation failed")]
    public async Task UploadTool_ConvertsHttpFailuresToSafeMcpErrors(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Post,
                "/api/v1/tasks/attachments",
                "{\"detail\":\"synthetic attachment upload secret\"}",
                statusCode);
        var file = Path.Combine(Path.GetTempPath(), $"taiga-upload-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(file, "error");
        var (http, auth) = TaigaTestClient.Create(handler);
        try
        {
            var error = await Assert.ThrowsAsync<McpException>(() =>
                new WorkItemAttachmentTools(NewApi(handler, auth))
                    .UploadWorkItemAttachment("task", 42, 123, file));

            Assert.Contains(((int)statusCode).ToString(), error.Message);
            Assert.Contains(category, error.Message);
            Assert.DoesNotContain("synthetic attachment upload secret", error.Message);
        }
        finally
        {
            http.Dispose();
            File.Delete(file);
        }
    }

    [Fact]
    public async Task UploadAsync_PropagatesCancellationWhileUploadIsInFlight()
    {
        using var handler = new CancellationUploadHandler();
        var options = Options.Create(new TaigaOptions
        {
            BaseUrl = TaigaTestClient.BaseUrl,
            Username = "synthetic-user",
            Password = "synthetic-password"
        });
        using var auth = new AuthClient(options, Microsoft.Extensions.Logging.Abstractions.NullLogger<AuthClient>.Instance);
        var file = Path.Combine(Path.GetTempPath(), $"taiga-upload-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(file, "cancel me");
        using var cancellation = new CancellationTokenSource();
        try
        {
            var api = NewApi(handler, auth);
            var upload = api.UploadAsync("task", 42, 123, file, cancellationToken: cancellation.Token);
            await handler.UploadStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => upload);
        }
        finally { File.Delete(file); }
    }

    [Fact]
    public void AttachmentMultipartContent_DoesNotPrecomputeAFileSizedContentLength()
    {
        var file = Path.Combine(Path.GetTempPath(), $"taiga-upload-{Guid.NewGuid():N}.bin");
        File.WriteAllBytes(file, new byte[1024 * 1024]);
        try
        {
            var source = AttachmentFileContract.Validate(file, Options.Create(new TaigaOptions { MaxAttachmentBytes = 1024 * 1024 }));
            using var content = new AttachmentMultipartContent(source, 42, 123, null, 1024 * 1024);

            Assert.Null(content.Headers.ContentLength);
        }
        finally { File.Delete(file); }
    }

    private static WorkItemAttachmentApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private static WorkItemAttachmentApi NewApi(CancellationUploadHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private static bool ContainsBytes(IReadOnlyList<byte> body, IReadOnlyList<byte> expected)
    {
        for (var offset = 0; offset <= body.Count - expected.Count; offset++)
        {
            var match = true;
            for (var index = 0; index < expected.Count; index++)
            {
                if (body[offset + index] != expected[index])
                {
                    match = false;
                    break;
                }
            }

            if (match) return true;
        }

        return false;
    }

}

internal sealed class CancellationUploadHandler : HttpMessageHandler
{
    public TaskCompletionSource UploadStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        if (request.RequestUri?.AbsolutePath.EndsWith("/auth", StringComparison.OrdinalIgnoreCase) == true)
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("{\"auth_token\":\"synthetic-token\"}")
            };

        UploadStarted.TrySetResult();
        await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
        throw new UnreachableException();
    }
}

internal static class AttachmentUploadFixtures
{
    public const string Response = """
        {"id":901,"project":123,"object_id":42,"name":"upload.txt","description":"A description","size":22,"url":"https://files.example/901"}
        """;
}
