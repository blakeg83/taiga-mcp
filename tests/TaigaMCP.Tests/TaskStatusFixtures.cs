namespace TaigaMCP.Tests;

internal static class TaskStatusFixtures
{
    public const string LocalizedProjectStatuses = """
        [
          {
            "id": 20,
            "project": 123,
            "name": "Done",
            "slug": "done",
            "order": 0,
            "color": "#00aa00",
            "is_closed": false
          },
          {
            "id": 21,
            "project": 123,
            "name": "Terminé",
            "slug": "termine",
            "order": 1,
            "color": null,
            "is_closed": true
          }
        ]
        """;
}
