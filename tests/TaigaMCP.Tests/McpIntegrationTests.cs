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
        foreach (var name in new[] { "list_issues", "list_user_stories", "list_tasks", "list_issue_statuses", "list_issue_priorities", "list_issue_severities", "list_issue_types" })
            Assert.False((await Call(name, new() { ["projectId"] = 123 })).IsError == true);
        Assert.False((await Call("get_user_story", new() { ["userStoryId"] = 90 })).IsError == true);
        var createdStory = await Call("create_user_story", new()
        {
            ["projectId"] = 123,
            ["subject"] = "Created backlog story"
        });
        Assert.False(createdStory.IsError == true);
        var createdStoryJson = JsonSerializer.Deserialize<JsonElement>(GetText(createdStory));
        Assert.Equal(102, createdStoryJson.GetProperty("id").GetInt32());
        Assert.Equal(4, createdStoryJson.GetProperty("version").GetInt32());
        Assert.Empty(createdStoryJson.GetProperty("tags").EnumerateArray());
        Assert.False(createdStoryJson.TryGetProperty("assigned_to", out _));
        Assert.False(createdStoryJson.TryGetProperty("milestone", out _));
        var createdStoryRequest = Assert.Single(taiga.Requests, request =>
            request.Method == "POST" && request.PathAndQuery == "/api/v1/userstories");
        var createdStoryBody = JsonSerializer.Deserialize<JsonElement>(createdStoryRequest.Body);
        Assert.Equal(new[] { "project", "subject" }, createdStoryBody.EnumerateObject().Select(property => property.Name).ToArray());
        Assert.Equal(123, createdStoryBody.GetProperty("project").GetInt32());
        Assert.Equal("Created backlog story", createdStoryBody.GetProperty("subject").GetString());
        var minimalReadBack = await Call("get_user_story", new() { ["userStoryId"] = createdStoryJson.GetProperty("id").GetInt32() });
        Assert.False(minimalReadBack.IsError == true);
        var minimalReadBackJson = JsonSerializer.Deserialize<JsonElement>(GetText(minimalReadBack));
        Assert.Equal(102, minimalReadBackJson.GetProperty("id").GetInt32());
        Assert.Equal(18, minimalReadBackJson.GetProperty("ref").GetInt32());
        Assert.Equal(4, minimalReadBackJson.GetProperty("version").GetInt32());
        var populatedStory = await Call("create_user_story", new()
        {
            ["projectId"] = 123,
            ["subject"] = "Assigned sprint story",
            ["description"] = "  Acceptance: the story can be reopened.  ",
            ["status"] = 2,
            ["assigned_to"] = 42,
            ["tags"] = new[] { "search", "saved" },
            ["milestoneId"] = 55
        });
        Assert.False(populatedStory.IsError == true);
        var populatedStoryJson = JsonSerializer.Deserialize<JsonElement>(GetText(populatedStory));
        Assert.Equal(103, populatedStoryJson.GetProperty("id").GetInt32());
        Assert.Equal(19, populatedStoryJson.GetProperty("ref").GetInt32());
        Assert.Equal(5, populatedStoryJson.GetProperty("version").GetInt32());
        Assert.Equal("  Acceptance: the story can be reopened.  ", populatedStoryJson.GetProperty("description").GetString());
        Assert.Equal(2, populatedStoryJson.GetProperty("status_id").GetInt32());
        Assert.Equal("In Progress", populatedStoryJson.GetProperty("status").GetString());
        Assert.Equal(42, populatedStoryJson.GetProperty("assigned_to").GetInt32());
        Assert.Equal(55, populatedStoryJson.GetProperty("milestone").GetInt32());
        Assert.Equal(new[] { "search", "saved" }, populatedStoryJson.GetProperty("tags").EnumerateArray().Select(tag => tag[0].GetString()));
        var populatedBody = JsonSerializer.Deserialize<JsonElement>(
            taiga.Requests.Last(request => request.Method == "POST" && request.PathAndQuery == "/api/v1/userstories").Body);
        Assert.Equal(
            new[] { "assigned_to", "description", "milestone", "project", "status", "subject", "tags" },
            populatedBody.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
        Assert.Equal("  Acceptance: the story can be reopened.  ", populatedBody.GetProperty("description").GetString());
        Assert.Equal(2, populatedBody.GetProperty("status").GetInt32());
        Assert.Equal(42, populatedBody.GetProperty("assigned_to").GetInt32());
        Assert.Equal(55, populatedBody.GetProperty("milestone").GetInt32());
        Assert.Equal(new[] { "search", "saved" }, populatedBody.GetProperty("tags").EnumerateArray().Select(tag => tag.GetString()));
        var populatedReadBack = await Call("get_user_story", new() { ["userStoryId"] = populatedStoryJson.GetProperty("id").GetInt32() });
        Assert.False(populatedReadBack.IsError == true);
        var populatedReadBackJson = JsonSerializer.Deserialize<JsonElement>(GetText(populatedReadBack));
        Assert.Equal(103, populatedReadBackJson.GetProperty("id").GetInt32());
        Assert.Equal(19, populatedReadBackJson.GetProperty("ref").GetInt32());
        Assert.Equal(5, populatedReadBackJson.GetProperty("version").GetInt32());
        Assert.Equal(42, populatedReadBackJson.GetProperty("assigned_to").GetInt32());
        Assert.Equal(55, populatedReadBackJson.GetProperty("milestone").GetInt32());
        Assert.Contains(taiga.Requests, request => request.Method == "GET" && request.PathAndQuery == "/api/v1/userstories/102");
        Assert.Contains(taiga.Requests, request => request.Method == "GET" && request.PathAndQuery == "/api/v1/userstories/103");

        var updatedStory = await Call("update_user_story", new()
        {
            ["userStoryId"] = 102,
            ["version"] = 4,
            ["clearFields"] = new[] { "milestone" },
            ["comment"] = "Move back to backlog."
        });
        Assert.False(updatedStory.IsError == true);
        var updatedStoryJson = JsonSerializer.Deserialize<JsonElement>(GetText(updatedStory));
        Assert.Equal(102, updatedStoryJson.GetProperty("id").GetInt32());
        Assert.Equal(5, updatedStoryJson.GetProperty("version").GetInt32());
        Assert.False(updatedStoryJson.TryGetProperty("milestone", out _));
        var updatedStoryRequest = Assert.Single(taiga.Requests, request =>
            request.Method == "PATCH" && request.PathAndQuery == "/api/v1/userstories/102");
        var updatedStoryBody = JsonSerializer.Deserialize<JsonElement>(updatedStoryRequest.Body);
        AssertPatchProperties(updatedStoryBody, "comment", "milestone", "version");
        Assert.Equal(JsonValueKind.Null, updatedStoryBody.GetProperty("milestone").ValueKind);
        Assert.Equal(4, updatedStoryBody.GetProperty("version").GetInt32());

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
        var body = JsonSerializer.Deserialize<JsonElement>(taiga.Requests.Single(r => r.Method == "PATCH" && r.PathAndQuery == "/api/v1/issues/42").Body);
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
        var invalidCreate = await Call("create_user_story", new() { ["projectId"] = 123, ["subject"] = " " });
        Assert.True(invalidCreate.IsError);
        Assert.Contains("subject must not be blank", GetText(invalidCreate));
        var invalid = await Call("update_issue", new() { ["issueId"] = 42, ["subject"] = null, ["version"] = 1 });
        Assert.True(invalid.IsError);
        Assert.Contains("requires a change", GetText(invalid));
        Assert.True((await Call("list_issues", new() { ["projectId"] = 0 })).IsError);
        Assert.True((await Call("resolve_project", new() { ["slug"] = " " })).IsError);
        Assert.Equal(count, taiga.Requests.Count);
    }

    [Fact]
    public async Task ProductionServer_UpdateUserStory_ReadsBackStateAndBindsOptionalArguments()
    {
        await using var taiga = FakeTaigaHttpServer.Start();
        var serverAssembly = Path.Combine(AppContext.BaseDirectory, "TaigaMCP.dll");
        await using var process = StrictMcpProcess.Start("dotnet", [serverAssembly], CreateEnvironment(taiga), Path.GetDirectoryName(serverAssembly));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        await using var client = await McpClientFactory.CreateAsync(process.Transport, cancellationToken: timeout.Token);
        async Task<CallToolResult> Call(string name, Dictionary<string, object?> arguments)
            => await client.CallToolAsync(name, arguments, cancellationToken: timeout.Token);

        var before = await Call("get_user_story", new() { ["userStoryId"] = 102 });
        Assert.False(before.IsError == true);
        var beforeJson = JsonSerializer.Deserialize<JsonElement>(GetText(before));
        Assert.Equal(4, beforeJson.GetProperty("version").GetInt32());
        Assert.False(beforeJson.TryGetProperty("milestone", out _));

        var placedInSprint = await Call("update_user_story", new()
        {
            ["userStoryId"] = 102,
            ["version"] = 4,
            ["milestoneId"] = 55
        });
        Assert.False(placedInSprint.IsError == true);
        var placedJson = JsonSerializer.Deserialize<JsonElement>(GetText(placedInSprint));
        Assert.Equal(5, placedJson.GetProperty("version").GetInt32());
        Assert.Equal(55, placedJson.GetProperty("milestone").GetInt32());
        var placedBody = JsonSerializer.Deserialize<JsonElement>(GetLastStoryPatch(taiga).Body);
        AssertPatchProperties(placedBody, "milestone", "version");

        var changedFields = await Call("update_user_story", new()
        {
            ["userStoryId"] = 102,
            ["version"] = 5,
            ["status"] = 2,
            ["assigned_to"] = 42,
            ["milestoneId"] = null
        });
        Assert.False(changedFields.IsError == true);
        var changedJson = JsonSerializer.Deserialize<JsonElement>(GetText(changedFields));
        Assert.Equal(6, changedJson.GetProperty("version").GetInt32());
        Assert.Equal(2, changedJson.GetProperty("status_id").GetInt32());
        Assert.Equal(42, changedJson.GetProperty("assigned_to").GetInt32());
        Assert.Equal(55, changedJson.GetProperty("milestone").GetInt32());
        var changedBody = JsonSerializer.Deserialize<JsonElement>(GetLastStoryPatch(taiga).Body);
        AssertPatchProperties(changedBody, "assigned_to", "status", "version");
        Assert.False(changedBody.TryGetProperty("milestone", out _));

        var clearedSprint = await Call("update_user_story", new()
        {
            ["userStoryId"] = 102,
            ["version"] = 6,
            ["clearFields"] = new[] { "milestone" },
            ["comment"] = "Move back to backlog."
        });
        Assert.False(clearedSprint.IsError == true);
        var clearedJson = JsonSerializer.Deserialize<JsonElement>(GetText(clearedSprint));
        Assert.Equal(7, clearedJson.GetProperty("version").GetInt32());
        Assert.False(clearedJson.TryGetProperty("milestone", out _));
        var clearedBody = JsonSerializer.Deserialize<JsonElement>(GetLastStoryPatch(taiga).Body);
        AssertPatchProperties(clearedBody, "comment", "milestone", "version");
        Assert.Equal(JsonValueKind.Null, clearedBody.GetProperty("milestone").ValueKind);

        var readBack = await Call("get_user_story", new() { ["userStoryId"] = 102 });
        Assert.False(readBack.IsError == true);
        var readBackJson = JsonSerializer.Deserialize<JsonElement>(GetText(readBack));
        Assert.Equal(7, readBackJson.GetProperty("version").GetInt32());
        Assert.Equal(2, readBackJson.GetProperty("status_id").GetInt32());
        Assert.Equal(42, readBackJson.GetProperty("assigned_to").GetInt32());
        Assert.Equal("Created backlog story", readBackJson.GetProperty("subject").GetString());
        Assert.Equal("Acceptance: the story can be reopened.", readBackJson.GetProperty("description").GetString());
        Assert.False(readBackJson.TryGetProperty("milestone", out _));

        var emptyFields = await Call("update_user_story", new()
        {
            ["userStoryId"] = 102,
            ["version"] = 7,
            ["description"] = string.Empty,
            ["tags"] = Array.Empty<string>()
        });
        Assert.False(emptyFields.IsError == true);
        var emptyJson = JsonSerializer.Deserialize<JsonElement>(GetText(emptyFields));
        Assert.Equal(string.Empty, emptyJson.GetProperty("description").GetString());
        Assert.Empty(emptyJson.GetProperty("tags").EnumerateArray());
        var emptyBody = JsonSerializer.Deserialize<JsonElement>(GetLastStoryPatch(taiga).Body);
        AssertPatchProperties(emptyBody, "description", "tags", "version");

        var patchCount = taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/userstories/102");
        var missingVersion = await Call("update_user_story", new()
        {
            ["userStoryId"] = 102,
            ["status"] = 1
        });
        Assert.True(missingVersion.IsError);
        Assert.Equal(patchCount, taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/userstories/102"));

        taiga.UserStoryUpdateStatusCode = System.Net.HttpStatusCode.Forbidden;
        var failed = await Call("update_user_story", new()
        {
            ["userStoryId"] = 102,
            ["version"] = 8,
            ["status"] = 1
        });
        Assert.True(failed.IsError);
        Assert.Contains("403", GetText(failed));
        Assert.Contains("permission denied", GetText(failed), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("synthetic update secret", GetText(failed));
        Assert.Equal(patchCount + 1, taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/userstories/102"));

        await process.DisposeAsync();
        await process.ValidationCompleted.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.Null(process.ValidationFailure);
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
                "create_task",
                "create_user_story",
                "get_issue",
                "get_task",
                "get_user_story",
                "list_issue_priorities",
                "list_issue_severities",
                "list_issue_statuses",
                "list_issue_types",
                "list_issues",
                "list_projects",
                "list_tasks",
                "list_user_stories",
                "resolve_project",
                "update_issue",
                "update_task",
                "update_user_story"
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

            var listTasks = Assert.Single(tools, tool => tool.Name == "list_tasks");
            var taskProperties = listTasks.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(
                new[] { "projectId", "page", "userStoryId", "milestoneId", "statusIds", "assignedTo", "tags", "query", "includeClosed" },
                taskProperties);
            var taskRequired = listTasks.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "projectId" }, taskRequired);

            var getUserStory = Assert.Single(tools, tool => tool.Name == "get_user_story");
            var getUserStoryProperties = getUserStory.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "userStoryId" }, getUserStoryProperties);
            var getUserStoryRequired = getUserStory.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "userStoryId" }, getUserStoryRequired);

            var getTask = Assert.Single(tools, tool => tool.Name == "get_task");
            var getTaskProperties = getTask.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "taskId" }, getTaskProperties);
            var getTaskRequired = getTask.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "taskId" }, getTaskRequired);

            var updateTask = Assert.Single(tools, tool => tool.Name == "update_task");
            var updateTaskProperties = updateTask.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(
                new[] { "taskId", "version", "subject", "description", "status", "assigned_to", "tags", "isBlocked", "blockedNote", "comment", "clearFields" },
                updateTaskProperties);
            var updateTaskRequired = updateTask.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "taskId", "version" }, updateTaskRequired);

            var createTask = Assert.Single(tools, tool => tool.Name == "create_task");
            var createTaskProperties = createTask.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(
                new[] { "projectId", "subject", "userStoryId", "milestoneId", "description", "status", "assigned_to", "tags" },
                createTaskProperties);
            var createTaskRequired = createTask.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "projectId", "subject" }, createTaskRequired);

            var createUserStory = Assert.Single(tools, tool => tool.Name == "create_user_story");
            var createUserStoryProperties = createUserStory.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(
                new[] { "projectId", "subject", "description", "status", "assigned_to", "tags", "milestoneId" },
                createUserStoryProperties);
            var createUserStoryRequired = createUserStory.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "projectId", "subject" }, createUserStoryRequired);

            var updateUserStory = Assert.Single(tools, tool => tool.Name == "update_user_story");
            var updateUserStoryProperties = updateUserStory.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(
                new[] { "userStoryId", "version", "subject", "description", "status", "assigned_to", "tags", "milestoneId", "comment", "clearFields" },
                updateUserStoryProperties);
            var updateUserStoryRequired = updateUserStory.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "userStoryId", "version" }, updateUserStoryRequired);

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

            var taskPage = await client.CallToolAsync(
                "list_tasks",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["page"] = 2,
                    ["userStoryId"] = 102,
                    ["milestoneId"] = 55,
                    ["statusIds"] = new[] { 11 },
                    ["assignedTo"] = 42,
                    ["tags"] = new[] { "a&b" },
                    ["query"] = "fix & revisión",
                    ["includeClosed"] = true
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(taskPage.IsError == true);
            var taskEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(taskPage));
            Assert.Equal(JsonValueKind.Object, taskEnvelope.ValueKind);
            Assert.Equal(2, taskEnvelope.GetProperty("page").GetInt32());
            var task = Assert.Single(taskEnvelope.GetProperty("items").EnumerateArray());
            Assert.Equal(203, task.GetProperty("id").GetInt32());
            Assert.Equal(102, task.GetProperty("user_story").GetInt32());
            Assert.Equal(55, task.GetProperty("milestone").GetInt32());
            Assert.True(taskEnvelope.GetProperty("total").GetInt32() == 1);
            var taskRequest = Assert.Single(taiga.Requests, request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/tasks", StringComparison.Ordinal));
            Assert.Equal(
                "/api/v1/tasks?project=123&page=2&status=11&user_story=102&milestone=55&assigned_to=42&tags=a%26b&q=fix%20%26%20revisi%C3%B3n",
                taskRequest.PathAndQuery);
            Assert.Equal("Bearer integration-token", taskRequest.Authorization);

            var taskDetail = await client.CallToolAsync(
                "get_task",
                new Dictionary<string, object?> { ["taskId"] = 203 },
                cancellationToken: protocolDeadline.Token);
            Assert.False(taskDetail.IsError == true);
            var taskDetailJson = JsonSerializer.Deserialize<JsonElement>(GetText(taskDetail));
            Assert.Equal(JsonValueKind.Object, taskDetailJson.ValueKind);
            Assert.Equal(203, taskDetailJson.GetProperty("id").GetInt32());
            Assert.Equal(17, taskDetailJson.GetProperty("ref").GetInt32());
            Assert.Equal(2, taskDetailJson.GetProperty("version").GetInt32());
            Assert.Equal("**Acceptance:** preserve Markdown and Unicode — ✓", taskDetailJson.GetProperty("description").GetString());
            var taskDetailRequest = Assert.Single(taiga.Requests, request => request.PathAndQuery == "/api/v1/tasks/203");
            Assert.Equal("Bearer integration-token", taskDetailRequest.Authorization);

            var updatedTask = await client.CallToolAsync(
                "update_task",
                new Dictionary<string, object?>
                {
                    ["taskId"] = 203,
                    ["version"] = 2,
                    ["description"] = string.Empty,
                    ["tags"] = Array.Empty<string>(),
                    ["isBlocked"] = false,
                    ["blockedNote"] = string.Empty,
                    ["clearFields"] = null
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(updatedTask.IsError == true, GetText(updatedTask));
            var updatedTaskJson = JsonSerializer.Deserialize<JsonElement>(GetText(updatedTask));
            Assert.Equal(3, updatedTaskJson.GetProperty("version").GetInt32());
            Assert.Equal(string.Empty, updatedTaskJson.GetProperty("description").GetString());
            Assert.Empty(updatedTaskJson.GetProperty("tags").EnumerateArray());
            Assert.False(updatedTaskJson.GetProperty("is_blocked").GetBoolean());
            using var updatedTaskBody = JsonDocument.Parse(
                taiga.Requests.Last(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/tasks/203").Body);
            AssertPatchProperties(updatedTaskBody.RootElement, "blocked_note", "description", "is_blocked", "tags", "version");
            Assert.Equal(string.Empty, updatedTaskBody.RootElement.GetProperty("blocked_note").GetString());
            Assert.False(updatedTaskBody.RootElement.TryGetProperty("assigned_to", out _));

            var createdTask = await client.CallToolAsync(
                "create_task",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["subject"] = "Integration child task",
                    ["userStoryId"] = 103,
                    ["description"] = "Acceptance: complete the saved-search endpoint.",
                    ["status"] = 11,
                    ["assigned_to"] = 42,
                    ["tags"] = new[] { "search" }
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(createdTask.IsError == true, GetText(createdTask));
            var createdTaskJson = JsonSerializer.Deserialize<JsonElement>(GetText(createdTask));
            Assert.Equal(204, createdTaskJson.GetProperty("id").GetInt32());
            Assert.Equal(103, createdTaskJson.GetProperty("user_story").GetInt32());
            Assert.Equal(55, createdTaskJson.GetProperty("milestone").GetInt32());
            var parentRequest = Assert.Single(taiga.Requests, request => request.Method == "GET" && request.PathAndQuery == "/api/v1/userstories/103");
            Assert.Equal("Bearer integration-token", parentRequest.Authorization);
            var createTaskRequest = Assert.Single(taiga.Requests, request => request.Method == "POST" && request.PathAndQuery == "/api/v1/tasks");
            using var createTaskBody = JsonDocument.Parse(createTaskRequest.Body);
            Assert.Equal(103, createTaskBody.RootElement.GetProperty("user_story").GetInt32());
            Assert.False(createTaskBody.RootElement.TryGetProperty("milestone", out _));

            var createdTaskReadBack = await client.CallToolAsync(
                "get_task",
                new Dictionary<string, object?> { ["taskId"] = 204 },
                cancellationToken: protocolDeadline.Token);
            Assert.False(createdTaskReadBack.IsError == true);
            var createdTaskReadBackJson = JsonSerializer.Deserialize<JsonElement>(GetText(createdTaskReadBack));
            Assert.Equal(204, createdTaskReadBackJson.GetProperty("id").GetInt32());
            Assert.Equal(103, createdTaskReadBackJson.GetProperty("user_story").GetInt32());
            Assert.Equal(55, createdTaskReadBackJson.GetProperty("milestone").GetInt32());
            Assert.Equal(1, createdTaskReadBackJson.GetProperty("version").GetInt32());
            Assert.Single(taiga.Requests, request => request.Method == "GET" && request.PathAndQuery == "/api/v1/tasks/204");

            var standaloneTask = await client.CallToolAsync(
                "create_task",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["subject"] = "Standalone task"
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(standaloneTask.IsError == true);
            var standaloneTaskJson = JsonSerializer.Deserialize<JsonElement>(GetText(standaloneTask));
            Assert.Equal(205, standaloneTaskJson.GetProperty("id").GetInt32());
            Assert.False(standaloneTaskJson.TryGetProperty("user_story", out _));
            Assert.False(standaloneTaskJson.TryGetProperty("milestone", out _));
            using var standaloneTaskBody = JsonDocument.Parse(
                taiga.Requests.Last(request => request.Method == "POST" && request.PathAndQuery == "/api/v1/tasks").Body);
            Assert.Equal(
                new[] { "project", "subject" },
                standaloneTaskBody.RootElement.EnumerateObject().Select(property => property.Name).ToArray());

            var explicitTask = await client.CallToolAsync(
                "create_task",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["subject"] = "Explicit task values",
                    ["userStoryId"] = null,
                    ["milestoneId"] = null,
                    ["description"] = "",
                    ["tags"] = Array.Empty<string>()
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(explicitTask.IsError == true);
            using var explicitTaskBody = JsonDocument.Parse(
                taiga.Requests.Last(request => request.Method == "POST" && request.PathAndQuery == "/api/v1/tasks").Body);
            Assert.Equal("", explicitTaskBody.RootElement.GetProperty("description").GetString());
            Assert.Empty(explicitTaskBody.RootElement.GetProperty("tags").EnumerateArray());
            Assert.False(explicitTaskBody.RootElement.TryGetProperty("user_story", out _));
            Assert.False(explicitTaskBody.RootElement.TryGetProperty("milestone", out _));

            var sprintTask = await client.CallToolAsync(
                "create_task",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["subject"] = "Standalone sprint task",
                    ["milestoneId"] = 55
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(sprintTask.IsError == true);
            var sprintTaskJson = JsonSerializer.Deserialize<JsonElement>(GetText(sprintTask));
            Assert.Equal(55, sprintTaskJson.GetProperty("milestone").GetInt32());
            using var sprintTaskBody = JsonDocument.Parse(
                taiga.Requests.Last(request => request.Method == "POST" && request.PathAndQuery == "/api/v1/tasks").Body);
            Assert.Equal(55, sprintTaskBody.RootElement.GetProperty("milestone").GetInt32());

            var taskPostCount = taiga.Requests.Count(request => request.Method == "POST" && request.PathAndQuery == "/api/v1/tasks");
            var invalidTask = await client.CallToolAsync(
                "create_task",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["subject"] = " "
                },
                cancellationToken: protocolDeadline.Token);
            Assert.True(invalidTask.IsError);
            Assert.Contains("subject must not be blank", GetText(invalidTask));
            Assert.Equal(taskPostCount, taiga.Requests.Count(request => request.Method == "POST" && request.PathAndQuery == "/api/v1/tasks"));

            taiga.TaskCreateStatusCode = System.Net.HttpStatusCode.BadRequest;
            var failedTask = await client.CallToolAsync(
                "create_task",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["subject"] = "Server rejected task"
                },
                cancellationToken: protocolDeadline.Token);
            Assert.True(failedTask.IsError);
            Assert.Contains("400", GetText(failedTask));
            Assert.Contains("status: rejected", GetText(failedTask));
            Assert.DoesNotContain("synthetic task secret", GetText(failedTask));

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
    public async Task ProductionServer_UpdateTask_CoversProgressAssignmentBlockingCommentsAndFailures()
    {
        await using var taiga = FakeTaigaHttpServer.Start();
        var serverAssembly = Path.Combine(AppContext.BaseDirectory, "TaigaMCP.dll");
        await using var process = StrictMcpProcess.Start("dotnet", [serverAssembly], CreateEnvironment(taiga), Path.GetDirectoryName(serverAssembly));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        await using (var client = await McpClientFactory.CreateAsync(process.Transport, cancellationToken: timeout.Token))
        {
            async Task<CallToolResult> Call(string name, Dictionary<string, object?> arguments)
                => await client.CallToolAsync(name, arguments, cancellationToken: timeout.Token);

            var initial = await Call("get_task", new() { ["taskId"] = 203 });
            Assert.False(initial.IsError == true);
            Assert.Equal(2, JsonSerializer.Deserialize<JsonElement>(GetText(initial)).GetProperty("version").GetInt32());

            var status = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 2,
                ["status"] = 11
            });
            Assert.False(status.IsError == true, GetText(status));
            Assert.Equal(3, JsonSerializer.Deserialize<JsonElement>(GetText(status)).GetProperty("version").GetInt32());
            AssertTaskPatch(taiga, ["status", "version"]);

            var assigned = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 3,
                ["assigned_to"] = 42
            });
            Assert.False(assigned.IsError == true, GetText(assigned));
            Assert.Equal(4, JsonSerializer.Deserialize<JsonElement>(GetText(assigned)).GetProperty("version").GetInt32());
            AssertTaskPatch(taiga, ["assigned_to", "version"]);

            var unassigned = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 4,
                ["clearFields"] = new[] { "assigned_to" }
            });
            Assert.False(unassigned.IsError == true, GetText(unassigned));
            var unassignedJson = JsonSerializer.Deserialize<JsonElement>(GetText(unassigned));
            Assert.Equal(5, unassignedJson.GetProperty("version").GetInt32());
            Assert.False(unassignedJson.TryGetProperty("assigned_to", out _));
            using (var unassignedBody = GetLastTaskPatchDocument(taiga))
            {
                AssertPatchProperties(unassignedBody.RootElement, "assigned_to", "version");
                Assert.Equal(JsonValueKind.Null, unassignedBody.RootElement.GetProperty("assigned_to").ValueKind);
            }

            var blocked = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 5,
                ["isBlocked"] = true,
                ["blockedNote"] = "Waiting for the dependency."
            });
            Assert.False(blocked.IsError == true, GetText(blocked));
            Assert.True(JsonSerializer.Deserialize<JsonElement>(GetText(blocked)).GetProperty("is_blocked").GetBoolean());
            AssertTaskPatch(taiga, ["blocked_note", "is_blocked", "version"]);

            var unblockedWithoutNote = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 6,
                ["isBlocked"] = false
            });
            Assert.False(unblockedWithoutNote.IsError == true, GetText(unblockedWithoutNote));
            var retainedNote = JsonSerializer.Deserialize<JsonElement>(GetText(unblockedWithoutNote));
            Assert.False(retainedNote.GetProperty("is_blocked").GetBoolean());
            Assert.Equal("Waiting for the dependency.", retainedNote.GetProperty("blocked_note").GetString());
            AssertTaskPatch(taiga, ["is_blocked", "version"]);

            var unblocked = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 7,
                ["isBlocked"] = false,
                ["blockedNote"] = string.Empty
            });
            Assert.False(unblocked.IsError == true, GetText(unblocked));
            var clearedBlock = JsonSerializer.Deserialize<JsonElement>(GetText(unblocked));
            Assert.False(clearedBlock.GetProperty("is_blocked").GetBoolean());
            Assert.Equal(string.Empty, clearedBlock.GetProperty("blocked_note").GetString());
            AssertTaskPatch(taiga, ["blocked_note", "is_blocked", "version"]);

            var comment = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 8,
                ["comment"] = "Dependency resolved."
            });
            Assert.False(comment.IsError == true, GetText(comment));
            Assert.Equal(9, JsonSerializer.Deserialize<JsonElement>(GetText(comment)).GetProperty("version").GetInt32());
            AssertTaskPatch(taiga, ["comment", "version"]);

            var emptyValues = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 9,
                ["description"] = string.Empty,
                ["tags"] = Array.Empty<string>()
            });
            Assert.False(emptyValues.IsError == true, GetText(emptyValues));
            var emptyJson = JsonSerializer.Deserialize<JsonElement>(GetText(emptyValues));
            Assert.Equal(10, emptyJson.GetProperty("version").GetInt32());
            Assert.Equal(string.Empty, emptyJson.GetProperty("description").GetString());
            Assert.Empty(emptyJson.GetProperty("tags").EnumerateArray());
            AssertTaskPatch(taiga, ["description", "tags", "version"]);

            var readBack = await Call("get_task", new() { ["taskId"] = 203 });
            Assert.False(readBack.IsError == true, GetText(readBack));
            var readBackJson = JsonSerializer.Deserialize<JsonElement>(GetText(readBack));
            Assert.Equal(10, readBackJson.GetProperty("version").GetInt32());
            Assert.Equal(102, readBackJson.GetProperty("user_story").GetInt32());
            Assert.Equal(55, readBackJson.GetProperty("milestone").GetInt32());
            Assert.False(readBackJson.TryGetProperty("assigned_to", out _));

            var patchCount = taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/tasks/203");
            var missingVersion = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["status"] = 11
            });
            Assert.True(missingVersion.IsError);
            Assert.Equal(patchCount, taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/tasks/203"));

            var invalidClear = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 10,
                ["clearFields"] = new[] { "blocked_note" }
            });
            Assert.True(invalidClear.IsError);
            Assert.Contains("unsupported field", GetText(invalidClear));
            Assert.Equal(patchCount, taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/tasks/203"));

            var stale = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 9,
                ["status"] = 11
            });
            Assert.True(stale.IsError);
            Assert.Contains("409", GetText(stale));
            Assert.Contains("conflict", GetText(stale), StringComparison.OrdinalIgnoreCase);
            Assert.Equal(patchCount + 1, taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/tasks/203"));

            taiga.TaskUpdateStatusCode = System.Net.HttpStatusCode.Forbidden;
            var forbidden = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 10,
                ["status"] = 11
            });
            Assert.True(forbidden.IsError);
            Assert.Contains("403", GetText(forbidden));
            Assert.Contains("permission denied", GetText(forbidden), StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic task update secret", GetText(forbidden));

            taiga.TaskUpdateStatusCode = System.Net.HttpStatusCode.NotFound;
            var missingTask = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 10,
                ["status"] = 11
            });
            Assert.True(missingTask.IsError);
            Assert.Contains("404", GetText(missingTask));
            Assert.Contains("resource not found", GetText(missingTask), StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic task update secret", GetText(missingTask));
        }

        await process.DisposeAsync();
        await process.ValidationCompleted.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.Null(process.ValidationFailure);
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

    private static RecordedTaigaRequest GetLastStoryPatch(FakeTaigaHttpServer taiga)
        => taiga.Requests.Last(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/userstories/102");

    private static void AssertTaskPatch(FakeTaigaHttpServer taiga, string[] expectedNames)
    {
        using var body = GetLastTaskPatchDocument(taiga);
        AssertPatchProperties(body.RootElement, expectedNames);
    }

    private static JsonDocument GetLastTaskPatchDocument(FakeTaigaHttpServer taiga)
        => JsonDocument.Parse(taiga.Requests.Last(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/tasks/203").Body);
}
