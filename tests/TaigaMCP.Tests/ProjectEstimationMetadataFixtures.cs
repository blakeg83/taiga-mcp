namespace TaigaMCP.Tests;

internal static class ProjectEstimationMetadataFixtures
{
    public const string Points = """
        [
          {
            "id": 21,
            "project": 123,
            "name": "Not estimated",
            "order": 0,
            "value": null,
            "description": "private point field"
          },
          {
            "id": 22,
            "project": 123,
            "name": "Half",
            "order": 1,
            "value": 0.5
          },
          {
            "id": 23,
            "project": 123,
            "name": "Five",
            "order": 2,
            "value": 5
          }
        ]
        """;

    public const string Roles = """
        [
          {
            "id": 7,
            "project": 123,
            "name": "Developer",
            "slug": "developer",
            "order": 1,
            "computable": true,
            "permissions": ["view_project"],
            "members_count": 4
          },
          {
            "id": 8,
            "project": 123,
            "name": "Reviewer",
            "computable": false
          }
        ]
        """;
}
