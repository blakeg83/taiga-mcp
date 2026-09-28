namespace TaigaMCP.Tests;

internal static class TaskListFixtures
{
    public const string Standalone = """
        [{
          "id":203,
          "ref":17,
          "project":12,
          "subject":"Document the search flow — ✓",
          "status":11,
          "status_extra_info":{"name":"Ready"},
          "assigned_to":null,
          "user_story":null,
          "milestone":null,
          "modified_date":"2026-09-28T12:00:00Z",
          "version":2
        }]
        """;

    public const string StoryLinkedClosed = """
        [{
          "id":204,
          "ref":18,
          "project":12,
          "subject":"Close the saved-search task",
          "status":44,
          "status_extra_info":{"name":"Terminado"},
          "assigned_to":42,
          "user_story":102,
          "milestone":55,
          "modified_date":"2026-09-28T12:01:00Z",
          "version":3
        }]
        """;

    public const string UnavailableStatusLabel = """
        [{
          "id":205,
          "ref":19,
          "project":12,
          "subject":"Task with an unavailable status label",
          "status":99,
          "status_extra_info":null,
          "assigned_to":42,
          "user_story":null,
          "milestone":null,
          "modified_date":"2026-09-28T12:02:00Z"
        }]
        """;
}
