using System.Text.Json;
using Xunit;

namespace TaigaMCP.Tests;

internal static class TaskCreateFixtures
{
    public const string StandaloneUnscheduledRequest = """
        {"project":12,"subject":"Capture deployment checklist"}
        """;

    public const string StandaloneSprintRequest = """
        {"project":12,"subject":"Prepare release notes","milestone":55}
        """;

    public const string StoryLinkedRequest = """
        {"project":12,"subject":"Implement saved-search endpoint","user_story":102}
        """;

    public const string ParentStoryWithSprint = """
        {
          "id":102,
          "ref":18,
          "project":12,
          "subject":"Allow saved searches",
          "status":7,
          "status_extra_info":{"name":"Ready"},
          "milestone":55,
          "version":4
        }
        """;

    public const string ParentStoryWithoutSprint = """
        {
          "id":103,
          "ref":19,
          "project":12,
          "subject":"Capture saved-search requirements",
          "status":7,
          "status_extra_info":{"name":"Ready"},
          "milestone":null,
          "version":2
        }
        """;

    public const string CreatedTask = """
        {
          "id":203,
          "ref":17,
          "project":12,
          "subject":"Implement saved-search endpoint",
          "description":"**Acceptance:** preserve Markdown and Unicode — ✓",
          "status":11,
          "status_extra_info":{"name":"Ready"},
          "assigned_to":42,
          "user_story":102,
          "milestone":55,
          "tags":[["search","#336699"]],
          "modified_date":"2026-09-28T12:00:00Z",
          "version":2
        }
        """;

    public static JsonElement Parse(string json)
        => JsonDocument.Parse(json).RootElement.Clone();
}

public sealed class TaskCreateFixtureTests
{
    [Fact]
    public void StandaloneUnscheduledRequestOmitsOptionalFields()
    {
        var request = TaskCreateFixtures.Parse(TaskCreateFixtures.StandaloneUnscheduledRequest);

        Assert.Equal(12, request.GetProperty("project").GetInt32());
        Assert.Equal("Capture deployment checklist", request.GetProperty("subject").GetString());
        Assert.Equal(2, request.EnumerateObject().Count());
    }

    [Fact]
    public void StandaloneSprintRequestUsesMilestoneWireKey()
    {
        var request = TaskCreateFixtures.Parse(TaskCreateFixtures.StandaloneSprintRequest);

        Assert.Equal(55, request.GetProperty("milestone").GetInt32());
        Assert.DoesNotContain(request.EnumerateObject(), property => property.Name == "user_story");
    }

    [Fact]
    public void StoryLinkedRequestOmitsRedundantMilestone()
    {
        var request = TaskCreateFixtures.Parse(TaskCreateFixtures.StoryLinkedRequest);

        Assert.Equal(102, request.GetProperty("user_story").GetInt32());
        Assert.DoesNotContain(request.EnumerateObject(), property => property.Name == "milestone");
    }
}
