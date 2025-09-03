using System;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

#nullable enable

public class IssueApiTests
{
    private sealed class TestHandler : HttpMessageHandler
    {
        public HttpRequestMessage? PatchRequest { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            if (request.Method.Method == "PATCH")
            {
                PatchRequest = request;
                var content = "{\"id\":2,\"project\":1,\"status\":1,\"severity\":1,\"type\":1,\"priority\":1,\"subject\":\"Test\",\"ref\":0,\"description\":null,\"assigned_to\":null,\"modified_date\":null,\"version\":1}";
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(content, Encoding.UTF8, "application/json")
                });
            }

            if (request.Method == HttpMethod.Get)
            {
                var json = "[{\"id\":1,\"name\":\"One\"}]";
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(json, Encoding.UTF8, "application/json")
                });
            }

            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
        }
    }

    [Fact]
    public async Task UpdateIssueAsync_UsesPatch()
    {
        var handler = new TestHandler();
        var http = new HttpClient(handler) { BaseAddress = new Uri("https://example.com/api/v1/") };

        var opts = Microsoft.Extensions.Options.Options.Create(new TaigaOptions());
        var auth = new AuthClient(opts);
        typeof(AuthClient).GetField("_token", BindingFlags.NonPublic | BindingFlags.Instance)!
            .SetValue(auth, "token");

        var cache = new IssueMetadataCache(http, auth);
        var api = new IssueApi(http, auth, cache);

        await api.UpdateIssueAsync(1, 2, "Test", 1, null, null, null, null, null, null, null);

        Assert.Equal("PATCH", handler.PatchRequest?.Method.Method);
    }
}
