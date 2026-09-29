namespace TaigaMCP.Tests;

internal static class WorkItemResolverFixtures
{
    public const string Issue = """
        {
          "id":203,
          "ref":42,
          "project":12,
          "subject":"Resolve the saved search issue",
          "version":3,
          "status":1
        }
        """;

    public const string UserStory = """
        {
          "id":304,
          "ref":42,
          "project":12,
          "subject":"Allow saved searches",
          "version":4,
          "status":7
        }
        """;

    public const string Task = """
        {
          "id":405,
          "ref":42,
          "project":12,
          "subject":"Implement saved-search endpoint",
          "version":5,
          "status":11
        }
        """;

    public const string Epic = """
        {
          "id":506,
          "ref":42,
          "project":12,
          "subject":"Saved-search delivery",
          "version":6,
          "status":7
        }
        """;

    public const string MismatchedProject = """
        {
          "id":203,
          "ref":42,
          "project":99,
          "subject":"Wrong project",
          "version":3
        }
        """;

    public const string MismatchedRef = """
        {
          "id":203,
          "ref":43,
          "project":12,
          "subject":"Wrong reference",
          "version":3
        }
        """;
}
