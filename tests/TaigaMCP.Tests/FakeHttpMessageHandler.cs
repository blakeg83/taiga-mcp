using TaigaMCP.Api;
using TaigaMCP.Config;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Text;

namespace TaigaMCP.Tests;

public sealed record RecordedHttpRequest(
    HttpMethod Method,
    Uri Uri,
    IReadOnlyDictionary<string, string[]> Headers,
    string Body);

public sealed class FakeHttpMessageHandler : HttpMessageHandler
{
    private readonly List<FakeRoute> _routes = [];
    private readonly ConcurrentQueue<RecordedHttpRequest> _requests = [];

    public IReadOnlyList<RecordedHttpRequest> Requests => _requests.ToArray();

    public FakeHttpMessageHandler AddJsonRoute(
        HttpMethod method,
        string path,
        string json,
        HttpStatusCode statusCode = HttpStatusCode.OK,
        IReadOnlyDictionary<string, string>? headers = null)
    {
        return AddRoute(method, path, _ => CreateResponse(statusCode, json, headers));
    }

    public FakeHttpMessageHandler AddTextRoute(
        HttpMethod method,
        string path,
        string text,
        HttpStatusCode statusCode = HttpStatusCode.OK,
        IReadOnlyDictionary<string, string>? headers = null)
    {
        return AddRoute(method, path, _ => CreateResponse(statusCode, text, headers));
    }

    public FakeHttpMessageHandler AddExceptionRoute(
        HttpMethod method,
        string path,
        Exception exception)
    {
        return AddRoute(method, path, _ => throw exception);
    }

    public FakeHttpMessageHandler AddRoute(
        HttpMethod method,
        string path,
        Func<RecordedHttpRequest, HttpResponseMessage> responder)
    {
        _routes.Add(new FakeRoute(method, path, responder));
        return this;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var body = request.Content is null
            ? string.Empty
            : await request.Content.ReadAsStringAsync(cancellationToken);
        var headers = request.Headers
            .Concat(request.Content?.Headers ?? Enumerable.Empty<KeyValuePair<string, IEnumerable<string>>>())
            .GroupBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(
                group => group.Key,
                group => group.SelectMany(pair => pair.Value).ToArray(),
                StringComparer.OrdinalIgnoreCase);
        var recorded = new RecordedHttpRequest(request.Method, request.RequestUri!, headers, body);
        _requests.Enqueue(recorded);

        var route = _routes.FirstOrDefault(candidate => candidate.Matches(recorded));
        if (route is null)
        {
            throw new InvalidOperationException($"No fake HTTP route matched {recorded.Method} {recorded.Uri.PathAndQuery}.");
        }

        return route.Responder(recorded);
    }

    private static HttpResponseMessage CreateResponse(
        HttpStatusCode statusCode,
        string body,
        IReadOnlyDictionary<string, string>? headers)
    {
        var response = new HttpResponseMessage(statusCode)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json")
        };
        if (headers is not null)
        {
            foreach (var header in headers)
            {
                response.Headers.TryAddWithoutValidation(header.Key, header.Value);
            }
        }

        return response;
    }

    private sealed record FakeRoute(
        HttpMethod Method,
        string Path,
        Func<RecordedHttpRequest, HttpResponseMessage> Responder)
    {
        public bool Matches(RecordedHttpRequest request)
            => request.Method == Method &&
               string.Equals(request.Uri.AbsolutePath, Path, StringComparison.OrdinalIgnoreCase);
    }
}

public static class TaigaTestClient
{
    public const string BaseUrl = "https://fake.taiga.test/api/v1/";
    public const string Token = "synthetic-token";

    public static (HttpClient Client, AuthClient Auth) Create(FakeHttpMessageHandler handler)
    {
        handler.AddJsonRoute(
            HttpMethod.Post,
            "/api/v1/auth",
            $"{{\"auth_token\":\"{Token}\",\"refresh\":\"synthetic-refresh\"}}");

        var options = Microsoft.Extensions.Options.Options.Create(new TaigaOptions
        {
            BaseUrl = BaseUrl,
            Username = "synthetic-user",
            Password = "synthetic-password"
        });
        var auth = new AuthClient(options, Microsoft.Extensions.Logging.Abstractions.NullLogger<AuthClient>.Instance);
        var client = new HttpClient(handler) { BaseAddress = new Uri(BaseUrl) };
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        return (client, auth);
    }
}

public sealed class TestHttpClientFactory(HttpMessageHandler handler) : IHttpClientFactory
{
    public HttpClient CreateClient(string name) => new(handler, disposeHandler: false)
    {
        BaseAddress = new Uri(TaigaTestClient.BaseUrl)
    };
}
