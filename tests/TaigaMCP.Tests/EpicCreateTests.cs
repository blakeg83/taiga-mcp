using System.Net;
using System.Text.Json;
using ModelContextProtocol;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class EpicCreateTests
{
    [Fact]
    public async Task CreateEpicAsync_MinimalRequestPreservesServerDefaultsAndMapsDetail()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/epics", EpicCreateFixtures.CreatedEpic, HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var epic = await NewApi(handler, auth).CreateEpicAsync(123, "Saved search experience");

            Assert.Equal(301, epic.Id);
            Assert.Equal(12, epic.Ref);
            Assert.Equal(123, epic.Project);
            Assert.Equal("Saved search experience", epic.Subject);
            Assert.Equal(7, epic.StatusId);
            Assert.Equal("Ready", epic.Status);
            Assert.Equal(42, epic.AssignedTo);
            Assert.Equal("#336699", epic.Color);
            Assert.Equal(4, epic.Version);

            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/epics"));
            using var body = JsonDocument.Parse(request.Body);
            Assert.Equal(
                new[] { "project", "subject" },
                body.RootElement.EnumerateObject().Select(property => property.Name).ToArray());
            Assert.Equal(123, body.RootElement.GetProperty("project").GetInt32());
            Assert.Equal("Saved search experience", body.RootElement.GetProperty("subject").GetString());
        }
    }

    [Fact]
    public async Task CreateEpicAsync_PopulatedRequestMapsOptionalFieldsAndPreservesText()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/epics", EpicCreateFixtures.CreatedEpic, HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            const string description = "  Group saved-search delivery work.  ";
            var epic = await NewApi(handler, auth).CreateEpicAsync(
                123,
                "Saved search experience",
                description,
                status: 7,
                assigned_to: 42,
                color: "#336699",
                tags: ["search", "saved"]);

            Assert.Equal("Group saved-search delivery work.", epic.Description);
            Assert.Equal(7, epic.StatusId);
            Assert.Equal(42, epic.AssignedTo);
            Assert.Equal("#336699", epic.Color);

            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/epics"));
            using var body = JsonDocument.Parse(request.Body);
            Assert.Equal(
                new[] { "assigned_to", "color", "description", "project", "status", "subject", "tags" },
                body.RootElement.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
            Assert.Equal(description, body.RootElement.GetProperty("description").GetString());
            Assert.Equal(7, body.RootElement.GetProperty("status").GetInt32());
            Assert.Equal(42, body.RootElement.GetProperty("assigned_to").GetInt32());
            Assert.Equal("#336699", body.RootElement.GetProperty("color").GetString());
            Assert.Equal(new[] { "search", "saved" }, body.RootElement.GetProperty("tags").EnumerateArray().Select(tag => tag.GetString()));
        }
    }

    [Fact]
    public async Task CreateEpicAsync_SendsExplicitEmptyDescriptionAndTags()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/epics", EpicCreateFixtures.CreatedEpic, HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await NewApi(handler, auth).CreateEpicAsync(123, "Saved search experience", description: "", tags: []);

            using var body = JsonDocument.Parse(Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/epics")).Body);
            Assert.Equal("", body.RootElement.GetProperty("description").GetString());
            Assert.Empty(body.RootElement.GetProperty("tags").EnumerateArray());
        }
    }

    [Theory]
    [InlineData(0, "valid", null, null)]
    [InlineData(123, " ", null, null)]
    [InlineData(123, "valid", 0, null)]
    [InlineData(123, "valid", null, -1)]
    public async Task CreateEpicAsync_RejectsInvalidInputsBeforeHttp(
        int projectId,
        string subject,
        int? status,
        int? assignedTo)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).CreateEpicAsync(
                projectId,
                subject,
                status: status,
                assigned_to: assignedTo));

            Assert.Empty(handler.Requests);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest, "validation failed")]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    public async Task CreateEpicAsync_ReportsServerFailureWithoutRetry(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/epics", "{\"detail\":\"secret epic data\"}", statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).CreateEpicAsync(123, "Saved search experience"));

            Assert.Contains(((int)statusCode).ToString(), exception.Message);
            Assert.Contains(category, exception.Message);
            Assert.DoesNotContain("secret epic data", exception.Message);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/epics"));
        }
    }

    [Fact]
    public async Task CreateEpicAsync_ReportsAmbiguousTransportFailureWithoutRetry()
    {
        var handler = new FakeHttpMessageHandler()
            .AddExceptionRoute(HttpMethod.Post, "/api/v1/epics", new IOException("synthetic timeout details"));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).CreateEpicAsync(123, "Saved search experience"));

            Assert.Contains("may already have applied", exception.Message);
            Assert.DoesNotContain("synthetic timeout details", exception.Message);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/epics"));
        }
    }

    [Fact]
    public async Task CreateEpicTool_ReportsHttpTimeoutAsPotentiallyAppliedWithoutRetry()
    {
        var handler = new FakeHttpMessageHandler()
            .AddExceptionRoute(
                HttpMethod.Post,
                "/api/v1/epics",
                new TaskCanceledException("Synthetic HttpClient timeout", new TimeoutException("secret timeout details")));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<McpException>(() =>
                new EpicTools(NewApi(handler, auth)).CreateEpic(123, "Saved search experience"));

            Assert.Contains("timed out", exception.Message);
            Assert.Contains("may already have applied", exception.Message);
            Assert.DoesNotContain("secret timeout details", exception.Message);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/epics"));
        }
    }

    [Fact]
    public async Task CreateEpicAsync_PreservesCallerCancellation()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                NewApi(handler, auth).CreateEpicAsync(123, "Saved search experience", cancellationToken: cancellation.Token));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task CreateEpicAsync_ReportsResponseMappingFailureAsPotentiallyApplied()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Post, "/api/v1/epics", "{\"project\":123}", HttpStatusCode.Created);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).CreateEpicAsync(123, "Saved search experience"));

            Assert.Contains("may already have applied", exception.Message);
            Assert.Single(handler.Requests, item => item.Method == HttpMethod.Post && item.Uri.AbsolutePath.EndsWith("/epics"));
        }
    }

    private static EpicApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));
}
