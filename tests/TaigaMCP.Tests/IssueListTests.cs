using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Caching;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class IssueListTests
{
    [Fact]
    public async Task LegacyListIssues_ReturnsBareArrayAndOpenOnlyQuery()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-statuses", "[{\"id\":1,\"name\":\"Open\"}]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/severities", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issue-types", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/priorities", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/issues", "[{\"id\":42,\"project\":123,\"subject\":\"Triage\",\"status\":1}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var tools = new IssueTools(new IssueApi(
                new TaigaTransport(new TestHttpClientFactory(handler), auth),
                new IssueMetadataCache(new TaigaTransport(new TestHttpClientFactory(handler), auth))));

            var result = await tools.ListIssues(123, page: 2);

            using var document = JsonDocument.Parse(result);
            Assert.Equal(JsonValueKind.Array, document.RootElement.ValueKind);
            Assert.Equal(42, document.RootElement[0].GetProperty("id").GetInt32());
            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/issues"));
            Assert.Equal("?project=123&page=2&status__is_closed=false", request.Uri.Query);
        }
    }
}
