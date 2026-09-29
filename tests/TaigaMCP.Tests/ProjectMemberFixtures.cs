namespace TaigaMCP.Tests;

internal static class ProjectMemberFixtures
{
    public const string MixedPage = """
        [
          {
            "id": 501,
            "user": 42,
            "project": 123,
            "role": 7,
            "is_admin": true,
            "role_name": "Product Owner",
            "full_name": "Active User",
            "is_user_active": true,
            "is_owner": true,
            "email": "private-admin@example.test",
            "user_email": "private-user@example.test",
            "invitation_extra_text": "private invitation text"
          },
          {
            "id": 502,
            "user": 43,
            "project": 123,
            "role": null,
            "is_admin": false,
            "role_name": null,
            "full_name": "Inactive User",
            "is_user_active": false,
            "is_owner": false,
            "email": "private-inactive@example.test",
            "user_email": "private-inactive-user@example.test"
          },
          {
            "id": 503,
            "user": null,
            "project": 123,
            "role": 8,
            "is_admin": false,
            "role_name": "Developer",
            "full_name": null,
            "is_user_active": false,
            "is_owner": null,
            "email": "pending@example.test",
            "invitation_extra_text": "pending invitation text"
          },
          {
            "id": 504,
            "user": 44,
            "project": 123,
            "role": null,
            "is_admin": false,
            "full_name": "Localized 名称",
            "is_user_active": true,
            "is_owner": false,
            "email": "private-localized@example.test",
            "user_email": "private-localized-user@example.test"
          },
          {
            "id": 505,
            "user": 45,
            "project": 123,
            "role": 9,
            "is_admin": false,
            "role_name": "Developer",
            "full_name": "Active User",
            "is_user_active": true,
            "is_owner": false,
            "email": "private-duplicate@example.test",
            "user_email": "private-duplicate-user@example.test"
          }
        ]
        """;
}
