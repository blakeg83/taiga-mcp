using System.Text.Json;
using TaigaMCP.Models;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class UserStoryStatusTests
{
    [Fact]
    public void StatusContractPreservesLocalizedNamesIndependentFlagsAndZeroValues()
    {
        var statuses = JsonSerializer.Deserialize<UserStoryStatusDto[]>(
            UserStoryStatusFixtures.LocalizedProjectStatuses)!;

        Assert.Collection(
            statuses,
            closed =>
            {
                Assert.Equal(10, closed.Id);
                Assert.Equal(123, closed.Project);
                Assert.Equal("Terminado", closed.Name);
                Assert.Equal("terminado", closed.Slug);
                Assert.Equal(0, closed.Order);
                Assert.Equal("#cc0000", closed.Color);
                Assert.True(closed.IsClosed);
                Assert.False(closed.IsArchived);
                Assert.Equal(0, closed.WipLimit);
            },
            archived =>
            {
                Assert.Equal(11, archived.Id);
                Assert.False(archived.IsClosed);
                Assert.True(archived.IsArchived);
                Assert.Null(archived.Color);
                Assert.Null(archived.WipLimit);
            });
    }

    [Fact]
    public void StatusResponseOmitsOnlyMissingOptionalValues()
    {
        var status = new UserStoryStatusDto
        {
            Id = 11,
            Name = "Guardado",
            Order = 0,
            IsClosed = false,
            IsArchived = true,
            WipLimit = 0
        };

        using var json = JsonDocument.Parse(ToolResponseJson.Serialize(status));
        var root = json.RootElement;

        Assert.Equal(11, root.GetProperty("id").GetInt32());
        Assert.Equal(0, root.GetProperty("order").GetInt32());
        Assert.False(root.GetProperty("is_closed").GetBoolean());
        Assert.True(root.GetProperty("is_archived").GetBoolean());
        Assert.Equal(0, root.GetProperty("wip_limit").GetInt32());
        Assert.False(root.TryGetProperty("project", out _));
        Assert.False(root.TryGetProperty("color", out _));
    }
}
