using System.Net;
using System.Text.Json;
using Xunit;

namespace TaigaMCP.Tests;

internal static class EpicStoryUnlinkFixtures
{
    public const int EpicId = 301;
    public const int UserStoryId = 102;

    public const string MissingRelationship = """
        {"detail":"Not found."}
        """;

    public const string PermissionDenied = """
        {"detail":"Permission denied."}
        """;

    public const string AuthenticationRejected = """
        {"detail":"Invalid token."}
        """;

    public const string UnexpectedSuccessfulBody = """
        {"removed":true}
        """;

    public static HttpResponseMessage NoContentResponse()
        => new(HttpStatusCode.NoContent);

    public static JsonElement Parse(string json)
        => JsonDocument.Parse(json).RootElement.Clone();
}

public sealed class EpicStoryUnlinkFixtureTests
{
    [Fact]
    public async Task NoContentFixtureUsesEmpty204Response()
    {
        using var response = EpicStoryUnlinkFixtures.NoContentResponse();

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Empty(await response.Content.ReadAsByteArrayAsync());
    }

    [Theory]
    [InlineData(EpicStoryUnlinkFixtures.MissingRelationship)]
    [InlineData(EpicStoryUnlinkFixtures.PermissionDenied)]
    [InlineData(EpicStoryUnlinkFixtures.AuthenticationRejected)]
    public void ErrorFixturesAreSafeDetailObjects(string body)
    {
        var json = EpicStoryUnlinkFixtures.Parse(body);

        Assert.Equal(JsonValueKind.Object, json.ValueKind);
        Assert.True(json.TryGetProperty("detail", out var detail));
        Assert.Equal(JsonValueKind.String, detail.ValueKind);
    }

    [Fact]
    public void UnexpectedSuccessfulBodyIsNotTheNoContentContract()
    {
        var json = EpicStoryUnlinkFixtures.Parse(EpicStoryUnlinkFixtures.UnexpectedSuccessfulBody);

        Assert.Equal(JsonValueKind.Object, json.ValueKind);
        Assert.True(json.GetProperty("removed").GetBoolean());
    }
}
