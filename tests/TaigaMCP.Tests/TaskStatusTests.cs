using System.Text.Json;
using TaigaMCP.Models;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class TaskStatusTests
{
    [Fact]
    public void StatusContractPreservesLocalizedNamesAndIndependentClosureFlags()
    {
        var statuses = JsonSerializer.Deserialize<TaskStatusDto[]>(
            TaskStatusFixtures.LocalizedProjectStatuses)!;

        Assert.Collection(
            statuses,
            open =>
            {
                Assert.Equal(20, open.Id);
                Assert.Equal(123, open.Project);
                Assert.Equal("Done", open.Name);
                Assert.Equal("done", open.Slug);
                Assert.Equal(0, open.Order);
                Assert.Equal("#00aa00", open.Color);
                Assert.False(open.IsClosed);
            },
            closed =>
            {
                Assert.Equal(21, closed.Id);
                Assert.Equal("Terminé", closed.Name);
                Assert.Equal("termine", closed.Slug);
                Assert.Equal(1, closed.Order);
                Assert.Null(closed.Color);
                Assert.True(closed.IsClosed);
            });
    }

    [Fact]
    public void StatusResponseDoesNotExposeStoryOnlyMetadata()
    {
        var status = new TaskStatusDto
        {
            Id = 21,
            Name = "Terminé",
            IsClosed = true
        };

        using var json = JsonDocument.Parse(ToolResponseJson.Serialize(status));
        var root = json.RootElement;

        Assert.Equal(21, root.GetProperty("id").GetInt32());
        Assert.Equal("Terminé", root.GetProperty("name").GetString());
        Assert.True(root.GetProperty("is_closed").GetBoolean());
        Assert.False(root.TryGetProperty("is_archived", out _));
        Assert.False(root.TryGetProperty("wip_limit", out _));
        Assert.False(root.TryGetProperty("project", out _));
    }
}
