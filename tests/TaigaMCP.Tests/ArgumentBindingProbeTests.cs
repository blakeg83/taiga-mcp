using System.IO.Pipelines;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using ModelContextProtocol;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class ArgumentBindingProbeTests
{
    [Fact]
    public async Task InstalledSdk_BindsExplicitFalseAndEmptyArray_AndRejectsMissingRequiredInteger()
    {
        var clientToServer = new Pipe();
        var serverToClient = new Pipe();
        await using var serverInput = clientToServer.Reader.AsStream(leaveOpen: true);
        await using var serverOutput = serverToClient.Writer.AsStream(leaveOpen: true);
        await using var clientInput = clientToServer.Writer.AsStream(leaveOpen: true);
        await using var clientOutput = serverToClient.Reader.AsStream(leaveOpen: true);

        var builder = Host.CreateApplicationBuilder();
        builder.Services
            .AddMcpServer()
            .WithStreamServerTransport(serverInput, serverOutput)
            .WithTools<ArgumentBindingProbeTools>();
        using var host = builder.Build();
        await host.StartAsync();

        var transport = new StreamClientTransport(clientInput, clientOutput);
        await using var client = await McpClientFactory.CreateAsync(transport);

        var result = await client.CallToolAsync(
            "probe_arguments",
            new Dictionary<string, object?>
            {
                ["requiredInteger"] = 7,
                ["optionalText"] = null,
                ["explicitFalse"] = false,
                ["items"] = Array.Empty<string>()
            });

        Assert.False(result.IsError == true);
        using var bound = JsonDocument.Parse(GetText(result));
        Assert.Equal(7, bound.RootElement.GetProperty("requiredInteger").GetInt32());
        Assert.Equal(JsonValueKind.Null, bound.RootElement.GetProperty("optionalText").ValueKind);
        Assert.False(bound.RootElement.GetProperty("explicitFalse").GetBoolean());
        Assert.Empty(bound.RootElement.GetProperty("items").EnumerateArray());

        var missingRequired = await IsToolFailureAsync(async () => await client.CallToolAsync(
            "probe_arguments",
            new Dictionary<string, object?>
            {
                ["explicitFalse"] = false
            }));
        Assert.True(missingRequired);

        await host.StopAsync();
    }

    private static async Task<bool> IsToolFailureAsync(Func<Task<CallToolResult>> call)
    {
        try
        {
            return (await call()).IsError == true;
        }
        catch (McpException)
        {
            return true;
        }
    }

    private static string GetText(CallToolResult result)
        => Assert.Single(result.Content.OfType<TextContentBlock>()).Text;
}

[McpServerToolType]
public sealed class ArgumentBindingProbeTools
{
    [McpServerTool(Name = "probe_arguments")]
    public string ProbeArguments(
        int requiredInteger,
        string? optionalText = "default",
        bool explicitFalse = true,
        string[]? items = null)
        => JsonSerializer.Serialize(new
        {
            requiredInteger,
            optionalText,
            explicitFalse,
            items
        });
}
