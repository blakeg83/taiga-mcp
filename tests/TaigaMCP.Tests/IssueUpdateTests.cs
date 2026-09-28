using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Caching;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class IssueUpdateTests
{
    [Theory]
    [InlineData("omitted")]
    [InlineData("set")]
    [InlineData("clear")]
    public async Task UpdateIssueAsync_UsesPresenceAwareAssignmentPayload(string assignmentCase)
    {
        var handler = CreateUpdateHandler(assignmentCase == "clear" ? null : assignmentCase == "set" ? 99 : null);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
            var api = new IssueApi(transport, new IssueMetadataCache(transport));

            _ = assignmentCase switch
            {
                "omitted" => await api.UpdateIssueAsync(42, version: 7, description: "Changed"),
                "set" => await api.UpdateIssueAsync(42, version: 7, description: "Changed", assigned_to: 99),
                "clear" => await api.UpdateIssueAsync(42, version: 7, description: "Changed", clearFields: ["assigned_to"]),
                _ => throw new InvalidOperationException()
            };

            var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            using var body = JsonDocument.Parse(patch.Body);
            var root = body.RootElement;
            Assert.Equal(7, root.GetProperty("version").GetInt32());
            Assert.Equal("Changed", root.GetProperty("description").GetString());

            if (assignmentCase == "omitted")
                Assert.False(root.TryGetProperty("assigned_to", out _));
            else if (assignmentCase == "set")
                Assert.Equal(99, root.GetProperty("assigned_to").GetInt32());
            else
            {
                Assert.True(root.TryGetProperty("assigned_to", out var assignedTo));
                Assert.Equal(JsonValueKind.Null, assignedTo.ValueKind);
            }
        }
    }

    [Theory]
    [InlineData("unknown")]
    [InlineData("conflict")]
    public async Task UpdateIssueAsync_RejectsInvalidClearFieldsBeforeHttp(string scenario)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
            var api = new IssueApi(transport, new IssueMetadataCache(transport));

            var exception = await Assert.ThrowsAsync<ArgumentException>(() => scenario switch
            {
                "unknown" => api.UpdateIssueAsync(42, version: 7, clearFields: ["description"]),
                "conflict" => api.UpdateIssueAsync(42, version: 7, assigned_to: 99, clearFields: ["assigned_to"]),
                _ => throw new InvalidOperationException()
            });

            Assert.Contains(scenario == "unknown" ? "unsupported" : "set and cleared", exception.Message, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain(handler.Requests, request => request.Uri.AbsolutePath.EndsWith("/issues/42", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task UpdateIssueAsync_AllowsExplicitClearAsTheOnlyChange()
    {
        var handler = CreateUpdateHandler(null);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
            var api = new IssueApi(transport, new IssueMetadataCache(transport));

            await api.UpdateIssueAsync(42, version: 7, clearFields: ["assigned_to"]);

            var patch = Assert.Single(handler.Requests, request => request.Method == HttpMethod.Patch);
            using var body = JsonDocument.Parse(patch.Body);
            Assert.Equal(JsonValueKind.Null, body.RootElement.GetProperty("assigned_to").ValueKind);
            Assert.Equal(7, body.RootElement.GetProperty("version").GetInt32());
        }
    }

    private static FakeHttpMessageHandler CreateUpdateHandler(int? assignedTo)
    {
        var assignedJson = assignedTo.HasValue ? $"\"assigned_to\":{assignedTo.Value}," : "\"assigned_to\":null,";
        return new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Patch,
                "/api/v1/issues/42",
                $$"""
                {"id":42,"ref":7,"project":123,"subject":"Updated","status":1,"severity":2,"type":3,"priority":4,{{assignedJson}}"version":8}
                """
            )
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-statuses", "[{\"id\":1,\"name\":\"Open\"}]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/severities", "[{\"id\":2,\"name\":\"Normal\"}]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-types", "[{\"id\":3,\"name\":\"Bug\"}]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/priorities", "[{\"id\":4,\"name\":\"Normal\"}]");
    }
}
