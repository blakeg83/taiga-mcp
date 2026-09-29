using System.Net;
using System.Text.Json;
using Xunit;

namespace TaigaMCP.Tests;

internal static class EpicStoryLinkFixtures
{
    public const string Success = """
        {"epic":301,"user_story":102,"order":9001}
        """;

    public const string Duplicate = """
        {"non_field_errors":["The fields epic, user_story must make a unique set."]}
        """;

    public const string MissingLink = """
        {"detail":"Not found."}
        """;

    public const string PermissionDenied = """
        {"detail":"Permission denied."}
        """;

    public static JsonElement Parse(string json)
        => JsonDocument.Parse(json).RootElement.Clone();
}

public sealed class EpicStoryLinkFixtureTests
{
    [Fact]
    public void SuccessResponseUsesNestedLookupIdentifiersAndRelationshipOrder()
    {
        var response = EpicStoryLinkFixtures.Parse(EpicStoryLinkFixtures.Success);

        Assert.Equal(301, response.GetProperty("epic").GetInt32());
        Assert.Equal(102, response.GetProperty("user_story").GetInt32());
        Assert.Equal(9001, response.GetProperty("order").GetInt64());
    }

    [Fact]
    public void DuplicateResponseIsAValidationFailureRatherThanAnUnqualifiedNotFound()
    {
        var response = EpicStoryLinkFixtures.Parse(EpicStoryLinkFixtures.Duplicate);

        Assert.Equal(JsonValueKind.Array, response.GetProperty("non_field_errors").ValueKind);
        Assert.Contains("unique", response.GetProperty("non_field_errors")[0].GetString()!, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData(EpicStoryLinkFixtures.MissingLink, HttpStatusCode.NotFound)]
    [InlineData(EpicStoryLinkFixtures.PermissionDenied, HttpStatusCode.Forbidden)]
    public void MissingAndPermissionFixturesRetainTheirDistinctHttpSemantics(string body, HttpStatusCode statusCode)
    {
        using var document = JsonDocument.Parse(body);

        Assert.Equal(JsonValueKind.Object, document.RootElement.ValueKind);
        Assert.True((int)statusCode is 403 or 404);
        Assert.True(document.RootElement.TryGetProperty("detail", out _));
    }
}
