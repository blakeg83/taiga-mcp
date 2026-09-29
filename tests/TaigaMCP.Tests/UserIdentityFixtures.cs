namespace TaigaMCP.Tests;

internal static class UserIdentityFixtures
{
    public const string Minimal = """
        {"id":42}
        """;

    public const string Populated = """
        {
          "id":42,
          "username":"synthetic-user",
          "full_name":"Synthetic User",
          "is_active":false
        }
        """;

    public const string AdminWithPrivateFields = """
        {
          "id":42,
          "username":"synthetic-user",
          "full_name":"Synthetic User",
          "is_active":true,
          "email":"private@example.test",
          "auth_token":"must-not-escape",
          "roles":["admin"],
          "uuid":"private-uuid"
        }
        """;

    public const string MissingId = """
        {"username":"synthetic-user"}
        """;

    public const string NonPositiveId = """
        {"id":0,"username":"synthetic-user"}
        """;

    public const string WrongIdType = """
        {"id":"42","username":"synthetic-user"}
        """;

    public const string Malformed = """
        {"id":42,
        """;
}
