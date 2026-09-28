using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json.Nodes;

namespace TaigaMCP.Tests;

public sealed record RecordedTaigaRequest(
    string Method,
    string PathAndQuery,
    string? Authorization,
    string Body);

public sealed class FakeTaigaHttpServer : IAsyncDisposable
{
    private readonly HttpListener _listener;
    private readonly CancellationTokenSource _shutdown = new();
    private readonly Task _listenTask;
    private readonly ConcurrentQueue<RecordedTaigaRequest> _requests = [];
    private readonly object _storyLock = new();
    private string _userStory102 = "{\"id\":102,\"ref\":18,\"project\":123,\"subject\":\"Created backlog story\",\"description\":\"Acceptance: the story can be reopened.\",\"status\":1,\"status_extra_info\":{\"name\":\"Ready\"},\"assigned_to\":null,\"tags\":[],\"milestone\":null,\"version\":4}";

    private FakeTaigaHttpServer(HttpListener listener, string baseUrl)
    {
        _listener = listener;
        BaseUrl = baseUrl;
        _listener.Start();
        _listenTask = ListenAsync();
    }

    public string BaseUrl { get; }

    public HttpStatusCode ProjectsStatusCode { get; set; } = HttpStatusCode.OK;

    public HttpStatusCode UserStoryUpdateStatusCode { get; set; } = HttpStatusCode.OK;

    public IReadOnlyList<RecordedTaigaRequest> Requests => _requests.ToArray();

    public static FakeTaigaHttpServer Start()
    {
        var portProbe = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        portProbe.Start();
        var port = ((System.Net.IPEndPoint)portProbe.LocalEndpoint).Port;
        portProbe.Stop();

        var listener = new HttpListener();
        var baseUrl = $"http://127.0.0.1:{port}/api/v1/";
        listener.Prefixes.Add(baseUrl);
        return new FakeTaigaHttpServer(listener, baseUrl);
    }

    public async ValueTask DisposeAsync()
    {
        _shutdown.Cancel();
        _listener.Stop();
        try
        {
            await _listenTask;
        }
        catch (HttpListenerException) when (_shutdown.IsCancellationRequested)
        {
        }
        catch (ObjectDisposedException) when (_shutdown.IsCancellationRequested)
        {
        }

        _listener.Close();
        _shutdown.Dispose();
    }

    private async Task ListenAsync()
    {
        while (!_shutdown.IsCancellationRequested)
        {
            HttpListenerContext context;
            try
            {
                context = await _listener.GetContextAsync();
            }
            catch (HttpListenerException) when (_shutdown.IsCancellationRequested)
            {
                return;
            }
            catch (ObjectDisposedException) when (_shutdown.IsCancellationRequested)
            {
                return;
            }

            await HandleAsync(context);
        }
    }

    private async Task HandleAsync(HttpListenerContext context)
    {
        var request = context.Request;
        using var reader = new StreamReader(request.InputStream, request.ContentEncoding ?? Encoding.UTF8);
        var body = await reader.ReadToEndAsync();
        _requests.Enqueue(new RecordedTaigaRequest(
            request.HttpMethod,
            request.Url?.PathAndQuery ?? string.Empty,
            request.Headers["Authorization"],
            body));

        var path = request.Url?.AbsolutePath ?? string.Empty;
        if (request.HttpMethod == HttpMethod.Post.Method && path.EndsWith("/auth", StringComparison.OrdinalIgnoreCase))
        {
            await RespondAsync(context.Response, HttpStatusCode.OK, "{\"auth_token\":\"integration-token\",\"refresh\":\"integration-refresh\"}");
            return;
        }

        if (request.HttpMethod == HttpMethod.Get.Method && path.EndsWith("/projects", StringComparison.OrdinalIgnoreCase))
        {
            if (ProjectsStatusCode != HttpStatusCode.OK)
            {
                await RespondAsync(context.Response, ProjectsStatusCode, "{\"detail\":\"synthetic upstream failure\"}");
                return;
            }

            var headers = new Dictionary<string, string>
            {
                ["x-paginated"] = "false",
                ["x-pagination-count"] = "1",
                ["x-pagination-current"] = "1"
            };
            await RespondAsync(context.Response, HttpStatusCode.OK, "[{\"id\":123,\"slug\":\"demo\",\"name\":\"Demo\"}]", headers);
            return;
        }

        if (request.HttpMethod == HttpMethod.Get.Method && path == "/api/v1/userstories/90")
        {
            await RespondAsync(
                context.Response,
                HttpStatusCode.OK,
                "{\"id\":90,\"ref\":2,\"project\":123,\"subject\":\"Story detail\",\"description\":\"**Ready**\",\"status\":1,\"status_extra_info\":{\"name\":\"Ready\"},\"assigned_to\":null,\"tags\":[],\"milestone\":null,\"version\":4}");
            return;
        }

        if (request.HttpMethod == HttpMethod.Get.Method && path == "/api/v1/userstories/102")
        {
            string story;
            lock (_storyLock)
                story = _userStory102;
            await RespondAsync(
                context.Response,
                HttpStatusCode.OK,
                story);
            return;
        }

        if (request.HttpMethod == HttpMethod.Get.Method && path == "/api/v1/userstories/103")
        {
            await RespondAsync(
                context.Response,
                HttpStatusCode.OK,
                """
                {"id":103,"ref":19,"project":123,"subject":"Assigned sprint story","description":"  Acceptance: the story can be reopened.  ","status":2,"status_extra_info":{"name":"In Progress"},"assigned_to":42,"tags":[["search","#336699"],["saved",null]],"milestone":55,"version":5}
                """);
            return;
        }

        if (request.HttpMethod == HttpMethod.Post.Method && path == "/api/v1/userstories")
        {
            var populated = body.Contains("\"milestone\":55", StringComparison.Ordinal);
            var createdStory = populated
                ? """
                  {"id":103,"ref":19,"project":123,"subject":"Assigned sprint story","description":"  Acceptance: the story can be reopened.  ","status":2,"status_extra_info":{"name":"In Progress"},"assigned_to":42,"tags":[["search","#336699"],["saved",null]],"milestone":55,"version":5}
                  """
                : """
                  {"id":102,"ref":18,"project":123,"subject":"Created backlog story","description":"Acceptance: the story can be reopened.","status":1,"status_extra_info":{"name":"Ready"},"assigned_to":null,"tags":[],"milestone":null,"version":4}
                  """;
            await RespondAsync(
                context.Response,
                HttpStatusCode.Created,
                createdStory);
            return;
        }

        if (request.HttpMethod == HttpMethod.Patch.Method && path == "/api/v1/userstories/102")
        {
            if (UserStoryUpdateStatusCode != HttpStatusCode.OK)
            {
                await RespondAsync(
                    context.Response,
                    UserStoryUpdateStatusCode,
                    "{\"detail\":\"synthetic update secret\"}");
                return;
            }

            var patch = JsonNode.Parse(body)?.AsObject();
            if (patch is null || !patch.TryGetPropertyValue("version", out var versionNode) ||
                versionNode is null || versionNode.GetValueKind() != JsonValueKind.Number)
            {
                await RespondAsync(context.Response, HttpStatusCode.BadRequest, "{\"version\":[\"invalid version\"]}");
                return;
            }

            string responseBody;
            HttpStatusCode responseStatus;
            lock (_storyLock)
            {
                var story = JsonNode.Parse(_userStory102)!.AsObject();
                var currentVersion = story["version"]!.GetValue<int>();
                var requestedVersion = versionNode.GetValue<int>();
                if (requestedVersion != currentVersion)
                {
                    responseStatus = HttpStatusCode.Conflict;
                    responseBody = "{\"detail\":\"version conflict\"}";
                }
                else
                {
                    foreach (var field in new[] { "subject", "description", "status", "assigned_to", "tags", "milestone" })
                    {
                        if (patch.ContainsKey(field))
                            story[field] = patch[field]?.DeepClone();
                    }

                    if (patch.TryGetPropertyValue("status", out var statusNode) && statusNode is not null)
                    {
                        story["status_extra_info"] = new JsonObject
                        {
                            ["name"] = statusNode.GetValue<int>() == 2 ? "In Progress" : "Ready"
                        };
                    }

                    story["version"] = currentVersion + 1;
                    _userStory102 = story.ToJsonString();
                    responseStatus = HttpStatusCode.OK;
                    responseBody = _userStory102;
                }
            }

            await RespondAsync(context.Response, responseStatus, responseBody);
            return;
        }

        string? payload = path switch
        {
            "/api/v1/resolver" => "{\"project\":123}",
            "/api/v1/issues/42" => "{\"id\":42,\"ref\":7,\"project\":123,\"subject\":\"Test\",\"version\":1}",
            "/api/v1/issues" when request.HttpMethod == "POST" => "{\"id\":42,\"project\":123,\"subject\":\"Created\",\"version\":1}",
            "/api/v1/issues" => "[{\"id\":42,\"project\":123,\"subject\":\"Test\",\"version\":1}]",
            "/api/v1/issue-statuses" => "[{\"id\":1,\"name\":\"Open\",\"is_closed\":false}]",
            "/api/v1/userstory-statuses" => "[{\"id\":1,\"name\":\"Ready\",\"is_closed\":false,\"is_archived\":false},{\"id\":2,\"name\":\"Terminado\",\"is_closed\":true,\"is_archived\":false},{\"id\":3,\"name\":\"Guardado\",\"is_closed\":false,\"is_archived\":true}]",
            "/api/v1/userstories" => "[{\"id\":90,\"ref\":2,\"subject\":\"Story\",\"status\":2},{\"id\":91,\"ref\":3,\"subject\":\"Archived story\",\"status\":3}]",
            "/api/v1/severities" or "/api/v1/priorities" or "/api/v1/issue-types" => "[{\"id\":1,\"name\":\"Normal\"}]",
            "/api/v1/history/issue/42" => "[]",
            _ => null
        };
        if (payload is not null)
        {
            await RespondAsync(context.Response, HttpStatusCode.OK, payload);
            return;
        }

        await RespondAsync(context.Response, HttpStatusCode.NotFound, "{\"detail\":\"not found\"}");
    }

    private static async Task RespondAsync(
        HttpListenerResponse response,
        HttpStatusCode statusCode,
        string body,
        IReadOnlyDictionary<string, string>? headers = null)
    {
        var bytes = Encoding.UTF8.GetBytes(body);
        response.StatusCode = (int)statusCode;
        response.ContentType = "application/json";
        response.ContentLength64 = bytes.Length;
        if (headers is not null)
        {
            foreach (var header in headers)
            {
                response.Headers[header.Key] = header.Value;
            }
        }

        await response.OutputStream.WriteAsync(bytes);
        response.Close();
    }
}
