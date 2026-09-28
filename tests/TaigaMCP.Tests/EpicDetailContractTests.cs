using System.Text.Json;
using TaigaMCP.Models;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class EpicDetailContractTests
{
    [Fact]
    public void RichFixtureDefinesTheApprovedDetailFieldsAndPreservesSummaryJson()
    {
        using var document = JsonDocument.Parse(EpicDetailFixtures.Rich);
        var source = document.RootElement;
        var detail = new EpicDetailDto
        {
            Id = source.GetProperty("id").GetInt32(),
            Ref = source.GetProperty("ref").GetInt32(),
            Project = source.GetProperty("project").GetInt32(),
            Subject = source.GetProperty("subject").GetString(),
            Description = source.GetProperty("description").GetString(),
            StatusId = source.GetProperty("status").GetInt32(),
            Status = source.GetProperty("status_extra_info").GetProperty("name").GetString(),
            Color = source.GetProperty("color").GetString(),
            Tags = source.GetProperty("tags").EnumerateArray().Select(tag => tag.Clone()).ToArray(),
            UserStoriesCounts = source.GetProperty("user_stories_counts").Clone(),
            Version = source.GetProperty("version").GetInt32()
        };

        var json = JsonSerializer.Deserialize<JsonElement>(ToolResponseJson.Serialize(detail));

        Assert.Equal(301, json.GetProperty("id").GetInt32());
        Assert.Equal(12, json.GetProperty("ref").GetInt32());
        Assert.Equal(123, json.GetProperty("project").GetInt32());
        Assert.Equal("**Acceptance:** preserve Markdown and Unicode — ✓", json.GetProperty("description").GetString());
        Assert.Equal("#336699", json.GetProperty("color").GetString());
        Assert.Equal(2, json.GetProperty("tags").GetArrayLength());
        Assert.Equal(3, json.GetProperty("user_stories_counts").GetProperty("total").GetInt32());
        Assert.Equal(4, json.GetProperty("version").GetInt32());

        var nullable = new EpicDetailDto { Id = 301, Ref = 12, Project = 123, Version = 0 };
        var nullableJson = JsonSerializer.Deserialize<JsonElement>(ToolResponseJson.Serialize(nullable));
        Assert.False(nullableJson.TryGetProperty("assigned_to", out _));
        Assert.False(nullableJson.TryGetProperty("user_stories_counts", out _));
    }
}
