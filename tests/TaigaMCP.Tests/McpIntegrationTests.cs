using System.Net;
using System.Text.Json;
using ModelContextProtocol;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class McpIntegrationTests
{
    [Fact]
    public async Task ProductionServer_CurrentUserBoundary_IsSafeForOptionalFieldsAndErrors()
    {
        await using var taiga = FakeTaigaHttpServer.Start();
        var assembly = Path.Combine(AppContext.BaseDirectory, "TaigaMCP.dll");
        await using var process = StrictMcpProcess.Start("dotnet", [assembly], CreateEnvironment(taiga), Path.GetDirectoryName(assembly));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        await using var client = await McpClientFactory.CreateAsync(process.Transport, cancellationToken: timeout.Token);

        async Task<CallToolResult> CallCurrentUser()
            => await client.CallToolAsync("get_current_user", new Dictionary<string, object?>(), cancellationToken: timeout.Token);

        taiga.CurrentUserResponseBody = "{\"id\":42}";
        var minimal = await CallCurrentUser();
        Assert.False(minimal.IsError == true);
        var minimalJson = JsonSerializer.Deserialize<JsonElement>(GetText(minimal));
        Assert.Equal(42, minimalJson.GetProperty("id").GetInt32());
        Assert.False(minimalJson.TryGetProperty("username", out _));
        Assert.False(minimalJson.TryGetProperty("full_name", out _));
        Assert.False(minimalJson.TryGetProperty("is_active", out _));

        taiga.CurrentUserResponseBody = "{\"id\":42,\"username\":\"false-user\",\"full_name\":\"False User\",\"is_active\":false,\"email\":\"mcp-private-sentinel\",\"auth_token\":\"mcp-token-sentinel\",\"roles\":[\"mcp-role-sentinel\"]}";
        var inactive = await CallCurrentUser();
        Assert.False(inactive.IsError == true);
        var inactiveJson = JsonSerializer.Deserialize<JsonElement>(GetText(inactive));
        Assert.False(inactiveJson.GetProperty("is_active").GetBoolean());
        Assert.DoesNotContain("mcp-private-sentinel", GetText(inactive));
        Assert.DoesNotContain("mcp-token-sentinel", GetText(inactive));
        Assert.DoesNotContain("mcp-role-sentinel", GetText(inactive));

        taiga.CurrentUserStatusCode = HttpStatusCode.Forbidden;
        taiga.CurrentUserResponseBody = "{\"detail\":\"mcp-forbidden-sentinel\"}";
        var forbidden = await CallCurrentUser();
        Assert.True(forbidden.IsError);
        Assert.Contains("403", GetText(forbidden));
        Assert.DoesNotContain("mcp-forbidden-sentinel", GetText(forbidden));

        taiga.CurrentUserStatusCode = HttpStatusCode.OK;
        taiga.CurrentUserResponseBody = "{\"id\":0,\"email\":\"mcp-malformed-sentinel\"}";
        var malformedIdentity = await CallCurrentUser();
        Assert.True(malformedIdentity.IsError);
        Assert.Contains("current-user identity", GetText(malformedIdentity));
        Assert.DoesNotContain("mcp-malformed-sentinel", GetText(malformedIdentity));

        taiga.CurrentUserResponseBody = "{\"id\":42,";
        var invalidJson = await CallCurrentUser();
        Assert.True(invalidJson.IsError);
        Assert.Contains("invalid JSON", GetText(invalidJson));
        Assert.DoesNotContain("mcp-invalid-json-sentinel", GetText(invalidJson));
        Assert.DoesNotContain(process.StderrLines, line =>
            line.Contains("mcp-private-sentinel", StringComparison.Ordinal) ||
            line.Contains("mcp-token-sentinel", StringComparison.Ordinal) ||
            line.Contains("mcp-role-sentinel", StringComparison.Ordinal) ||
            line.Contains("mcp-forbidden-sentinel", StringComparison.Ordinal) ||
            line.Contains("mcp-malformed-sentinel", StringComparison.Ordinal));
    }

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
        var currentUserTool = Assert.Single(tools, tool => tool.Name == "get_current_user");
        Assert.Empty(currentUserTool.JsonSchema.GetProperty("properties").EnumerateObject());
        Assert.DoesNotContain("cancellationToken", currentUserTool.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name));
        var currentUser = await Call("get_current_user", new());
        Assert.False(currentUser.IsError == true);
        var currentUserJson = JsonSerializer.Deserialize<JsonElement>(GetText(currentUser));
        Assert.Equal(42, currentUserJson.GetProperty("id").GetInt32());
        Assert.Equal("integration-user", currentUserJson.GetProperty("username").GetString());
        Assert.Equal("Integration User", currentUserJson.GetProperty("full_name").GetString());
        Assert.True(currentUserJson.GetProperty("is_active").GetBoolean());
        var currentUserId = currentUserJson.GetProperty("id").GetInt32();
        Assert.False(currentUserJson.TryGetProperty("email", out _));
        Assert.False(currentUserJson.TryGetProperty("auth_token", out _));
        Assert.False(currentUserJson.TryGetProperty("roles", out _));
        Assert.Contains(taiga.Requests, request => request.Method == "GET" && request.PathAndQuery == "/api/v1/users/me");
        foreach (var member in new string?[] { null, "" })
        {
            Assert.False((await Call("list_projects", new() { ["member"] = member })).IsError == true);
            Assert.DoesNotContain("member=", taiga.Requests.Last().PathAndQuery);
        }
        Assert.False((await Call("resolve_project", new() { ["slug"] = "demo" })).IsError == true);
        foreach (var name in new[] { "list_issues", "list_user_stories", "list_user_story_statuses", "list_tasks", "list_epics", "list_issue_statuses", "list_issue_priorities", "list_issue_severities", "list_issue_types" })
            Assert.False((await Call(name, new() { ["projectId"] = 123 })).IsError == true);
        Assert.False((await Call("get_epic", new() { ["epicId"] = 301 })).IsError == true);
        Assert.True((await Call("get_epic", new() { ["epicId"] = 0 })).IsError == true);
        var epicStatuses = await Call("list_epic_statuses", new() { ["projectId"] = 123 });
        Assert.False(epicStatuses.IsError == true, GetText(epicStatuses));
        var epicStatusEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(epicStatuses));
        var selectedEpicStatusId = Assert.Single(
            epicStatusEnvelope.GetProperty("items").EnumerateArray(),
            status => status.GetProperty("id").GetInt32() == 7)
            .GetProperty("id")
            .GetInt32();
        Assert.Equal("/api/v1/epic-statuses?project=123&page=1", taiga.Requests.Last(request =>
            request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/epic-statuses?", StringComparison.Ordinal)).PathAndQuery);
        var createdEpic = await Call("create_epic", new()
        {
            ["projectId"] = 123,
            ["subject"] = "Integration epic"
        });
        Assert.False(createdEpic.IsError == true);
        var createdEpicJson = JsonSerializer.Deserialize<JsonElement>(GetText(createdEpic));
        Assert.Equal(301, createdEpicJson.GetProperty("id").GetInt32());
        Assert.Equal(12, createdEpicJson.GetProperty("ref").GetInt32());
        Assert.Equal(4, createdEpicJson.GetProperty("version").GetInt32());
        var createdEpicRequest = Assert.Single(taiga.Requests, request =>
            request.Method == "POST" && request.PathAndQuery == "/api/v1/epics");
        var createdEpicBody = JsonSerializer.Deserialize<JsonElement>(createdEpicRequest.Body);
        Assert.Equal(new[] { "project", "subject" }, createdEpicBody.EnumerateObject().Select(property => property.Name).ToArray());
        Assert.Equal(123, createdEpicBody.GetProperty("project").GetInt32());
        Assert.Equal("Integration epic", createdEpicBody.GetProperty("subject").GetString());
        var populatedEpic = await Call("create_epic", new()
        {
            ["projectId"] = 123,
            ["subject"] = "Integration epic",
            ["description"] = "  Group saved-search delivery work.  ",
            ["status"] = selectedEpicStatusId,
            ["assigned_to"] = 42,
            ["color"] = "#336699",
            ["tags"] = new[] { "search", "saved" }
        });
        Assert.False(populatedEpic.IsError == true);
        var populatedEpicBody = JsonSerializer.Deserialize<JsonElement>(
            taiga.Requests.Last(request => request.Method == "POST" && request.PathAndQuery == "/api/v1/epics").Body);
        Assert.Equal(
            new[] { "assigned_to", "color", "description", "project", "status", "subject", "tags" },
            populatedEpicBody.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
        Assert.Equal("  Group saved-search delivery work.  ", populatedEpicBody.GetProperty("description").GetString());
        Assert.Equal(selectedEpicStatusId, populatedEpicBody.GetProperty("status").GetInt32());
        Assert.Equal(42, populatedEpicBody.GetProperty("assigned_to").GetInt32());
        Assert.Equal("#336699", populatedEpicBody.GetProperty("color").GetString());
        Assert.Equal(new[] { "search", "saved" }, populatedEpicBody.GetProperty("tags").EnumerateArray().Select(tag => tag.GetString()));
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
            ["assigned_to"] = currentUserId,
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

        foreach (var (kind, id, version, path) in new[]
        {
            ("issue", 42, 1, "/api/v1/issues/42"),
            ("user_story", 102, 5, "/api/v1/userstories/102"),
            ("task", 203, 2, "/api/v1/tasks/203"),
            ("epic", 301, 4, "/api/v1/epics/301")
        })
        {
            var comment = await Call("add_work_item_comment", new()
            {
                ["kind"] = kind,
                ["id"] = id,
                ["version"] = version,
                ["text"] = "**Progress**\n@alice — revisión ✓"
            });
            Assert.False(comment.IsError == true, GetText(comment));
            var receipt = JsonSerializer.Deserialize<JsonElement>(GetText(comment));
            Assert.Equal(kind, receipt.GetProperty("kind").GetString());
            Assert.Equal(id, receipt.GetProperty("id").GetInt32());
            Assert.Equal(version + 1, receipt.GetProperty("version").GetInt32());
            Assert.True(receipt.GetProperty("comment_submitted").GetBoolean());
            var request = taiga.Requests.Last(item => item.Method == "PATCH" && item.PathAndQuery == path);
            using var commentBody = JsonDocument.Parse(request.Body);
            AssertPatchProperties(commentBody.RootElement, "comment", "version");
            Assert.Equal("**Progress**\n@alice — revisión ✓", commentBody.RootElement.GetProperty("comment").GetString());
            Assert.Equal(version, commentBody.RootElement.GetProperty("version").GetInt32());
        }

        var count = taiga.Requests.Count;
        var invalidKind = await Call("add_work_item_comment", new()
        {
            ["kind"] = "feature",
            ["id"] = 203,
            ["version"] = 2,
            ["text"] = "not submitted"
        });
        Assert.True(invalidKind.IsError);
        var blankComment = await Call("add_work_item_comment", new()
        {
            ["kind"] = "task",
            ["id"] = 203,
            ["version"] = 2,
            ["text"] = " "
        });
        Assert.True(blankComment.IsError);
        var negativeVersion = await Call("add_work_item_comment", new()
        {
            ["kind"] = "task",
            ["id"] = 203,
            ["version"] = -1,
            ["text"] = "not submitted"
        });
        Assert.True(negativeVersion.IsError);
        Assert.Equal(count, taiga.Requests.Count);
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

        var sprintPage = await Call("list_sprints", new()
        {
            ["projectId"] = 123,
            ["closed"] = false
        });
        Assert.False(sprintPage.IsError == true, GetText(sprintPage));
        var sprintEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(sprintPage));
        var milestoneId = sprintEnvelope.GetProperty("items")[0].GetProperty("id").GetInt32();
        Assert.Equal(55, milestoneId);
        Assert.Equal("/api/v1/milestones?project=123&page=1&closed=false", taiga.Requests.Last(request => request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/milestones?", StringComparison.Ordinal)).PathAndQuery);

        var statusPage = await Call("list_user_story_statuses", new()
        {
            ["projectId"] = 123,
            ["page"] = 1
        });
        Assert.False(statusPage.IsError == true, GetText(statusPage));
        var statusEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(statusPage));
        var statusItems = statusEnvelope.GetProperty("items").EnumerateArray().ToArray();
        Assert.All(statusItems, status => Assert.True(status.TryGetProperty("is_archived", out _), GetText(statusPage)));
        var closedStatus = Assert.Single(statusItems, status =>
            status.TryGetProperty("is_closed", out var isClosed) && isClosed.GetBoolean());
        Assert.Equal("Terminado", closedStatus.GetProperty("name").GetString());
        Assert.False(closedStatus.GetProperty("is_archived").GetBoolean());
        Assert.Equal(1, closedStatus.GetProperty("order").GetInt32());
        Assert.False(closedStatus.TryGetProperty("wip_limit", out _));
        Assert.True(closedStatus.TryGetProperty("id", out _), GetText(statusPage));
        var closedStatusId = closedStatus.GetProperty("id").GetInt32();
        var readyStatus = Assert.Single(statusItems, status =>
            status.GetProperty("id").GetInt32() == 1);
        Assert.Equal(0, readyStatus.GetProperty("wip_limit").GetInt32());
        var archivedStatus = Assert.Single(statusItems, status =>
            status.GetProperty("id").GetInt32() == 3);
        Assert.False(archivedStatus.GetProperty("is_closed").GetBoolean());
        Assert.True(archivedStatus.GetProperty("is_archived").GetBoolean());
        Assert.False(archivedStatus.TryGetProperty("color", out _));
        Assert.False(archivedStatus.TryGetProperty("wip_limit", out _));

        var before = await Call("get_user_story", new() { ["userStoryId"] = 102 });
        Assert.False(before.IsError == true);
        var beforeJson = JsonSerializer.Deserialize<JsonElement>(GetText(before));
        var fetchedStoryVersion = beforeJson.GetProperty("version").GetInt32();
        Assert.Equal(4, fetchedStoryVersion);
        Assert.False(beforeJson.TryGetProperty("milestone", out _));

        var placedInSprint = await Call("update_user_story", new()
        {
            ["userStoryId"] = 102,
            ["version"] = fetchedStoryVersion,
            ["milestoneId"] = milestoneId
        });
        Assert.False(placedInSprint.IsError == true);
        var placedJson = JsonSerializer.Deserialize<JsonElement>(GetText(placedInSprint));
        Assert.Equal(5, placedJson.GetProperty("version").GetInt32());
        Assert.Equal(55, placedJson.GetProperty("milestone").GetInt32());
        var placedBody = JsonSerializer.Deserialize<JsonElement>(GetLastStoryPatch(taiga).Body);
        AssertPatchProperties(placedBody, "milestone", "version");
        Assert.Equal(fetchedStoryVersion, placedBody.GetProperty("version").GetInt32());
        Assert.Equal(milestoneId, placedBody.GetProperty("milestone").GetInt32());

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

        var current = await Call("get_user_story", new() { ["userStoryId"] = 102 });
        Assert.False(current.IsError == true);
        var currentJson = JsonSerializer.Deserialize<JsonElement>(GetText(current));
        var transition = await Call("update_user_story", new()
        {
            ["userStoryId"] = 102,
            ["version"] = currentJson.GetProperty("version").GetInt32(),
            ["status"] = closedStatusId
        });
        Assert.False(transition.IsError == true, GetText(transition));
        var transitionJson = JsonSerializer.Deserialize<JsonElement>(GetText(transition));
        Assert.Equal(closedStatusId, transitionJson.GetProperty("status_id").GetInt32());
        Assert.Equal(currentJson.GetProperty("version").GetInt32() + 1, transitionJson.GetProperty("version").GetInt32());
        var transitionBody = JsonSerializer.Deserialize<JsonElement>(GetLastStoryPatch(taiga).Body);
        AssertPatchProperties(transitionBody, "status", "version");
        Assert.Equal(closedStatusId, transitionBody.GetProperty("status").GetInt32());
        Assert.Equal(currentJson.GetProperty("version").GetInt32(), transitionBody.GetProperty("version").GetInt32());

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
            ["version"] = 9,
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
    public async Task ProductionServer_CreateEpic_ReadsBackAndReportsSafeFailures()
    {
        await using var taiga = FakeTaigaHttpServer.Start();
        var serverAssembly = Path.Combine(AppContext.BaseDirectory, "TaigaMCP.dll");
        await using var process = StrictMcpProcess.Start("dotnet", [serverAssembly], CreateEnvironment(taiga), Path.GetDirectoryName(serverAssembly));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        await using var client = await McpClientFactory.CreateAsync(process.Transport, cancellationToken: timeout.Token);
        async Task<CallToolResult> Call(string name, Dictionary<string, object?> arguments)
            => await client.CallToolAsync(name, arguments, cancellationToken: timeout.Token);

        var created = await Call("create_epic", new()
        {
            ["projectId"] = 123,
            ["subject"] = "Integration epic"
        });
        Assert.False(created.IsError == true, GetText(created));
        var createdJson = JsonSerializer.Deserialize<JsonElement>(GetText(created));
        Assert.Equal(301, createdJson.GetProperty("id").GetInt32());
        Assert.Equal(12, createdJson.GetProperty("ref").GetInt32());
        Assert.Equal(4, createdJson.GetProperty("version").GetInt32());
        var minimalBody = JsonSerializer.Deserialize<JsonElement>(
            taiga.Requests.Single(request => request.Method == "POST" && request.PathAndQuery == "/api/v1/epics").Body);
        Assert.Equal(new[] { "project", "subject" }, minimalBody.EnumerateObject().Select(property => property.Name).ToArray());

        var readBack = await Call("get_epic", new() { ["epicId"] = createdJson.GetProperty("id").GetInt32() });
        Assert.False(readBack.IsError == true, GetText(readBack));
        var readBackJson = JsonSerializer.Deserialize<JsonElement>(GetText(readBack));
        Assert.Equal(301, readBackJson.GetProperty("id").GetInt32());
        Assert.Equal(4, readBackJson.GetProperty("version").GetInt32());

        var populated = await Call("create_epic", new()
        {
            ["projectId"] = 123,
            ["subject"] = "Integration epic",
            ["description"] = "  Group saved-search delivery work.  ",
            ["status"] = 7,
            ["assigned_to"] = 42,
            ["color"] = "#336699",
            ["tags"] = new[] { "search", "saved" }
        });
        Assert.False(populated.IsError == true, GetText(populated));
        var populatedBody = JsonSerializer.Deserialize<JsonElement>(
            taiga.Requests.Last(request => request.Method == "POST" && request.PathAndQuery == "/api/v1/epics").Body);
        Assert.Equal("  Group saved-search delivery work.  ", populatedBody.GetProperty("description").GetString());
        Assert.Equal(7, populatedBody.GetProperty("status").GetInt32());
        Assert.Equal(42, populatedBody.GetProperty("assigned_to").GetInt32());
        Assert.Equal("#336699", populatedBody.GetProperty("color").GetString());
        Assert.Equal(new[] { "search", "saved" }, populatedBody.GetProperty("tags").EnumerateArray().Select(tag => tag.GetString()));
        Assert.DoesNotContain(taiga.Requests, request => request.PathAndQuery.Contains("related_userstories", StringComparison.Ordinal));
        Assert.DoesNotContain(taiga.Requests, request => request.PathAndQuery.EndsWith("/projects", StringComparison.Ordinal));

        taiga.EpicCreateStatusCode = System.Net.HttpStatusCode.BadRequest;
        taiga.EpicCreateErrorBody = "{\"project\":[\"epics are disabled\"],\"status\":[\"invalid status\"],\"color\":[\"invalid color\"],\"detail\":\"secret disabled-project details\"}";
        var disabled = await Call("create_epic", new()
        {
            ["projectId"] = 123,
            ["subject"] = "Disabled epic",
            ["status"] = 99,
            ["color"] = "not-a-color"
        });
        Assert.True(disabled.IsError == true);
        Assert.Contains("400", GetText(disabled));
        Assert.Contains("project: rejected", GetText(disabled));
        Assert.Contains("status: rejected", GetText(disabled));
        Assert.Contains("color: rejected", GetText(disabled));
        Assert.DoesNotContain("secret disabled-project details", GetText(disabled));

        taiga.EpicCreateStatusCode = System.Net.HttpStatusCode.Forbidden;
        taiga.EpicCreateErrorBody = "{\"detail\":\"secret epic permission details\"}";
        var forbidden = await Call("create_epic", new() { ["projectId"] = 123, ["subject"] = "Forbidden epic" });
        Assert.True(forbidden.IsError == true);
        Assert.Contains("403", GetText(forbidden));
        Assert.Contains("permission denied", GetText(forbidden), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("secret epic permission details", GetText(forbidden));

        taiga.EpicCreateStatusCode = System.Net.HttpStatusCode.Created;
        taiga.EpicCreateResponseBody = "{\"project\":123}";
        var malformed = await Call("create_epic", new() { ["projectId"] = 123, ["subject"] = "Malformed epic" });
        Assert.True(malformed.IsError == true);
        Assert.Contains("may already have applied", GetText(malformed));
        Assert.Equal(5, taiga.Requests.Count(request => request.Method == "POST" && request.PathAndQuery == "/api/v1/epics"));

        await process.DisposeAsync();
        await process.ValidationCompleted.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.Null(process.ValidationFailure);
    }

    [Fact]
    public async Task ProductionServer_UpdateEpic_BindsOptionalArgumentsAndReportsSafeFailures()
    {
        await using var taiga = FakeTaigaHttpServer.Start();
        var serverAssembly = Path.Combine(AppContext.BaseDirectory, "TaigaMCP.dll");
        await using var process = StrictMcpProcess.Start("dotnet", [serverAssembly], CreateEnvironment(taiga), Path.GetDirectoryName(serverAssembly));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        await using var client = await McpClientFactory.CreateAsync(process.Transport, cancellationToken: timeout.Token);
        async Task<CallToolResult> Call(string name, Dictionary<string, object?> arguments)
            => await client.CallToolAsync(name, arguments, cancellationToken: timeout.Token);

        var tools = await client.ListToolsAsync(cancellationToken: timeout.Token);
        var updateEpic = Assert.Single(tools, tool => tool.Name == "update_epic");
        Assert.Equal(new[] { "epicId", "version" }, updateEpic.JsonSchema.GetProperty("required").EnumerateArray().Select(value => value.GetString()));

        var memberPage = await Call("list_project_members", new() { ["projectId"] = 123 });
        Assert.False(memberPage.IsError == true, GetText(memberPage));
        var memberEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(memberPage));
        var memberUserId = memberEnvelope.GetProperty("items")[0].GetProperty("user_id").GetInt32();
        Assert.Equal(42, memberUserId);

        var commentOnly = await Call("update_epic", new()
        {
            ["epicId"] = 301,
            ["version"] = 4,
            ["comment"] = "Delivery complete."
        });
        Assert.False(commentOnly.IsError == true, GetText(commentOnly));
        var commentJson = JsonSerializer.Deserialize<JsonElement>(GetText(commentOnly));
        Assert.Equal(301, commentJson.GetProperty("id").GetInt32());
        Assert.Equal(5, commentJson.GetProperty("version").GetInt32());
        var commentBody = JsonSerializer.Deserialize<JsonElement>(GetLastEpicPatch(taiga).Body);
        AssertPatchProperties(commentBody, "comment", "version");
        Assert.Equal("Delivery complete.", commentBody.GetProperty("comment").GetString());

        var assigned = await Call("update_epic", new()
        {
            ["epicId"] = 301,
            ["version"] = 4,
            ["subject"] = "Assigned integration epic",
            ["description"] = "Updated content",
            ["assigned_to"] = memberUserId,
            ["tags"] = new[] { "search", "delivery" }
        });
        Assert.False(assigned.IsError == true, GetText(assigned));
        var assignedJson = JsonSerializer.Deserialize<JsonElement>(GetText(assigned));
        Assert.Equal("Updated integration epic", assignedJson.GetProperty("subject").GetString());
        Assert.Equal(memberUserId, assignedJson.GetProperty("assigned_to").GetInt32());
        var assignedBody = JsonSerializer.Deserialize<JsonElement>(GetLastEpicPatch(taiga).Body);
        AssertPatchProperties(assignedBody, "assigned_to", "description", "subject", "tags", "version");
        Assert.Equal(memberUserId, assignedBody.GetProperty("assigned_to").GetInt32());
        Assert.Equal("Assigned integration epic", assignedBody.GetProperty("subject").GetString());

        taiga.EpicUpdateResponseBody =
            """
            {"id":301,"ref":12,"project":123,"subject":"Assigned integration epic","description":"Updated content","status":7,"status_extra_info":{"name":"Ready"},"color":"#336699","tags":[["search","delivery"]],"version":6}
            """;
        var unassigned = await Call("update_epic", new()
        {
            ["epicId"] = 301,
            ["version"] = 5,
            ["clearFields"] = new[] { "assigned_to" }
        });
        Assert.False(unassigned.IsError == true, GetText(unassigned));
        var unassignedJson = JsonSerializer.Deserialize<JsonElement>(GetText(unassigned));
        Assert.False(unassignedJson.TryGetProperty("assigned_to", out _));
        var unassignedBody = JsonSerializer.Deserialize<JsonElement>(GetLastEpicPatch(taiga).Body);
        AssertPatchProperties(unassignedBody, "assigned_to", "version");
        Assert.Equal(JsonValueKind.Null, unassignedBody.GetProperty("assigned_to").ValueKind);

        var explicitNulls = await Call("update_epic", new()
        {
            ["epicId"] = 301,
            ["version"] = 4,
            ["status"] = 7,
            ["description"] = null,
            ["assigned_to"] = null,
            ["color"] = null,
            ["tags"] = Array.Empty<string>(),
            ["comment"] = null,
            ["clearFields"] = null
        });
        Assert.False(explicitNulls.IsError == true, GetText(explicitNulls));
        var explicitNullBody = JsonSerializer.Deserialize<JsonElement>(GetLastEpicPatch(taiga).Body);
        AssertPatchProperties(explicitNullBody, "status", "tags", "version");
        Assert.Equal(7, explicitNullBody.GetProperty("status").GetInt32());
        Assert.Empty(explicitNullBody.GetProperty("tags").EnumerateArray());
        Assert.False(explicitNullBody.TryGetProperty("assigned_to", out _));

        var patchCount = taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/epics/301");
        var missingVersion = await Call("update_epic", new() { ["epicId"] = 301, ["status"] = 7 });
        Assert.True(missingVersion.IsError);
        Assert.Equal(patchCount, taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/epics/301"));

        taiga.EpicUpdateStatusCode = HttpStatusCode.Forbidden;
        var forbidden = await Call("update_epic", new() { ["epicId"] = 301, ["version"] = 4, ["status"] = 7 });
        Assert.True(forbidden.IsError);
        Assert.Contains("403", GetText(forbidden));
        Assert.Contains("permission denied", GetText(forbidden), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("synthetic epic update secret", GetText(forbidden));

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
            async Task<CallToolResult> Call(string name, Dictionary<string, object?> arguments)
                => await client.CallToolAsync(name, arguments, cancellationToken: protocolDeadline.Token);

            var tools = await client.ListToolsAsync(cancellationToken: protocolDeadline.Token);
            var expectedNames = new[]
            {
                "add_work_item_comment",
                "create_epic",
                "create_issue",
                "create_task",
                "create_user_story",
                "get_current_user",
                "get_epic",
                "get_issue",
                "get_task",
                "get_user_story",
                "link_user_story_to_epic",
                "list_epic_statuses",
                "list_epic_user_stories",
                "list_epics",
                "list_issue_priorities",
                "list_issue_severities",
                "list_issue_statuses",
                "list_issue_types",
                "list_issues",
                 "list_project_members",
                 "list_projects",
                 "list_sprints",
                 "list_task_statuses",
                "list_tasks",
                "list_user_stories",
                "list_user_story_statuses",
                "list_work_item_comments",
                "resolve_project",
                "resolve_work_item",
                "unlink_user_story_from_epic",
                "update_epic",
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

             var listProjectMembers = Assert.Single(tools, tool => tool.Name == "list_project_members");
            var memberProperties = listProjectMembers.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "projectId", "page" }, memberProperties);
            var memberRequired = listProjectMembers.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
             Assert.Equal(new[] { "projectId" }, memberRequired);

             var listSprints = Assert.Single(tools, tool => tool.Name == "list_sprints");
             var sprintProperties = listSprints.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
             Assert.Equal(new[] { "projectId", "page", "closed" }, sprintProperties);
             var sprintRequired = listSprints.JsonSchema.GetProperty("required").EnumerateArray()
                 .Select(value => value.GetString()).ToArray();
             Assert.Equal(new[] { "projectId" }, sprintRequired);

            async Task<string> CallMemberBoundaryAsync(Dictionary<string, object?> arguments)
            {
                try
                {
                    var result = await client.CallToolAsync(
                        "list_project_members",
                        arguments,
                        cancellationToken: protocolDeadline.Token);
                    return result.IsError == true ? "error_result" : "success";
                }
                catch (McpException)
                {
                    return "mcp_exception";
                }
            }

            async Task<string> CallSprintBoundaryAsync(Dictionary<string, object?> arguments)
            {
                try
                {
                    var result = await client.CallToolAsync(
                        "list_sprints",
                        arguments,
                        cancellationToken: protocolDeadline.Token);
                    return result.IsError == true ? "error_result" : "success";
                }
                catch (McpException)
                {
                    return "mcp_exception";
                }
            }

            Assert.Equal("error_result", await CallSprintBoundaryAsync(new Dictionary<string, object?>()));
            Assert.Equal("error_result", await CallSprintBoundaryAsync(new Dictionary<string, object?> { ["projectId"] = null }));
            var sprintWithoutClosed = await Call("list_sprints", new() { ["projectId"] = 123 });
            Assert.False(sprintWithoutClosed.IsError == true, GetText(sprintWithoutClosed));
            var sprintWithoutClosedJson = JsonSerializer.Deserialize<JsonElement>(GetText(sprintWithoutClosed));
            Assert.Equal(55, sprintWithoutClosedJson.GetProperty("items")[0].GetProperty("id").GetInt32());
            Assert.Equal(2, sprintWithoutClosedJson.GetProperty("total").GetInt32());
            Assert.Equal(2, sprintWithoutClosedJson.GetProperty("next_page").GetInt32());
            Assert.True(sprintWithoutClosedJson.GetProperty("has_more").GetBoolean());
            var omittedClosedRequest = taiga.Requests.Last(request => request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/milestones?", StringComparison.Ordinal));
            Assert.Equal("/api/v1/milestones?project=123&page=1", omittedClosedRequest.PathAndQuery);

            var sprintWithNullClosed = await Call("list_sprints", new()
            {
                ["projectId"] = 123,
                ["page"] = 2,
                ["closed"] = null
            });
            Assert.False(sprintWithNullClosed.IsError == true, GetText(sprintWithNullClosed));
            Assert.Equal("/api/v1/milestones?project=123&page=2", taiga.Requests.Last(request => request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/milestones?", StringComparison.Ordinal)).PathAndQuery);

            var openSprints = await Call("list_sprints", new()
            {
                ["projectId"] = 123,
                ["page"] = 3,
                ["closed"] = false
            });
            Assert.False(openSprints.IsError == true, GetText(openSprints));
            Assert.Equal("/api/v1/milestones?project=123&page=3&closed=false", taiga.Requests.Last(request => request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/milestones?", StringComparison.Ordinal)).PathAndQuery);

            var closedSprints = await Call("list_sprints", new()
            {
                ["projectId"] = 123,
                ["page"] = 4,
                ["closed"] = true
            });
            Assert.False(closedSprints.IsError == true, GetText(closedSprints));
            Assert.Equal("/api/v1/milestones?project=123&page=4&closed=true", taiga.Requests.Last(request => request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/milestones?", StringComparison.Ordinal)).PathAndQuery);

            var invalidSprint = await Call("list_sprints", new() { ["projectId"] = 0 });
            Assert.True(invalidSprint.IsError == true);
            Assert.Contains("projectId", GetText(invalidSprint));

            taiga.SprintStatusCode = System.Net.HttpStatusCode.Forbidden;
            var forbiddenSprints = await Call("list_sprints", new() { ["projectId"] = 123 });
            Assert.True(forbiddenSprints.IsError == true);
            Assert.Contains("403", GetText(forbiddenSprints));
            Assert.Contains("permission denied", GetText(forbiddenSprints), StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic sprint secret", GetText(forbiddenSprints));
            taiga.SprintStatusCode = System.Net.HttpStatusCode.OK;

            async Task<string> CallStoryStatusBoundaryAsync(Dictionary<string, object?> arguments)
            {
                try
                {
                    var result = await client.CallToolAsync(
                        "list_user_story_statuses",
                        arguments,
                        cancellationToken: protocolDeadline.Token);
                    return result.IsError == true ? "error_result" : "success";
                }
                catch (McpException)
                {
                    return "mcp_exception";
                }
            }

            async Task<string> CallTaskStatusBoundaryAsync(Dictionary<string, object?> arguments)
            {
                try
                {
                    var result = await client.CallToolAsync(
                        "list_task_statuses",
                        arguments,
                        cancellationToken: protocolDeadline.Token);
                    return result.IsError == true ? "error_result" : "success";
                }
                catch (McpException)
                {
                    return "mcp_exception";
                }
            }

            async Task<string> CallEpicStatusBoundaryAsync(Dictionary<string, object?> arguments)
            {
                try
                {
                    var result = await client.CallToolAsync(
                        "list_epic_statuses",
                        arguments,
                        cancellationToken: protocolDeadline.Token);
                    return result.IsError == true ? "error_result" : "success";
                }
                catch (McpException)
                {
                    return "mcp_exception";
                }
            }

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

            var listUserStoryStatuses = Assert.Single(tools, tool => tool.Name == "list_user_story_statuses");
            var storyStatusProperties = listUserStoryStatuses.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "projectId", "page" }, storyStatusProperties);
            var storyStatusRequired = listUserStoryStatuses.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "projectId" }, storyStatusRequired);

            var listTaskStatuses = Assert.Single(tools, tool => tool.Name == "list_task_statuses");
            var taskStatusProperties = listTaskStatuses.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "projectId", "page" }, taskStatusProperties);
            var taskStatusRequired = listTaskStatuses.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "projectId" }, taskStatusRequired);
            Assert.DoesNotContain("isArchived", listTaskStatuses.Description, StringComparison.Ordinal);
            Assert.DoesNotContain("wip_limit", listTaskStatuses.Description, StringComparison.Ordinal);

            var listEpicStatuses = Assert.Single(tools, tool => tool.Name == "list_epic_statuses");
            var epicStatusProperties = listEpicStatuses.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "projectId", "page" }, epicStatusProperties);
            var epicStatusRequired = listEpicStatuses.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "projectId" }, epicStatusRequired);
            Assert.DoesNotContain("isArchived", listEpicStatuses.Description, StringComparison.Ordinal);
            Assert.DoesNotContain("wip_limit", listEpicStatuses.Description, StringComparison.Ordinal);

            var listEpicUserStories = Assert.Single(tools, tool => tool.Name == "list_epic_user_stories");
            var epicStoryProperties = listEpicUserStories.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "epicId", "page" }, epicStoryProperties);
            var epicStoryRequired = listEpicUserStories.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "epicId" }, epicStoryRequired);
            Assert.Contains("one page", listEpicUserStories.Description, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("get_user_story", listEpicUserStories.Description, StringComparison.Ordinal);
            Assert.DoesNotContain("created", listEpicUserStories.Description, StringComparison.OrdinalIgnoreCase);

            var unlinkUserStoryFromEpic = Assert.Single(tools, tool => tool.Name == "unlink_user_story_from_epic");
            var unlinkProperties = unlinkUserStoryFromEpic.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "epicId", "userStoryId" }, unlinkProperties);
            var unlinkRequired = unlinkUserStoryFromEpic.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "epicId", "userStoryId" }, unlinkRequired);
            Assert.Contains("204", unlinkUserStoryFromEpic.Description, StringComparison.Ordinal);
            Assert.Contains("404", unlinkUserStoryFromEpic.Description, StringComparison.Ordinal);

            var listTasks = Assert.Single(tools, tool => tool.Name == "list_tasks");
            var taskProperties = listTasks.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(
                new[] { "projectId", "page", "userStoryId", "milestoneId", "statusIds", "assignedTo", "tags", "query", "includeClosed" },
                taskProperties);
            var taskRequired = listTasks.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "projectId" }, taskRequired);

            var listEpics = Assert.Single(tools, tool => tool.Name == "list_epics");
            var epicProperties = listEpics.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(
                new[] { "projectId", "page", "statusIds", "assignedTo", "tags", "query", "includeClosed" },
                epicProperties);
            var epicRequired = listEpics.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "projectId" }, epicRequired);

            var getUserStory = Assert.Single(tools, tool => tool.Name == "get_user_story");
            var getUserStoryProperties = getUserStory.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "userStoryId" }, getUserStoryProperties);
            var getUserStoryRequired = getUserStory.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "userStoryId" }, getUserStoryRequired);

            var getEpic = Assert.Single(tools, tool => tool.Name == "get_epic");
            var getEpicProperties = getEpic.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "epicId" }, getEpicProperties);
            var getEpicRequired = getEpic.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "epicId" }, getEpicRequired);

            var updateEpic = Assert.Single(tools, tool => tool.Name == "update_epic");
            var updateEpicProperties = updateEpic.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(
                new[] { "epicId", "version", "subject", "description", "status", "assigned_to", "color", "tags", "comment", "clearFields" },
                updateEpicProperties);
            var updateEpicRequired = updateEpic.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "epicId", "version" }, updateEpicRequired);

            var linkUserStoryToEpic = Assert.Single(tools, tool => tool.Name == "link_user_story_to_epic");
            var linkProperties = linkUserStoryToEpic.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "epicId", "userStoryId", "order" }, linkProperties);
            var linkRequired = linkUserStoryToEpic.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "epicId", "userStoryId" }, linkRequired);

            var createEpic = Assert.Single(tools, tool => tool.Name == "create_epic");
            var createEpicProperties = createEpic.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(
                new[] { "projectId", "subject", "description", "status", "assigned_to", "color", "tags" },
                createEpicProperties);
            var createEpicRequired = createEpic.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "projectId", "subject" }, createEpicRequired);

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

            var addWorkItemComment = Assert.Single(tools, tool => tool.Name == "add_work_item_comment");
            var commentProperties = addWorkItemComment.JsonSchema.GetProperty("properties").EnumerateObject().ToArray();
            Assert.Equal(new[] { "kind", "id", "version", "text" }, commentProperties.Select(property => property.Name));
            Assert.Equal(
                new[] { "issue", "user_story", "task", "epic" },
                commentProperties.Single(property => property.Name == "kind").Value.GetProperty("enum")
                    .EnumerateArray().Select(value => value.GetString()));
            var commentRequired = addWorkItemComment.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "kind", "id", "version", "text" }, commentRequired);

            var listWorkItemComments = Assert.Single(tools, tool => tool.Name == "list_work_item_comments");
            var listCommentProperties = listWorkItemComments.JsonSchema.GetProperty("properties").EnumerateObject().Select(property => property.Name).ToArray();
            Assert.Equal(new[] { "kind", "id", "page" }, listCommentProperties);
            var listCommentRequired = listWorkItemComments.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "kind", "id" }, listCommentRequired);
            Assert.Contains("opaque", listWorkItemComments.Description, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("next_page", listWorkItemComments.Description, StringComparison.Ordinal);

            var resolveWorkItem = Assert.Single(tools, tool => tool.Name == "resolve_work_item");
            var resolveProperties = resolveWorkItem.JsonSchema.GetProperty("properties").EnumerateObject().ToArray();
            Assert.Equal(new[] { "projectId", "kind", "ref" }, resolveProperties.Select(property => property.Name));
            Assert.Equal(
                new[] { "issue", "user_story", "task", "epic" },
                resolveProperties.Single(property => property.Name == "kind").Value.GetProperty("enum")
                    .EnumerateArray().Select(value => value.GetString()));
            var resolveRequired = resolveWorkItem.JsonSchema.GetProperty("required").EnumerateArray()
                .Select(value => value.GetString()).ToArray();
            Assert.Equal(new[] { "projectId", "kind", "ref" }, resolveRequired);
            Assert.DoesNotContain("cancellationToken", resolveProperties.Select(property => property.Name));

            var expectedResolvedIds = new Dictionary<string, int>
            {
                ["issue"] = 42,
                ["user_story"] = 102,
                ["task"] = 203,
                ["epic"] = 301
            };
            var expectedRoutes = new Dictionary<string, string>
            {
                ["issue"] = "issues",
                ["user_story"] = "userstories",
                ["task"] = "tasks",
                ["epic"] = "epics"
            };
            foreach (var expected in expectedResolvedIds)
            {
                var resolved = await client.CallToolAsync(
                    "resolve_work_item",
                    new Dictionary<string, object?>
                    {
                        ["projectId"] = 123,
                        ["kind"] = expected.Key,
                        ["ref"] = 42
                    },
                    cancellationToken: protocolDeadline.Token);
                Assert.False(resolved.IsError == true, GetText(resolved));
                var resolvedJson = JsonSerializer.Deserialize<JsonElement>(GetText(resolved));
                Assert.Equal(expected.Key, resolvedJson.GetProperty("kind").GetString());
                Assert.Equal(expected.Value, resolvedJson.GetProperty("id").GetInt32());
                Assert.Equal(42, resolvedJson.GetProperty("ref").GetInt32());
                Assert.Equal(123, resolvedJson.GetProperty("project").GetInt32());
                Assert.Contains(
                    taiga.Requests,
                    request => request.Method == "GET" &&
                               request.PathAndQuery == $"/api/v1/{expectedRoutes[expected.Key]}/by_ref?project=123&ref=42");
            }

            async Task<string> CallResolverBoundaryAsync(Dictionary<string, object?> arguments)
            {
                try
                {
                    var result = await client.CallToolAsync(
                        "resolve_work_item",
                        arguments,
                        cancellationToken: protocolDeadline.Token);
                    return result.IsError == true ? "error_result" : "success";
                }
                catch (McpException)
                {
                    return "mcp_exception";
                }
            }

            var resolverRequestsBeforeBindingChecks = taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.Contains("/by_ref?", StringComparison.Ordinal));
            Assert.Equal("error_result", await CallResolverBoundaryAsync(new Dictionary<string, object?>
            {
                ["projectId"] = 123,
                ["kind"] = "task"
            }));
            Assert.Equal("error_result", await CallResolverBoundaryAsync(new Dictionary<string, object?>
            {
                ["projectId"] = 123,
                ["kind"] = "task",
                ["ref"] = null
            }));
            Assert.Equal(resolverRequestsBeforeBindingChecks, taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.Contains("/by_ref?", StringComparison.Ordinal)));

            async Task<string> CallCommentBoundaryAsync(Dictionary<string, object?> arguments)
            {
                try
                {
                    var result = await client.CallToolAsync(
                        "list_work_item_comments",
                        arguments,
                        cancellationToken: protocolDeadline.Token);
                    return result.IsError == true ? "error_result" : "success";
                }
                catch (McpException)
                {
                    return "mcp_exception";
                }
            }

            var commentRequestsBeforeBindingChecks = taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/history/", StringComparison.Ordinal));
            Assert.Equal("error_result", await CallCommentBoundaryAsync(new Dictionary<string, object?>
            {
                ["kind"] = "issue"
            }));
            Assert.Equal("error_result", await CallCommentBoundaryAsync(new Dictionary<string, object?>
            {
                ["kind"] = "issue",
                ["id"] = 42,
                ["page"] = null
            }));
            Assert.Equal(commentRequestsBeforeBindingChecks, taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/history/", StringComparison.Ordinal)));

            var comments = await client.CallToolAsync(
                "list_work_item_comments",
                new Dictionary<string, object?>
                {
                    ["kind"] = "issue",
                    ["id"] = 42
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(comments.IsError == true, GetText(comments));
            var commentEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(comments));
            Assert.Equal(1, commentEnvelope.GetProperty("page").GetInt32());
            Assert.Equal(JsonValueKind.Array, commentEnvelope.GetProperty("items").ValueKind);
            Assert.Equal(JsonValueKind.Null, commentEnvelope.GetProperty("total").ValueKind);
            Assert.Equal(
                "/api/v1/history/issue/42?type=comment&page=1",
                taiga.Requests.Last(request => request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/history/", StringComparison.Ordinal)).PathAndQuery);
            var commentRequestsAfterSuccess = taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/history/", StringComparison.Ordinal));
            var invalidCommentId = await client.CallToolAsync(
                "list_work_item_comments",
                new Dictionary<string, object?> { ["kind"] = "issue", ["id"] = 0 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(invalidCommentId.IsError == true);
            Assert.Contains("id", GetText(invalidCommentId), StringComparison.OrdinalIgnoreCase);
            Assert.Equal(commentRequestsAfterSuccess, taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/history/", StringComparison.Ordinal)));

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

            var memberRequestsBeforeBindingChecks = taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/memberships", StringComparison.Ordinal));
            Assert.Equal("error_result", await CallMemberBoundaryAsync(new Dictionary<string, object?>()));
            Assert.Equal("error_result", await CallMemberBoundaryAsync(new Dictionary<string, object?> { ["projectId"] = null }));
            Assert.Equal("error_result", await CallMemberBoundaryAsync(new Dictionary<string, object?> { ["projectId"] = 123, ["page"] = null }));
            Assert.Equal(memberRequestsBeforeBindingChecks, taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/memberships", StringComparison.Ordinal)));

            var memberPage = await client.CallToolAsync(
                "list_project_members",
                new Dictionary<string, object?> { ["projectId"] = 123 },
                cancellationToken: protocolDeadline.Token);
            Assert.False(memberPage.IsError == true, GetText(memberPage));
            var memberEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(memberPage));
            Assert.Equal(JsonValueKind.Object, memberEnvelope.ValueKind);
            Assert.Equal(1, memberEnvelope.GetProperty("page").GetInt32());
            Assert.Equal(3, memberEnvelope.GetProperty("total").GetInt32());
            Assert.Equal(2, memberEnvelope.GetProperty("next_page").GetInt32());
            Assert.True(memberEnvelope.GetProperty("has_more").GetBoolean());
            var members = memberEnvelope.GetProperty("items").EnumerateArray().ToArray();
            Assert.Equal(3, members.Length);
            Assert.Equal(501, members[0].GetProperty("membership_id").GetInt32());
            Assert.Equal(42, members[0].GetProperty("user_id").GetInt32());
            Assert.False(members[0].TryGetProperty("email", out _));
            Assert.False(members[0].TryGetProperty("user_email", out _));
            Assert.Equal(43, members[1].GetProperty("user_id").GetInt32());
            Assert.False(members[1].GetProperty("is_user_active").GetBoolean());
            Assert.False(members[2].TryGetProperty("user_id", out _));
            Assert.Equal(8, members[2].GetProperty("role_id").GetInt32());
            var memberRequest = Assert.Single(taiga.Requests, request =>
                request.Method == "GET" && request.PathAndQuery == "/api/v1/memberships?project=123&page=1");
            Assert.Equal("Bearer integration-token", memberRequest.Authorization);

            var explicitMemberPage = await client.CallToolAsync(
                "list_project_members",
                new Dictionary<string, object?> { ["projectId"] = 123, ["page"] = 4 },
                cancellationToken: protocolDeadline.Token);
            Assert.False(explicitMemberPage.IsError == true, GetText(explicitMemberPage));
            var explicitMemberEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(explicitMemberPage));
            Assert.Equal(4, explicitMemberEnvelope.GetProperty("page").GetInt32());
            Assert.Single(taiga.Requests, request =>
                request.Method == "GET" && request.PathAndQuery == "/api/v1/memberships?project=123&page=4");

            var memberUserId = members[0].GetProperty("user_id").GetInt32();
            var membershipId = members[0].GetProperty("membership_id").GetInt32();
            var assignedFromMember = await client.CallToolAsync(
                "create_user_story",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["subject"] = "Member-driven assignment",
                    ["assigned_to"] = memberUserId
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(assignedFromMember.IsError == true, GetText(assignedFromMember));
            var assignedRequest = Assert.Single(taiga.Requests, request =>
                request.Method == "POST" && request.PathAndQuery == "/api/v1/userstories" &&
                request.Body.Contains("Member-driven assignment", StringComparison.Ordinal));
            using (var assignedBody = JsonDocument.Parse(assignedRequest.Body))
            {
                Assert.Equal(memberUserId, assignedBody.RootElement.GetProperty("assigned_to").GetInt32());
                Assert.NotEqual(membershipId, assignedBody.RootElement.GetProperty("assigned_to").GetInt32());
            }

            var invalidMember = await client.CallToolAsync(
                "list_project_members",
                new Dictionary<string, object?> { ["projectId"] = 0 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(invalidMember.IsError == true);
            Assert.Contains("projectId", GetText(invalidMember));

            taiga.MembershipStatusCode = System.Net.HttpStatusCode.Forbidden;
            var forbiddenMembers = await client.CallToolAsync(
                "list_project_members",
                new Dictionary<string, object?> { ["projectId"] = 123 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(forbiddenMembers.IsError == true);
            Assert.Contains("403", GetText(forbiddenMembers));
            Assert.Contains("permission denied", GetText(forbiddenMembers), StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic membership secret", GetText(forbiddenMembers));
            taiga.MembershipStatusCode = System.Net.HttpStatusCode.OK;

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

            var epicPage = await client.CallToolAsync(
                "list_epics",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["page"] = 3,
                    ["statusIds"] = new[] { 7 },
                    ["assignedTo"] = 42,
                    ["tags"] = new[] { "a&b" },
                    ["query"] = "fix & revisión",
                    ["includeClosed"] = true
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(epicPage.IsError == true);
            var epicEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(epicPage));
            Assert.Equal(JsonValueKind.Object, epicEnvelope.ValueKind);
            Assert.Equal(3, epicEnvelope.GetProperty("page").GetInt32());
            Assert.Equal(301, epicEnvelope.GetProperty("items")[0].GetProperty("id").GetInt32());
            Assert.Equal("#336699", epicEnvelope.GetProperty("items")[0].GetProperty("color").GetString());
            var epicRequest = taiga.Requests.Last(request => request.PathAndQuery.Contains("/api/v1/epics", StringComparison.Ordinal));
            Assert.Equal(
                "/api/v1/epics?project=123&page=3&status=7&assigned_to=42&tags=a%26b&q=fix%20%26%20revisi%C3%B3n",
                epicRequest.PathAndQuery);

            var omittedEpicStatusPage = await client.CallToolAsync(
                "list_epic_statuses",
                new Dictionary<string, object?> { ["projectId"] = 123 },
                cancellationToken: protocolDeadline.Token);
            Assert.False(omittedEpicStatusPage.IsError == true, GetText(omittedEpicStatusPage));
            var omittedEpicStatusEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(omittedEpicStatusPage));
            Assert.Equal(1, omittedEpicStatusEnvelope.GetProperty("page").GetInt32());
            Assert.Equal(3, omittedEpicStatusEnvelope.GetProperty("items").GetArrayLength());
            Assert.Equal(JsonValueKind.Number, omittedEpicStatusEnvelope.GetProperty("total").ValueKind);
            Assert.False(omittedEpicStatusEnvelope.GetProperty("items")[0].TryGetProperty("is_archived", out _));
            Assert.False(omittedEpicStatusEnvelope.GetProperty("items")[0].TryGetProperty("wip_limit", out _));
            var omittedEpicStatusRequest = taiga.Requests.Last(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/epic-statuses?", StringComparison.Ordinal));
            Assert.Equal("/api/v1/epic-statuses?project=123&page=1", omittedEpicStatusRequest.PathAndQuery);

            var epicStatusRequestsBeforeBindingChecks = taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/epic-statuses?", StringComparison.Ordinal));
            Assert.Equal("error_result", await CallEpicStatusBoundaryAsync(new Dictionary<string, object?>()));
            Assert.Equal("error_result", await CallEpicStatusBoundaryAsync(new Dictionary<string, object?> { ["projectId"] = null }));
            Assert.Equal("error_result", await CallEpicStatusBoundaryAsync(new Dictionary<string, object?> { ["projectId"] = 123, ["page"] = null }));
            Assert.Equal(epicStatusRequestsBeforeBindingChecks, taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/epic-statuses?", StringComparison.Ordinal)));

            var epicStatusPage = await client.CallToolAsync(
                "list_epic_statuses",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["page"] = 2
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(epicStatusPage.IsError == true, GetText(epicStatusPage));
            var epicStatusEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(epicStatusPage));
            Assert.Equal(2, epicStatusEnvelope.GetProperty("page").GetInt32());
            Assert.Equal(3, epicStatusEnvelope.GetProperty("total").GetInt32());
            Assert.Equal(3, epicStatusEnvelope.GetProperty("next_page").GetInt32());
            Assert.True(epicStatusEnvelope.GetProperty("has_more").GetBoolean());
            var epicStatuses = epicStatusEnvelope.GetProperty("items").EnumerateArray().ToArray();
            Assert.Equal(3, epicStatuses.Length);
            Assert.Equal("Terminé", epicStatuses[1].GetProperty("name").GetString());
            Assert.True(epicStatuses[1].GetProperty("is_closed").GetBoolean());
            Assert.False(epicStatuses[1].TryGetProperty("is_archived", out _));
            Assert.False(epicStatuses[1].TryGetProperty("wip_limit", out _));
            var returnedOpenEpicStatusId = epicStatuses[0].GetProperty("id").GetInt32();
            var returnedClosedEpicStatusId = epicStatuses[1].GetProperty("id").GetInt32();
            Assert.Equal(7, returnedOpenEpicStatusId);
            Assert.Equal(8, returnedClosedEpicStatusId);
            var epicStatusRequest = taiga.Requests.Last(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/epic-statuses?", StringComparison.Ordinal));
            Assert.Equal("/api/v1/epic-statuses?project=123&page=2", epicStatusRequest.PathAndQuery);

            taiga.EpicStatusStatusCode = System.Net.HttpStatusCode.Forbidden;
            var forbiddenEpicStatuses = await client.CallToolAsync(
                "list_epic_statuses",
                new Dictionary<string, object?> { ["projectId"] = 123 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(forbiddenEpicStatuses.IsError == true);
            Assert.Contains("403", GetText(forbiddenEpicStatuses));
            Assert.Contains("permission denied", GetText(forbiddenEpicStatuses), StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic epic status secret", GetText(forbiddenEpicStatuses));
            taiga.EpicStatusStatusCode = System.Net.HttpStatusCode.OK;

            var epicDetail = await client.CallToolAsync(
                "get_epic",
                new Dictionary<string, object?> { ["epicId"] = 301 },
                cancellationToken: protocolDeadline.Token);
            Assert.False(epicDetail.IsError == true);
            var epicDetailJson = JsonSerializer.Deserialize<JsonElement>(GetText(epicDetail));
            Assert.Equal(301, epicDetailJson.GetProperty("id").GetInt32());
            Assert.Equal("**Acceptance:** preserve Markdown and Unicode — ✓", epicDetailJson.GetProperty("description").GetString());
            Assert.Equal(4, epicDetailJson.GetProperty("version").GetInt32());
            Assert.Equal(3, epicDetailJson.GetProperty("user_stories_counts").GetProperty("total").GetInt32());
            Assert.False(epicDetailJson.TryGetProperty("assigned_to", out _));
            var epicDetailRequest = Assert.Single(taiga.Requests, request =>
                request.Method == "GET" && request.PathAndQuery == "/api/v1/epics/301");
            Assert.Equal("Bearer integration-token", epicDetailRequest.Authorization);
            Assert.DoesNotContain(taiga.Requests, request => request.PathAndQuery.Contains("related_userstories", StringComparison.Ordinal));

            var linked = await client.CallToolAsync(
                "link_user_story_to_epic",
                new Dictionary<string, object?>
                {
                    ["epicId"] = 301,
                    ["userStoryId"] = 102,
                    ["order"] = 9001
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(linked.IsError == true, GetText(linked));
            var linkedJson = JsonSerializer.Deserialize<JsonElement>(GetText(linked));
            Assert.Equal(301, linkedJson.GetProperty("epic_id").GetInt32());
            Assert.Equal(102, linkedJson.GetProperty("user_story_id").GetInt32());
            Assert.Equal(9001, linkedJson.GetProperty("order").GetInt64());
            Assert.True(linkedJson.GetProperty("created").GetBoolean());
            var linkPost = Assert.Single(taiga.Requests, request =>
                request.Method == "POST" && request.PathAndQuery == "/api/v1/epics/301/related_userstories");
            using (var linkBody = JsonDocument.Parse(linkPost.Body))
            {
                Assert.Equal(301, linkBody.RootElement.GetProperty("epic").GetInt32());
                Assert.Equal(102, linkBody.RootElement.GetProperty("user_story").GetInt32());
                Assert.Equal(9001, linkBody.RootElement.GetProperty("order").GetInt64());
            }

            var repeatedLink = await client.CallToolAsync(
                "link_user_story_to_epic",
                new Dictionary<string, object?>
                {
                    ["epicId"] = 301,
                    ["userStoryId"] = 102
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(repeatedLink.IsError == true, GetText(repeatedLink));
            var repeatedLinkJson = JsonSerializer.Deserialize<JsonElement>(GetText(repeatedLink));
            Assert.Equal(9001, repeatedLinkJson.GetProperty("order").GetInt64());
            Assert.False(repeatedLinkJson.GetProperty("created").GetBoolean());
            Assert.DoesNotContain(taiga.Requests, request =>
                request.Method == "POST" && request.PathAndQuery == "/api/v1/epics/301/related_userstories" &&
                request.Body == "{\"epic\":301,\"user_story\":102}");

            var relationshipListRequestsBefore = taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/epics/301/related_userstories?", StringComparison.Ordinal));
            var storyDetailRequestsBeforeRelationshipList = taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery == "/api/v1/userstories/102");
            var relationshipPage = await client.CallToolAsync(
                "list_epic_user_stories",
                new Dictionary<string, object?> { ["epicId"] = 301 },
                cancellationToken: protocolDeadline.Token);
            Assert.False(relationshipPage.IsError == true, GetText(relationshipPage));
            var relationshipEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(relationshipPage));
            Assert.Equal(1, relationshipEnvelope.GetProperty("page").GetInt32());
            Assert.Equal(1, relationshipEnvelope.GetProperty("total").GetInt32());
            Assert.False(relationshipEnvelope.GetProperty("has_more").GetBoolean());
            var relationship = Assert.Single(relationshipEnvelope.GetProperty("items").EnumerateArray());
            Assert.Equal(301, relationship.GetProperty("epic_id").GetInt32());
            Assert.Equal(102, relationship.GetProperty("user_story_id").GetInt32());
            Assert.Equal(9001, relationship.GetProperty("order").GetInt64());
            Assert.False(relationship.TryGetProperty("created", out _));
            var relationshipListRequest = Assert.Single(taiga.Requests, request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/epics/301/related_userstories?", StringComparison.Ordinal));
            Assert.Equal("/api/v1/epics/301/related_userstories?page=1", relationshipListRequest.PathAndQuery);
            Assert.Equal(relationshipListRequestsBefore + 1, taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/epics/301/related_userstories?", StringComparison.Ordinal)));
            Assert.Equal(storyDetailRequestsBeforeRelationshipList, taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery == "/api/v1/userstories/102"));

            var selectedStory = await client.CallToolAsync(
                "get_user_story",
                new Dictionary<string, object?> { ["userStoryId"] = relationship.GetProperty("user_story_id").GetInt32() },
                cancellationToken: protocolDeadline.Token);
            Assert.False(selectedStory.IsError == true, GetText(selectedStory));
            Assert.Equal(102, JsonSerializer.Deserialize<JsonElement>(GetText(selectedStory)).GetProperty("id").GetInt32());

            var unlinked = await client.CallToolAsync(
                "unlink_user_story_from_epic",
                new Dictionary<string, object?>
                {
                    ["epicId"] = 301,
                    ["userStoryId"] = 102
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(unlinked.IsError == true, GetText(unlinked));
            var unlinkJson = JsonSerializer.Deserialize<JsonElement>(GetText(unlinked));
            Assert.Equal(301, unlinkJson.GetProperty("epic_id").GetInt32());
            Assert.Equal(102, unlinkJson.GetProperty("user_story_id").GetInt32());
            Assert.True(unlinkJson.GetProperty("removed").GetBoolean());
            var unlinkRequest = Assert.Single(taiga.Requests, request =>
                request.Method == "DELETE" && request.PathAndQuery == "/api/v1/epics/301/related_userstories/102");
            Assert.Equal(string.Empty, unlinkRequest.Body);
            Assert.DoesNotContain(taiga.Requests, request =>
                request.Method is "PATCH" or "DELETE" &&
                (request.PathAndQuery == "/api/v1/epics/301" || request.PathAndQuery == "/api/v1/userstories/102"));

            var relationshipPageAfterUnlink = await client.CallToolAsync(
                "list_epic_user_stories",
                new Dictionary<string, object?> { ["epicId"] = 301 },
                cancellationToken: protocolDeadline.Token);
            Assert.False(relationshipPageAfterUnlink.IsError == true, GetText(relationshipPageAfterUnlink));
            var relationshipEnvelopeAfterUnlink = JsonSerializer.Deserialize<JsonElement>(GetText(relationshipPageAfterUnlink));
            Assert.Empty(relationshipEnvelopeAfterUnlink.GetProperty("items").EnumerateArray());
            Assert.Equal(0, relationshipEnvelopeAfterUnlink.GetProperty("total").GetInt32());

            var repeatedUnlink = await client.CallToolAsync(
                "unlink_user_story_from_epic",
                new Dictionary<string, object?> { ["epicId"] = 301, ["userStoryId"] = 102 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(repeatedUnlink.IsError == true);
            Assert.Contains("404", GetText(repeatedUnlink));
            Assert.Contains("resource not found", GetText(repeatedUnlink), StringComparison.OrdinalIgnoreCase);

            var missingUnlinkArgument = await client.CallToolAsync(
                "unlink_user_story_from_epic",
                new Dictionary<string, object?> { ["epicId"] = 301 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(missingUnlinkArgument.IsError == true);
            var nullUnlinkArgument = await client.CallToolAsync(
                "unlink_user_story_from_epic",
                new Dictionary<string, object?> { ["epicId"] = null, ["userStoryId"] = 102 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(nullUnlinkArgument.IsError == true);

            taiga.EpicStoryUnlinkStatusCode = System.Net.HttpStatusCode.Forbidden;
            var forbiddenUnlink = await client.CallToolAsync(
                "unlink_user_story_from_epic",
                new Dictionary<string, object?> { ["epicId"] = 301, ["userStoryId"] = 102 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(forbiddenUnlink.IsError == true);
            Assert.Contains("403", GetText(forbiddenUnlink));
            Assert.Contains("permission denied", GetText(forbiddenUnlink), StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic unlink secret", GetText(forbiddenUnlink));
            taiga.EpicStoryUnlinkStatusCode = System.Net.HttpStatusCode.NoContent;

            var missingRelationshipEpic = await client.CallToolAsync(
                "list_epic_user_stories",
                new Dictionary<string, object?>(),
                cancellationToken: protocolDeadline.Token);
            Assert.True(missingRelationshipEpic.IsError == true);
            var nullRelationshipPage = await client.CallToolAsync(
                "list_epic_user_stories",
                new Dictionary<string, object?> { ["epicId"] = 301, ["page"] = null },
                cancellationToken: protocolDeadline.Token);
            Assert.True(nullRelationshipPage.IsError == true);

            taiga.EpicStoryListStatusCode = System.Net.HttpStatusCode.Forbidden;
            var forbiddenRelationshipList = await client.CallToolAsync(
                "list_epic_user_stories",
                new Dictionary<string, object?> { ["epicId"] = 301 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(forbiddenRelationshipList.IsError == true);
            Assert.Contains("403", GetText(forbiddenRelationshipList));
            Assert.Contains("permission denied", GetText(forbiddenRelationshipList), StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic relationship list secret", GetText(forbiddenRelationshipList));
            taiga.EpicStoryListStatusCode = System.Net.HttpStatusCode.OK;

            taiga.EpicDetailStatusCode = System.Net.HttpStatusCode.Forbidden;
            var forbiddenEpic = await client.CallToolAsync(
                "get_epic",
                new Dictionary<string, object?> { ["epicId"] = 301 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(forbiddenEpic.IsError == true);
            Assert.Contains("403", GetText(forbiddenEpic));
            Assert.Contains("permission denied", GetText(forbiddenEpic), StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic epic detail secret", GetText(forbiddenEpic));

            taiga.EpicDetailStatusCode = System.Net.HttpStatusCode.NotFound;
            var missingEpic = await client.CallToolAsync(
                "get_epic",
                new Dictionary<string, object?> { ["epicId"] = 301 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(missingEpic.IsError == true);
            Assert.Contains("404", GetText(missingEpic));
            Assert.Contains("resource not found", GetText(missingEpic), StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("synthetic epic detail secret", GetText(missingEpic));

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

            var omittedStoryStatusPage = await client.CallToolAsync(
                "list_user_story_statuses",
                new Dictionary<string, object?> { ["projectId"] = 123 },
                cancellationToken: protocolDeadline.Token);
            Assert.False(omittedStoryStatusPage.IsError == true, GetText(omittedStoryStatusPage));
            var omittedStoryStatusEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(omittedStoryStatusPage));
            Assert.Equal(1, omittedStoryStatusEnvelope.GetProperty("page").GetInt32());
            Assert.Equal(3, omittedStoryStatusEnvelope.GetProperty("items").GetArrayLength());
            var omittedStoryStatusRequest = taiga.Requests.Last(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/userstory-statuses?", StringComparison.Ordinal));
            Assert.Equal("/api/v1/userstory-statuses?project=123&page=1", omittedStoryStatusRequest.PathAndQuery);

            var statusRequestsBeforeBindingChecks = taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/userstory-statuses?", StringComparison.Ordinal));
            Assert.Equal("error_result", await CallStoryStatusBoundaryAsync(new Dictionary<string, object?>()));
            Assert.Equal("error_result", await CallStoryStatusBoundaryAsync(new Dictionary<string, object?> { ["projectId"] = null }));
            Assert.Equal("error_result", await CallStoryStatusBoundaryAsync(new Dictionary<string, object?> { ["projectId"] = 123, ["page"] = null }));
            Assert.Equal(statusRequestsBeforeBindingChecks, taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/userstory-statuses?", StringComparison.Ordinal)));

            var storyStatusPage = await client.CallToolAsync(
                "list_user_story_statuses",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["page"] = 2
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(storyStatusPage.IsError == true, GetText(storyStatusPage));
            var storyStatusEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(storyStatusPage));
            Assert.Equal(2, storyStatusEnvelope.GetProperty("page").GetInt32());
            Assert.Equal(JsonValueKind.Null, storyStatusEnvelope.GetProperty("total").ValueKind);
            var storyStatuses = storyStatusEnvelope.GetProperty("items").EnumerateArray().ToArray();
            Assert.Equal(3, storyStatuses.Length);
            Assert.Equal("Terminado", storyStatuses[1].GetProperty("name").GetString());
            Assert.True(storyStatuses[1].GetProperty("is_closed").GetBoolean());
            Assert.True(storyStatuses[2].GetProperty("is_archived").GetBoolean());
            var storyStatusRequest = taiga.Requests.Last(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/userstory-statuses?", StringComparison.Ordinal));
            Assert.Equal("/api/v1/userstory-statuses?project=123&page=2", storyStatusRequest.PathAndQuery);

            var invalidStoryStatusCall = await client.CallToolAsync(
                "list_user_story_statuses",
                new Dictionary<string, object?> { ["projectId"] = 0 },
                cancellationToken: protocolDeadline.Token);
            Assert.True(invalidStoryStatusCall.IsError == true);
            Assert.Contains("positive", GetText(invalidStoryStatusCall), StringComparison.OrdinalIgnoreCase);

            var omittedTaskStatusPage = await client.CallToolAsync(
                "list_task_statuses",
                new Dictionary<string, object?> { ["projectId"] = 123 },
                cancellationToken: protocolDeadline.Token);
            Assert.False(omittedTaskStatusPage.IsError == true, GetText(omittedTaskStatusPage));
            var omittedTaskStatusEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(omittedTaskStatusPage));
            Assert.Equal(1, omittedTaskStatusEnvelope.GetProperty("page").GetInt32());
            Assert.Equal(3, omittedTaskStatusEnvelope.GetProperty("items").GetArrayLength());
            Assert.False(omittedTaskStatusEnvelope.GetProperty("items")[0].TryGetProperty("is_archived", out _));
            Assert.False(omittedTaskStatusEnvelope.GetProperty("items")[0].TryGetProperty("wip_limit", out _));
            var omittedTaskStatusRequest = taiga.Requests.Last(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/task-statuses?", StringComparison.Ordinal));
            Assert.Equal("/api/v1/task-statuses?project=123&page=1", omittedTaskStatusRequest.PathAndQuery);

            var taskStatusRequestsBeforeBindingChecks = taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/task-statuses?", StringComparison.Ordinal));
            Assert.Equal("error_result", await CallTaskStatusBoundaryAsync(new Dictionary<string, object?>()));
            Assert.Equal("error_result", await CallTaskStatusBoundaryAsync(new Dictionary<string, object?> { ["projectId"] = null }));
            Assert.Equal("error_result", await CallTaskStatusBoundaryAsync(new Dictionary<string, object?> { ["projectId"] = 123, ["page"] = null }));
            Assert.Equal(taskStatusRequestsBeforeBindingChecks, taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/task-statuses?", StringComparison.Ordinal)));

            var taskStatusPage = await client.CallToolAsync(
                "list_task_statuses",
                new Dictionary<string, object?>
                {
                    ["projectId"] = 123,
                    ["page"] = 2
                },
                cancellationToken: protocolDeadline.Token);
            Assert.False(taskStatusPage.IsError == true, GetText(taskStatusPage));
            var taskStatusEnvelope = JsonSerializer.Deserialize<JsonElement>(GetText(taskStatusPage));
            Assert.Equal(2, taskStatusEnvelope.GetProperty("page").GetInt32());
            var taskStatuses = taskStatusEnvelope.GetProperty("items").EnumerateArray().ToArray();
            Assert.Equal(3, taskStatuses.Length);
            Assert.Equal("Terminé", taskStatuses[1].GetProperty("name").GetString());
            Assert.True(taskStatuses[1].GetProperty("is_closed").GetBoolean());
            Assert.False(taskStatuses[1].TryGetProperty("is_archived", out _));
            Assert.False(taskStatuses[1].TryGetProperty("wip_limit", out _));
            var returnedOpenTaskStatusId = taskStatuses[0].GetProperty("id").GetInt32();
            var returnedClosedTaskStatusId = taskStatuses[1].GetProperty("id").GetInt32();
            var taskStatusRequest = taiga.Requests.Last(request =>
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/task-statuses?", StringComparison.Ordinal));
            Assert.Equal("/api/v1/task-statuses?project=123&page=2", taskStatusRequest.PathAndQuery);

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
                    ["statusIds"] = new[] { returnedOpenTaskStatusId },
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
                request.Method == "GET" && request.PathAndQuery.StartsWith("/api/v1/tasks?project=", StringComparison.Ordinal));
            Assert.Equal(
                $"/api/v1/tasks?project=123&page=2&status={returnedOpenTaskStatusId}&user_story=102&milestone=55&assigned_to=42&tags=a%26b&q=fix%20%26%20revisi%C3%B3n",
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
                    ["status"] = returnedClosedTaskStatusId,
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
            AssertPatchProperties(updatedTaskBody.RootElement, "blocked_note", "description", "is_blocked", "status", "tags", "version");
            Assert.Equal(returnedClosedTaskStatusId, updatedTaskBody.RootElement.GetProperty("status").GetInt32());
            Assert.Equal(2, updatedTaskBody.RootElement.GetProperty("version").GetInt32());
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
            var clearedByServer = JsonSerializer.Deserialize<JsonElement>(GetText(unblockedWithoutNote));
            Assert.False(clearedByServer.GetProperty("is_blocked").GetBoolean());
            Assert.Equal(string.Empty, clearedByServer.GetProperty("blocked_note").GetString());
            AssertTaskPatch(taiga, ["is_blocked", "version"]);

            var unblockedWithNonemptyNote = await Call("update_task", new()
            {
                ["taskId"] = 203,
                ["version"] = 7,
                ["isBlocked"] = false,
                ["blockedNote"] = "This note cannot persist while unblocked."
            });
            Assert.False(unblockedWithNonemptyNote.IsError == true, GetText(unblockedWithNonemptyNote));
            var clearedNonemptyNote = JsonSerializer.Deserialize<JsonElement>(GetText(unblockedWithNonemptyNote));
            Assert.False(clearedNonemptyNote.GetProperty("is_blocked").GetBoolean());
            Assert.Equal(string.Empty, clearedNonemptyNote.GetProperty("blocked_note").GetString());
            using (var nonemptyNoteBody = GetLastTaskPatchDocument(taiga))
            {
                AssertPatchProperties(nonemptyNoteBody.RootElement, "blocked_note", "is_blocked", "version");
                Assert.Equal("This note cannot persist while unblocked.", nonemptyNoteBody.RootElement.GetProperty("blocked_note").GetString());
            }

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
    public async Task ProductionServer_ResolvesTaskThenReadsAndUpdatesItsInternalId()
    {
        await using var taiga = FakeTaigaHttpServer.Start();
        var serverAssembly = Path.Combine(AppContext.BaseDirectory, "TaigaMCP.dll");
        await using var process = StrictMcpProcess.Start("dotnet", [serverAssembly], CreateEnvironment(taiga), Path.GetDirectoryName(serverAssembly));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        await using (var client = await McpClientFactory.CreateAsync(process.Transport, cancellationToken: timeout.Token))
        {
            async Task<CallToolResult> Call(string name, Dictionary<string, object?> arguments)
                => await client.CallToolAsync(name, arguments, cancellationToken: timeout.Token);

            var resolved = await Call("resolve_work_item", new()
            {
                ["projectId"] = 123,
                ["kind"] = "task",
                ["ref"] = 42
            });
            Assert.False(resolved.IsError == true, GetText(resolved));
            var resolvedJson = JsonSerializer.Deserialize<JsonElement>(GetText(resolved));
            Assert.Equal("task", resolvedJson.GetProperty("kind").GetString());
            Assert.Equal(203, resolvedJson.GetProperty("id").GetInt32());
            Assert.Equal(42, resolvedJson.GetProperty("ref").GetInt32());

            var detail = await Call("get_task", new()
            {
                ["taskId"] = resolvedJson.GetProperty("id").GetInt32()
            });
            Assert.False(detail.IsError == true, GetText(detail));
            var detailJson = JsonSerializer.Deserialize<JsonElement>(GetText(detail));
            var version = detailJson.GetProperty("version").GetInt32();
            Assert.Equal(2, version);

            var update = await Call("update_task", new()
            {
                ["taskId"] = resolvedJson.GetProperty("id").GetInt32(),
                ["version"] = version,
                ["status"] = 11
            });
            Assert.False(update.IsError == true, GetText(update));
            Assert.Equal(3, JsonSerializer.Deserialize<JsonElement>(GetText(update)).GetProperty("version").GetInt32());

            using var patch = JsonDocument.Parse(
                taiga.Requests.Last(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/tasks/203").Body);
            Assert.Equal(2, patch.RootElement.GetProperty("version").GetInt32());

            var byRefRequestsBeforeFailures = taiga.Requests.Count(request =>
                request.Method == "GET" && request.PathAndQuery.Contains("/by_ref?", StringComparison.Ordinal));
            var missing = await Call("resolve_work_item", new()
            {
                ["projectId"] = 999,
                ["kind"] = "task",
                ["ref"] = 42
            });
            Assert.True(missing.IsError);
            Assert.Contains("404", GetText(missing));
            Assert.Contains("resource not found", GetText(missing), StringComparison.OrdinalIgnoreCase);

            var invalidProject = await Call("resolve_work_item", new()
            {
                ["projectId"] = 0,
                ["kind"] = "task",
                ["ref"] = 42
            });
            Assert.True(invalidProject.IsError);
            var invalidKind = await Call("resolve_work_item", new()
            {
                ["projectId"] = 123,
                ["kind"] = "wrong_kind",
                ["ref"] = 42
            });
            Assert.True(invalidKind.IsError);
            var invalidRef = await Call("resolve_work_item", new()
            {
                ["projectId"] = 123,
                ["kind"] = "task",
                ["ref"] = 0
            });
            Assert.True(invalidRef.IsError);
            Assert.Equal(
                byRefRequestsBeforeFailures + 1,
                taiga.Requests.Count(request =>
                    request.Method == "GET" && request.PathAndQuery.Contains("/by_ref?", StringComparison.Ordinal)));
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

            await using (var process = StrictMcpProcess.Start(
                "cmd.exe",
                ["/d", "/c", "call contaminated.cmd"],
                CreateEnvironment(taiga),
                temporaryRoot))
            using (var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5)))
            {
                await Assert.ThrowsAnyAsync<Exception>(async () =>
                    await McpClientFactory.CreateAsync(process.Transport, cancellationToken: timeout.Token));

                await process.ValidationCompleted.WaitAsync(timeout.Token);
                Assert.True(
                    process.RawStdoutLines.Contains("REVIEW: non-JSON stdout contamination"),
                    $"stdout=[{string.Join(" | ", process.RawStdoutLines)}]; stderr=[{string.Join(" | ", process.StderrLines)}]; validation={process.ValidationFailure}");
                var failure = Assert.IsType<InvalidDataException>(process.ValidationFailure);
                Assert.Contains("not JSON", failure.Message);
            }
        }
        finally
        {
            await DeleteTemporaryApplicationCopyAsync(temporaryRoot);
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

    private static async Task DeleteTemporaryApplicationCopyAsync(string path)
    {
        var tempRoot = Path.GetFullPath(Path.GetTempPath());
        var fullPath = Path.GetFullPath(path);
        if (!fullPath.StartsWith(tempRoot, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Temporary application copy escaped the system temp directory.");

        for (var attempt = 0; ; attempt++)
        {
            try
            {
                Directory.Delete(fullPath, recursive: true);
                return;
            }
            catch (Exception exception) when
                ((exception is IOException or UnauthorizedAccessException) && attempt < 19)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(100));
            }
        }
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

    private static RecordedTaigaRequest GetLastEpicPatch(FakeTaigaHttpServer taiga)
        => taiga.Requests.Last(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/epics/301");

    private static void AssertTaskPatch(FakeTaigaHttpServer taiga, string[] expectedNames)
    {
        using var body = GetLastTaskPatchDocument(taiga);
        AssertPatchProperties(body.RootElement, expectedNames);
    }

    private static JsonDocument GetLastTaskPatchDocument(FakeTaigaHttpServer taiga)
        => JsonDocument.Parse(taiga.Requests.Last(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/tasks/203").Body);
}
