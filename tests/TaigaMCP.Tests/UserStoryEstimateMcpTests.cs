using System.Text.Json;
using ModelContextProtocol;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class UserStoryEstimateMcpTests
{
    [Fact]
    public async Task ProductionServer_SetUserStoryEstimates_BindsEntriesAndPreservesNativeState()
    {
        await using var taiga = FakeTaigaHttpServer.Start();
        taiga.UserStory102ResponseBody =
            """
            {"id":102,"ref":18,"project":123,"subject":"Estimated story","status":1,"status_extra_info":{"name":"Ready"},"points":{"7":22,"8":21},"total_points":null,"version":4}
            """;
        var assembly = Path.Combine(AppContext.BaseDirectory, "TaigaMCP.dll");
        await using var process = StrictMcpProcess.Start(
            "dotnet",
            [assembly],
            CreateEnvironment(taiga),
            Path.GetDirectoryName(assembly));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        await using var client = await McpClientFactory.CreateAsync(process.Transport, cancellationToken: timeout.Token);

        var tools = await client.ListToolsAsync(cancellationToken: timeout.Token);
        var estimateTool = Assert.Single(tools, tool => tool.Name == "set_user_story_estimates");
        var properties = estimateTool.JsonSchema.GetProperty("properties").EnumerateObject()
            .Select(property => property.Name)
            .ToArray();
        Assert.Equal(new[] { "userStoryId", "version", "rolePoints" }, properties);
        Assert.Equal(
            new[] { "userStoryId", "version", "rolePoints" },
            estimateTool.JsonSchema.GetProperty("required").EnumerateArray().Select(value => value.GetString()));
        Assert.Contains("roleId", estimateTool.JsonSchema.GetProperty("properties").GetProperty("rolePoints")
            .GetProperty("items").GetProperty("properties").EnumerateObject().Select(property => property.Name));
        Assert.Contains("pointId", estimateTool.JsonSchema.GetProperty("properties").GetProperty("rolePoints")
            .GetProperty("items").GetProperty("properties").EnumerateObject().Select(property => property.Name));

        async Task<CallToolResult> Call(string name, Dictionary<string, object?> arguments)
            => await client.CallToolAsync(name, arguments, cancellationToken: timeout.Token);

        var pointPage = await Call("list_points", new() { ["projectId"] = 123 });
        Assert.False(pointPage.IsError == true, GetText(pointPage));
        var unestimatedPointId = JsonSerializer.Deserialize<JsonElement>(GetText(pointPage))
            .GetProperty("items")
            .EnumerateArray()
            .Single(item => item.GetProperty("value").ValueKind == JsonValueKind.Null)
            .GetProperty("id")
            .GetInt32();

        var single = await Call("set_user_story_estimates", new()
        {
            ["userStoryId"] = 102,
            ["version"] = 4,
            ["rolePoints"] = new object[]
            {
                new Dictionary<string, object?> { ["roleId"] = 7, ["pointId"] = unestimatedPointId }
            }
        });
        Assert.False(single.IsError == true, GetText(single));
        var singleJson = JsonSerializer.Deserialize<JsonElement>(GetText(single));
        Assert.Equal(5, singleJson.GetProperty("version").GetInt32());
        Assert.Equal(unestimatedPointId, singleJson.GetProperty("points").GetProperty("7").GetInt32());
        Assert.Equal(21, singleJson.GetProperty("points").GetProperty("8").GetInt32());
        Assert.False(singleJson.TryGetProperty("total_points", out _));

        var singlePatch = JsonSerializer.Deserialize<JsonElement>(
            taiga.Requests.Last(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/userstories/102").Body);
        AssertPatchProperties(singlePatch, "points", "version");
        Assert.Equal(4, singlePatch.GetProperty("version").GetInt32());
        Assert.Equal(unestimatedPointId, singlePatch.GetProperty("points").GetProperty("7").GetInt32());
        Assert.False(singlePatch.GetProperty("points").TryGetProperty("8", out _));

        var multiple = await Call("set_user_story_estimates", new()
        {
            ["userStoryId"] = 102,
            ["version"] = 5,
            ["rolePoints"] = new object[]
            {
                new Dictionary<string, object?> { ["roleId"] = 7, ["pointId"] = 22 },
                new Dictionary<string, object?> { ["roleId"] = 8, ["pointId"] = unestimatedPointId }
            }
        });
        Assert.False(multiple.IsError == true, GetText(multiple));
        var multipleJson = JsonSerializer.Deserialize<JsonElement>(GetText(multiple));
        Assert.Equal(6, multipleJson.GetProperty("version").GetInt32());
        Assert.Equal(22, multipleJson.GetProperty("points").GetProperty("7").GetInt32());
        Assert.Equal(unestimatedPointId, multipleJson.GetProperty("points").GetProperty("8").GetInt32());

        var duplicate = await Call("set_user_story_estimates", new()
        {
            ["userStoryId"] = 102,
            ["version"] = 6,
            ["rolePoints"] = new object[]
            {
                new Dictionary<string, object?> { ["roleId"] = 7, ["pointId"] = 22 },
                new Dictionary<string, object?> { ["roleId"] = 7, ["pointId"] = 21 }
            }
        });
        Assert.True(duplicate.IsError);
        Assert.Contains("duplicate role", GetText(duplicate), StringComparison.OrdinalIgnoreCase);
        Assert.Equal(2, taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/userstories/102"));

        async Task AssertInvalidArguments(Dictionary<string, object?> arguments)
        {
            var patchCount = taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/userstories/102");
            try
            {
                var invalid = await Call("set_user_story_estimates", arguments);
                Assert.True(invalid.IsError, GetText(invalid));
            }
            catch (McpException)
            {
            }

            Assert.Equal(
                patchCount,
                taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/userstories/102"));
        }

        await AssertInvalidArguments(new()
        {
            ["userStoryId"] = 102,
            ["version"] = 6
        });
        await AssertInvalidArguments(new()
        {
            ["userStoryId"] = 102,
            ["version"] = 6,
            ["rolePoints"] = null
        });
        await AssertInvalidArguments(new()
        {
            ["userStoryId"] = 102,
            ["version"] = 6,
            ["rolePoints"] = new object[] { null! }
        });
        await AssertInvalidArguments(new()
        {
            ["userStoryId"] = 102,
            ["version"] = 6,
            ["rolePoints"] = new object[]
            {
                new Dictionary<string, object?> { ["roleId"] = 7 }
            }
        });
        await AssertInvalidArguments(new()
        {
            ["userStoryId"] = 102,
            ["version"] = 6,
            ["rolePoints"] = new object[]
            {
                new Dictionary<string, object?> { ["roleId"] = "seven", ["pointId"] = 21 }
            }
        });
        await AssertInvalidArguments(new()
        {
            ["userStoryId"] = 102,
            ["version"] = 6,
            ["rolePoints"] = new object[]
            {
                new Dictionary<string, object?> { ["roleId"] = 0, ["pointId"] = 21 }
            }
        });
        await AssertInvalidArguments(new()
        {
            ["userStoryId"] = 102,
            ["version"] = 6,
            ["rolePoints"] = new object[]
            {
                new Dictionary<string, object?> { ["roleId"] = 7, ["pointId"] = 0 }
            }
        });
        await AssertInvalidArguments(new()
        {
            ["userStoryId"] = 102,
            ["version"] = -1,
            ["rolePoints"] = new object[]
            {
                new Dictionary<string, object?> { ["roleId"] = 7, ["pointId"] = 21 }
            }
        });

        taiga.UserStoryUpdateResponseOverride = "{\"id\":102,\"version\":7}";
        var malformedSuccess = await Call("set_user_story_estimates", new()
        {
            ["userStoryId"] = 102,
            ["version"] = 6,
            ["rolePoints"] = new object[]
            {
                new Dictionary<string, object?> { ["roleId"] = 7, ["pointId"] = 22 }
            }
        });
        Assert.True(malformedSuccess.IsError);
        Assert.Contains("may already have applied", GetText(malformedSuccess));
        Assert.Contains("points", GetText(malformedSuccess), StringComparison.OrdinalIgnoreCase);
        Assert.Equal(3, taiga.Requests.Count(request => request.Method == "PATCH" && request.PathAndQuery == "/api/v1/userstories/102"));

        await process.DisposeAsync();
        await process.ValidationCompleted.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.Null(process.ValidationFailure);
    }

    private static IReadOnlyDictionary<string, string> CreateEnvironment(FakeTaigaHttpServer taiga)
        => new Dictionary<string, string>
        {
            ["TAIGA__BASEURL"] = taiga.BaseUrl,
            ["TAIGA__USERNAME"] = "integration-user",
            ["TAIGA__PASSWORD"] = "integration-password",
            ["DOTNET_NOLOGO"] = "1"
        };

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
