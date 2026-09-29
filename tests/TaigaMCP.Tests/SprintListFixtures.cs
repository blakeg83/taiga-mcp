namespace TaigaMCP.Tests;

internal static class SprintListFixtures
{
    public const string OpenAndClosed = """
        [
          {
            "id":301,
            "project":12,
            "name":"Sprint 2026-09",
            "slug":"sprint-2026-09",
            "estimated_start":"2026-09-01",
            "estimated_finish":"2026-09-14",
            "closed":false,
            "owner":null,
            "user_stories":[{"id":901,"subject":"Nested story must be ignored"}],
            "total_points":12.0,
            "closed_points":null
          },
          {
            "id":302,
            "project":12,
            "name":"Sprint 2026-08",
            "slug":"sprint-2026-08",
            "estimated_start":"2026-08-17",
            "estimated_finish":"2026-08-31",
            "closed":true,
            "owner":42,
            "user_stories":[],
            "total_points":{},
            "closed_points":{"1":2}
          }
        ]
        """;

    public const string OpenWithNullOptionalExtras = """
        [{
          "id":303,
          "project":12,
          "name":"Sprint without optional extras",
          "slug":"sprint-without-optional-extras",
          "estimated_start":"2026-10-01",
          "estimated_finish":"2026-10-14",
          "closed":false,
          "owner":null,
          "disponibility":null,
          "user_stories":null,
          "total_points":null,
          "closed_points":null
        }]
        """;
}
