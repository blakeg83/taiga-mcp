using System.Text.Json;
using Xunit;

namespace TaigaMCP.Tests;

internal static class UserStoryUpdateFixtures
{
    public const string UntouchedFields = """
        {"description":"Changed","version":7}
        """;

    public const string Unassign = """
        {"assigned_to":null,"version":7}
        """;

    public const string RemoveFromSprint = """
        {"milestone":null,"version":7}
        """;

    public const string ClearDescriptionAndTags = """
        {"description":"","tags":[],"version":7}
        """;

    public const string CommentOnly = """
        {"comment":"Returned to backlog.","version":7}
        """;

    public static JsonElement Parse(string json)
        => JsonDocument.Parse(json).RootElement.Clone();
}

public sealed class UserStoryUpdateFixtureTests
{
    [Fact]
    public void OmittedAssignmentAndSprintRemainAbsent()
    {
        var request = UserStoryUpdateFixtures.Parse(UserStoryUpdateFixtures.UntouchedFields);

        Assert.Equal(
            new[] { "description", "version" },
            request.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
        Assert.False(request.TryGetProperty("assigned_to", out _));
        Assert.False(request.TryGetProperty("milestone", out _));
    }

    [Fact]
    public void ClearFieldsUseTaigaWireKeysAndExplicitNulls()
    {
        var unassign = UserStoryUpdateFixtures.Parse(UserStoryUpdateFixtures.Unassign);
        var removeFromSprint = UserStoryUpdateFixtures.Parse(UserStoryUpdateFixtures.RemoveFromSprint);

        Assert.Equal(JsonValueKind.Null, unassign.GetProperty("assigned_to").ValueKind);
        Assert.Equal(JsonValueKind.Null, removeFromSprint.GetProperty("milestone").ValueKind);
        Assert.False(unassign.TryGetProperty("milestone", out _));
        Assert.False(removeFromSprint.TryGetProperty("assigned_to", out _));
    }

    [Fact]
    public void EmptyDescriptionAndTagsRemainExplicitValues()
    {
        var request = UserStoryUpdateFixtures.Parse(UserStoryUpdateFixtures.ClearDescriptionAndTags);

        Assert.Equal(string.Empty, request.GetProperty("description").GetString());
        Assert.Empty(request.GetProperty("tags").EnumerateArray());
    }

    [Fact]
    public void CommentOnlyUpdateIncludesVersionAndComment()
    {
        var request = UserStoryUpdateFixtures.Parse(UserStoryUpdateFixtures.CommentOnly);

        Assert.Equal(
            new[] { "comment", "version" },
            request.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
        Assert.Equal("Returned to backlog.", request.GetProperty("comment").GetString());
        Assert.Equal(7, request.GetProperty("version").GetInt32());
    }
}
