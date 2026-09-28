using System.Text.Json;
using Xunit;

namespace TaigaMCP.Tests;

internal static class EpicCreateFixtures
{
    public const string MinimalRequest = """
        {"project":123,"subject":"Saved search experience"}
        """;

    public const string PopulatedRequest = """
        {
          "project":123,
          "subject":"Saved search experience",
          "description":"Group saved-search delivery work.",
          "status":7,
          "assigned_to":42,
          "color":"#336699",
          "tags":["search","saved"]
        }
        """;

    public const string CreatedEpic = """
        {
          "id":301,
          "ref":12,
          "project":123,
          "subject":"Saved search experience",
          "description":"Group saved-search delivery work.",
          "status":7,
          "status_extra_info":{"name":"Ready"},
          "assigned_to":42,
          "color":"#336699",
          "tags":[["search","#336699"],["saved",null]],
          "modified_date":"2026-09-28T12:03:00Z",
          "version":4
        }
        """;

    public static JsonElement Parse(string json)
        => JsonDocument.Parse(json).RootElement.Clone();
}

public sealed class EpicCreateFixtureTests
{
    [Fact]
    public void MinimalRequestOmitsOptionalFieldsSoProjectDefaultsApply()
    {
        var request = EpicCreateFixtures.Parse(EpicCreateFixtures.MinimalRequest);

        Assert.Equal(123, request.GetProperty("project").GetInt32());
        Assert.Equal("Saved search experience", request.GetProperty("subject").GetString());
        Assert.Equal(2, request.EnumerateObject().Count());
    }

    [Fact]
    public void PopulatedRequestUsesTaigaWireKeysAndTagsArray()
    {
        var request = EpicCreateFixtures.Parse(EpicCreateFixtures.PopulatedRequest);

        Assert.Equal(
            new[] { "assigned_to", "color", "description", "project", "status", "subject", "tags" },
            request.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
        Assert.Equal(new[] { "search", "saved" }, request.GetProperty("tags").EnumerateArray().Select(tag => tag.GetString()));
    }
}
