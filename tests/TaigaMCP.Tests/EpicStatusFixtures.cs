namespace TaigaMCP.Tests;

internal static class EpicStatusFixtures
{
    public const string LocalizedProjectStatuses = """
        [
          {
            "id": 30,
            "project": 123,
            "name": "En revisión",
            "slug": "en-revision",
            "order": 0,
            "color": "#336699",
            "is_closed": false
          },
          {
            "id": 31,
            "project": 123,
            "name": "Terminé",
            "slug": "termine",
            "is_closed": true
          }
        ]
        """;
}
