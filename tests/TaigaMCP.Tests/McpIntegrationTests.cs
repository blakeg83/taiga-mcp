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

        await using var process = StrictMcpProcess.Start(
            "dotnet",
            [serverAssembly],
            CreateEnvironment(taiga),
            Path.GetDirectoryName(serverAssembly));
        using var protocolDeadline = new CancellationTokenSource(TimeSpan.FromSeconds(15));

        await using (var client = await McpClientFactory.CreateAsync(process.Transport, cancellationToken: protocolDeadline.Token))
        {
            var tools = await client.ListToolsAsync(cancellationToken: protocolDeadline.Token);
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

            var result = await client.CallToolAsync(
                "list_projects",
                new Dictionary<string, object?>(),
                cancellationToken: protocolDeadline.Token);
            Assert.False(result.IsError == true);
            var projects = JsonSerializer.Deserialize<JsonElement>(GetText(result));
            Assert.Equal(JsonValueKind.Array, projects.ValueKind);
            Assert.Equal(123, projects[0].GetProperty("id").GetInt32());

            var projectRequest = Assert.Single(taiga.Requests, request => request.PathAndQuery.StartsWith("/api/v1/projects", StringComparison.Ordinal));
            Assert.Equal("Bearer integration-token", projectRequest.Authorization);
            Assert.Contains("member=6", projectRequest.PathAndQuery);
            Assert.Contains("page=1", projectRequest.PathAndQuery);

            taiga.ProjectsStatusCode = System.Net.HttpStatusCode.InternalServerError;
            var failed = await client.CallToolAsync(
                "list_projects",
                new Dictionary<string, object?>(),
                cancellationToken: protocolDeadline.Token);
            Assert.True(failed.IsError);
            Assert.Contains("error", GetText(failed), StringComparison.OrdinalIgnoreCase);
        }

        await process.DisposeAsync();
        await process.ValidationCompleted.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.Null(process.ValidationFailure);
        Assert.NotEmpty(process.RawStdoutLines);
        foreach (var line in process.RawStdoutLines)
        {
            McpProtocolLineValidator.ValidateLine(line);
        }
    }

    [Fact]
    public async Task ProductionServer_RejectsStartupStdoutContaminationInTemporaryCopy()
    {
        await using var taiga = FakeTaigaHttpServer.Start();
        var temporaryRoot = CreateTemporaryApplicationCopy();
        try
        {
            var copiedAssembly = Path.Combine(temporaryRoot, "TaigaMCP.dll");
            var launcher = Path.Combine(temporaryRoot, "contaminated.cmd");
            File.WriteAllText(
                launcher,
                $"@echo off\r\necho REVIEW: non-JSON stdout contamination\r\ndotnet \"{copiedAssembly}\"\r\n",
                System.Text.Encoding.ASCII);

            await using var process = StrictMcpProcess.Start(
                "cmd.exe",
                ["/d", "/c", "call contaminated.cmd"],
                CreateEnvironment(taiga),
                temporaryRoot);
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));

            await Assert.ThrowsAnyAsync<Exception>(async () =>
                await McpClientFactory.CreateAsync(process.Transport, cancellationToken: timeout.Token));

            await process.ValidationCompleted.WaitAsync(timeout.Token);
            Assert.True(
                process.RawStdoutLines.Contains("REVIEW: non-JSON stdout contamination"),
                $"stdout=[{string.Join(" | ", process.RawStdoutLines)}]; stderr=[{string.Join(" | ", process.StderrLines)}]; validation={process.ValidationFailure}");
            var failure = Assert.IsType<InvalidDataException>(process.ValidationFailure);
            Assert.Contains("not JSON", failure.Message);
        }
        finally
        {
            Directory.Delete(temporaryRoot, recursive: true);
        }
    }

    [Theory]
    [InlineData("")]
    [InlineData("plain-text log line")]
    [InlineData("42")]
    public void ProtocolLineValidator_RejectsNonProtocolOutput(string line)
    {
        Assert.ThrowsAny<Exception>(() => McpProtocolLineValidator.ValidateLine(line));
    }

    private static IReadOnlyDictionary<string, string> CreateEnvironment(FakeTaigaHttpServer taiga)
        => new Dictionary<string, string>
        {
            ["TAIGA__BASEURL"] = taiga.BaseUrl,
            ["TAIGA__USERNAME"] = "integration-user",
            ["TAIGA__PASSWORD"] = "integration-password",
            ["DOTNET_NOLOGO"] = "1"
        };

    private static string CreateTemporaryApplicationCopy()
    {
        var temporaryRoot = Path.Combine(Path.GetTempPath(), $"TaigaMCP-review-{Guid.NewGuid():N}");
        Directory.CreateDirectory(temporaryRoot);
        foreach (var file in Directory.EnumerateFiles(AppContext.BaseDirectory))
        {
            File.Copy(file, Path.Combine(temporaryRoot, Path.GetFileName(file)));
        }

        return temporaryRoot;
    }

    private static string GetText(CallToolResult result)
        => Assert.Single(result.Content.OfType<TextContentBlock>()).Text;
}
