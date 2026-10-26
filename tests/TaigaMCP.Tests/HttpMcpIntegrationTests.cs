using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class HttpMcpIntegrationTests
{
    private static readonly string[] CredentialSentinels =
    [
        "server-side-user-sentinel",
        "server-side-password-sentinel",
        "integration-token",
        "integration-refresh"
    ];

    [Fact]
    public async Task HttpTransport_InitializesDiscoversAndInvokesReadOnlyTool_WithoutCredentialLeakage()
    {
        await using var taiga = FakeTaigaHttpServer.Start();
        var server = await HttpMcpProcess.StartAsync(
            Path.Combine(AppContext.BaseDirectory, "TaigaMCP.dll"),
            taiga.BaseUrl,
            "/private-mcp",
            "server-side-user-sentinel",
            "server-side-password-sentinel");

        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
            var initialize = await server.SendAsync(
                client,
                new
                {
                    jsonrpc = "2.0",
                    id = 0,
                    method = "initialize",
                    @params = new
                    {
                        protocolVersion = "2025-06-18",
                        capabilities = new { },
                        clientInfo = new { name = "taiga-mcp-test", version = "1.0" }
                    }
                });

            Assert.Equal(HttpStatusCode.OK, initialize.StatusCode);
            Assert.True(initialize.Headers.TryGetValues("Mcp-Session-Id", out var sessionValues));
            var sessionId = Assert.Single(sessionValues!);
            _ = await ReadAndAssertNoCredentialLeakageAsync(initialize);

            using var initialized = await server.SendAsync(
                client,
                new
                {
                    jsonrpc = "2.0",
                    method = "notifications/initialized",
                },
                sessionId);
            Assert.True(initialized.StatusCode is HttpStatusCode.Accepted or HttpStatusCode.OK);
            _ = await ReadAndAssertNoCredentialLeakageAsync(initialized);

            using var toolsList = await server.SendAsync(
                client,
                new
                {
                    jsonrpc = "2.0",
                    id = 1,
                    method = "tools/list",
                    @params = new { }
                },
                sessionId);
            Assert.Equal(HttpStatusCode.OK, toolsList.StatusCode);
            var toolsBody = await ReadAndAssertNoCredentialLeakageAsync(toolsList);
            using var toolsDocument = ParseMcpJson(toolsBody);
            var tools = toolsDocument.RootElement.GetProperty("result").GetProperty("tools");
            var toolNames = tools.EnumerateArray().Select(tool => tool.GetProperty("name").GetString()).ToArray();
            Assert.Equal(44, toolNames.Length);
            Assert.Equal(toolNames.Length, toolNames.Distinct(StringComparer.Ordinal).Count());
            Assert.Equal(1, toolNames.Count(name => name == "list_projects"));

            using var call = await server.SendAsync(
                client,
                new
                {
                    jsonrpc = "2.0",
                    id = 2,
                    method = "tools/call",
                    @params = new
                    {
                        name = "list_projects",
                        arguments = new { page = 1 }
                    }
                },
                sessionId);
            Assert.Equal(HttpStatusCode.OK, call.StatusCode);
            var callBody = await ReadAndAssertNoCredentialLeakageAsync(call);
            using var callDocument = ParseMcpJson(callBody);
            var callResult = callDocument.RootElement.GetProperty("result");
            Assert.False(
                callResult.TryGetProperty("isError", out var isError) &&
                isError.ValueKind == JsonValueKind.True &&
                isError.GetBoolean(),
                callBody);
            var contentText = Assert.Single(
                callResult.GetProperty("content").EnumerateArray(),
                content => content.GetProperty("type").GetString() == "text")
                .GetProperty("text")
                .GetString();
            using var projects = JsonDocument.Parse(contentText!);
            Assert.Contains(
                projects.RootElement.EnumerateArray(),
                project => project.GetProperty("name").GetString() == "Demo");

            Assert.Contains(
                taiga.Requests,
                request => request.Method == "GET" &&
                           request.PathAndQuery.StartsWith("/api/v1/projects?", StringComparison.Ordinal) &&
                           request.Authorization == "Bearer integration-token");
        }
        finally
        {
            await server.DisposeAsync();
        }

        AssertNoCredentialLeakage(server.Diagnostics);
        AssertNoCredentialLeakage(server.StandardOutput);
    }

    private static async Task<string> ReadAndAssertNoCredentialLeakageAsync(HttpResponseMessage response)
    {
        var body = await response.Content.ReadAsStringAsync();
        var headers = string.Join(
            "\n",
            response.Headers
                .Concat(response.Content.Headers)
                .SelectMany(header => header.Value.Select(value => $"{header.Key}: {value}")));
        AssertNoCredentialLeakage(body);
        AssertNoCredentialLeakage(headers);
        return body;
    }

    private static void AssertNoCredentialLeakage(string value)
    {
        foreach (var sentinel in CredentialSentinels)
            Assert.DoesNotContain(sentinel, value, StringComparison.Ordinal);
    }

    private static JsonDocument ParseMcpJson(string body)
    {
        var json = body.Trim();
        if (!json.StartsWith("{", StringComparison.Ordinal))
        {
            var dataLines = json
                .Split('\n')
                .Where(line => line.StartsWith("data:", StringComparison.Ordinal))
                .Select(line => line["data:".Length..].Trim())
                .ToArray();
            json = string.Join("\n", dataLines);
        }

        return JsonDocument.Parse(json);
    }

    private sealed class HttpMcpProcess : IAsyncDisposable
    {
        private readonly Process _process;
        private readonly Task<string> _standardOutputTask;
        private readonly Task<string> _diagnosticsTask;
        private readonly Uri _endpoint;
        private int _disposed;

        private HttpMcpProcess(
            Process process,
            Task<string> standardOutputTask,
            Task<string> diagnosticsTask,
            Uri endpoint)
        {
            _process = process;
            _standardOutputTask = standardOutputTask;
            _diagnosticsTask = diagnosticsTask;
            _endpoint = endpoint;
        }

        public string StandardOutput { get; private set; } = string.Empty;

        public string Diagnostics { get; private set; } = string.Empty;

        public static async Task<HttpMcpProcess> StartAsync(
            string assemblyPath,
            string taigaBaseUrl,
            string path,
            string username,
            string password)
        {
            var port = GetAvailablePort();
            var endpoint = new Uri($"http://127.0.0.1:{port}{path}");
            var startInfo = new ProcessStartInfo
            {
                FileName = "dotnet",
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(assemblyPath)!
            };
            startInfo.ArgumentList.Add(assemblyPath);
            startInfo.Environment["TAIGA__BASEURL"] = taigaBaseUrl;
            startInfo.Environment["TAIGA__USERNAME"] = username;
            startInfo.Environment["TAIGA__PASSWORD"] = password;
            startInfo.Environment["MCP__TRANSPORT"] = "http";
            startInfo.Environment["MCP__ADDRESS"] = "127.0.0.1";
            startInfo.Environment["MCP__PORT"] = port.ToString();
            startInfo.Environment["MCP__PATH"] = path;
            startInfo.Environment["DOTNET_NOLOGO"] = "1";

            var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            if (!process.Start())
            {
                process.Dispose();
                throw new InvalidOperationException("Could not start the HTTP MCP process.");
            }

            var server = new HttpMcpProcess(
                process,
                process.StandardOutput.ReadToEndAsync(),
                process.StandardError.ReadToEndAsync(),
                endpoint);
            try
            {
                await server.WaitUntilReadyAsync();
                return server;
            }
            catch
            {
                await server.DisposeAsync();
                throw;
            }
        }

        public async Task<HttpResponseMessage> SendAsync(
            HttpClient client,
            object message,
            string? sessionId = null)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, _endpoint)
            {
                Content = new StringContent(
                    JsonSerializer.Serialize(message),
                    Encoding.UTF8,
                    "application/json")
            };
            request.Headers.Accept.ParseAdd("application/json");
            request.Headers.Accept.ParseAdd("text/event-stream");
            if (sessionId is not null)
                request.Headers.TryAddWithoutValidation("Mcp-Session-Id", sessionId);

            return await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
        }

        public async ValueTask DisposeAsync()
        {
            if (Interlocked.Exchange(ref _disposed, 1) != 0)
                return;

            try
            {
                _process.StandardInput.Close();
            }
            catch (ObjectDisposedException)
            {
            }

            if (!_process.HasExited)
            {
                _process.Kill(entireProcessTree: true);
                await _process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
            }

            StandardOutput = await _standardOutputTask.WaitAsync(TimeSpan.FromSeconds(5));
            Diagnostics = await _diagnosticsTask.WaitAsync(TimeSpan.FromSeconds(5));
            _process.Dispose();
        }

        private async Task WaitUntilReadyAsync()
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            using var client = new HttpClient { Timeout = TimeSpan.FromMilliseconds(500) };
            var readinessEndpoint = new UriBuilder(_endpoint) { Path = "/__taiga_mcp_readiness__" }.Uri;
            while (true)
            {
                timeout.Token.ThrowIfCancellationRequested();
                if (_process.HasExited)
                {
                    var diagnostics = _diagnosticsTask.IsCompletedSuccessfully ? _diagnosticsTask.Result : "";
                    throw new InvalidOperationException($"HTTP MCP process exited before listening. Diagnostics: {diagnostics}");
                }

                try
                {
                    using var request = new HttpRequestMessage(HttpMethod.Get, readinessEndpoint);
                    request.Headers.Accept.ParseAdd("application/json");
                    using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
                    return;
                }
                catch (HttpRequestException)
                {
                    await Task.Delay(TimeSpan.FromMilliseconds(50), timeout.Token);
                }
                catch (TaskCanceledException) when (!timeout.IsCancellationRequested)
                {
                    await Task.Delay(TimeSpan.FromMilliseconds(50), timeout.Token);
                }
            }
        }

        private static int GetAvailablePort()
        {
            using var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            return ((IPEndPoint)listener.LocalEndpoint).Port;
        }
    }
}
