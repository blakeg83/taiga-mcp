namespace TaigaMCP.Tests;

internal static class UserStoryStatusFixtures
{
    public const string LocalizedProjectStatuses = """
        [
          {
            "id": 10,
            "project": 123,
            "name": "Terminado",
            "slug": "terminado",
            "order": 0,
            "color": "#cc0000",
            "is_closed": true,
            "is_archived": false,
            "wip_limit": 0
          },
          {
            "id": 11,
            "project": 123,
            "name": "Guardado",
            "slug": "guardado",
            "order": 1,
            "color": null,
            "is_closed": false,
            "is_archived": true,
            "wip_limit": null
          }
        ]
        """;
}
