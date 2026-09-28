namespace TaigaMCP.Tests;

internal static class TaskDetailFixtures
{
    public const string Standalone = """
        {
          "id":203,
          "ref":17,
          "project":12,
          "subject":"Document the search flow — ✓",
          "description":"**Acceptance:** preserve Markdown and Unicode — ✓",
          "status":11,
          "status_extra_info":{"name":"Ready","color":"#00aa00","is_closed":false},
          "assigned_to":null,
          "user_story":null,
          "milestone":null,
          "tags":[["search","#336699"],["backend",null]],
          "modified_date":"2026-09-28T12:00:00Z",
          "version":2,
          "due_date":null,
          "due_date_reason":"",
          "due_date_status":"not_set",
          "is_blocked":false,
          "blocked_note":"",
          "is_closed":false,
          "future_field":"ignored"
        }
        """;

    public const string StoryLinked = """
        {
          "id":204,
          "ref":18,
          "project":12,
          "subject":"Close the saved-search task",
          "description":"Waiting for the saved-search API to be deployed.",
          "status":44,
          "status_extra_info":{"name":"Terminado","color":"#cc0000","is_closed":false},
          "assigned_to":42,
          "user_story":102,
          "milestone":55,
          "tags":[["search","#336699"]],
          "modified_date":"2026-09-28T12:01:00Z",
          "version":3,
          "due_date":"2026-10-15",
          "due_date_reason":"Release readiness review",
          "due_date_status":"set",
          "is_blocked":true,
          "blocked_note":"Waiting for the saved-search API.",
          "is_closed":false,
          "new_detail_field":{"kept":true}
        }
        """;

    public const string MissingVersion = """
        {"id":203,"ref":17,"project":12,"subject":"Missing version"}
        """;

    public const string InvalidIdentity = """
        {"id":0,"ref":17,"project":12,"version":2}
        """;
}
