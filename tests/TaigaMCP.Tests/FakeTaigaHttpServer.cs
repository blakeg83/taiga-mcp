using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json;
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
    private readonly object _taskLock = new();
    private readonly object _epicStoryLinkLock = new();
    private string _userStory102 = "{\"id\":102,\"ref\":18,\"project\":123,\"subject\":\"Created backlog story\",\"description\":\"Acceptance: the story can be reopened.\",\"status\":1,\"status_extra_info\":{\"name\":\"Ready\"},\"assigned_to\":null,\"tags\":[],\"milestone\":null,\"version\":4}";
    private string _task203 = "{\"id\":203,\"ref\":17,\"project\":123,\"subject\":\"Integration task\",\"description\":\"**Acceptance:** preserve Markdown and Unicode — ✓\",\"status\":11,\"status_extra_info\":{\"name\":\"Ready\"},\"assigned_to\":null,\"user_story\":102,\"milestone\":55,\"tags\":[[\"search\",\"#336699\"]],\"modified_date\":\"2026-09-28T12:00:00Z\",\"version\":2,\"is_blocked\":false,\"blocked_note\":\"\",\"is_closed\":false}";
    private bool _epicStoryLinkExists;
    private long _epicStoryLinkOrder;

    private FakeTaigaHttpServer(HttpListener listener, string baseUrl)
    {
        _listener = listener;
        BaseUrl = baseUrl;
        _listener.Start();
        _listenTask = ListenAsync();
    }

    public string BaseUrl { get; }

    public HttpStatusCode ProjectsStatusCode { get; set; } = HttpStatusCode.OK;

    public HttpStatusCode MembershipStatusCode { get; set; } = HttpStatusCode.OK;

    public HttpStatusCode CurrentUserStatusCode { get; set; } = HttpStatusCode.OK;

    public string CurrentUserResponseBody { get; set; } =
        "{\"id\":42,\"username\":\"integration-user\",\"full_name\":\"Integration User\",\"is_active\":true,\"email\":\"private@example.test\",\"auth_token\":\"must-not-escape\",\"roles\":[\"admin\"]}";

    public HttpStatusCode UserStoryUpdateStatusCode { get; set; } = HttpStatusCode.OK;

    public HttpStatusCode TaskCreateStatusCode { get; set; } = HttpStatusCode.Created;

    public HttpStatusCode TaskUpdateStatusCode { get; set; } = HttpStatusCode.OK;

    public HttpStatusCode EpicListStatusCode { get; set; } = HttpStatusCode.OK;

    public HttpStatusCode EpicDetailStatusCode { get; set; } = HttpStatusCode.OK;

    public HttpStatusCode EpicCreateStatusCode { get; set; } = HttpStatusCode.Created;

    public string EpicCreateResponseBody { get; set; } =
        """
        {"id":301,"ref":12,"project":123,"subject":"Integration epic","description":"Group saved-search delivery work.","status":7,"status_extra_info":{"name":"Ready"},"assigned_to":42,"color":"#336699","tags":[["search","#336699"]],"modified_date":"2026-09-28T12:03:00Z","version":4}
        """;

    public string EpicCreateErrorBody { get; set; } = "{\"detail\":\"synthetic epic create secret\"}";

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

        if (request.HttpMethod == HttpMethod.Get.Method && path == "/api/v1/users/me")
        {
            await RespondAsync(
                context.Response,
                CurrentUserStatusCode,
                CurrentUserResponseBody);
            return;
        }

        if (request.HttpMethod == HttpMethod.Get.Method && path.EndsWith("/by_ref", StringComparison.OrdinalIgnoreCase))
        {
            var responseBody = path switch
            {
                "/api/v1/issues/by_ref" => "{\"id\":42,\"ref\":42,\"project\":123,\"subject\":\"Resolved issue\",\"version\":1}",
                "/api/v1/userstories/by_ref" => "{\"id\":102,\"ref\":42,\"project\":123,\"subject\":\"Resolved story\",\"version\":4}",
                "/api/v1/tasks/by_ref" => "{\"id\":203,\"ref\":42,\"project\":123,\"subject\":\"Resolved task\",\"version\":2}",
                "/api/v1/epics/by_ref" => "{\"id\":301,\"ref\":42,\"project\":123,\"subject\":\"Resolved epic\",\"version\":4}",
                _ => null
            };
            await RespondAsync(
                context.Response,
                responseBody is null ? HttpStatusCode.NotFound : HttpStatusCode.OK,
                responseBody ?? "{\"detail\":\"not found\"}");
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

        if (request.HttpMethod == HttpMethod.Get.Method && path == "/api/v1/memberships")
        {
            if (MembershipStatusCode != HttpStatusCode.OK)
            {
                await RespondAsync(context.Response, MembershipStatusCode, "{\"detail\":\"synthetic membership secret\"}");
                return;
            }

            await RespondAsync(
                context.Response,
                HttpStatusCode.OK,
                """
                [
                  {"id":501,"user":42,"project":123,"role":7,"is_admin":true,"role_name":"Product Owner","full_name":"Active User","is_user_active":true,"is_owner":true,"email":"private-admin@example.test","user_email":"private-user@example.test"},
                  {"id":502,"user":43,"project":123,"role":null,"is_admin":false,"role_name":null,"full_name":"Inactive User","is_user_active":false,"is_owner":false,"email":"private-inactive@example.test"},
                  {"id":503,"user":null,"project":123,"role":8,"is_admin":false,"role_name":"Developer","full_name":null,"is_user_active":false,"is_owner":null,"email":"pending@example.test","invitation_extra_text":"private invitation text"}
                ]
                """,
                new Dictionary<string, string>
                {
                    ["x-paginated"] = "true",
                    ["x-pagination-count"] = "3",
                    ["x-pagination-next"] = "/api/v1/memberships?project=123&page=2"
                });
            return;
        }

        if (request.HttpMethod == HttpMethod.Get.Method && path.EndsWith("/tasks", StringComparison.OrdinalIgnoreCase))
        {
            await RespondAsync(
                context.Response,
                HttpStatusCode.OK,
                "[{\"id\":203,\"ref\":17,\"project\":123,\"subject\":\"Integration task\",\"status\":11,\"status_extra_info\":{\"name\":\"Ready\"},\"assigned_to\":null,\"user_story\":102,\"milestone\":55,\"modified_date\":\"2026-09-28T12:00:00Z\",\"version\":2}]",
                new Dictionary<string, string>
                {
                    ["x-paginated"] = "false",
                    ["x-pagination-count"] = "1",
                    ["x-pagination-current"] = "1"
                });
            return;
        }

        if (request.HttpMethod == HttpMethod.Get.Method && path == "/api/v1/tasks/203")
        {
            string task;
            lock (_taskLock)
                task = _task203;
            await RespondAsync(
                context.Response,
                HttpStatusCode.OK,
                task);
            return;
        }

        if (request.HttpMethod == HttpMethod.Get.Method && path.EndsWith("/epics", StringComparison.OrdinalIgnoreCase))
        {
            if (EpicListStatusCode != HttpStatusCode.OK)
            {
                await RespondAsync(context.Response, EpicListStatusCode, "{\"detail\":\"synthetic epic failure\"}");
                return;
            }

            await RespondAsync(
                context.Response,
                HttpStatusCode.OK,
                "[{\"id\":301,\"ref\":12,\"project\":123,\"subject\":\"Integration epic\",\"status\":7,\"status_extra_info\":{\"name\":\"Ready\"},\"assigned_to\":42,\"color\":\"#336699\",\"tags\":[[\"search\",\"#336699\"]],\"modified_date\":\"2026-09-28T12:03:00Z\",\"version\":4}]",
                new Dictionary<string, string>
                {
                    ["x-paginated"] = "false",
                    ["x-pagination-count"] = "1",
                    ["x-pagination-current"] = "1"
                });
            return;
        }

        if (request.HttpMethod == HttpMethod.Post.Method && path == "/api/v1/epics")
        {
            if (EpicCreateStatusCode != HttpStatusCode.Created)
            {
                await RespondAsync(context.Response, EpicCreateStatusCode, EpicCreateErrorBody);
                return;
            }

            await RespondAsync(context.Response, HttpStatusCode.Created, EpicCreateResponseBody);
            return;
        }

        if (path == "/api/v1/epics/301/related_userstories/102")
        {
            bool exists;
            long order;
            lock (_epicStoryLinkLock)
            {
                exists = _epicStoryLinkExists;
                order = _epicStoryLinkOrder;
            }

            if (request.HttpMethod == HttpMethod.Get.Method && exists)
            {
                await RespondAsync(
                    context.Response,
                    HttpStatusCode.OK,
                    $"{{\"epic\":301,\"user_story\":102,\"order\":{order}}}");
                return;
            }

            if (request.HttpMethod == HttpMethod.Get.Method)
            {
                await RespondAsync(context.Response, HttpStatusCode.NotFound, "{\"detail\":\"not found\"}");
                return;
            }
        }

        if (request.HttpMethod == HttpMethod.Post.Method && path == "/api/v1/epics/301/related_userstories")
        {
            var link = JsonNode.Parse(body)?.AsObject();
            lock (_epicStoryLinkLock)
            {
                _epicStoryLinkExists = true;
                _epicStoryLinkOrder = link?["order"]?.GetValue<long>() ?? 9001;
            }

            await RespondAsync(
                context.Response,
                HttpStatusCode.Created,
                $"{{\"epic\":301,\"user_story\":102,\"order\":{_epicStoryLinkOrder}}}");
            return;
        }

        if (request.HttpMethod == HttpMethod.Get.Method && path == "/api/v1/epics/301")
        {
            if (EpicDetailStatusCode != HttpStatusCode.OK)
            {
                await RespondAsync(context.Response, EpicDetailStatusCode, "{\"detail\":\"synthetic epic detail secret\"}");
                return;
            }

            await RespondAsync(
                context.Response,
                HttpStatusCode.OK,
                """
                {"id":301,"ref":12,"project":123,"subject":"Integration epic","description":"**Acceptance:** preserve Markdown and Unicode — ✓","status":7,"status_extra_info":{"name":"Ready"},"assigned_to":null,"color":"#336699","tags":[["search","#336699"]],"modified_date":"2026-09-28T12:03:00Z","is_closed":false,"is_blocked":true,"blocked_note":"Waiting for the saved-search API.","client_requirement":true,"team_requirement":false,"user_stories_counts":{"total":3,"closed":1},"version":4,"future_detail_field":{"ignored":true}}
                """);
            return;
        }

        if (request.HttpMethod == HttpMethod.Get.Method && path == "/api/v1/tasks/204")
        {
            await RespondAsync(
                context.Response,
                HttpStatusCode.OK,
                """
                {"id":204,"ref":18,"project":123,"subject":"Integration child task","description":"Acceptance: complete the saved-search endpoint.","status":11,"status_extra_info":{"name":"Ready"},"assigned_to":42,"user_story":103,"milestone":55,"tags":[["search","#336699"]],"modified_date":"2026-09-28T12:01:00Z","version":1,"is_closed":false}
                """);
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

        if (request.HttpMethod == HttpMethod.Post.Method && path == "/api/v1/tasks")
        {
            if (TaskCreateStatusCode != HttpStatusCode.Created)
            {
                await RespondAsync(
                    context.Response,
                    TaskCreateStatusCode,
                    "{\"status\":[\"synthetic task secret\"]}");
                return;
            }

            var create = JsonNode.Parse(body)?.AsObject();
            var userStoryId = create?["user_story"]?.GetValue<int>();
            var milestoneId = create?["milestone"]?.GetValue<int>();
            var responseBody = userStoryId == 103
                ? """
                  {"id":204,"ref":18,"project":123,"subject":"Integration child task","description":"Acceptance: complete the saved-search endpoint.","status":11,"status_extra_info":{"name":"Ready"},"assigned_to":42,"user_story":103,"milestone":55,"tags":[["search","#336699"]],"modified_date":"2026-09-28T12:01:00Z","version":1,"is_closed":false}
                  """
                : milestoneId == 55
                    ? """
                      {"id":206,"ref":20,"project":123,"subject":"Standalone sprint task","description":"","status":11,"status_extra_info":{"name":"Ready"},"assigned_to":null,"user_story":null,"milestone":55,"tags":[],"modified_date":"2026-09-28T12:02:00Z","version":1,"is_closed":false}
                      """
                    : """
                      {"id":205,"ref":19,"project":123,"subject":"Standalone task","description":"","status":11,"status_extra_info":{"name":"Ready"},"assigned_to":null,"user_story":null,"milestone":null,"tags":[],"modified_date":"2026-09-28T12:02:00Z","version":1,"is_closed":false}
                      """;
            await RespondAsync(
                context.Response,
                HttpStatusCode.Created,
                responseBody);
            return;
        }

        if (request.HttpMethod == HttpMethod.Patch.Method && path == "/api/v1/tasks/203")
        {
            if (TaskUpdateStatusCode != HttpStatusCode.OK)
            {
                await RespondAsync(
                    context.Response,
                    TaskUpdateStatusCode,
                    "{\"detail\":\"synthetic task update secret\"}");
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
            lock (_taskLock)
            {
                var task = JsonNode.Parse(_task203)!.AsObject();
                var currentVersion = task["version"]!.GetValue<int>();
                var requestedVersion = versionNode.GetValue<int>();
                if (requestedVersion != currentVersion)
                {
                    responseStatus = HttpStatusCode.Conflict;
                    responseBody = "{\"detail\":\"version conflict\"}";
                }
                else
                {
                    foreach (var field in new[] { "subject", "description", "status", "assigned_to", "tags", "is_blocked", "blocked_note" })
                    {
                        if (patch.ContainsKey(field))
                            task[field] = patch[field]?.DeepClone();
                    }

                    if (task["is_blocked"]?.GetValue<bool>() == false)
                        task["blocked_note"] = string.Empty;

                    if (patch.TryGetPropertyValue("status", out var statusNode) && statusNode is not null)
                    {
                        task["status_extra_info"] = new JsonObject
                        {
                            ["name"] = statusNode.GetValue<int>() == 11 ? "Ready" : "In Progress"
                        };
                    }

                    task["version"] = currentVersion + 1;
                    _task203 = task.ToJsonString();
                    responseStatus = HttpStatusCode.OK;
                    responseBody = _task203;
                }
            }

            await RespondAsync(context.Response, responseStatus, responseBody);
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

        if (request.HttpMethod == HttpMethod.Patch.Method && path == "/api/v1/issues/42")
        {
            var patch = JsonNode.Parse(body)?.AsObject();
            var version = patch?["version"]?.GetValue<int>() ?? -1;
            await RespondAsync(
                context.Response,
                HttpStatusCode.OK,
                $"{{\"id\":42,\"ref\":7,\"project\":123,\"subject\":\"Test\",\"status\":1,\"severity\":2,\"type\":3,\"priority\":4,\"version\":{version + 1}}}");
            return;
        }

        if (request.HttpMethod == HttpMethod.Patch.Method && path == "/api/v1/epics/301")
        {
            var patch = JsonNode.Parse(body)?.AsObject();
            var version = patch?["version"]?.GetValue<int>() ?? -1;
            await RespondAsync(context.Response, HttpStatusCode.OK, $"{{\"version\":{version + 1}}}");
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
