using System.Text.Json;
using TaigaMCP.Models;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class EpicListTests
{
    [Fact]
    public void EpicDto_PublicContractUsesStableNamesAndPreservesNullableFields()
    {
        using var document = JsonDocument.Parse(EpicListFixtures.OpenAndClosed);
        var first = document.RootElement[0];
        var tags = first.GetProperty("tags").EnumerateArray().Select(tag => tag.Clone()).ToArray();
        var epic = new EpicDto
        {
            Id = first.GetProperty("id").GetInt32(),
            Ref = first.GetProperty("ref").GetInt32(),
            Project = first.GetProperty("project").GetInt32(),
            Subject = first.GetProperty("subject").GetString(),
            StatusId = first.GetProperty("status").GetInt32(),
            Status = first.GetProperty("status_extra_info").GetProperty("name").GetString(),
            AssignedTo = first.GetProperty("assigned_to").GetInt32(),
            Color = first.GetProperty("color").GetString(),
            Tags = tags,
            Modified = first.GetProperty("modified_date").GetString(),
            Version = first.GetProperty("version").GetInt32()
        };

        var json = JsonSerializer.Deserialize<JsonElement>(ToolResponseJson.Serialize(epic));

        Assert.Equal(301, json.GetProperty("id").GetInt32());
        Assert.Equal(12, json.GetProperty("ref").GetInt32());
        Assert.Equal(123, json.GetProperty("project").GetInt32());
        Assert.Equal(7, json.GetProperty("status_id").GetInt32());
        Assert.Equal("Ready", json.GetProperty("status").GetString());
        Assert.Equal(42, json.GetProperty("assigned_to").GetInt32());
        Assert.Equal("#336699", json.GetProperty("color").GetString());
        Assert.Equal("2026-09-28T12:03:00Z", json.GetProperty("modified").GetString());
        Assert.Equal(4, json.GetProperty("version").GetInt32());
        Assert.Equal(2, json.GetProperty("tags").GetArrayLength());

        var nullable = new EpicDto { Id = 302, Ref = 13 };
        var nullableJson = JsonSerializer.Deserialize<JsonElement>(ToolResponseJson.Serialize(nullable));
        Assert.False(nullableJson.TryGetProperty("assigned_to", out _));
        Assert.False(nullableJson.TryGetProperty("color", out _));
        Assert.False(nullableJson.TryGetProperty("version", out _));
    }
}
