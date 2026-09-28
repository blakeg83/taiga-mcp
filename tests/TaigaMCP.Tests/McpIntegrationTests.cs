using System.Text.Json;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class McpIntegrationTests
{
    [Fact]
    public async Task ProductionServer_AllToolsAndNullEmptyArguments_KeepContracts()
    {
        await using var taiga = FakeTaigaHttpServer.Start();
        var assembly = Path.Combine(AppContext.BaseDirectory, "TaigaMCP.dll");
        await using var process = StrictMcpProcess.Start("dotnet", [assembly], CreateEnvironment(taiga), Path.GetDirectoryName(assembly));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        await using var client = await McpClientFactory.CreateAsync(process.Transport, cancellationToken: timeout.Token);
        async Task<CallToolResult> Call(string name, Dictionary<string, object?> arguments)
            => await client.CallToolAsync(name, arguments, cancellationToken: timeout.Token);

        var tools = await client.ListToolsAsync(cancellationToken: timeout.Token);
        foreach (var tool in tools)
        {
            Assert.False(string.IsNullOrWhiteSpace(tool.Description));
            foreach (var property in tool.JsonSchema.GetProperty("properties").EnumerateObject())
                Assert.False(string.IsNullOrWhiteSpace(property.Value.GetProperty("description").GetString()));
        }
        foreach (var member in new string?[] { null, "" })
        {
            Assert.False((await Call("list_projects", new() { ["member"] = member })).IsError == true);
            Assert.DoesNotContain("member=", taiga.Requests.Last().PathAndQuery);
        }
        Assert.False((await Call("resolve_project", new() { ["slug"] = "demo" })).IsError == true);
        foreach (var name in new[] { "list_issues", "list_user_stories", "list_issue_statuses", "list_issue_priorities", "list_issue_severities", "list_issue_types" })
            Assert.False((await Call(name, new() { ["projectId"] = 123 })).IsError == true);
        Assert.False((await Call("get_user_story", new() { ["userStoryId"] = 90 })).IsError == true);
        var detail = await Call("get_issue", new() { ["issueId"] = 42 });
        Assert.False(detail.IsError == true);
        Assert.False(JsonSerializer.Deserialize<JsonElement>(GetText(detail)).GetProperty("issue").TryGetProperty("assigned_to", out _));
        Assert.False((await Call("create_issue", new() { ["projectId"] = 123, ["subject"] = "Created" })).IsError == true);
        var createBody = JsonSerializer.Deserialize<JsonElement>(taiga.Requests.Single(r => r.Method == "POST" && r.PathAndQuery == "/api/v1/issues").Body);
        Assert.False(createBody.TryGetProperty("description", out _));

        Assert.False((await Call("update_issue", new()
        {
            ["issueId"] = 42,
            ["version"] = 0,
            ["description"] = "",
            ["tags"] = Array.Empty<string>()
        })).IsError == true);
        var body = JsonSerializer.Deserialize<JsonElement>(taiga.Requests.Single(r => r.Method == "PATCH").Body);
        AssertPatchProperties(body, "description", "tags", "version");
        Assert.False(body.TryGetProperty("subject", out _));
        Assert.Equal("", body.GetProperty("description").GetString());
        Assert.Equal(0, body.GetProperty("tags").GetArrayLength());
        Assert.Equal(0, body.GetProperty("version").GetInt32());

        Assert.False((await Call("update_issue", new()
        {
            ["issueId"] = 42,
            ["version"] = 1,
            ["status"] = 1
        })).IsError == true);
        body = JsonSerializer.Deserialize<JsonElement>(taiga.Requests.Last(request => request.Method == "PATCH").Body);
        AssertPatchProperties(body, "status", "version");
        Assert.False(body.TryGetProperty("subject", out _));
        Assert.Equal(1, body.GetProperty("status").GetInt32());
        Assert.Equal(1, body.GetProperty("version").GetInt32());

        Assert.False((await Call("update_issue", new()
        {
            ["issueId"] = 42,
            ["version"] = 2,
            ["clearFields"] = new[] { "assigned_to" }
        })).IsError == true);
        body = JsonSerializer.Deserialize<JsonElement>(taiga.Requests.Last(request => request.Method == "PATCH").Body);
        AssertPatchProperties(body, "assigned_to", "version");
        Assert.True(body.TryGetProperty("assigned_to", out var assignedTo));
        Assert.Equal(JsonValueKind.Null, assignedTo.ValueKind);
        Assert.Equal(2, body.GetProperty("version").GetInt32());

        Assert.False((await Call("update_issue", new()
        {
            ["issueId"] = 42,
            ["version"] = 3,
            ["comment"] = "Returned to triage."
        })).IsError == true);
        body = JsonSerializer.Deserialize<JsonElement>(taiga.Requests.Last(request => request.Method == "PATCH").Body);
        AssertPatchProperties(body, "comment", "version");
        Assert.False(body.TryGetProperty("subject", out _));
        Assert.Equal("Returned to triage.", body.GetProperty("comment").GetString());
        Assert.Equal(3, body.GetProperty("version").GetInt32());

        var count = taiga.Requests.Count;
        var invalid = await Call("update_issue", new() { ["issueId"] = 42, ["subject"] = null, ["version"] = 1 });
        Assert.True(invalid.IsError);
        Assert.Contains("requires a change", GetText(invalid));
        Assert.True((await Call("list_issues", new() { ["projectId"] = 0 })).IsError);
        Assert.True((await Call("resolve_project", new() { ["slug"] = " " })).IsError);
        Assert.Equal(count, taiga.Requests.Count);
    }
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
                "get_user_story",
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

            foreach (var tool in tools)
                Assert.DoesNotContain("cancellationToken", tool.JsonSchema.GetProperty("properties").EnumerateObject().Select(p => p.Name));

            var listProjects = Assert.Single(tools, tool => tool.Name == "list_projects");
            var listProjectsSchema = listProjects.JsonSchema;
            Assert.Contains("member", listProjectsSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name));
            var listProjectsRequired = listProjectsSchema.TryGetProperty("required", out var required)
                ? required.EnumerateArray().Select(value => value.GetString()).ToArray()
                : [];
            Assert.DoesNotContain("member", listProjectsRequired);

            var listIssues = Assert.Single(tools, tool => tool.Name == "list_issues");
            Assert.Contains("projectId", listIssues.JsonSchema.GetProperty("required").EnumerateArray().Select(value => value.GetString()));
            var issueProperties = listIssues.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Contains("statusIds", issueProperties);
            Assert.Contains("assignedTo", issueProperties);
            Assert.Contains("typeId", issueProperties);
            Assert.Contains("priorityId", issueProperties);
            Assert.Contains("severityId", issueProperties);
            Assert.Contains("tags", issueProperties);
            Assert.Contains("query", issueProperties);
            Assert.Contains("includeClosed", issueProperties);
            Assert.Contains("includePageInfo", issueProperties);

            var listUserStories = Assert.Single(tools, tool => tool.Name == "list_user_stories");
            var storyProperties = listUserStories.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Contains("statusIds", storyProperties);
            Assert.Contains("assignedTo", storyProperties);
            Assert.Contains("milestoneId", storyProperties);
            Assert.Contains("backlogOnly", storyProperties);
            Assert.Contains("tags", storyProperties);
            Assert.Contains("query", storyProperties);
            Assert.Contains("includeClosed", storyProperties);
            Assert.Contains("includeArchived", storyProperties);
            Assert.Contains("includePageInfo", storyProperties);
            var storyRequired = listUserStories.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "projectId" }, storyRequired);

            var getUserStory = Assert.Single(tools, tool => tool.Name == "get_user_story");
            var getUserStoryProperties = getUserStory.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "userStoryId" }, getUserStoryProperties);
            var getUserStoryRequired = getUserStory.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "userStoryId" }, getUserStoryRequired);

            var updateIssue = Assert.Single(tools, tool => tool.Name == "update_issue");
            var updateProperties = updateIssue.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Contains("subject", updateProperties);
            Assert.Contains("clearFields", updateProperties);
            var updateRequired = updateIssue.JsonSchema.GetProperty("required").EnumerateArray().Select(value => value.GetString()).ToArray();
            Assert.Contains("issueId", updateRequired);
            Assert.Contains("version", updateRequired);
            Assert.DoesNotContain("subject", updateRequired);

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
            Assert.DoesNotContain("member=", projectRequest.PathAndQuery);
            Assert.Contains("page=1", projectRequest.PathAndQuery);

            var issuePage = await client.CallToolAsync(
                "list_issues",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["statusIds"] = new[] { 1 },
                    ["includePageInfo"] = true
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(issuePage.IsError == true);
            var page = JsonSerializer.Deserialize<JsonElement>(GetText(issuePage));
            Assert.Equal(JsonValueKind.Object, page.ValueKind);
            Assert.Equal(JsonValueKind.Array, page.GetProperty("items").ValueKind);
            Assert.True(page.TryGetProperty("total", out var total));
            Assert.Equal(JsonValueKind.Null, total.ValueKind);
            var issueRequest = taiga.Requests.Last(request => request.PathAndQuery.Contains("/api/v1/issues", StringComparison.Ordinal));
            Assert.Equal("/api/v1/issues?project=123&page=1&status=1", issueRequest.PathAndQuery);

            var storyPage = await client.CallToolAsync(
                "list_user_stories",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["page"] = 2,
                    ["statusIds"] = new[] { 2, 3 },
                    ["assignedTo"] = 42,
                    ["backlogOnly"] = true,
                    ["tags"] = new[] { "a&b" },
                    ["query"] = "fix & revisión",
                    ["includeClosed"] = true,
                    ["includeArchived"] = true,
                    ["includePageInfo"] = true
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(storyPage.IsError == true);
            var storyEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(storyPage));
            Assert.Equal(JsonValueKind.Object, storyEnvelope.ValueKind);
            Assert.Equal(2, storyEnvelope.GetProperty("page").GetInt32());
            Assert.Equal(JsonValueKind.Array, storyEnvelope.GetProperty("items").ValueKind);
            Assert.False(storyEnvelope.GetProperty("items")[0].TryGetProperty("version", out _));
            var storyRequest = taiga.Requests.Last(request => request.PathAndQuery.Contains("/api/v1/userstories", StringComparison.Ordinal));
            Assert.Equal(
                "/api/v1/userstories?project=123&page=2&status=2%2C3&assigned_to=42&milestone__isnull=true&tags=a%26b&q=fix%20%26%20revisi%C3%B3n",
                storyRequest.PathAndQuery);

            var storyDetail = await client.CallToolAsync(
                "get_user_story",
                new Dictionary<string, object?> { ["userStoryId"] = 90 },
                cancellationToken: protocolDeadline.Token);
            Assert.False(storyDetail.IsError == true);
            var detail = JsonSerializer.Deserialize<JsonElement>(GetText(storyDetail));
            Assert.Equal(90, detail.GetProperty("id").GetInt32());
            Assert.Equal(4, detail.GetProperty("version").GetInt32());
            Assert.Equal("**Ready**", detail.GetProperty("description").GetString());
            var storyDetailRequest = Assert.Single(taiga.Requests, request => request.PathAndQuery == "/api/v1/userstories/90");
            Assert.Equal("Bearer integration-token", storyDetailRequest.Authorization);

            var legacy = await client.CallToolAsync("list_projects", new Dictionary<string, object?> { ["member"] = "6" }, cancellationToken: protocolDeadline.Token);
            Assert.False(legacy.IsError == true);
            Assert.Contains("member=6", taiga.Requests.Last().PathAndQuery);

            taiga.ProjectsStatusCode = System.Net.HttpStatusCode.InternalServerError;
            var failed = await client.CallToolAsync(
                "list_projects",
                new Dictionary<string, object?>(),
                cancellationToken: protocolDeadline.Token);
            Assert.True(failed.IsError);
            Assert.Contains("500", GetText(failed));
            Assert.Contains("upstream failure", GetText(failed));
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

    private static void AssertPatchProperties(JsonElement body, params string[] expectedNames)
    {
        var actualNames = body.EnumerateObject().Select(property => property.Name);
        Assert.Equal(
            expectedNames.OrderBy(name => name, StringComparer.Ordinal),
            actualNames.OrderBy(name => name, StringComparer.Ordinal));
    }
}
