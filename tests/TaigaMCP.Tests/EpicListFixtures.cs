namespace TaigaMCP.Tests;

internal static class EpicListFixtures
{
    public const string OpenAndClosed = """
        [{
          "id":301,
          "ref":12,
          "project":123,
          "subject":"Saved search epic — ✓",
          "status":7,
          "status_extra_info":{"name":"Ready"},
          "assigned_to":42,
          "color":"#336699",
          "tags":[["search","#336699"],["saved",null]],
          "modified_date":"2026-09-28T12:03:00Z",
          "version":4
        },{
          "id":302,
          "ref":13,
          "project":123,
          "subject":"Closed epic",
          "status":8,
          "status_extra_info":{"name":"Terminado"},
          "assigned_to":null,
          "color":null,
          "tags":[],
          "modified_date":"2026-09-28T12:04:00Z"
        }]
        """;
}
