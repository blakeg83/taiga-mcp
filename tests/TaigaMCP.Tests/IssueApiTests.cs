using System;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Options;
using Xunit;

public class IssueApiTests
{
    private static IssueApi CreateApi(Func<HttpRequestMessage, HttpResponseMessage> responder)
    {
        var handler = new DelegateHandler(responder);
        var http = new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") };
        var auth = new AuthClient(Options.Create(new TaigaOptions { Username = "u", Password = "p" }));
        var cache = new IssueMetadataCache(http, auth);
        return new IssueApi(http, auth, cache);
    }

    [Fact]
    public async Task CreateIssueAsync_AllowsNullFields()
    {
        var api = CreateApi(req =>
        {
            if (req.RequestUri!.AbsolutePath.EndsWith("auth"))
            {
                var content = new StringContent("{\"auth_token\":\"t\"}", Encoding.UTF8, "application/json");
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = content };
            }
            if (req.RequestUri!.AbsolutePath.EndsWith("issues") && req.Method == HttpMethod.Post)
            {
                return new HttpResponseMessage(HttpStatusCode.OK);
            }
            throw new InvalidOperationException("Unexpected request: " + req.RequestUri);
        });

        var ok = await api.CreateIssueAsync(1, "subj", null, null, null, null, null, null, null);
        Assert.True(ok);
    }

    [Fact]
    public async Task ListIssuesAsync_HandlesNullFields()
    {
        var api = CreateApi(req =>
        {
            if (req.RequestUri!.AbsolutePath.EndsWith("auth"))
            {
                var content = new StringContent("{\"auth_token\":\"t\"}", Encoding.UTF8, "application/json");
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = content };
            }
            var path = req.RequestUri!.AbsolutePath;
            var query = req.RequestUri!.Query;
            if (path == "/issue-statuses" && query.Contains("is_closed=true"))
            {
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent("[]", Encoding.UTF8, "application/json")
                };
            }
            if (path == "/issue-statuses")
            {
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent("[{\"id\":1,\"name\":\"New\"}]", Encoding.UTF8, "application/json")
                };
            }
            if (path == "/severities")
            {
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent("[{\"id\":1,\"name\":\"Major\"}]", Encoding.UTF8, "application/json")
                };
            }
            if (path == "/issue-types")
            {
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent("[{\"id\":1,\"name\":\"Bug\"}]", Encoding.UTF8, "application/json")
                };
            }
            if (path == "/priorities")
            {
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent("[{\"id\":1,\"name\":\"High\"}]", Encoding.UTF8, "application/json")
                };
            }
            if (path == "/issues")
            {
                var body = "[{\"id\":1,\"ref\":1,\"subject\":\"Test\",\"status\":null,\"severity\":null,\"type\":null,\"priority\":null,\"assigned_to\":null}]";
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(body, Encoding.UTF8, "application/json")
                };
            }
            throw new InvalidOperationException("Unexpected request: " + req.RequestUri);
        });

        var items = await api.ListIssuesAsync(1, 1);
        Assert.Single(items);
        var issue = items[0];
        Assert.Null(issue.Status);
        Assert.Null(issue.Severity);
        Assert.Null(issue.Type);
        Assert.Null(issue.Priority);
        Assert.Null(issue.AssignedTo);
    }

    private sealed class DelegateHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, HttpResponseMessage> _responder;

        public DelegateHandler(Func<HttpRequestMessage, HttpResponseMessage> responder)
        {
            _responder = responder;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(_responder(request));
    }
}
