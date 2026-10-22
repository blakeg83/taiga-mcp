using System.Text.Json;
using Xunit;

namespace TaigaMCP.Tests;

internal static class UserStoryCreateFixtures
{
    public const string MinimalRequest = """
        {"project":12,"subject":"Allow saved searches"}
        """;

    public const string PopulatedRequest = """
        {
          "project":12,
          "subject":"Allow saved searches",
          "description":"Acceptance: saved searches can be reopened.",
          "status":7,
          "assigned_to":42,
          "tags":["search","saved"],
          "milestone":55
        }
        """;

    public const string CreatedStory = """
        {
          "id":102,
          "ref":18,
          "project":12,
          "subject":"Allow saved searches",
          "description":"Acceptance: saved searches can be reopened.",
          "status":7,
          "status_extra_info":{"name":"Ready"},
          "assigned_to":42,
          "tags":[["search","#336699"],["saved",null]],
          "milestone":55,
          "points":{"7":23},
          "total_points":5.5,
          "modified_date":"2026-09-28T12:00:00Z",
          "version":4
        }
        """;

    public static JsonElement Parse(string json)
        => JsonDocument.Parse(json).RootElement.Clone();
}

public sealed class UserStoryCreateFixtureTests
{
    [Fact]
    public void MinimalRequestOmitsOptionalFieldsSoProjectDefaultsApply()
    {
        var request = UserStoryCreateFixtures.Parse(UserStoryCreateFixtures.MinimalRequest);

        Assert.Equal(12, request.GetProperty("project").GetInt32());
        Assert.Equal("Allow saved searches", request.GetProperty("subject").GetString());
        Assert.Equal(2, request.EnumerateObject().Count());
    }

    [Fact]
    public void PopulatedRequestUsesTaigaWireKeysAndTagsArray()
    {
        var request = UserStoryCreateFixtures.Parse(UserStoryCreateFixtures.PopulatedRequest);

        Assert.Equal(
            new[] { "assigned_to", "description", "milestone", "project", "status", "subject", "tags" },
            request.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
        Assert.Equal(new[] { "search", "saved" }, request.GetProperty("tags").EnumerateArray().Select(tag => tag.GetString()));
    }
}
