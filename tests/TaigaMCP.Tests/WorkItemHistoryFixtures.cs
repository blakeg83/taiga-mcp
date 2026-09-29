namespace TaigaMCP.Tests;

internal static class WorkItemHistoryFixtures
{
    public const string CommentsPage = """
        [
          {
            "id":"550e8400-e29b-41d4-a716-446655440000",
            "type":1,
            "comment":"**Progress**\n@alice — revisión ✓",
            "comment_html":"<p>private rendered form</p>",
            "created_at":"2026-09-28T12:01:00Z",
            "edit_comment_date":"2026-09-28T12:05:00Z",
            "user":{"pk":42,"name":"Example User","username":"example","is_active":true}
          },
          {
            "id":"blank-comment",
            "comment":"   ",
            "created_at":"2026-09-28T12:02:00Z",
            "user":{"pk":42,"name":"Example User","username":"example","is_active":true}
          },
          {
            "id":"hidden-comment",
            "is_hidden":true,
            "comment":"hidden content",
            "created_at":"2026-09-28T12:03:00Z",
            "user":{"pk":42,"name":"Example User","username":"example","is_active":true}
          },
          {
            "id":"deleted-comment",
            "comment":"deleted content",
            "delete_comment_date":"2026-09-28T12:04:00Z",
            "created_at":"2026-09-28T12:04:00Z",
            "user":{"pk":42,"name":"Example User","username":"example","is_active":true}
          },
          {
            "id":"missing-actor",
            "comment":"The original actor is no longer available.",
            "created_at":"2026-09-28T12:06:00Z",
            "user":{"pk":null,"name":null,"username":null,"is_active":false}
          },
          {
            "id":"inactive-actor",
            "comment":"Inactive authors remain identifiable.",
            "created_at":"2026-09-28T12:06:30Z",
            "user":{"pk":9,"name":"Inactive User","username":"inactive","is_active":false}
          },
          {
            "id":"surrounding-whitespace",
            "comment":"  Keep surrounding whitespace  ",
            "created_at":"2026-09-28T12:07:00Z",
            "user":{"pk":42,"name":"Example User","username":"example","is_active":true}
          }
        ]
        """;

    public const string PaginatedBody = """
        {
          "count":3,
          "next":"https://fake.taiga.test/api/v1/history/userstory/102?type=comment&page=2",
          "previous":null,
          "results":[
            {
              "id":"edited-entry",
              "comment":"Edited Markdown **text**",
              "created_at":"2026-09-28T12:07:00Z",
              "edit_comment_date":"2026-09-28T12:08:00Z",
              "user":{"pk":7,"name":"Editor","username":"editor","is_active":true}
            }
          ]
        }
        """;
}
