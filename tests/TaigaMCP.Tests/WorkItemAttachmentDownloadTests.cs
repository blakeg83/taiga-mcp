using System.Net;
using System.Net.Http.Headers;
using System.Security;
using System.Text.Json;
using Microsoft.Extensions.Options;
using TaigaMCP.Api;
using TaigaMCP.Config;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemAttachmentDownloadTests
{
    [Fact]
    public async Task DownloadAsync_PreservesValidSignedQueryWithoutRecovery()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901",
                DownloadFixtures.DetailWithUrl("https://files.example/protected.bin?token=valid%2Bsignature#_taiga-refresh:901", size: 3))
            .AddRoute(HttpMethod.Get, "/protected.bin", request =>
            {
                Assert.Equal("?token=valid%2Bsignature", request.Uri.Query);
                Assert.False(request.Headers.ContainsKey("Authorization"));
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([1, 2, 3]) };
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                await NewApi(handler, auth).DownloadAsync("task", 901, destination);
                Assert.Equal(new byte[] { 1, 2, 3 }, await File.ReadAllBytesAsync(destination));
                Assert.Equal(3, handler.Requests.Count);
            }
            finally { File.Delete(destination); }
        }
    }

    [Theory]
    [InlineData("task", "expired")]
    [InlineData("issue", "expired")]
    [InlineData("task", null)]
    [InlineData("issue", null)]
    public async Task DownloadAsync_RefreshesRejectedMediaUrlWithoutRefreshingApiAuthentication(string kind, string? token)
    {
        var metadataReads = 0;
        var detailPath = kind == "issue" ? "/api/v1/issues/attachments/901" : "/api/v1/tasks/attachments/901";
        var originalUrl = "https://files.example/protected.bin" + (token is null ? "" : $"?token={token}");
        const string freshUrl = "https://files.example/protected.bin?token=fresh%2Bsignature#_taiga-refresh:901";
        var handler = new FakeHttpMessageHandler()
            .AddRoute(HttpMethod.Get, detailPath, _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(DownloadFixtures.DetailWithUrl(++metadataReads == 1 ? originalUrl : freshUrl, size: 3))
            })
            .AddRoute(HttpMethod.Get, "/protected.bin", request => request.Uri.Query == "?token=fresh%2Bsignature"
                ? new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([1, 2, 3]) }
                : new HttpResponseMessage(HttpStatusCode.Forbidden) { Content = new StringContent("media secret") });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var result = await NewApi(handler, auth).DownloadAsync(kind, 901, destination);

                Assert.Equal(new byte[] { 1, 2, 3 }, await File.ReadAllBytesAsync(destination));
                Assert.Equal(freshUrl, result.Attachment.Url);
                Assert.Equal(2, metadataReads);
                var mediaRequests = handler.Requests.Where(request => request.Uri.AbsolutePath == "/protected.bin").ToArray();
                Assert.Equal(2, mediaRequests.Length);
                Assert.All(mediaRequests, request => Assert.False(request.Headers.ContainsKey("Authorization")));
                Assert.Single(handler.Requests, request => request.Uri.AbsolutePath == "/api/v1/auth");
                Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath == "/api/v1/auth/refresh");
                Assert.Empty(Directory.EnumerateFiles(Path.GetDirectoryName(destination)!, $".{Path.GetFileName(destination)}.*.download"));
            }
            finally { File.Delete(destination); }
        }
    }

    [Theory]
    [InlineData(false, 1)]
    [InlineData(true, 2)]
    public async Task DownloadAsync_BoundsMedia403RecoveryAndReportsSafeContext(bool changedUrl, int expectedMediaRequests)
    {
        var metadataReads = 0;
        var handler = new FakeHttpMessageHandler()
            .AddRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(DownloadFixtures.DetailWithUrl(
                    $"https://files.example/protected.bin?token=secret{(changedUrl ? ++metadataReads : 0)}", size: 3))
            })
            .AddTextRoute(HttpMethod.Get, "/protected.bin", "media secret", HttpStatusCode.Forbidden);
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).DownloadAsync("task", 901, destination));

            Assert.Equal(HttpStatusCode.Forbidden, error.StatusCode);
            Assert.Contains("attachment download HTTP 403: media access denied", error.Message);
            Assert.DoesNotContain("secret", error.Message);
            Assert.DoesNotContain("files.example", error.Message);
            Assert.Equal(2, handler.Requests.Count(request => request.Uri.AbsolutePath == "/api/v1/tasks/attachments/901"));
            Assert.Equal(expectedMediaRequests, handler.Requests.Count(request => request.Uri.AbsolutePath == "/protected.bin"));
            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath == "/api/v1/auth/refresh");
            Assert.False(File.Exists(destination));
            Assert.Empty(Directory.EnumerateFiles(Path.GetDirectoryName(destination)!, $".{Path.GetFileName(destination)}.*.download"));
        }
    }

    [Fact]
    public async Task DownloadAsync_DistinguishesMetadata403WithoutMediaRequestsOrRecovery()
    {
        var handler = new FakeHttpMessageHandler()
            .AddTextRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", "metadata secret", HttpStatusCode.Forbidden);
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).DownloadAsync("task", 901, destination));

            Assert.Equal(HttpStatusCode.Forbidden, error.StatusCode);
            Assert.Contains("attachment metadata request failed", error.Message);
            Assert.Contains("permission denied", error.Message);
            Assert.DoesNotContain("secret", error.Message);
            Assert.Equal(2, handler.Requests.Count);
            Assert.False(File.Exists(destination));
        }
    }

    [Theory]
    [InlineData("epic", "/api/v1/epics/attachments/901")]
    [InlineData("user_story", "/api/v1/userstories/attachments/901")]
    [InlineData("task", "/api/v1/tasks/attachments/901")]
    [InlineData("issue", "/api/v1/issues/attachments/901")]
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
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.DetailWithUrl("https://fake.taiga.test/media/901.bin", size: 3))
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

    [Fact]
    public async Task DownloadAsync_EnforcesLimitWhenContentLengthIsUnavailableAndCleansPartialFile()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.DetailWithSize)
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new UnknownLengthContent([1, 2, 3, 4, 5])
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var tempPrefix = $".{Path.GetFileName(destination)}.";
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var api = NewApi(handler, auth, maxBytes: 4);
                var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                    api.DownloadAsync("task", 901, destination));

                Assert.Contains("exceeds", error.Message);
                Assert.False(File.Exists(destination));
                Assert.Empty(Directory.EnumerateFiles(Path.GetDirectoryName(destination)!, $"{tempPrefix}*.download"));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_CleansPartialFileAfterInterruptedResponse()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.DetailWithSize)
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new FaultingContent([1, 2, 3, 4], failAfter: 2)
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                    NewApi(handler, auth).DownloadAsync("task", 901, destination));

                Assert.Contains("network or local destination", error.Message);
                Assert.DoesNotContain("stream secret", error.Message);
                Assert.False(File.Exists(destination));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_RejectsResponseShorterThanDeclaredContentLength()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.DetailWithSize)
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ =>
            {
                var content = new ByteArrayContent([1, 2, 3, 4]);
                content.Headers.ContentLength = 5;
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = content };
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                    NewApi(handler, auth).DownloadAsync("task", 901, destination));

                Assert.Contains("declared content length", error.Message);
                Assert.False(File.Exists(destination));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_RejectsResponseShorterThanAttachmentMetadataSizeWithoutContentLength()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.DetailWithSize)
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new UnknownLengthContent([1, 2, 3])
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                    NewApi(handler, auth).DownloadAsync("task", 901, destination));

                Assert.Contains("declared attachment size", error.Message);
                Assert.False(File.Exists(destination));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_RejectsUnknownLengthWhenMetadataSizeIsAbsent()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.DetailWithoutSize)
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new UnknownLengthContent([1, 2, 3])
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                    NewApi(handler, auth).DownloadAsync("task", 901, destination));

                Assert.Contains("declared size", error.Message);
                Assert.False(File.Exists(destination));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_RejectsContentLengthWhenMetadataSizeIsAbsent()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.DetailWithoutSize)
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([1, 2, 3])
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                    NewApi(handler, auth).DownloadAsync("task", 901, destination));

                Assert.Contains("declared size", error.Message);
                Assert.False(File.Exists(destination));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_PropagatesCancellationAndCleansPartialFile()
    {
        var content = new BlockingContent();
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.DetailWithSize)
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = content
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            try
            {
                var download = NewApi(handler, auth).DownloadAsync("task", 901, destination, cancellation.Token);
                await content.ReadStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
                cancellation.Cancel();

                await Assert.ThrowsAnyAsync<OperationCanceledException>(() => download);
                Assert.False(File.Exists(destination));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_DoesNotSendBearerToExternalSourceOrRedirect()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks/attachments/901",
                DownloadFixtures.DetailWithUrl("https://files.example/external/901.bin", size: 3))
            .AddRoute(HttpMethod.Get, "/external/901.bin", _ => new HttpResponseMessage(HttpStatusCode.Redirect)
            {
                Headers = { Location = new Uri("https://redirect.example/signed/901.bin") }
            })
            .AddRoute(HttpMethod.Get, "/signed/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([9, 8, 7])
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                await NewApi(handler, auth).DownloadAsync("task", 901, destination);

                var fileRequests = handler.Requests
                    .Where(request => request.Uri.AbsolutePath is "/external/901.bin" or "/signed/901.bin")
                    .ToArray();
                Assert.Equal(2, fileRequests.Length);
                Assert.All(fileRequests, request => Assert.False(request.Headers.ContainsKey("Authorization")));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_DropsBearerWhenTrustedSourceRedirectsExternal()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks/attachments/901",
                DownloadFixtures.DetailWithUrl("https://fake.taiga.test/media/redirect", size: 3))
            .AddRoute(HttpMethod.Get, "/media/redirect", _ => new HttpResponseMessage(HttpStatusCode.Redirect)
            {
                Headers = { Location = new Uri("https://files.example/signed/901.bin") }
            })
            .AddRoute(HttpMethod.Get, "/signed/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([6, 5, 4])
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                await NewApi(handler, auth).DownloadAsync("task", 901, destination);

                var apiRequest = Assert.Single(handler.Requests, request => request.Uri.AbsolutePath == "/media/redirect");
                var externalRequest = Assert.Single(handler.Requests, request => request.Uri.AbsolutePath == "/signed/901.bin");
                Assert.Equal("Bearer synthetic-token", apiRequest.Headers["Authorization"].Single());
                Assert.False(externalRequest.Headers.ContainsKey("Authorization"));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_IgnoresTraversalAttemptInUpstreamFilename()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks/attachments/901",
                DownloadFixtures.DetailWithUrl("https://fake.taiga.test/media/901.bin", "..\\evil.bin", size: 2))
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([4, 2])
            });
        var directory = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}");
        var nested = Path.Combine(directory, "nested");
        Directory.CreateDirectory(nested);
        var destination = Path.Combine(nested, "explicit.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                await NewApi(handler, auth).DownloadAsync("task", 901, destination);

                Assert.Equal(new byte[] { 4, 2 }, await File.ReadAllBytesAsync(destination));
                Assert.False(File.Exists(Path.Combine(directory, "evil.bin")));
            }
            finally
            {
                File.Delete(destination);
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    [Fact]
    public async Task DownloadAsync_RejectsUnsupportedRedirectSchemeAndCleansTemporaryFile()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks/attachments/901",
                DownloadFixtures.DetailWithUrl("https://fake.taiga.test/media/redirect", size: 3))
            .AddRoute(HttpMethod.Get, "/media/redirect", _ => new HttpResponseMessage(HttpStatusCode.Redirect)
            {
                Headers = { Location = new Uri("file:///secret.bin") }
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                    NewApi(handler, auth).DownloadAsync("task", 901, destination));

                Assert.Contains("unsupported redirect URL", error.Message);
                Assert.False(File.Exists(destination));
                Assert.Empty(Directory.EnumerateFiles(Path.GetDirectoryName(destination)!, $".{Path.GetFileName(destination)}.*.download"));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_KeepsBearerOnSameOriginRedirect()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks/attachments/901",
                DownloadFixtures.DetailWithUrl("https://fake.taiga.test/media/redirect", size: 3))
            .AddRoute(HttpMethod.Get, "/media/redirect", _ => new HttpResponseMessage(HttpStatusCode.Redirect)
            {
                Headers = { Location = new Uri("/media/final", UriKind.Relative) }
            })
            .AddRoute(HttpMethod.Get, "/media/final", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([3, 2, 1])
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                await NewApi(handler, auth).DownloadAsync("task", 901, destination);

                var fileRequests = handler.Requests
                    .Where(request => request.Uri.AbsolutePath is "/media/redirect" or "/media/final")
                    .ToArray();
                Assert.Equal(2, fileRequests.Length);
                Assert.All(fileRequests, request => Assert.Equal("Bearer synthetic-token", request.Headers["Authorization"].Single()));
            }
            finally { File.Delete(destination); }
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized, "authentication rejected")]
    [InlineData(HttpStatusCode.NotFound, "resource not found")]
    public async Task DownloadAsync_ReportsSafeBinaryHttpFailures(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/auth/refresh", "{}", HttpStatusCode.Unauthorized)
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.Detail)
            .AddJsonRoute(HttpMethod.Get, "/media/901.bin", "{\"detail\":\"binary secret\"}", statusCode);
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                    NewApi(handler, auth).DownloadAsync("task", 901, destination));

                Assert.Contains(category, error.Message);
                Assert.DoesNotContain("binary secret", error.Message);
                Assert.False(File.Exists(destination));
            }
            finally { File.Delete(destination); }
        }
    }

    [Fact]
    public async Task DownloadAsync_RejectsMalformedUrlAndIgnoresUpstreamFilename()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/tasks/attachments/901",
                DownloadFixtures.DetailWithUrl("file:///escape/..\\evil.bin", "..\\evil.bin"));
        var directory = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        var destination = Path.Combine(directory, "safe.bin");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                    NewApi(handler, auth).DownloadAsync("task", 901, destination));

                Assert.Contains("unsupported download URL", error.Message);
                Assert.False(File.Exists(destination));
                Assert.False(File.Exists(Path.Combine(directory, "evil.bin")));
            }
            finally
            {
                File.Delete(destination);
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    [Fact]
    public async Task DownloadAsync_PreservesExistingDestination()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/tasks/attachments/901", DownloadFixtures.Detail)
            .AddRoute(HttpMethod.Get, "/media/901.bin", _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([1, 2, 3])
            });
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        await File.WriteAllBytesAsync(destination, [7, 7, 7]);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            try
            {
                var error = await Assert.ThrowsAsync<ArgumentException>(() =>
                    NewApi(handler, auth).DownloadAsync("task", 901, destination));

                Assert.Contains("never overwrite", error.Message);
                Assert.Equal(new byte[] { 7, 7, 7 }, await File.ReadAllBytesAsync(destination));
                Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath == "/media/901.bin");
            }
            finally { File.Delete(destination); }
        }
    }

    private static WorkItemAttachmentApi NewApi(FakeHttpMessageHandler handler, AuthClient auth, long maxBytes = 10 * 1024 * 1024)
        => new(
            new TaigaTransport(new TestHttpClientFactory(handler), auth),
            Options.Create(new TaigaOptions { BaseUrl = TaigaTestClient.BaseUrl, MaxAttachmentBytes = maxBytes }));
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

    public const string DetailWithoutSize = """
        {
          "id":901,
          "project":123,
          "object_id":42,
          "name":"..\\evil.bin",
          "url":"https://fake.taiga.test/media/901.bin"
        }
        """;

    public const string DetailWithSize = """
        {
          "id":901,
          "project":123,
          "object_id":42,
          "name":"metadata-sized.bin",
          "size":4,
          "url":"https://fake.taiga.test/media/901.bin"
        }
        """;

    public static string DetailWithUrl(string url, string name = "upstream-name.bin", int? size = null)
        => $"{{\"id\":901,\"project\":123,\"object_id\":42,\"name\":{JsonSerializer.Serialize(name)},\"size\":{JsonSerializer.Serialize(size)},\"url\":{JsonSerializer.Serialize(url)}}}";
}

internal sealed class UnknownLengthContent(byte[] bytes) : HttpContent
{
    protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context)
        => stream.WriteAsync(bytes).AsTask();

    protected override Task<Stream> CreateContentReadStreamAsync()
        => Task.FromResult<Stream>(new MemoryStream(bytes, writable: false));

    protected override bool TryComputeLength(out long length)
    {
        length = 0;
        return false;
    }
}

internal sealed class FaultingContent(byte[] bytes, int failAfter) : HttpContent
{
    protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context)
        => stream.WriteAsync(bytes).AsTask();

    protected override Task<Stream> CreateContentReadStreamAsync()
        => Task.FromResult<Stream>(new FaultingStream(bytes, failAfter));

    protected override bool TryComputeLength(out long length)
    {
        length = 0;
        return false;
    }

    private sealed class FaultingStream(byte[] bytes, int failAfter) : MemoryStream(bytes, writable: false)
    {
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            if (Position >= failAfter)
                throw new IOException("stream secret");

            var remaining = failAfter - (int)Position;
            return base.ReadAsync(buffer[..Math.Min(buffer.Length, remaining)], cancellationToken);
        }
    }
}

internal sealed class BlockingContent : HttpContent
{
    public TaskCompletionSource ReadStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

    protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context)
        => Task.CompletedTask;

    protected override Task<Stream> CreateContentReadStreamAsync()
        => Task.FromResult<Stream>(new BlockingStream(ReadStarted));

    protected override bool TryComputeLength(out long length)
    {
        length = 0;
        return false;
    }

    private sealed class BlockingStream(TaskCompletionSource readStarted) : Stream
    {
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => 0;
        public override long Position { get => 0; set => throw new NotSupportedException(); }
        public override void Flush() => throw new NotSupportedException();
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            readStarted.TrySetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return 0;
        }
    }
}
