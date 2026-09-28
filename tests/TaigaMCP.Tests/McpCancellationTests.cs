using System.IO.Pipelines;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using ModelContextProtocol.Client;
using ModelContextProtocol.Server;
using TaigaMCP.Api;
using TaigaMCP.Config;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class McpCancellationTests
{
    [Fact]
    public async Task ProductionTool_McpCancellation_ReachesInFlightHttpSend()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var cancelled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var handler = new AsyncHttpHandler(async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/auth")) return AuthenticationTests.Json("{\"auth_token\":\"synthetic\"}");
            entered.SetResult();
            try { await Task.Delay(Timeout.Infinite, token); }
            catch (OperationCanceledException) { cancelled.SetResult(); throw; }
            throw new InvalidOperationException("Unexpected continuation");
        });
        var toServer = new Pipe();
        var toClient = new Pipe();
        await using var serverInput = toServer.Reader.AsStream();
        await using var serverOutput = toClient.Writer.AsStream();
        await using var clientInput = toServer.Writer.AsStream();
        await using var clientOutput = toClient.Reader.AsStream();
        var builder = Host.CreateApplicationBuilder();
        builder.Services.AddSingleton<IHttpClientFactory>(new TestHttpClientFactory(handler));
        builder.Services.AddSingleton(new AuthClient(Options.Create(new TaigaOptions { Username = "synthetic", Password = "synthetic" }), NullLogger<AuthClient>.Instance));
        builder.Services.AddSingleton<TaigaTransport>();
        builder.Services.AddSingleton<ProjectApi>();
        builder.Services.AddMcpServer().WithStreamServerTransport(serverInput, serverOutput).WithTools<ProjectTools>();
        using var host = builder.Build();
        await host.StartAsync();
        try
        {
            using var writer = new StreamWriter(clientInput, new System.Text.UTF8Encoding(false), leaveOpen: true) { AutoFlush = true };
            using var reader = new StreamReader(clientOutput, leaveOpen: true);
            await writer.WriteLineAsync("""{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"cancellation-test","version":"1"}}}""");
            Assert.NotNull(await reader.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(5)));
            await writer.WriteLineAsync("""{"jsonrpc":"2.0","method":"notifications/initialized"}""");
            await writer.WriteLineAsync("""{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}""");
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
            await writer.WriteLineAsync("""{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":2,"reason":"synthetic cancellation"}}""");
            await cancelled.Task.WaitAsync(TimeSpan.FromSeconds(5));
        }
        finally { await host.StopAsync(); }
    }
}
