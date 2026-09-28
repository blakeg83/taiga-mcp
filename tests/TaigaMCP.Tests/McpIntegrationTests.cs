using System.Text.Json;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class McpIntegrationTests
{
    [Fact]
    public async Task ProductionServer_ListsAllTools_InvokesReadTool_AndReportsUpstreamFailure()
    {
        await using var taiga = FakeTaigaHttpServer.Start();
        var serverAssembly = Path.Combine(AppContext.BaseDirectory, "TaigaMCP.dll");
        Assert.True(File.Exists(serverAssembly), $"Expected the application assembly at {serverAssembly}");

        var stderr = new List<string>();
        var transport = new StdioClientTransport(new StdioClientTransportOptions
        {
            Name = "TaigaMCP integration",
            Command = "dotnet",
            Arguments = [serverAssembly],
            WorkingDirectory = Path.GetDirectoryName(serverAssembly),
            EnvironmentVariables = new Dictionary<string, string?>
            {
                ["TAIGA__BASEURL"] = taiga.BaseUrl,
                ["TAIGA__USERNAME"] = "integration-user",
                ["TAIGA__PASSWORD"] = "integration-password",
                ["DOTNET_NOLOGO"] = "1"
            },
            StandardErrorLines = line => stderr.Add(line)
        });

        await using var client = await McpClientFactory.CreateAsync(transport);
        var tools = await client.ListToolsAsync();
        var expectedNames = new[]
        {
            "create_issue",
            "get_issue",
            "list_issue_priorities",
            "list_issue_severities",
            "list_issue_statuses",
            "list_issue_types",
            "list_issues",
            "list_projects",
            "list_user_stories",
            "resolve_project",
            "update_issue"
        };
        Assert.Equal(expectedNames, tools.Select(tool => tool.Name).OrderBy(name => name));

        var listProjects = Assert.Single(tools, tool => tool.Name == "list_projects");
        var listProjectsSchema = listProjects.JsonSchema;
        Assert.Contains("member", listProjectsSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name));
        var listProjectsRequired = listProjectsSchema.TryGetProperty("required", out var required)
            ? required.EnumerateArray().Select(value => value.GetString()).ToArray()
            : [];
        Assert.DoesNotContain("member", listProjectsRequired);

        var listIssues = Assert.Single(tools, tool => tool.Name == "list_issues");
        Assert.Contains("projectId", listIssues.JsonSchema.GetProperty("required").EnumerateArray().Select(value => value.GetString()));

        var result = await client.CallToolAsync("list_projects", new Dictionary<string, object?>());
        Assert.False(result.IsError == true);
        var projects = JsonSerializer.Deserialize<JsonElement>(GetText(result));
        Assert.Equal(JsonValueKind.Array, projects.ValueKind);
        Assert.Equal(123, projects[0].GetProperty("id").GetInt32());

        var projectRequest = Assert.Single(taiga.Requests, request => request.PathAndQuery.StartsWith("/api/v1/projects", StringComparison.Ordinal));
        Assert.Equal("Bearer integration-token", projectRequest.Authorization);
        Assert.Contains("member=6", projectRequest.PathAndQuery);
        Assert.Contains("page=1", projectRequest.PathAndQuery);

        taiga.ProjectsStatusCode = System.Net.HttpStatusCode.InternalServerError;
        var failed = await client.CallToolAsync("list_projects", new Dictionary<string, object?>());
        Assert.True(failed.IsError);
        Assert.Contains("error", GetText(failed), StringComparison.OrdinalIgnoreCase);
    }

    private static string GetText(CallToolResult result)
        => Assert.Single(result.Content.OfType<TextContentBlock>()).Text;
}
