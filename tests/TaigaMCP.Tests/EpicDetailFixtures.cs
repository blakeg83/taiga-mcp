namespace TaigaMCP.Tests;

internal static class EpicDetailFixtures
{
    public const string Rich = """
        {
          "id":301,
          "ref":12,
          "project":123,
          "subject":"Saved search epic — ✓",
          "description":"**Acceptance:** preserve Markdown and Unicode — ✓",
          "status":7,
          "status_extra_info":{"name":"Ready","color":"#00aa00","is_closed":false},
          "assigned_to":null,
          "color":"#336699",
          "tags":[["search","#336699"],["saved",null]],
          "modified_date":"2026-09-28T12:03:00Z",
          "is_closed":false,
          "is_blocked":true,
          "blocked_note":"Waiting for the saved-search API.",
          "client_requirement":true,
          "team_requirement":false,
          "user_stories_counts":{"total":3,"closed":1,"new_summary_field":true},
          "version":4,
          "future_detail_field":{"ignored":true}
        }
        """;
}
